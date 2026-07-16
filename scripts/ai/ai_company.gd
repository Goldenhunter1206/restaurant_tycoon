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
## building_id -> true once its supply policies match this rival's style.
var _procurement_tuned: Dictionary = {}


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
	_plan_procurement(day)
	_plan_workforce(day)
	_consider_headquarters(day)
	_consider_competition(day)
	_plan_security(day)
	_plan_underworld(day)
	_plan_civic(day)


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


## Rivals invest in their people too: retain an at-risk employee or develop an
## under-skilled one. Gated by operational skill so weak rivals neglect staff.
func _plan_workforce(day: int) -> void:
	if company.restaurants.is_empty():
		return
	if _rng.randf() > profile.operational_skill * 0.5:
		return
	var rest: RestaurantState = company.restaurants[_rng.randi_range(0, company.restaurants.size() - 1)]
	var at_risk: StaffMember = null
	for member: StaffMember in rest.staff:
		if member.resignation_committed_day >= 0:
			continue
		if at_risk == null or member.resignation_risk > at_risk.resignation_risk:
			at_risk = member
	if at_risk != null and at_risk.resignation_risk >= 0.45:
		_command(&"staff.set_contract", {
			"building_id": rest.building_id,
			"staff_uid": at_risk.uid,
			"contract_type": at_risk.contract_type,
			"hourly_wage": snappedf(at_risk.hourly_wage * 1.08, 0.05),
			"overtime_allowed": at_risk.overtime_allowed,
			"maximum_overtime_hours": at_risk.maximum_overtime_hours,
		}, "retain:%d:%d" % [at_risk.uid, day])
		return
	var staff_mgr: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/StaffManager")
	if staff_mgr == null:
		return
	var hint: Dictionary = staff_mgr.suggest_training(company.id, rest.building_id)
	if not hint.is_empty():
		_command(&"staff.train", {
			"building_id": rest.building_id,
			"staff_uid": int(hint.get("staff_uid", -1)),
			"program_id": StringName(hint.get("program_id", &"")),
		}, "train:%d:%d" % [int(hint.get("staff_uid", -1)), day])


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
		_consider_interior(rest, day)


## Rivals invest in their rooms too: keep furniture repaired via policy, and
## once cash allows, upgrade to a better designer set. Runs headlessly —
## evaluation never touches the 3D scene.
func _consider_interior(rest: RestaurantState, day: int) -> void:
	if rest.repair_policy != &"auto":
		_command(&"furniture.set_repair_policy", {"building_id": rest.building_id, "policy": &"auto", "threshold": 0.5}, "repair-policy:%d" % rest.building_id)
	# Weekly (staggered per branch) look at a richer template.
	if (day + rest.building_id) % 7 != 0 or company.cash < 6000.0:
		return
	var pick: InteriorTemplateDef = RestaurantManager.interior.choose_template_for(rest, company.cash * 0.35)
	if pick == null:
		return
	# Skip when the room already scores at least as well as the candidate.
	var current: InteriorEvaluation = RestaurantManager.interior.evaluate(rest.interior_layout)
	var candidate: InteriorEvaluation = RestaurantManager.interior.evaluate(pick.build_layout())
	var current_sum: float = 0.0
	var candidate_sum: float = 0.0
	for value: float in current.segment_appeal.values():
		current_sum += value
	for value: float in candidate.segment_appeal.values():
		candidate_sum += value
	if candidate_sum <= current_sum + 0.5 or candidate.table_seats.size() < current.table_seats.size():
		return
	var result: CommandResult = _command(&"layout.apply_template", {"building_id": rest.building_id, "template_id": pick.id}, "layout:%d:%s" % [rest.building_id, pick.id])
	if result.ok:
		_record("interior", String(pick.id), [], "appeal %.1f -> %.1f" % [current_sum, candidate_sum])


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
		_command(&"menu.set_entry", {"building_id": rest.building_id, "dish_id": entry.dish_id, "price": price, "tier": tier_id, "enabled": true}, "menu:%d:%s" % [rest.building_id, entry.dish_id])
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
		_command(&"restaurant.set_channels", {"building_id": rest.building_id, "dine_in": true, "delivery": true}, "channels:%d" % rest.building_id)
		_command(&"delivery.set_cap", {"building_id": rest.building_id, "cap": 4}, "delivery-cap:%d" % rest.building_id)
		_record("tactical", "enabled delivery at %s" % rest.restaurant_name, [], "")
		_news("%s now delivers from %s." % [company.display_name, DISTRICT_NAMES.get(rest.district, "town")])


