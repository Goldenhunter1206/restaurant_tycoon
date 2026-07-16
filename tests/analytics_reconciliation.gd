class_name AnalyticsReconciliation
extends RefCounted
## Static reconciliation + determinism suite for the analytics pipeline.
##
## Headless caveat: in `godot --headless --script` the main script's compile-time
## dependency tree is compiled BEFORE autoload globals are registered. CompanyState
## and RestaurantState transitively reference the CompanyManager autoload
## (RestaurantState.company()), and SaveGame references CompanyState — so naming any
## of them as a class here would fail to compile. We therefore build every such
## object via load(path).new() at RUN time (autoloads booted by then) and type
## loosely, and reach autoload singletons through the tree root — the sim_harness
## discipline. Only autoload-free classes (BusinessEvent) are referenced by name.
## Run via scripts/tests/test_analytics.gd.

const AM_SCRIPT: String = "res://scripts/autoload/analytics_manager.gd"
const CS_SCRIPT: String = "res://scripts/data/company_state.gd"
const RS_SCRIPT: String = "res://scripts/data/restaurant_state.gd"
const SG_SCRIPT: String = "res://scripts/data/save_game.gd"

static var _checks: int = 0


static func run() -> Dictionary:
	_checks = 0
	var failures: Array[String] = []
	_test_profit_reconciles(failures)
	_test_restaurant_totals(failures)
	_test_determinism_roundtrip(failures)
	_test_rankings_edge_cases(failures)
	_test_knowledge_gating(failures)
	_test_retention_bound(failures)
	return {"ok": failures.is_empty(), "checks": _checks, "failures": failures}


static func _expect(cond: bool, message: String, failures: Array[String]) -> void:
	_checks += 1
	if not cond:
		failures.append(message)


## Autoload globals are not identifiers at a --script main script's compile time,
## so reach the singletons through the tree root.
static func _autoload(node_name: String) -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(node_name)
	return null


# --- Builders (runtime load(), no compile-time class references) --------------


static func _new_manager() -> Node:
	var am: Node = load(AM_SCRIPT).new()
	am._enrich_enabled = false
	am._build_rankings()
	return am


static func _make_company(id: StringName, is_player: bool, reputation: float = 3.5) -> Object:
	var c: Object = load(CS_SCRIPT).new()
	c.id = id
	c.is_player = is_player
	c.display_name = String(id)
	c.reputation = reputation
	c.cash = 20000.0
	return c


static func _make_rest(company: Object, building_id: int, district: String) -> Object:
	var r: Object = load(RS_SCRIPT).new()
	r.building_id = building_id
	r.company_id = company.id
	r.district = district
	r.owned_outright = true  # no rent tuning lookups in tests
	r.star_rating = 4.0
	r.reset_today()
	company.restaurants.append(r)
	return r


# --- Tests -------------------------------------------------------------------


## Criterion 1: company profit == Σ ledger categories for the closed day.
static func _test_profit_reconciles(failures: Array[String]) -> void:
	var am: Node = _new_manager()
	var c: Object = _make_company(&"player", true)
	var r: Object = _make_rest(c, 101, "C")
	c.transact(&"dine_in_sales", 800.0)
	r.record_sale(800.0)
	c.transact(&"delivery_sales", 200.0)
	r.record_sale(200.0)
	r.today["expenses"] = 350.0
	c.transact(&"wages", -250.0)
	c.transact(&"rent", -100.0)
	c.close_day(2, 0.0, -50000.0)  # closes day 1
	am.snapshot_company(c, 1)
	am.snapshot_restaurant(c, r, 1)
	var rec: Dictionary = am.reconcile_company(c, 1)
	_expect(bool(rec.get("ok", false)), "profit did not reconcile with ledger", failures)
	_expect(is_equal_approx(float(rec.get("profit", 0.0)), 650.0), "profit expected 650, got %s" % rec.get("profit"), failures)
	_expect(is_equal_approx(float(rec.get("ledger_sum", 0.0)), 650.0), "ledger_sum expected 650, got %s" % rec.get("ledger_sum"), failures)
	var branch: Dictionary = am.restaurant_report(101)
	_expect(is_equal_approx(float((branch.get("metrics", {}) as Dictionary).get("sales", 0.0)), 1000.0), "branch sales expected 1000", failures)
	am.free()


## Criterion 2: Σ restaurant sales reconciles to company sales with an explicit
## corporate/unassigned remainder.
static func _test_restaurant_totals(failures: Array[String]) -> void:
	var am: Node = _new_manager()
	var c: Object = _make_company(&"player", true)
	var r1: Object = _make_rest(c, 201, "C")
	var r2: Object = _make_rest(c, 202, "N")
	r1.record_sale(500.0)
	r2.record_sale(300.0)
	# Company books 900 in dine-in sales — 100 is corporate/unassigned.
	c.transact(&"dine_in_sales", 900.0)
	c.close_day(2, 0.0, -50000.0)
	am.snapshot_company(c, 1)
	am.snapshot_restaurant(c, r1, 1)
	am.snapshot_restaurant(c, r2, 1)
	var rec: Dictionary = am.reconcile_company(c, 1)
	_expect(is_equal_approx(float(rec.get("branch_sales", 0.0)), 800.0), "branch_sales expected 800, got %s" % rec.get("branch_sales"), failures)
	_expect(is_equal_approx(float(rec.get("company_sales", 0.0)), 900.0), "company_sales expected 900, got %s" % rec.get("company_sales"), failures)
	_expect(is_equal_approx(float(rec.get("unassigned", 0.0)), 100.0), "unassigned remainder expected 100, got %s" % rec.get("unassigned"), failures)
	am.free()


