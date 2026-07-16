extends Node
## AnalyticsManager (autoload) — the single historical-metrics pipeline.
##
## Ingests typed business events continuously and closes compact daily fact
## buckets at the day-change edge. It is registered in city.gd BETWEEN
## CompanyManager and RestaurantManager, so when day_changed fires it runs
## AFTER every company's books are closed (CompanyState.history[-1] is final and
## ranks are snapshotted) but BEFORE RestaurantManager resets each branch's
## per-day counters (rest.today is still intact). Reports and Rankings read
## these buckets; nothing scrapes live managers to reconstruct history.
##
## New-autoload note: this is not a global identifier until an editor restart,
## so other scripts reach it via get_node_or_null("/root/AnalyticsManager").

const SCHEMA_VERSION: int = 1
const WEEK_DAYS: int = 7
const QUARTER_DAYS: int = 42  # 3 presentation months of 14 days

signal buckets_closed(day: int)

# Tunables (data/tuning.json "analytics").
var _event_retention_days: int = 45
var _daily_retention_days: int = 120
var _rank_news_threshold: int = 1
var _market_window: int = 7

# Compact fact rows. Each row:
#   {grain, period, scope_kind, scope_id, day, company_id?, metrics:{id:float}, ...}
var _daily: Array[Dictionary] = []
var _weekly: Array[Dictionary] = []
var _quarterly: Array[Dictionary] = []
# Rolling event journal (plain dicts, trimmed by retention).
var _events: Array[Dictionary] = []
var _events_summarized: int = 0

# DeliveryManager keeps no per-day/per-branch stats, so we accumulate them from
# its delivery_completed signal: building_id -> {done, failed, time_sum}.
var _delivery_accum: Dictionary = {}

# Per-ranking rank snapshots for day-over-day movement arrows.
var _ranks_today: Dictionary = {}      # ranking_id -> {company_id: rank}
var _ranks_yesterday: Dictionary = {}

var _ranking_registry: Dictionary = {}  # ranking_id -> RankingDef
var _ranking_order: Array[StringName] = []
var _initialized: bool = false
## Cross-manager enrichment (payroll/inventory/demographics/market share). The
## live autoload leaves this on; headless reconciliation tests turn it off so the
## pure bucket logic runs without booting every other manager.
var _enrich_enabled: bool = true


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_load_tuning()
	_build_rankings()
	var save: SaveGame = CompanyManager.loaded_save
	if save != null:
		restore_from_save(save)
	# Connected here (after CompanyManager, before RestaurantManager) so the
	# handler sees closed books + live rest.today.
	GameClock.day_changed.connect(_on_day_changed)
	var router: Node = get_node_or_null("/root/BranchCommandRouter")
	if router != null and router.has_signal("command_executed"):
		router.connect("command_executed", _on_command_executed)
	if DeliveryManager.has_signal("delivery_completed"):
		DeliveryManager.delivery_completed.connect(_on_delivery_completed)
	var staff: Node = get_node_or_null("/root/StaffManager")
	if staff != null:
		if staff.has_signal("staff_resigned"):
			staff.connect("staff_resigned", _on_staff_resigned)
		if staff.has_signal("labor_event_started"):
			staff.connect("labor_event_started", _on_labor_event)


func _load_tuning() -> void:
	_event_retention_days = int(EconomyManager.tuning_value("analytics.event_retention_days", 45))
	_daily_retention_days = int(EconomyManager.tuning_value("analytics.daily_retention_days", 120))
	_rank_news_threshold = maxi(1, int(EconomyManager.tuning_value("analytics.rank_news_threshold", 1)))
	_market_window = maxi(1, int(EconomyManager.tuning_value("analytics.market_share_window_days", 7)))


# --- Daily close -------------------------------------------------------------


func _on_day_changed(day: int) -> void:
	var closed_day: int = day - 1
	for company: CompanyState in CompanyManager.companies:
		snapshot_company(company, closed_day)
		for rest: RestaurantState in company.restaurants:
			snapshot_restaurant(company, rest, closed_day)
	_delivery_accum.clear()
	if closed_day >= 1 and closed_day % WEEK_DAYS == 0:
		_rollup(&"week", closed_day, WEEK_DAYS)
	if closed_day >= 1 and closed_day % QUARTER_DAYS == 0:
		_rollup(&"quarter", closed_day, QUARTER_DAYS)
	_snapshot_ranks()
	_publish_rank_news(closed_day)
	_trim_daily()
	_trim_events()
	buckets_closed.emit(closed_day)