func _wants_delivery(_rest: RestaurantState) -> bool:
	return company.cash > 5000.0


## Marketing-minded companies buy ad pushes when cash allows: channel scale
## follows marketing_style + unlocked capabilities, claims are only made when
## true, and the decision uses the same preview as the player — degraded by
## the profile's forecast accuracy.
func _consider_marketing(rest: RestaurantState) -> void:
	if company.cash < 4000.0:
		return
	if _rng.randf() > profile.marketing_style * 0.35:
		return
	var campaign: MarketingCampaign = _design_campaign(rest)
	var def: MarketingChannelDef = MarketingManager.channel(campaign.channel_id)
	# Judge estimated cost per reached person with imperfect information.
	var preview: Dictionary = MarketingManager.preview(campaign, _forecast_noise())
	var people: int = int(preview.get("people", 0))
	if people <= 0:
		return
	var cost_per_head: float = float(preview.get("total_cost", 0.0)) / people
	if cost_per_head > 15.0 + 25.0 * profile.risk_tolerance:
		return
	if float(preview.get("total_cost", 0.0)) > company.cash * 0.35:
		return
	if def != null and def.needs_placement:
		var site: AdPlacement = _pick_billboard_site(rest)
		if site == null:
			return
		var rent: CommandResult = MarketingManager.rent_placement(company.id, site.id, campaign.days_left + 7)
		if not rent.ok:
			return
		campaign.placement_ids = [site.id] as Array[int]
	var result: CommandResult = _command(&"marketing.start_local", {"building_id": rest.building_id, "campaign": campaign, "exact_cost": campaign.cost_per_day}, "marketing:%d:%s" % [rest.building_id, campaign.channel_id])
	if result.ok:
		_record("tactical", "%s campaign at %s" % [campaign.channel_id, rest.restaurant_name], [],
			"$%.0f/day for %d days" % [campaign.cost_per_day, campaign.days_left])
		_news("%s launched a %s campaign around %s." % [company.display_name,
			String(campaign.channel_id).replace("_", " "),
			DISTRICT_NAMES.get(rest.district, "town")])


## Build the campaign the profile would want: biggest unlocked channel it can
## fund (scaled by marketing_style), truthful claim matching its identity.
func _design_campaign(rest: RestaurantState) -> MarketingCampaign:
	var campaign: MarketingCampaign = MarketingCampaign.new()
	campaign.company_id = company.id
	campaign.building_id = rest.building_id
	campaign.channel_id = &"flyer"
	if profile.marketing_style > 0.65 and company.cash > 25000.0 \
			and CapabilityRegistry.has(company.id, &"marketing.citywide") \
			and MarketingManager.channel(&"radio") != null:
		campaign.channel_id = &"radio"
		campaign.building_id = -1
	elif profile.marketing_style > 0.45 and company.cash > 10000.0 \
			and CapabilityRegistry.has(company.id, &"marketing.billboards") \
			and MarketingManager.channel(&"billboard") != null:
		campaign.channel_id = &"billboard"
		campaign.building_id = -1
	elif profile.marketing_style > 0.55 and company.cash > 8000.0 \
			and MarketingManager.channel(&"poster") != null \
			and CapabilityRegistry.has(company.id, &"marketing.billboards"):
		campaign.channel_id = &"poster"
	campaign.target_segments = profile.target_demographics.duplicate()
	campaign.utility_bonus = 0.1 + 0.1 * profile.marketing_style
	campaign.intensity = clampf(0.75 + 0.75 * profile.marketing_style, 0.5, 2.0)
	campaign.days_left = 5 + int(profile.marketing_style * 9.0)
	var def: MarketingChannelDef = MarketingManager.channel(campaign.channel_id)
	if def != null:
		campaign.radius = def.base_radius
		campaign.days_left = clampi(campaign.days_left, def.min_days, def.max_days)
	campaign.claim = _pick_truthful_claim()
	return campaign


## Claims consistent with the profile's identity — and only when actually
## true today, so credibility holds.
func _pick_truthful_claim() -> StringName:
	var wanted: Array[StringName] = []
	if profile.price_bias < 0.35:
		wanted.append(&"lowest_price")
	if profile.quality_bias > 0.6:
		wanted.append(&"highest_quality")
	if profile.operational_skill > 0.7:
		wanted.append(&"best_staff")
	for claim: StringName in wanted:
		if MarketingManager.claim_check(company.id, claim):
			return claim
	return &""