## Criterion: filters/comparisons return deterministic values across save/load.
static func _test_determinism_roundtrip(failures: Array[String]) -> void:
	var am: Node = _new_manager()
	var c: Object = _make_company(&"player", true)
	var r: Object = _make_rest(c, 301, "C")
	for day: int in range(1, 6):
		r.reset_today()
		var sales: float = 100.0 * float(day)
		c.transact(&"dine_in_sales", sales)
		r.record_sale(sales)
		c.close_day(day + 1, 0.0, -50000.0)
		am.snapshot_company(c, day)
		am.snapshot_restaurant(c, r, day)
	var before: Array[float] = am.metric_series(&"revenue", &"company", "player", 10, &"day")
	var save: Object = load(SG_SCRIPT).new()
	am.write_save(save)
	var path: String = "user://test_analytics_roundtrip.tres"
	ResourceSaver.save(save, path)
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var am2: Node = _new_manager()
	am2.restore_from_save(loaded)
	var after: Array[float] = am2.metric_series(&"revenue", &"company", "player", 10, &"day")
	_expect(before.size() == 5, "expected 5 daily revenue points, got %d" % before.size(), failures)
	_expect(before == after, "series changed across save/load: %s vs %s" % [before, after], failures)
	_expect(is_equal_approx(am2.sum_window(&"company", "player", &"revenue", 10), 1500.0), "restored 10-day revenue sum expected 1500", failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	am.free()
	am2.free()


## Criterion: rankings handle ties, closures, new companies, and bankruptcies.
static func _test_rankings_edge_cases(failures: Array[String]) -> void:
	var am: Node = _new_manager()
	var cm: Node = _autoload("CompanyManager")
	var p: Object = _make_company(&"player", true, 4.0)
	_make_rest(p, 1, "C")
	var a: Object = _make_company(&"rivalA", false, 4.0)
	_make_rest(a, 2, "C")  # ties the player on reputation + branch count
	var b: Object = _make_company(&"rivalB", false, 2.0)
	var dead: Object = _make_company(&"rivalDead", false, 5.0)
	dead.is_bankrupt = true
	cm.companies.assign([p, a, b, dead])
	cm.player = p
	var ranks: Array = am.rankings(&"value")
	_expect(ranks.size() == 3, "bankrupt company must be excluded (got %d)" % ranks.size(), failures)
	_expect(String(ranks[-1]["company_id"]) == "rivalB", "lowest rank should be rivalB", failures)
	_expect(int(ranks[0]["rank"]) == 1 and int(ranks[1]["rank"]) == 2, "ranks must be dense/sequential", failures)
	var c2: Object = _make_company(&"rivalC", false, 4.5)
	_make_rest(c2, 3, "C")
	_make_rest(c2, 4, "C")
	cm.companies.assign([p, a, b, dead, c2])
	var ranks2: Array = am.rankings(&"value")
	_expect(ranks2.size() == 4, "newly added company must appear (got %d)" % ranks2.size(), failures)
	_expect(String(ranks2[0]["company_id"]) == "rivalC", "rivalC (2 branches, 4.5) should lead", failures)
	cm.companies.clear()
	am.free()


## Criterion: rival reports never expose data outside the knowledge rules.
static func _test_knowledge_gating(failures: Array[String]) -> void:
	var am: Node = _new_manager()
	var cm: Node = _autoload("CompanyManager")
	var p: Object = _make_company(&"player", true, 4.0)
	_make_rest(p, 1, "C")
	var rival: Object = _make_company(&"rivalX", false, 3.5)
	_make_rest(rival, 2, "C")
	cm.companies.assign([p, rival])
	cm.player = p
	for rid: StringName in [&"value", &"revenue", &"profit"]:
		var ranks: Array = am.rankings(rid)
		for entry: Dictionary in ranks:
			if bool(entry["is_player"]):
				_expect(not bool(entry["estimated"]), "player's own %s must be exact" % rid, failures)
			else:
				_expect(bool(entry["estimated"]), "rival %s must be flagged estimated at report_depth 0" % rid, failures)
	cm.companies.clear()
	am.free()


## Criterion: long sessions keep the event journal within its retention budget.
static func _test_retention_bound(failures: Array[String]) -> void:
	var am: Node = _new_manager()
	var gc: Node = _autoload("GameClock")
	var saved_day: int = int(gc.day)
	gc.day = 100
	for d: int in range(1, 101):
		am._events.append(BusinessEvent.make(BusinessEvent.DAY_CLOSE, &"player", d, 0, {}))
	am._trim_events()
	_expect(am._events.size() <= am._event_retention_days + 1, "events not trimmed: %d kept" % am._events.size(), failures)
	_expect(am._events_summarized > 0, "trimmed events were not counted as summarized", failures)
	gc.day = saved_day
	am.free()
