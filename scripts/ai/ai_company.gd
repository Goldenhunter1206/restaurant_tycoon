class_name AiCompany
extends RefCounted
## Layered planner for one rival company: strategic (daily), tactical (a few
## passes per day), incident response, and an execution queue that adds a
## human reaction delay. Decisions use only public information and the shared
## command layer, so the AI can't touch money or state the player couldn't.
## All randomness comes from a per-company seeded RNG — same seed, same game.

const JOURNAL_CAP: int = 60
const MINUTES_PER_DAY: int = 24 * 60
const DISTRICT_NAMES: Dictionary = {
	"C": "the City Center", "D": "Downtown", "N": "the Neighborhood",
	"R": "the Riverside", "P": "the Park quarter",
}

var company: CompanyState
var profile: CompetitorProfile
## Decision journal ring buffer (newest last): {day, minute, layer, chosen,
## considered, predicted, actual}. Runtime-only; powers debugging + intel.
var journal: Array[Dictionary] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Pending actions: {at: total_minute, kind, args, predicted}.
var _queue: Array[Dictionary] = []
var _cooldown_until: Dictionary = {}
var _menu_review_day: Dictionary = {}
var _tactical_hours: Array[int] = []


func setup(target: CompanyState, world_seed: int) -> void:
	company = target
	profile = target.profile
	_rng.seed = world_seed ^ hash(target.id)
	# Stagger tactical passes so rivals don't all act on the same hour.
	var shift: int = absi(int(hash(target.id))) % 3
	_tactical_hours = [8 + shift, 12 + shift, 16 + shift, 20 + shift]


# --- Clock hooks (fanned out by CompanyManager) -------------------------------


func on_minute() -> void:
	if _queue.is_empty():
		return
	var now: int = GameClock.total_minutes()
	for i: int in range(_queue.size() - 1, -1, -1):
		if int(_queue[i]["at"]) <= now:
			var item: Dictionary = _queue[i]
			_queue.remove_at(i)
			_execute(item)


func on_hour(day: int, hour: int) -> void:
	if company.is_bankrupt:
		return
	_respond_incidents()
	if hour in _tactical_hours:
		_plan_tactical(day)


func on_day(day: int) -> void:
	if company.is_bankrupt:
		return
	_plan_liquidity(day)
	_plan_expansion(day)


# --- Strategic planner ---------------------------------------------------------


func _plan_liquidity(day: int) -> void:
	var reserve: float = _cash_reserve_floor()
	if company.cash >= reserve:
		return
	var loan_max: float = float(EconomyManager.tuning_value("loan.max", 50000.0))
	var wanted: float = minf(reserve * 2.0 - company.cash, loan_max - company.loan)
	if wanted > 500.0:
		if company.take_loan(snappedf(wanted, 100.0), loan_max):
			_record("strategic", "take_loan $%.0f" % wanted, [], "restores cash reserve")
			return
	# Loans exhausted and still under water: shed the worst branch.
	if company.cash < 0.0 and company.restaurants.size() > 1:
		var worst: RestaurantState = _worst_branch()
		if worst != null and _branch_profit(worst, 5) < 0.0:
			_enqueue(&"close", {"building_id": worst.building_id},
				"stops the bleeding at %s" % worst.restaurant_name)