## Build and store one company daily bucket from the just-closed history entry.
## Public + explicit-arg so reconciliation tests can drive it without the tree.
func snapshot_company(company: CompanyState, closed_day: int) -> Dictionary:
	if company.history.is_empty():
		return {}
	var summary: Dictionary = company.history[-1]
	var stamp: int = int(summary.get("day", closed_day))
	var ledger: Dictionary = summary.get("ledger", {})
	var m: Dictionary = {
		"revenue": float(summary.get("income", 0.0)),
		"expenses": -float(summary.get("expenses", 0.0)),  # positive magnitude
		"profit": float(summary.get("profit", 0.0)),
		"cash": float(summary.get("cash", company.cash)),
		"loan": company.loan,
		"reputation": company.reputation,
		"restaurant_count": float(company.restaurants.size()),
		"inventory_value": _inventory_value(company),
		"payroll": _payroll(company),
		"share_of_voice": _share_of_voice(company),
		"market_share": _market_share(company),
	}
	var row: Dictionary = {
		"grain": &"day", "period": stamp, "scope_kind": &"company",
		"scope_id": String(company.id), "day": stamp, "company_id": String(company.id),
		"metrics": m, "ledger": (ledger as Dictionary).duplicate(),
	}
	_daily.append(row)
	return row


## Build and store one restaurant daily bucket from the live (pre-reset)
## rest.today counters plus the day's delivery accumulator.
func snapshot_restaurant(company: CompanyState, rest: RestaurantState, closed_day: int) -> Dictionary:
	var t: Dictionary = rest.today
	var sales: float = float(t.get("sales", 0.0))
	var expenses: float = float(t.get("expenses", 0.0))
	var acc: Dictionary = _delivery_accum.get(rest.building_id, {})
	var done: int = int(acc.get("done", 0))
	var failed: int = int(acc.get("failed", 0))
	var time_sum: float = float(acc.get("time_sum", 0.0))
	var m: Dictionary = {
		"sales": sales,
		"branch_expenses": expenses,
		"branch_profit": sales - expenses,
		"guests": float(t.get("guests", 0)),
		"orders": float(t.get("orders", 0)),
		"lost_demand": float(t.get("queue_leaves", 0)),
		"cancelled": float(t.get("cancelled", 0)),
		"stockouts": float(t.get("stockouts", 0)),
		"staffing_cost": _branch_staffing_cost(rest),
		"rent": _branch_rent(rest),
		"rating": rest.star_rating,
		"seats": float(rest.table_count),
		"deliveries": float(done),
		"delivery_fail_rate": (float(failed) / float(done + failed)) if (done + failed) > 0 else 0.0,
		"avg_delivery_time": (time_sum / float(done)) if done > 0 else 0.0,
	}
	var row: Dictionary = {
		"grain": &"day", "period": closed_day, "scope_kind": &"restaurant",
		"scope_id": str(rest.building_id), "day": closed_day, "company_id": String(company.id),
		"metrics": m,
		"by_category": (t.get("by_category", {}) as Dictionary).duplicate(),
		"demographics": _demographics(rest.building_id),
	}
	_daily.append(row)
	return row


# --- Metric enrichment (guarded cross-manager reads) -------------------------


func _inventory_value(company: CompanyState) -> float:
	if not _enrich_enabled:
		return 0.0
	if SupplyManager.has_method("company_inventory_value"):
		return float(SupplyManager.company_inventory_value(company.id))
	var total: float = 0.0
	for rest: RestaurantState in company.restaurants:
		var inv: Object = rest.inventory
		if inv != null and inv.has_method("total_value"):
			total += float(inv.call("total_value"))
	return total