## Prefer a vacant site near our branch; marketers also grab sites in
## districts where a competitor operates (contention).
func _pick_billboard_site(rest: RestaurantState) -> AdPlacement:
	var vacant: Array[AdPlacement] = MarketingManager.vacant_placements()
	if vacant.is_empty():
		return null
	var best: AdPlacement = null
	var best_score: float = -INF
	for site: AdPlacement in vacant:
		var score: float = -site.rent_per_day * 0.01
		score -= site.world_pos.distance_to(rest.door_pos) * 0.002
		if profile.aggression > 0.55:
			for other: CompanyState in CompanyManager.companies:
				if other.id == company.id:
					continue
				for other_rest: RestaurantState in other.restaurants:
					if other_rest.district == site.district:
						score += 0.5
		score += _rng.randf() * profile.planning_noise * 2.0
		if score > best_score:
			best_score = score
			best = site
	return best


## A competitor named us in a comparison ad — marketers answer with their own
## campaign, everyone remembers it in the log.
func on_rival_comparison(campaign: MarketingCampaign) -> void:
	if company.is_bankrupt or company.restaurants.is_empty():
		return
	var now: int = GameClock.total_minutes()
	if int(_cooldown_until.get(&"comparison_reply", 0)) > now:
		return
	_cooldown_until[&"comparison_reply"] = now + 2 * MINUTES_PER_DAY
	_record("incident", "named in a comparison ad by %s" % campaign.company_id, [], "")
	if profile.marketing_style > 0.4 and company.cash > 4000.0:
		_consider_marketing(company.restaurants[0])


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
			var candidate_uid: int = int(args["candidate_uid"])
			var candidate: JobCandidate = null
			for market_candidate: JobCandidate in RestaurantManager.job_market:
				if market_candidate.uid == candidate_uid:
					candidate = market_candidate
					break
			var result: CommandResult = CommandResult.fail(&"candidate_gone", "Candidate is no longer available.")
			if candidate != null:
				result = _command(&"staff.hire", {"building_id": int(args["building_id"]), "candidate_uid": candidate.uid, "offer": {"hourly_wage": candidate.hourly_wage, "shift_start": float(args["shift_start"]), "shift_hours": 8.0, "contract_type": &"permanent"}}, "hire:%d" % candidate.uid)
			_record_outcome(item, result)
		&"enter_competition":
			var awards: Node = _awards_manager()
			var result: CommandResult = CommandResult.fail(&"router_unavailable", "Awards system unavailable.")
			if awards != null:
				var entry_recipe: RecipeDef = null
				for pool_recipe: RecipeDef in RecipeManager.rival_recipe_pool():
					if pool_recipe.id == StringName(args["recipe_id"]):
						entry_recipe = pool_recipe
						break
				result = awards.enter_competition(
					company.id, int(args["uid"]), entry_recipe, StringName(args["tier"]))
				if result.ok:
					_news("%s entered the %s." % [company.display_name, String(args.get("label", "contest"))])
			_record_outcome(item, result)
		&"buy_warehouse":
			var result: CommandResult = SupplyManager.buy_warehouse_cmd(company.id, int(args["building_id"]))
			if result.ok and result.payload is WarehouseState:
				var wh: WarehouseState = result.payload
				# Route every branch through the new warehouse.
				for rest: RestaurantState in company.restaurants:
					SupplyManager.assign_restaurant_cmd(company.id, wh.id, rest.building_id, true)
				_news("%s opened a central warehouse." % company.display_name)
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
				_command(&"menu.set_entry", {"building_id": rest.building_id, "dish_id": entry.dish_id, "price": snappedf(price, 0.5), "tier": entry.tier, "enabled": true}, "defend-price:%d:%s" % [rest.building_id, entry.dish_id])
				cut += 1
			if cut > 0:
				_news("%s cut prices near %s." % [company.display_name,
					DISTRICT_NAMES.get(rest.district, "town")])
			_record_outcome(item, CommandResult.good(cut))