func _plan_expansion(day: int) -> void:
	var now: int = GameClock.total_minutes()
	if int(_cooldown_until.get(&"expansion", 0)) > now:
		return
	if company.restaurants.size() >= 2 + int(profile.expansion_appetite * 4.0):
		return
	# Appetite gates how often the company even looks at the market.
	if _rng.randf() > profile.expansion_appetite * 0.6:
		_record("strategic", "expansion deferred", [], "appetite roll failed")
		return
	var reserve: float = _cash_reserve_floor()
	var candidates: Array[Dictionary] = RestaurantManager.purchasable_buildings()
	if candidates.is_empty():
		return
	var pool: Array[Dictionary] = candidates.slice(0, mini(40, candidates.size()))
	var considered: Array = []
	var best: Dictionary = {}
	var best_score: float = 0.55
	for _i: int in mini(10, pool.size()):
		var info: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
		var building_id: int = int(info["id"])
		var fee: float = RestaurantManager.signing_fee_for(building_id)
		if company.cash - fee < reserve + 4000.0:
			continue
		var fit: float = _demographic_fit(building_id)
		var afford: float = clampf(1.0 - fee / maxf(company.cash - reserve, 1.0), -1.0, 1.0)
		var crowding: float = _competition_near(info) * 0.25
		var noise: float = _rng.randfn(0.0, _forecast_noise() * 0.4)
		var score: float = fit * 1.2 + afford * 0.8 - crowding + noise
		considered.append("%d:%.2f" % [building_id, score])
		if score > best_score:
			best_score = score
			best = info
	if best.is_empty():
		_record("strategic", "expansion: no viable location", considered, "")
		return
	var district: String = String(best.get("district", "N"))
	var branch_name: String = "%s — %s" % [company.display_name, DISTRICT_NAMES.get(district, "Riverside")]
	_enqueue(&"purchase", {"building_id": int(best["id"]), "name": branch_name},
		"opens a branch in %s (score %.2f)" % [DISTRICT_NAMES.get(district, district), best_score])
	_record("strategic", "expand to building %d" % int(best["id"]), considered,
		"score %.2f beats %.2f threshold" % [best_score, 0.55])
	var cooldown_days: float = lerpf(9.0, 3.0, profile.expansion_appetite)
	_cooldown_until[&"expansion"] = now + int(cooldown_days * MINUTES_PER_DAY)


# --- Tactical planner ----------------------------------------------------------


func _plan_tactical(day: int) -> void:
	for rest: RestaurantState in company.restaurants:
		_ensure_staffing(rest)
		_tune_menu(rest, day)
		_ensure_channels(rest)
		_consider_marketing(rest)


## Keeps the baseline crew: two cook/waiter pairs covering lunch + dinner,
## one driver once delivery makes sense. Rivals hire from the same public
## job market as the player — candidates they take are gone for everyone.
func _ensure_staffing(rest: RestaurantState) -> void:
	if company.cash < 2500.0:
		return
	var wanted: Array[Dictionary] = [
		{"type": &"cook", "count": 2, "shifts": [10.0, 14.0]},
		{"type": &"waiter", "count": 2, "shifts": [10.0, 14.0]},
	]
	if rest.delivery_enabled or _wants_delivery(rest):
		wanted.append({"type": &"driver", "count": 1, "shifts": [12.0]})
	# A deep kitchen queue justifies a third cook.
	if rest.cook_backlog.size() > 5:
		wanted[0]["count"] = 3
		wanted[0]["shifts"] = [10.0, 14.0, 12.0]
	for want: Dictionary in wanted:
		var type_id: StringName = want["type"]
		var have: int = _staff_count(rest, type_id)
		if have >= int(want["count"]):
			continue
		var candidate: JobCandidate = _pick_candidate(type_id)
		if candidate == null:
			continue
		var shifts: Array = want["shifts"]
		var shift_start: float = float(shifts[mini(have, shifts.size() - 1)])
		_enqueue(&"hire", {
			"building_id": rest.building_id,
			"candidate_uid": candidate.uid,
			"shift_start": shift_start,
		}, "fills a %s slot at %s" % [type_id, rest.restaurant_name])
		return  # One hire per pass per branch — no panic sprees.


## Skilled operators pick the best value-for-wage candidate; sloppy ones grab
## whoever is on top of the pile.
func _pick_candidate(type_id: StringName) -> JobCandidate:
	var pool: Array[JobCandidate] = RestaurantManager.candidates_for(type_id)
	if pool.is_empty():
		return null
	if _rng.randf() > profile.operational_skill:
		return pool[_rng.randi_range(0, pool.size() - 1)]
	var best: JobCandidate = null
	var best_value: float = -INF
	for cand: JobCandidate in pool:
		var total: float = 0.0
		for value: Variant in cand.attributes.values():
			total += float(value)
		var avg: float = total / maxf(1.0, float(cand.attributes.size()))
		var value_for_wage: float = avg / maxf(1.0, cand.hourly_wage)
		if value_for_wage > best_value:
			best_value = value_for_wage
			best = cand
	return best