func _payroll(company: CompanyState) -> float:
	if not _enrich_enabled:
		return 0.0
	var staff: Node = get_node_or_null("/root/StaffManager")
	if staff != null and staff.has_method("workforce_analytics"):
		var wa: Dictionary = staff.call("workforce_analytics", company.id)
		return float(wa.get("payroll_daily", 0.0))
	var total: float = 0.0
	for rest: RestaurantState in company.restaurants:
		total += _branch_staffing_cost(rest)
	return total


func _share_of_voice(company: CompanyState) -> float:
	if not _enrich_enabled:
		return 0.0
	if MarketingManager.has_method("share_of_voice"):
		return float(MarketingManager.share_of_voice(company.id))
	return 0.0


func _branch_staffing_cost(rest: RestaurantState) -> float:
	var total: float = 0.0
	for member: StaffMember in rest.staff:
		if member.has_method("daily_pay"):
			total += float(member.daily_pay())
	return total


func _branch_rent(rest: RestaurantState) -> float:
	if rest.owned_outright:
		return 0.0
	var rents: Dictionary = EconomyManager.tuning_value("rent.daily_by_district", {})
	return float(rents.get(rest.district, 120.0))


func _demographics(building_id: int) -> Dictionary:
	if not _enrich_enabled:
		return {}
	if DemandManager.has_method("customer_profile"):
		return (DemandManager.customer_profile(building_id) as Dictionary).duplicate()
	return {}


## Trailing revenue window, exact for the player, estimated for rivals — same
## knowledge rules the Rankings screen uses (RivalIntel). Reads sales_history,
## so it trails the just-closed day by one for both sides (kept symmetric).
func _revenue_window(company: CompanyState) -> float:
	if company.is_player:
		return _exact_revenue_window(company)
	return RivalIntel.estimated_revenue(company, _market_window)


func _exact_revenue_window(company: CompanyState) -> float:
	var rev: float = 0.0
	for rest: RestaurantState in company.restaurants:
		var n: int = mini(_market_window, rest.sales_history.size())
		for i: int in n:
			rev += rest.sales_history[rest.sales_history.size() - 1 - i]
	return rev


func _market_share(company: CompanyState) -> float:
	if not _enrich_enabled:
		return 0.0
	var total: float = 0.0
	for other: CompanyState in CompanyManager.companies:
		if other.is_bankrupt:
			continue
		total += _revenue_window(other)
	if total <= 0.0:
		return 0.0
	return clampf(_revenue_window(company) / total, 0.0, 1.0)


# --- Event journal -----------------------------------------------------------


## Public entry so any system can drop an explanatory event on the journal.
func record_event(ev_type: StringName, company_id: StringName, fields: Dictionary = {}) -> void:
	var minute: int = int(GameClock.game_hours * 60.0)
	_events.append(BusinessEvent.make(ev_type, company_id, GameClock.day, minute, fields))


func _on_command_executed(command_id: StringName, result: Variant, actor_context: Variant) -> void:
	if result == null or not bool(result.get("ok")):
		return
	var cid: String = String(command_id)
	var ctx: Dictionary = actor_context if actor_context is Dictionary else {}
	var company_id: StringName = StringName(ctx.get("company_id", &"player"))
	var cost: float = float(result.get("actual_cost") if result.get("actual_cost") != null else 0.0)
	if is_zero_approx(cost):
		cost = float(result.get("estimated_cost") if result.get("estimated_cost") != null else 0.0)
	var ev_type: StringName = BusinessEvent.COMMAND
	if cid.contains("price"):
		ev_type = BusinessEvent.PRICE_CHANGE
	elif cid.contains("purchase") or cid.contains("location") or cid.contains("expand"):
		ev_type = BusinessEvent.EXPANSION
	elif absf(cost) < 500.0:
		return  # skip small routine commands to keep the journal meaningful
	var payload: Dictionary = result.get("payload") if result.get("payload") is Dictionary else {}
	var building_id: int = int(payload.get("building_id", -1))
	var title: String = String(result.get("explanation") if result.get("explanation") != null else "")
	if title.is_empty():
		title = String(result.get("message") if result.get("message") != null else cid)
	record_event(ev_type, company_id, {"amount": -absf(cost), "title": title, "restaurant_id": building_id})