## Procurement strategy: bias each branch's supply policies to this rival's
## cheap-vs-premium style and safety-stock appetite, then consider a central
## warehouse once it runs two or more branches. All via the shared commands.
func _plan_procurement(_day: int) -> void:
	for rest: RestaurantState in company.restaurants:
		if _procurement_tuned.has(rest.building_id):
			continue
		_procurement_tuned[rest.building_id] = true
		var inv: InventoryState = SupplyManager.inventory_for_restaurant(rest)
		for ing: StringName in inv.policies.keys():
			var policy: ReorderPolicy = inv.policies[ing]
			var supplier: SupplierDef = SupplyManager.supplier_for_style(ing, profile.procurement_style)
			_command(&"inventory.set_policy", {"building_id": rest.building_id, "ingredient_id": ing, "fields": {
				"preferred_supplier": supplier.id if supplier != null else &"",
				"target_stock": ceilf(policy.target_stock * profile.safety_stock_bias),
				"reorder_point": ceilf(policy.reorder_point * profile.safety_stock_bias),
				"mode": &"automatic",
			}}, "supply-policy:%d:%s" % [rest.building_id, ing])
	# Warehouse consideration.
	var now: int = GameClock.total_minutes()
	if int(_cooldown_until.get(&"warehouse", 0)) > now:
		return
	if company.restaurants.size() < 2:
		return
	if not CapabilityRegistry.has(company.id, &"supply.warehouses"):
		return
	if not SupplyManager.warehouses_of(company.id).is_empty():
		return
	if _rng.randf() > profile.warehouse_appetite:
		return
	var price: float = SupplyManager.warehouse_price()
	if company.cash - price < _cash_reserve_floor():
		return
	var buildable: Array[Dictionary] = SupplyManager.purchasable_warehouse_buildings()
	if buildable.is_empty():
		return
	var target: Dictionary = buildable[_rng.randi_range(0, buildable.size() - 1)]
	_enqueue(&"buy_warehouse", {"building_id": int(target["id"])}, "opens a central warehouse")
	_record("strategic", "buy warehouse #%d" % int(target["id"]), [],
		"warehouse_appetite %.2f" % profile.warehouse_appetite)
	_cooldown_until[&"warehouse"] = now + 12 * MINUTES_PER_DAY


## Fresh branch defaults: dine-in only, standard hours; staff arrive via the
## next tactical passes because hiring runs through the shared job market.
func _setup_new_branch(rest: RestaurantState) -> void:
	var open_hour: float = 11.0 if profile.price_bias > 0.7 else 10.0
	_command(&"restaurant.set_hours", {"building_id": rest.building_id, "open_hour": open_hour, "close_hour": 22.0}, "hours:%d" % rest.building_id)
	_command(&"restaurant.set_channels", {"building_id": rest.building_id, "dine_in": true, "delivery": false}, "channels:%d" % rest.building_id)
	_menu_review_day.erase(rest.building_id)
	_command(&"furniture.set_repair_policy", {"building_id": rest.building_id, "policy": &"auto", "threshold": 0.5}, "repair-policy:%d" % rest.building_id)
	# Fit the branch with the best designer set the war chest allows.
	var pick: InteriorTemplateDef = RestaurantManager.interior.choose_template_for(rest, company.cash * 0.35)
	if pick != null:
		var result: CommandResult = _command(&"layout.apply_template", {"building_id": rest.building_id, "template_id": pick.id}, "layout:%d:%s" % [rest.building_id, pick.id])
		if result.ok:
			_record("interior", String(pick.id), [], "furnished new branch")


func _command(command_id: StringName, arguments: Dictionary, suffix: String) -> CommandResult:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return CommandResult.fail(&"router_unavailable", "The command router is unavailable.")
	var router: Node = tree.root.get_node_or_null("/root/BranchCommandRouter")
	if router == null:
		return CommandResult.fail(&"router_unavailable", "The command router is unavailable.")
	return router.call(
		"execute",
		command_id,
		arguments,
		{"kind": &"ai", "id": String(company.id), "company_id": company.id},
		"ai:%s:%d:%s:%s" % [company.id, GameClock.total_minutes(), command_id, suffix]) as CommandResult


# --- Journal & helpers ---------------------------------------------------------


# --- Competitions ---------------------------------------------------------------


## Enter open recipe competitions when the profile's appetite, the expected
## score, and the fee line up. Direct challenges are always answered. Rivals
## cook from the shared starter pool (no per-company recipe books yet).
func _consider_competition(_day: int) -> void:
	var awards: Node = _awards_manager()
	if awards == null:
		return
	for comp: CompetitionState in awards.active_competitions():
		if comp.status != &"entry" or comp.has_entry(company.id):
			continue
		var def: CompetitionDef = awards.competition_defs.get(comp.def_id)
		if def == null:
			continue
		if company.cash - def.entry_fee < _cash_reserve_floor():
			continue
		var challenged: bool = comp.challengee_id == company.id or comp.challenger_id == company.id
		if not challenged and _rng.randf() > profile.competition_appetite:
			_record("strategic", "skip %s" % def.display_name, [], "competition appetite roll failed")
			continue
		var pick: Dictionary = _pick_competition_entry(def)
		if pick.is_empty():
			continue
		var recipe: RecipeDef = pick["recipe"]
		# Imperfect information: the rival judges its own chances through noise.
		var expected: float = clampf(float(pick["expected"]) + _rng.randfn(0.0, _forecast_noise() * 0.2), 0.0, 1.0)
		if not challenged and expected * def.reward_cash <= def.entry_fee:
			_record("strategic", "skip %s" % def.display_name, [],
				"expected %.2f not worth the $%.0f fee" % [expected, def.entry_fee])
			continue
		_enqueue(&"enter_competition", {
			"uid": comp.uid, "recipe_id": recipe.id, "tier": pick["tier"], "label": def.display_name,
		}, "enters %s with %s (expected %.2f)" % [def.display_name, recipe.display_name, expected])