## Re-prices and re-tiers the menu from the company's quality/price identity.
## Hysteresis: a branch menu is only touched every few days, so rivals don't
## thrash prices minute-to-minute.
func _tune_menu(rest: RestaurantState, day: int) -> void:
	if day - int(_menu_review_day.get(rest.building_id, -99)) < 3:
		return
	_menu_review_day[rest.building_id] = day
	var price_factor: float = lerpf(0.82, 1.28, profile.price_bias)
	var changed: int = 0
	for entry: MenuEntry in rest.menu:
		if not entry.enabled:
			continue
		var rec: RecipeDef = RecipeManager.recipe(entry.dish_id)
		if rec == null:
			continue
		var tier_id: StringName = _tier_for_bias(entry.dish_id)
		var suggested: float = RecipeManager.suggested_price_for(rec)
		var price: float = suggested * price_factor
		var tier: QualityTier = RecipeManager.tier_for(entry.dish_id, tier_id)
		if tier != null:
			price = maxf(price, tier.ingredient_cost * 1.2)  # Positive-margin guard.
		price = snappedf(price, 0.5)
		if absf(price - entry.price) < 0.5 and tier_id == entry.tier:
			continue
		RestaurantManager.set_menu_entry_cmd(company.id, rest.building_id,
			entry.dish_id, price, tier_id, true)
		changed += 1
	if changed > 0:
		_record("tactical", "re-priced %d dishes at %s" % [changed, rest.restaurant_name],
			[], "price factor %.2f" % price_factor)
		if profile.price_bias <= 0.35:
			_news("%s cut prices in %s." % [company.display_name, DISTRICT_NAMES.get(rest.district, "town")])


func _tier_for_bias(dish_id: StringName) -> StringName:
	var preferred: StringName = &"med"
	if profile.quality_bias < 0.35:
		preferred = &"low"
	elif profile.quality_bias > 0.7:
		preferred = &"high"
	if RecipeManager.tier_for(dish_id, preferred) != null:
		return preferred
	return &"med"


func _ensure_channels(rest: RestaurantState) -> void:
	if rest.delivery_enabled:
		return
	if not _wants_delivery(rest):
		return
	if _staff_count(rest, &"driver") > 0:
		RestaurantManager.set_channels_cmd(company.id, rest.building_id, true, true)
		RestaurantManager.set_delivery_cap_cmd(company.id, rest.building_id, 4)
		_record("tactical", "enabled delivery at %s" % rest.restaurant_name, [], "")
		_news("%s now delivers from %s." % [company.display_name, DISTRICT_NAMES.get(rest.district, "town")])


func _wants_delivery(_rest: RestaurantState) -> bool:
	return company.cash > 5000.0


## Marketing-minded companies buy local ad pushes when cash allows.
func _consider_marketing(rest: RestaurantState) -> void:
	if company.cash < 4000.0:
		return
	if _rng.randf() > profile.marketing_style * 0.35:
		return
	var campaign: MarketingCampaign = MarketingCampaign.new()
	campaign.company_id = company.id
	campaign.building_id = rest.building_id
	if not profile.target_demographics.is_empty():
		campaign.demographic = profile.target_demographics[_rng.randi_range(0, profile.target_demographics.size() - 1)]
	campaign.radius = 450.0
	campaign.utility_bonus = 0.1 + 0.1 * profile.marketing_style
	campaign.cost_per_day = snappedf(100.0 + 140.0 * profile.marketing_style, 5.0)
	campaign.days_left = 5
	var result: CommandResult = MarketingManager.start_campaign(campaign)
	if result.ok:
		_record("tactical", "ad campaign at %s" % rest.restaurant_name, [],
			"$%.0f/day for %d days" % [campaign.cost_per_day, campaign.days_left])
		_news("%s launched an ad campaign around %s." % [company.display_name,
			DISTRICT_NAMES.get(rest.district, "town")])