func _on_delivery_completed(order: Variant, success: bool) -> void:
	if order == null:
		return
	var bid: int = int(order.get("restaurant_id") if order.get("restaurant_id") != null else -1)
	var acc: Dictionary = _delivery_accum.get(bid, {"done": 0, "failed": 0, "time_sum": 0.0})
	if success:
		acc["done"] = int(acc["done"]) + 1
		var placed: int = int(order.get("placed_minute") if order.get("placed_minute") != null else GameClock.total_minutes())
		acc["time_sum"] = float(acc["time_sum"]) + maxf(0.0, float(GameClock.total_minutes() - placed))
	else:
		acc["failed"] = int(acc["failed"]) + 1
	_delivery_accum[bid] = acc


func _on_staff_resigned(member: Variant, building_id: int) -> void:
	var who: String = "A staff member"
	if member != null and member.get("display_name") != null:
		who = String(member.get("display_name"))
	var company_id: StringName = _company_of_building(building_id)
	record_event(BusinessEvent.STAFF_LOST, company_id, {"restaurant_id": building_id, "title": "%s resigned" % who})


func _on_labor_event(event: Variant) -> void:
	if not (event is Dictionary):
		return
	var headline: String = String((event as Dictionary).get("headline", ""))
	var title: String = headline if not headline.is_empty() else String((event as Dictionary).get("type", "Labor event")).capitalize()
	record_event(BusinessEvent.STAFF_LOST, &"player", {"title": title, "tags": ["labor"]})


func _company_of_building(building_id: int) -> StringName:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id) if RestaurantManager.by_building is Dictionary else null
	if rest != null:
		return rest.company_id
	return &"player"


func events_for_day(scope_kind: StringName, scope_id: String, day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev: Dictionary in _events:
		if int(ev.get("day", -1)) != day:
			continue
		if scope_kind == &"restaurant":
			if int(ev.get("restaurant_id", -1)) == int(scope_id):
				out.append(ev)
		else:
			if String(ev.get("company_id", "")) == scope_id:
				out.append(ev)
	return out


func events_in_range(company_id: StringName, from_day: int, to_day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev: Dictionary in _events:
		var d: int = int(ev.get("day", -1))
		if d >= from_day and d <= to_day and String(ev.get("company_id", "")) == String(company_id):
			out.append(ev)
	return out


# --- Rollups + retention -----------------------------------------------------


func _rollup(grain: StringName, closed_day: int, span: int) -> void:
	var from_day: int = closed_day - span + 1
	var period: int = _period_index(grain, closed_day)
	var groups: Dictionary = {}
	var counts: Dictionary = {}
	for row: Dictionary in _daily:
		var d: int = int(row.get("day", -1))
		if d < from_day or d > closed_day:
			continue
		var key: String = "%s:%s" % [row["scope_kind"], row["scope_id"]]
		if not groups.has(key):
			groups[key] = {
				"grain": grain, "period": period, "day": closed_day,
				"scope_kind": row["scope_kind"], "scope_id": row["scope_id"],
				"company_id": row.get("company_id", ""), "metrics": {},
			}
			counts[key] = 0
		_accumulate_metrics(groups[key]["metrics"], row["metrics"])
		counts[key] = int(counts[key]) + 1
	for key: String in groups:
		_finalize_metrics(groups[key]["metrics"], int(counts[key]))
		if grain == &"week":
			_weekly.append(groups[key])
		else:
			_quarterly.append(groups[key])


func _accumulate_metrics(acc: Dictionary, src: Dictionary) -> void:
	for mid: StringName in src:
		var def: MetricDef = MetricDef.by_id(mid)
		var agg: int = def.agg if def != null else MetricDef.Agg.SUM
		var v: float = float(src[mid])
		match agg:
			MetricDef.Agg.MAX:
				acc[mid] = maxf(float(acc.get(mid, -1e30)), v)
			MetricDef.Agg.LAST:
				acc[mid] = v  # rows iterate in append (day) order, last wins
			_:
				acc[mid] = float(acc.get(mid, 0.0)) + v  # SUM and AVG accumulate


func _finalize_metrics(acc: Dictionary, count: int) -> void:
	if count <= 0:
		return
	for mid: StringName in acc:
		var def: MetricDef = MetricDef.by_id(mid)
		if def != null and def.agg == MetricDef.Agg.AVG:
			acc[mid] = float(acc[mid]) / float(count)


func _period_index(grain: StringName, closed_day: int) -> int:
	if grain == &"week":
		return (closed_day - 1) / WEEK_DAYS + 1
	return (closed_day - 1) / QUARTER_DAYS + 1


func _trim_daily() -> void:
	if _daily.is_empty():
		return
	var max_day: int = int(_daily[-1]["day"])
	var cutoff: int = max_day - _daily_retention_days
	if cutoff <= 0:
		return
	var kept: Array[Dictionary] = []
	for row: Dictionary in _daily:
		if int(row["day"]) > cutoff:
			kept.append(row)
	_daily = kept


func _trim_events() -> void:
	if _events.is_empty():
		return
	var cutoff: int = GameClock.day - _event_retention_days
	if cutoff <= 0:
		return
	var kept: Array[Dictionary] = []
	for ev: Dictionary in _events:
		if int(ev.get("day", 0)) > cutoff:
			kept.append(ev)
		else:
			_events_summarized += 1
	_events = kept


# --- Query surface -----------------------------------------------------------


func _rows_for(scope_kind: StringName, scope_id: String, interval: StringName) -> Array[Dictionary]:
	var src: Array[Dictionary] = _weekly if interval == &"week" else _daily
	var out: Array[Dictionary] = []
	for row: Dictionary in src:
		if row["scope_kind"] == scope_kind and String(row["scope_id"]) == scope_id:
			out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["day"]) < int(b["day"]))
	return out