## Best starter-pool recipe/tier for the brief: target-segment appeal plus
## constraint compliance (novelty is unknowable before entries lock).
func _pick_competition_entry(def: CompetitionDef) -> Dictionary:
	var probe: CompetitionJudge = CompetitionJudge.new()
	var best: Dictionary = {}
	var best_score: float = -1.0
	for recipe: RecipeDef in RecipeManager.rival_recipe_pool():
		if def.product_type != &"" and recipe.product_type != def.product_type:
			continue
		var comply: float = float(probe.compliance(recipe, def)["score"])
		for tier_def: QualityTier in RecipeManager.tiers_for(recipe.id):
			var scored: Dictionary = RecipeManager.score(recipe, tier_def.tier)
			var appeal: float = float(scored.get("overall", 0.5))
			if not def.target_demographics.is_empty():
				var by_segment: Dictionary = scored.get("by_segment", {})
				appeal = 0.0
				for segment: StringName in def.target_demographics:
					appeal += float(by_segment.get(segment, 0.5))
				appeal /= def.target_demographics.size()
			var expected: float = 0.6 * appeal + 0.25 * comply + 0.075
			if expected > best_score:
				best_score = expected
				best = {"recipe": recipe, "tier": tier_def.tier, "expected": expected}
	return best


func _awards_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(^"AwardsManager")


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


func _consider_headquarters(day: int) -> void:
	# Strategic construction is intentionally staggered so rivals do not all buy
	# offices on the same tick. Every action still goes through the player commands.
	if (day + absi(hash(company.id))) % 7 != 0:
		return
	var manager: Node = Engine.get_main_loop().root.get_node_or_null("HeadquartersManager")
	if not is_instance_valid(manager):
		return
	var state: HeadquartersState = manager.call("state_for", company.id) as HeadquartersState
	if state == null or state.has_active_project():
		return
	var current_upkeep: float = float(manager.call("upkeep_for", company.id))
	var reserve: float = _cash_reserve_floor() + current_upkeep * 7.0
	if state.tier == 0:
		var offices: Array = manager.call("eligible_buildings", company.id)
		if offices.is_empty() or company.cash - 6000.0 < reserve + 560.0:
			return
		var office: Dictionary = offices[_rng.randi_range(0, offices.size() - 1)]
		var acquisition: CommandResult = manager.call("start_acquisition_cmd", company.id, int(office.get("id", -1))) as CommandResult
		if acquisition != null and acquisition.ok:
			_news("%s secured an office for its new headquarters." % company.name)
		return

	var next_tier: HeadquartersTierDef = manager.call("tier_def", state.tier + 1) as HeadquartersTierDef
	if next_tier != null:
		var tier_reserve: float = _cash_reserve_floor() + next_tier.base_upkeep * 7.0
		if company.cash - next_tier.cost >= tier_reserve:
			var tier_result: CommandResult = manager.call("start_tier_upgrade_cmd", company.id) as CommandResult
			if tier_result != null and tier_result.ok:
				_news("%s began expanding its headquarters." % company.name)
				return

	var choices: Array[Dictionary] = [
		{"id": &"marketing", "score": profile.marketing_style},
		{"id": &"operations", "score": profile.operational_skill},
		{"id": &"analytics", "score": profile.forecast_accuracy},
		{"id": &"procurement", "score": (profile.procurement_style + profile.warehouse_appetite) * 0.5},
		{"id": &"security", "score": 0.3 + 0.4 * profile.operational_skill},
		{"id": &"underworld", "score": profile.crime_appetite},
		{"id": &"government", "score": 0.25 + 0.5 * profile.corruption_appetite},
	]
	choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	for choice: Dictionary in choices:
		var definition: DepartmentDef = manager.call("department_def", choice["id"]) as DepartmentDef
		if definition == null:
			continue
		var next_level: int = state.department_level(definition.id) + 1
		if next_level > definition.max_level() or state.tier < definition.required_tier_for(next_level):
			continue
		var projected_upkeep: float = current_upkeep + definition.upkeep_for(next_level) - definition.upkeep_for(next_level - 1)
		var cost: float = definition.cost_for(next_level)
		if company.cash - cost < _cash_reserve_floor() + projected_upkeep * 7.0:
			continue
		var result: CommandResult = manager.call("start_department_project_cmd", company.id, definition.id) as CommandResult
		if result != null and result.ok:
			return