## Incident response to a competitor (player included) opening near one of
## our branches: aggressive companies cut prices, marketers counter-advertise.
func on_competitor_opened(new_rest: RestaurantState) -> void:
	if company.is_bankrupt or new_rest.company_id == company.id:
		return
	var threatened: RestaurantState = null
	for rest: RestaurantState in company.restaurants:
		if rest.door_pos.distance_to(new_rest.door_pos) < 300.0:
			threatened = rest
			break
	if threatened == null:
		return
	var now: int = GameClock.total_minutes()
	var gate: StringName = StringName("defend_%d" % threatened.building_id)
	if int(_cooldown_until.get(gate, 0)) > now:
		return
	if _rng.randf() > profile.aggression:
		_record("incident", "ignored competitor near %s" % threatened.restaurant_name, [],
			"aggression roll failed")
		return
	_cooldown_until[gate] = now + 2 * MINUTES_PER_DAY
	if profile.marketing_style > 0.55 and company.cash > 4000.0:
		_consider_marketing(threatened)
		_record("incident", "counter-marketing at %s" % threatened.restaurant_name, [],
			"competitor opened nearby")
	else:
		_enqueue(&"defend_prices", {"building_id": threatened.building_id},
			"undercuts the newcomer near %s" % threatened.restaurant_name)
		_record("incident", "price defense at %s" % threatened.restaurant_name, [],
			"competitor opened nearby")


# --- Incident responder ----------------------------------------------------------


func _respond_incidents() -> void:
	# Cash panic: immediate emergency loan, no reaction delay — but at most
	# once per day, so a doomed company can't drain the credit line in hours.
	if company.cash < 300.0:
		var now: int = GameClock.total_minutes()
		if int(_cooldown_until.get(&"emergency_loan", 0)) > now:
			return
		var loan_max: float = float(EconomyManager.tuning_value("loan.max", 50000.0))
		if company.take_loan(minf(3000.0, loan_max - company.loan), loan_max):
			_cooldown_until[&"emergency_loan"] = now + MINUTES_PER_DAY
			_record("incident", "emergency loan", [], "cash was $%.0f" % company.cash)


# --- Execution queue ---------------------------------------------------------------


func _enqueue(kind: StringName, args: Dictionary, predicted: String) -> void:
	for item: Dictionary in _queue:
		if item["kind"] == kind and item["args"] == args:
			return  # Already planned.
	_queue.append({
		"at": GameClock.total_minutes() + _reaction_delay(),
		"kind": kind,
		"args": args,
		"predicted": predicted,
	})


func _execute(item: Dictionary) -> void:
	if company.is_bankrupt:
		return
	var args: Dictionary = item["args"]
	match StringName(item["kind"]):
		&"purchase":
			var result: CommandResult = RestaurantManager.purchase_location(
				company.id, int(args["building_id"]), String(args["name"]))
			if result.ok:
				var rest: RestaurantState = result.payload
				_setup_new_branch(rest)
				_news("%s opened %s in %s." % [company.display_name,
					rest.restaurant_name, DISTRICT_NAMES.get(rest.district, "town")])
			_record_outcome(item, result)
		&"close":
			var rest: RestaurantState = RestaurantManager.by_building.get(int(args["building_id"]))
			var branch_name: String = rest.restaurant_name if rest != null else "a branch"
			var district: String = rest.district if rest != null else "N"
			var result: CommandResult = RestaurantManager.close_branch(company.id, int(args["building_id"]))
			if result.ok:
				_news("%s closed %s in %s." % [company.display_name, branch_name,
					DISTRICT_NAMES.get(district, "town")])
			_record_outcome(item, result)
		&"hire":
			var result: CommandResult = RestaurantManager.hire(company.id,
				int(args["building_id"]), int(args["candidate_uid"]),
				float(args["shift_start"]))
			_record_outcome(item, result)
		&"defend_prices":
			var rest: RestaurantState = RestaurantManager.by_building.get(int(args["building_id"]))
			if rest == null or rest.company_id != company.id:
				return
			var cut: int = 0
			for entry: MenuEntry in rest.menu:
				if not entry.enabled:
					continue
				var price: float = entry.price * 0.9
				var tier: QualityTier = RecipeManager.tier_for(entry.dish_id, entry.tier)
				if tier != null:
					price = maxf(price, tier.ingredient_cost * 1.15)
				RestaurantManager.set_menu_entry_cmd(company.id, rest.building_id,
					entry.dish_id, snappedf(price, 0.5), entry.tier, true)
				cut += 1
			if cut > 0:
				_news("%s cut prices near %s." % [company.display_name,
					DISTRICT_NAMES.get(rest.district, "town")])
			_record_outcome(item, CommandResult.good(cut))