func metric_series(metric_id: StringName, scope_kind: StringName, scope_id: String, days: int, interval: StringName = &"day") -> Array[float]:
	var rows: Array[Dictionary] = _rows_for(scope_kind, scope_id, interval)
	var n: int = mini(days, rows.size())
	var out: Array[float] = []
	for i: int in range(rows.size() - n, rows.size()):
		out.append(float((rows[i]["metrics"] as Dictionary).get(metric_id, 0.0)))
	return out


func query(spec: ReportQuery) -> Dictionary:
	var rows: Array[Dictionary] = _rows_for(spec.scope_kind, spec.scope_id, spec.interval)
	var n: int = mini(spec.days, rows.size())
	var labels: Array[int] = []
	for i: int in range(rows.size() - n, rows.size()):
		labels.append(int(rows[i]["day"]))
	var series: Array = [metric_series(spec.metric_id, spec.scope_kind, spec.scope_id, spec.days, spec.interval)]
	for cid: String in spec.compare_ids:
		series.append(metric_series(spec.metric_id, spec.scope_kind, cid, spec.days, spec.interval))
	return {"labels": labels, "series": series, "metric_id": spec.metric_id}


func latest(scope_kind: StringName, scope_id: String, metric_id: StringName, fallback: float = 0.0) -> float:
	var rows: Array[Dictionary] = _rows_for(scope_kind, scope_id, &"day")
	if rows.is_empty():
		return fallback
	return float((rows[-1]["metrics"] as Dictionary).get(metric_id, fallback))


func delta(scope_kind: StringName, scope_id: String, metric_id: StringName) -> float:
	var rows: Array[Dictionary] = _rows_for(scope_kind, scope_id, &"day")
	if rows.size() < 2:
		return 0.0
	var a: float = float((rows[-1]["metrics"] as Dictionary).get(metric_id, 0.0))
	var b: float = float((rows[-2]["metrics"] as Dictionary).get(metric_id, 0.0))
	return a - b


func sum_window(scope_kind: StringName, scope_id: String, metric_id: StringName, days: int) -> float:
	var vals: Array[float] = metric_series(metric_id, scope_kind, scope_id, days, &"day")
	var total: float = 0.0
	for v: float in vals:
		total += v
	return total


func company_dashboard(company_id: StringName) -> Dictionary:
	var rows: Array[Dictionary] = _rows_for(&"company", String(company_id), &"day")
	if rows.is_empty():
		return {}
	var prev: Dictionary = rows[-2]["metrics"] if rows.size() >= 2 else {}
	return {"metrics": rows[-1]["metrics"], "prev": prev, "day": int(rows[-1]["day"]), "ledger": rows[-1].get("ledger", {})}