# --- Underworld & security (feature 12) ----------------------------------------


func _crime_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("CrimeManager")


func _government_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("GovernmentManager")


# --- Civic planner (feature 13) -------------------------------------------------


## Compliance first (diligence-driven), influence second (appetite-driven).
## Same commands and costs as the player; bounded by cash reserve, scrutiny
## and the scenario's corruption mode.
func _plan_civic(day: int) -> void:
	var gov: Node = _government_manager()
	if gov == null or not gov.call("enabled") or company.is_bankrupt:
		return
	var civic: Resource = gov.call("civic_for", company.id)
	if civic == null:
		return
	var reserve: float = maxf(_cash_reserve_floor(),
		float(_tuning("government.ai.min_cash_reserve", 6000.0)))
	if _rng.randf() < profile.compliance_diligence:
		_civic_comply(gov, civic, reserve)
	if (day + absi(hash(company.id))) % 4 != 0:
		return
	if profile.corruption_appetite <= 0.05 or company.cash < reserve:
		return
	_civic_influence(gov, civic, reserve)


func _civic_comply(gov: Node, civic: Resource, reserve: float) -> void:
	# Fix violations whose underlying fact has recovered (repairs/restock ran).
	for row: Dictionary in civic.call("open_violations"):
		var fix: CommandResult = gov.call("fix_violation_cmd", company.id, int(row.get("uid", -1)))
		if fix != null and fix.ok:
			_record("civic", "fix_violation", [], "cleared: %s" % String(row.get("label", "")))
	# Renew permits at (or just before) expiry.
	var clock: int = _clock_day()
	for permit: Dictionary in civic.get("permits"):
		var status: String = String(permit.get("status", ""))
		var expiring: bool = status == "active" and clock >= int(permit.get("expires_day", 0)) - 2
		if status == "lapsed" or expiring:
			var cost: float = float(permit.get("cost", 500.0))
			if company.cash - cost > reserve:
				gov.call("renew_permit_cmd", company.id,
					StringName(String(permit.get("permit_id", ""))))
	# Pay affordable fines; appeal big ones when feeling lucky.
	for fine: Dictionary in civic.call("unpaid_fines"):
		var amount: float = float(fine.get("amount", 0.0))
		var appealable: bool = not bool(fine.get("appealed_once", false)) \
			and clock <= int(fine.get("appeal_deadline_day", 0))
		if appealable and amount > 2000.0 and _rng.randf() < profile.risk_tolerance * 0.5:
			gov.call("appeal_fine_cmd", company.id, int(fine.get("uid", -1)))
		elif company.cash - amount > reserve:
			gov.call("pay_fine_cmd", company.id, int(fine.get("uid", -1)))


func _civic_influence(gov: Node, civic: Resource, reserve: float) -> void:
	# Declared donations to the mayor: cheap, safe standing.
	if _rng.randf() < profile.corruption_appetite:
		var amount: float = clampf(company.cash * 0.04, 250.0, 1500.0 + 2000.0 * profile.corruption_appetite)
		if company.cash - amount > reserve:
			var result: CommandResult = gov.call("donate_cmd", company.id, &"mayor", amount, &"declared")
			if result != null and result.ok:
				_record("civic", "donate", [], "donated %.0f to the mayor" % amount)
	# Bribes only for the truly corrupt, when the scenario allows them.
	if bool(gov.call("corruption_enabled")) and profile.corruption_appetite >= 0.5 \
			and _rng.randf() < profile.corruption_appetite * profile.risk_tolerance * 0.5:
		var target_official: StringName = &"mayor"
		if not (civic.call("open_violations") as Array).is_empty():
			target_official = &"food_inspector"
		var envelope: float = clampf(company.cash * 0.05, 600.0, 2500.0)
		if company.cash - envelope > reserve:
			var bribe: CommandResult = gov.call("bribe_cmd", company.id, target_official, envelope)
			if bribe != null and bribe.ok:
				_record("civic", "bribe", [], "paid %s an envelope" % String(target_official))
	# Back development proposals in districts where the company operates.
	var proposals: Array = gov.call("open_proposals")
	if not proposals.is_empty() and _rng.randf() < profile.corruption_appetite:
		var own_districts: Array[String] = []
		for rest: RestaurantState in company.restaurants:
			own_districts.append(rest.district)
		for project in proposals:
			if not own_districts.has(String(project.get("district"))):
				continue
			var pledge: float = clampf(company.cash * 0.03, 200.0, 1200.0)
			if company.cash - pledge <= reserve:
				break
			var lobby: CommandResult = gov.call("lobby_development_cmd", company.id,
				int(project.get("uid")), pledge)
			if lobby != null and lobby.ok:
				_record("civic", "lobby", [], "backed a project in %s" % String(project.get("district")))
			break
	# Report a rival branch when aggressive (the fee is wasted if baseless).
	if profile.aggression >= 0.5 and _rng.randf() < profile.aggression * 0.25:
		var target: int = _civic_report_target()
		if target >= 0:
			var report: CommandResult = gov.call("request_inspection_cmd", company.id, target)
			if report != null and report.ok:
				_record("civic", "report_rival", [], "reported building %d" % target)