## Fresh branch defaults: dine-in only, standard hours; staff arrive via the
## next tactical passes because hiring runs through the shared job market.
func _setup_new_branch(rest: RestaurantState) -> void:
	var open_hour: float = 11.0 if profile.price_bias > 0.7 else 10.0
	RestaurantManager.set_hours_cmd(company.id, rest.building_id, open_hour, 22.0)
	RestaurantManager.set_channels_cmd(company.id, rest.building_id, true, false)
	_menu_review_day.erase(rest.building_id)


# --- Journal & helpers ---------------------------------------------------------


func _record(layer: String, chosen: String, considered: Array, predicted: String) -> void:
	journal.append({
		"day": GameClock.day,
		"minute": GameClock.total_minutes(),
		"layer": layer,
		"chosen": chosen,
		"considered": considered,
		"predicted": predicted,
	})
	while journal.size() > JOURNAL_CAP:
		journal.remove_at(0)


func _record_outcome(item: Dictionary, result: CommandResult) -> void:
	journal.append({
		"day": GameClock.day,
		"minute": GameClock.total_minutes(),
		"layer": "execute",
		"chosen": "%s %s" % [item["kind"], item["args"]],
		"considered": [],
		"predicted": item["predicted"],
		"actual": "ok" if result.ok else String(result.code),
	})
	while journal.size() > JOURNAL_CAP:
		journal.remove_at(0)


func _news(text: String) -> void:
	company.log_move(GameClock.day, "news", text)
	company.message.emit("news", text)


func _cash_reserve_floor() -> float:
	return 1500.0 + 4500.0 * (1.0 - profile.risk_tolerance)


func _reaction_delay() -> int:
	var scale: float = 1.0
	match GameSetup.difficulty:
		&"easy":
			scale = 1.5
		&"hard":
			scale = 0.7
	var jitter: float = 1.0 + _rng.randf_range(-profile.planning_noise, profile.planning_noise)
	return maxi(10, int(float(profile.reaction_delay_min) * scale * jitter))


func _forecast_noise() -> float:
	var accuracy: float = profile.forecast_accuracy
	match GameSetup.difficulty:
		&"easy":
			accuracy *= 0.85
		&"hard":
			accuracy = minf(1.0, accuracy + 0.1)
	return 1.0 - accuracy


func _demographic_fit(building_id: int) -> float:
	if profile.target_demographics.is_empty():
		return 0.55
	var mix: Dictionary = DemandManager.customer_profile(building_id)
	if mix.is_empty():
		return 0.4
	var total: float = 0.0
	for demo: StringName in profile.target_demographics:
		total += float(mix.get(demo, 0.0))
	return clampf(total * 2.2, 0.0, 1.0)


func _competition_near(info: Dictionary) -> float:
	var pos: Vector3 = info.get("door_pos", info.get("position", Vector3.ZERO))
	var count: int = 0
	for rest: RestaurantState in RestaurantManager.all_restaurants():
		if rest.door_pos.distance_to(pos) < 250.0:
			count += 1
	return float(count)


func _staff_count(rest: RestaurantState, type_id: StringName) -> int:
	var count: int = 0
	for member: StaffMember in rest.staff:
		if member.type_id == type_id:
			count += 1
	return count


func _branch_profit(rest: RestaurantState, days: int) -> float:
	var total: float = 0.0
	var count: int = mini(days, rest.sales_history.size())
	for i: int in count:
		var idx: int = rest.sales_history.size() - 1 - i
		total += rest.sales_history[idx]
		if idx < rest.expense_history.size():
			total -= rest.expense_history[idx]
	return total


func _worst_branch() -> RestaurantState:
	var worst: RestaurantState = null
	var worst_profit: float = INF
	for rest: RestaurantState in company.restaurants:
		var profit: float = _branch_profit(rest, 5)
		if profit < worst_profit:
			worst_profit = profit
			worst = rest
	return worst