func restaurant_report(building_id: int) -> Dictionary:
	var rows: Array[Dictionary] = _rows_for(&"restaurant", str(building_id), &"day")
	if rows.is_empty():
		return {}
	return {"metrics": rows[-1]["metrics"], "day": int(rows[-1]["day"]), "by_category": rows[-1].get("by_category", {}), "demographics": rows[-1].get("demographics", {})}


func has_history() -> bool:
	return not _daily.is_empty()


# --- Reconciliation (acceptance criteria 1 & 2) ------------------------------


## Company profit == sum of ledger categories, and the company's sales
## categories reconcile to the sum over branches with an explicit unassigned
## (corporate) remainder. `day` < 0 uses the latest closed day.
func reconcile_company(company: CompanyState, day: int = -1) -> Dictionary:
	var summary: Dictionary = {}
	if day < 0:
		if not company.history.is_empty():
			summary = company.history[-1]
	else:
		for s: Dictionary in company.history:
			if int(s.get("day", -999)) == day:
				summary = s
				break
	if summary.is_empty():
		return {"ok": false, "reason": "no_summary"}
	var stamp: int = int(summary.get("day", day))
	var ledger: Dictionary = summary.get("ledger", {})
	var ledger_sum: float = 0.0
	for k: StringName in ledger:
		ledger_sum += float(ledger[k])
	var profit: float = float(summary.get("profit", 0.0))
	var profit_ok: bool = is_equal_approx(ledger_sum, profit) or absf(ledger_sum - profit) < 0.01
	var company_sales: float = float(ledger.get(&"dine_in_sales", 0.0)) + float(ledger.get(&"delivery_sales", 0.0))
	var branch_sales: float = 0.0
	for rest: RestaurantState in company.restaurants:
		branch_sales += _branch_sales_for_day(rest.building_id, stamp)
	return {
		"ok": profit_ok,
		"day": stamp,
		"profit": profit,
		"ledger_sum": ledger_sum,
		"company_sales": company_sales,
		"branch_sales": branch_sales,
		"unassigned": company_sales - branch_sales,
	}


func _branch_sales_for_day(building_id: int, day: int) -> float:
	for row: Dictionary in _daily:
		if row["scope_kind"] == &"restaurant" and String(row["scope_id"]) == str(building_id) and int(row["day"]) == day:
			return float((row["metrics"] as Dictionary).get("sales", 0.0))
	return 0.0


# --- Rankings ----------------------------------------------------------------


func _reg(def: RankingDef) -> void:
	_ranking_registry[def.id] = def
	_ranking_order.append(def.id)


func _build_rankings() -> void:
	_reg(RankingDef.new(&"value", "Company Value", &"trophy", MetricDef.Unit.RAW,
		func(c: CompanyState, e: bool) -> float: return RivalIntel.score(c, e), 0.4))
	_reg(RankingDef.new(&"revenue", "Revenue", &"coin", MetricDef.Unit.MONEY,
		func(c: CompanyState, e: bool) -> float: return _rank_revenue(c, e), 0.2))
	_reg(RankingDef.new(&"profit", "Profit", &"bank", MetricDef.Unit.MONEY,
		func(c: CompanyState, e: bool) -> float: return _rank_profit(c, e), 0.2))
	_reg(RankingDef.new(&"market_share", "Market Share", &"chart_up", MetricDef.Unit.PERCENT,
		func(c: CompanyState, _e: bool) -> float: return _rank_market_share(c), 0.0))
	_reg(RankingDef.new(&"reputation", "Reputation", &"star", MetricDef.Unit.RATING,
		func(c: CompanyState, _e: bool) -> float: return RivalIntel.avg_rating(c), 0.2))
	_reg(RankingDef.new(&"delivery", "Delivery", &"scooter", MetricDef.Unit.PERCENT,
		func(c: CompanyState, _e: bool) -> float: return _rank_delivery(c), 0.0))
	_reg(RankingDef.new(&"recipe", "Recipe Popularity", &"pizza", MetricDef.Unit.COUNT,
		func(c: CompanyState, _e: bool) -> float: return _rank_recipe(c), 0.0))
	_reg(RankingDef.new(&"awards", "Awards", &"trophy", MetricDef.Unit.COUNT,
		func(c: CompanyState, _e: bool) -> float: return _rank_awards(c), 0.0))
	_reg(RankingDef.new(&"scenario", "Scenario Score", &"trophy", MetricDef.Unit.RAW,
		func(c: CompanyState, e: bool) -> float: return _scenario_score(c, e), 0.0))