func _civic_report_target() -> int:
	var candidates: Array[int] = []
	for rest: RestaurantState in RestaurantManager.all_restaurants():
		if rest.company_id != company.id:
			candidates.append(rest.building_id)
	if candidates.is_empty():
		return -1
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _clock_day() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 1
	var clock: Node = tree.root.get_node_or_null("GameClock")
	return int(clock.get("day")) if clock != null else 1


## Defensive posture: after being hit (or when appetite-driven rivals operate),
## buy guards, equipment, and insurance for exposed branches.
func _plan_security(day: int) -> void:
	var crime: Node = _crime_manager()
	if crime == null or not crime.call("enabled") or company.restaurants.is_empty():
		return
	if (day + absi(hash(company.id))) % 3 != 0:
		return
	var reserve: float = _cash_reserve_floor()
	for rest: RestaurantState in company.restaurants:
		var sec: Resource = crime.call("security_for", rest.building_id)
		if sec == null:
			continue
		var recent_hit: bool = int(sec.get("last_incident_day")) >= 0 \
			and day - int(sec.get("last_incident_day")) <= 6
		var want: float = profile.operational_skill * 0.5 + (0.5 if recent_hit else 0.0)
		if _rng.randf() > want:
			continue
		if int(sec.get("equipment_level")) < 2 and company.cash - 900.0 > reserve:
			crime.call("upgrade_security_cmd", company.id, rest.building_id)
		elif recent_hit and int(sec.get("insurance_level")) < 1 and company.cash - 2000.0 > reserve:
			crime.call("set_insurance_cmd", company.id, rest.building_id, 1)
		elif recent_hit and String(sec.get("alert_level")) == "normal":
			crime.call("set_alert_cmd", company.id, rest.building_id, &"elevated")
		_maybe_hire_guard(crime, rest, reserve)


func _maybe_hire_guard(_crime: Node, rest: RestaurantState, reserve: float) -> void:
	var guard_cap: int = _capability_level(&"security.guard_capacity")
	if guard_cap <= 0 or company.cash - 1000.0 < reserve:
		return
	var guards: int = 0
	for member: StaffMember in rest.staff:
		var def: StaffTypeDef = RestaurantManager.staff_type(member.type_id)
		if def != null and def.operational_tags.has(&"security"):
			guards += 1
	if guards >= guard_cap:
		return
	var pool: Array[JobCandidate] = RestaurantManager.candidates_for(&"guard")
	if pool.is_empty():
		return
	RestaurantManager.hire(company.id, rest.building_id, pool[0].uid, 9.0, 12.0)