func ranking_ids() -> Array[StringName]:
	return _ranking_order.duplicate()


func ranking_def(ranking_id: StringName) -> RankingDef:
	return _ranking_registry.get(ranking_id)


func rankings(ranking_id: StringName) -> Array[Dictionary]:
	var def: RankingDef = _ranking_registry.get(ranking_id)
	if def == null:
		return []
	var depth: int = _analytics_depth()
	var entries: Array[Dictionary] = []
	for company: CompanyState in CompanyManager.companies:
		if company.is_bankrupt:
			continue
		var exact: bool = company.is_player or depth >= 2
		entries.append({"c": company, "score": def.score(company, exact), "exact": exact})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"] if def.higher_is_better else a["score"] < b["score"])
	var result: Array[Dictionary] = []
	for i: int in entries.size():
		var e: Dictionary = entries[i]
		var c: CompanyState = e["c"]
		result.append({
			"rank": i + 1,
			"company_id": c.id,
			"display_name": c.display_name,
			"brand_color": c.brand_color,
			"is_player": c.is_player,
			"score": float(e["score"]),
			"estimated": not bool(e["exact"]) and not c.is_player,
			"movement": _ranking_movement(ranking_id, c.id),
			"strength": _known_strength(c),
			"unit": def.unit,
		})
	return result


## Rank climb since yesterday: positive = climbed. 0 when unknown.
func _ranking_movement(ranking_id: StringName, company_id: StringName) -> int:
	var y: Dictionary = _ranks_yesterday.get(ranking_id, {})
	var t: Dictionary = _ranks_today.get(ranking_id, {})
	if not y.has(company_id) or not t.has(company_id):
		return 0
	return int(y[company_id]) - int(t[company_id])


func _snapshot_ranks() -> void:
	_ranks_yesterday = _ranks_today.duplicate(true)
	_ranks_today = {}
	for rid: StringName in _ranking_order:
		var order: Array[Dictionary] = rankings(rid)
		var map: Dictionary = {}
		for entry: Dictionary in order:
			map[entry["company_id"]] = entry["rank"]
		_ranks_today[rid] = map


func _publish_rank_news(closed_day: int) -> void:
	var t: Dictionary = _ranks_today.get(&"value", {})
	var y: Dictionary = _ranks_yesterday.get(&"value", {})
	if y.is_empty():
		return
	for company: CompanyState in CompanyManager.companies:
		var prev: int = int(y.get(company.id, 0))
		var now: int = int(t.get(company.id, 0))
		if prev <= 0 or now <= 0 or prev == now or absi(prev - now) < _rank_news_threshold:
			continue
		var climbed: bool = now < prev
		if company.is_player:
			EconomyManager.post_message(
				"good" if climbed else "alert",
				"You %s to #%d in the city rankings." % ["climbed" if climbed else "slipped", now])
		record_event(BusinessEvent.RANK_CHANGE, company.id, {
			"amount": float(prev - now),
			"title": "%s %s to #%d" % [company.display_name, "climbed" if climbed else "slipped", now],
		})


func next_target(ranking_id: StringName, company_id: StringName) -> Dictionary:
	var order: Array[Dictionary] = rankings(ranking_id)
	var idx: int = -1
	for i: int in order.size():
		if order[i]["company_id"] == company_id:
			idx = i
			break
	if idx < 0:
		return {}
	if idx == 0:
		return {"leader": true, "rank": 1}
	var target: Dictionary = order[idx - 1]
	return {
		"leader": false,
		"rank": order[idx]["rank"],
		"target_name": target["display_name"],
		"target_rank": target["rank"],
		"gap": float(target["score"]) - float(order[idx]["score"]),
	}