## Offensive planner: build crew, then run an operation the profile can afford,
## favouring rank-adjacent rivals and retaliation. Bounded by heat and cash.
func _plan_underworld(day: int) -> void:
	var crime: Node = _crime_manager()
	if crime == null or not crime.call("enabled"):
		return
	if profile.crime_appetite <= 0.01 or company.is_bankrupt:
		return
	if int(crime.call("action_tier", company.id)) <= 0:
		return
	if (day + absi(hash(company.id))) % 2 != 0:
		return
	var heat_state: Resource = crime.call("heat_for", company.id)
	var heat_ceiling: float = float(_tuning("crime.ai.heat_backoff", 55.0)) * (0.5 + profile.risk_tolerance)
	if heat_state != null and float(heat_state.get("heat")) > heat_ceiling:
		return
	var reserve: float = maxf(_cash_reserve_floor(), float(_tuning("crime.ai.min_cash_reserve", 8000.0)))
	if company.cash < reserve:
		return
	_ensure_crew(crime, day)
	if _rng.randf() > profile.crime_appetite:
		return
	var target: Dictionary = _pick_crime_target(crime)
	if target.is_empty():
		return
	var action_id: StringName = _pick_crime_action(crime, target)
	if action_id == &"":
		return
	var preview: Dictionary = crime.call("preview_operation", company.id, action_id, int(target["building"]))
	if not bool(preview.get("ok", false)):
		return
	if company.cash - float(preview.get("cost", 0.0)) < reserve:
		return
	if float(preview.get("success_chance", 0.0)) < 0.35:
		return
	var result: CommandResult = crime.call("launch_operation_cmd", company.id, action_id, int(target["building"]))
	if result != null and result.ok:
		_record("underworld", String(action_id), [], "launched op vs %s" % String(target.get("company", "")))


func _ensure_crew(crime: Node, day: int) -> void:
	var capacity: int = int(crime.call("crew_capacity", company.id))
	var crew: Array = crime.call("crew_of", company.id)
	if crew.size() >= capacity or company.cash < _cash_reserve_floor() + 800.0:
		return
	var market: Array = crime.call("market_candidates", company.id)
	if market.is_empty():
		return
	var pick: Dictionary = market[0]
	for candidate: Dictionary in market:
		if float(candidate.get("skill", 0.0)) > float(pick.get("skill", 0.0)):
			pick = candidate
	crime.call("hire_agent_cmd", company.id, pick)
	var _unused: int = day


func _pick_crime_target(crime: Node) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var retaliate_against: Dictionary = _recent_attackers(crime)
	var retaliation_weight: float = float(_tuning("crime.ai.retaliation_weight", 2.0))
	for rest: RestaurantState in RestaurantManager.all_restaurants():
		if rest.company_id == company.id:
			continue
		var owner: CompanyState = CompanyManager.company(rest.company_id)
		if owner == null or owner.is_bankrupt:
			continue
		var weight: float = 1.0
		if retaliate_against.has(rest.company_id):
			weight *= retaliation_weight * (0.5 + profile.aggression)
		candidates.append({"building": rest.building_id, "company": rest.company_id, "weight": weight})
	if candidates.is_empty():
		return {}
	return _weighted_pick(candidates)


func _recent_attackers(crime: Node) -> Dictionary:
	var out: Dictionary = {}
	for rest: RestaurantState in company.restaurants:
		var sec: Resource = crime.call("security_for", rest.building_id)
		if sec == null:
			continue
		for row: Dictionary in sec.get("incidents"):
			var suspect: String = String(row.get("suspected_company", ""))
			if not suspect.is_empty():
				out[StringName(suspect)] = true
	return out


func _pick_crime_action(crime: Node, target: Dictionary) -> StringName:
	var available: Array = crime.call("actions_for", company.id)
	var target_company: StringName = target.get("company", &"")
	var is_company_target: bool = false
	var options: Array[Dictionary] = []
	for entry: Dictionary in available:
		if not bool(entry.get("ok", false)):
			continue
		var def: CrimeActionDef = entry.get("def")
		if def == null or def.cost > company.cash * 0.4:
			continue
		# Ruthless-only violent actions need a mean streak.
		var weight: float = 1.0 + float(3 - def.tier) * 0.3
		if def.tier >= 3 and profile.aggression < 0.6:
			continue
		options.append({"id": def.id, "weight": weight})
	if options.is_empty():
		return &""
	var _unused_company: StringName = target_company
	var _unused_flag: bool = is_company_target
	return StringName(_weighted_pick(options).get("id", &""))


func _weighted_pick(items: Array[Dictionary]) -> Dictionary:
	var total: float = 0.0
	for item: Dictionary in items:
		total += maxf(0.0, float(item.get("weight", 1.0)))
	if total <= 0.0:
		return items[_rng.randi_range(0, items.size() - 1)]
	var roll: float = _rng.randf() * total
	for item: Dictionary in items:
		roll -= maxf(0.0, float(item.get("weight", 1.0)))
		if roll <= 0.0:
			return item
	return items[items.size() - 1]


func _capability_level(cap_id: StringName) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var registry: Node = tree.root.get_node_or_null("CapabilityRegistry")
	if registry == null:
		return 0
	return int(registry.call("capacity", company.id, cap_id))


func _tuning(path: String, fallback: Variant) -> Variant:
	return EconomyManager.tuning_value(path, fallback)


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