func _analytics_depth() -> int:
	var player: CompanyState = CompanyManager.player
	if player == null:
		return 0
	if CapabilityRegistry.has_method("level"):
		return int(CapabilityRegistry.level(player.id, &"analytics.report_depth"))
	return 0


func _rank_revenue(c: CompanyState, exact: bool) -> float:
	if c.is_player or exact:
		return _exact_revenue_window(c)
	return RivalIntel.estimated_revenue(c, _market_window)


func _rank_profit(c: CompanyState, exact: bool) -> float:
	if c.is_player or exact:
		return sum_window(&"company", String(c.id), &"profit", _market_window)
	return RivalIntel.estimated_revenue(c, _market_window) * 0.15


func _rank_market_share(c: CompanyState) -> float:
	return _market_share(c)


func _rank_delivery(c: CompanyState) -> float:
	if c.is_player:
		var num: float = 0.0
		var den: int = 0
		for rest: RestaurantState in c.restaurants:
			var rows: Array[Dictionary] = _rows_for(&"restaurant", str(rest.building_id), &"day")
			var take: int = mini(WEEK_DAYS, rows.size())
			for i: int in range(rows.size() - take, rows.size()):
				num += 1.0 - float((rows[i]["metrics"] as Dictionary).get("delivery_fail_rate", 0.0))
				den += 1
		return (num / float(den)) if den > 0 else 0.0
	return clampf(RivalIntel.avg_rating(c) / 5.0, 0.0, 1.0)


func _rank_recipe(c: CompanyState) -> float:
	if c.is_player:
		var units: float = 0.0
		for rest: RestaurantState in c.restaurants:
			for key: String in rest.recipe_sales:
				units += float((rest.recipe_sales[key] as Dictionary).get("units", 0))
		return units
	var price: float = RivalIntel.avg_menu_price(c)
	return (RivalIntel.estimated_revenue(c, WEEK_DAYS) / price) if price > 0.0 else 0.0


func _scenario_score(c: CompanyState, exact: bool) -> float:
	var trophy_weight: float = float(EconomyManager.tuning_value("awards.scenario_weight_per_trophy", 1200.0))
	return _rank_profit(c, exact) * 0.5 + RivalIntel.avg_rating(c) * 2000.0 \
		+ float(c.restaurants.size()) * 1500.0 + _rank_awards(c) * trophy_weight


## Trophies and medals are public record — no exact/estimated gating.
func _rank_awards(c: CompanyState) -> float:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var awards: Node = tree.root.get_node_or_null(^"AwardsManager") if tree != null else null
	if awards == null:
		return 0.0
	return float(awards.trophies_for(c.id))


func _known_strength(c: CompanyState) -> String:
	var rating: float = RivalIntel.avg_rating(c)
	if rating >= 4.5:
		return "Top rating %.1f in the city" % rating
	if c.restaurants.size() >= 3:
		return "Widest network — %d branches" % c.restaurants.size()
	var price: float = RivalIntel.avg_menu_price(c)
	if price > 0.0 and price < 12.0:
		return "Value pricing (avg $%.0f)" % price
	return "Rating %.1f · %d branch%s" % [rating, c.restaurants.size(), "es" if c.restaurants.size() != 1 else ""]


# --- Save / load -------------------------------------------------------------


func write_save(save: SaveGame) -> void:
	save.set("analytics_schema_version", SCHEMA_VERSION)
	save.set("analytics_daily", _daily.duplicate(true))
	save.set("analytics_weekly", _weekly.duplicate(true))
	save.set("analytics_quarterly", _quarterly.duplicate(true))
	save.set("analytics_events", _events.duplicate(true))


func restore_from_save(save: SaveGame) -> void:
	_daily = _as_rows(save.get("analytics_daily"))
	_weekly = _as_rows(save.get("analytics_weekly"))
	_quarterly = _as_rows(save.get("analytics_quarterly"))
	_events = _as_rows(save.get("analytics_events"))


func _as_rows(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if value is Array:
		for e: Variant in value:
			if e is Dictionary:
				out.append(e)
	return out
