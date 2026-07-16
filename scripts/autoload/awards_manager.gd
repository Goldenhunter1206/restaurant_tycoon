extends Node
## AwardsManager — feature 11 orchestrator: per-branch star ratings, food-guide
## inspections, quarterly city awards, and recipe competitions. Samples at day
## close via AnalyticsManager.buckets_closed — after company books close and
## analytics buckets are written, but before RestaurantManager resets
## rest.today. Pure math lives in scripts/awards/*.gd; this node owns autoload
## access, money, news, and persistence. Not a global identifier until the
## editor restarts — reach it via get_node("/root/AwardsManager").

signal rating_changed(building_id: int)
signal inspection_completed(building_id: int, record: Dictionary)
signal award_granted(result: AwardResult)
signal competition_updated(competition: CompetitionState)

const SCHEMA_VERSION: int = 1
const AWARDS_DIR: String = "res://data/awards"
const COMPETITIONS_DIR: String = "res://data/competitions"

var ratings: Dictionary = {}  ## building_id -> RestaurantRatingState
var award_results: Array[AwardResult] = []
var award_claimed: Dictionary = {}  ## "award_id@period" -> true (idempotent rewards)
var competitions: Array[CompetitionState] = []
var next_competition_uid: int = 1
var award_defs: Dictionary = {}  ## id -> AwardDef
var competition_defs: Dictionary = {}  ## id -> CompetitionDef

var rating_math: RatingService = RatingService.new()
var evaluator: AwardEvaluator = AwardEvaluator.new()
var judge: CompetitionJudge = CompetitionJudge.new()

var _initialized: bool = false
var _analytics: Node = null


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	rating_math.configure(EconomyManager.tuning_value)
	_load_defs()
	_analytics = _autoload_node("AnalyticsManager")
	var save: SaveGame = CompanyManager.loaded_save
	if save != null:
		restore_from_save(save)
	# Branches present at load predate the awards system: age unknown, treat as
	# established (opened_day 1). Branches appearing later seed at day close
	# with their true opening day.
	_ensure_rating_states(1)
	if _analytics != null and _analytics.has_signal("buckets_closed"):
		_analytics.connect("buckets_closed", _on_buckets_closed)


# --- Day close ----------------------------------------------------------------


func _on_buckets_closed(closed_day: int) -> void:
	_ensure_rating_states(closed_day)
	_sample_ratings(closed_day)
	_run_due_inspections(closed_day)
	var cadence: int = maxi(7, int(EconomyManager.tuning_value("awards.cadence_days", 42)))
	if closed_day >= cadence and closed_day % cadence == 0:
		_evaluate_awards(closed_day, cadence)
	_tick_competitions(closed_day)


func _sample_ratings(closed_day: int) -> void:
	for company: CompanyState in CompanyManager.companies:
		for rest: RestaurantState in company.restaurants:
			var state: RestaurantRatingState = ratings.get(rest.building_id)
			if state == null:
				continue
			var inputs: Dictionary = _gather_dimension_inputs(company, rest)
			var outcome: Dictionary = rating_math.sample(state, closed_day, inputs)
			rest.star_rating = float(outcome["stars"])
			if bool(outcome.get("warned_now", false)):
				_publish_star_warning(company, rest, state)
			if bool(outcome.get("star_lost", false)):
				_publish_star_loss(company, rest, state)
			rating_changed.emit(rest.building_id)


## Raw 0..100 dimension inputs for one closed day, gathered from the live sim
## (rest.today is still intact in the buckets_closed slot).
func _gather_dimension_inputs(company: CompanyState, rest: RestaurantState) -> Dictionary:
	var staff_mgr: Node = _autoload_node("StaffManager")
	var effects: Dictionary = {}
	if staff_mgr != null:
		effects = staff_mgr.role_effects_for(rest)
	var scope_id: String = str(rest.building_id)
	# Food: menu quality + demographic fit + kitchen crew consistency.
	var quality_sum: float = 0.0
	var appeal_sum: float = 0.0
	var dish_count: int = 0
	for entry: MenuEntry in rest.enabled_menu():
		var quality: float = RestaurantManager.quality_for(entry.dish_id, entry.tier)
		var appeal: float = quality
		if RecipeManager.is_recipe(entry.dish_id):
			appeal = RecipeManager.overall_appeal(entry.dish_id, entry.tier, rest.building_id)
		quality_sum += quality
		appeal_sum += appeal
		dish_count += 1
	var avg_quality: float = (quality_sum / dish_count) if dish_count > 0 else 0.5
	var avg_appeal: float = (appeal_sum / dish_count) if dish_count > 0 else 0.5
	var food01: float = clampf(
		0.5 * avg_quality + 0.3 * avg_appeal + 0.2 * _effect_norm(float(effects.get("cook", 0.0))), 0.0, 1.0)
	# Service: crew effect + served share - wait/leave penalty.
	var guests: float = float(rest.today.get("guests", 0))
	var lost: float = 0.0
	if _analytics != null:
		lost = float(_analytics.latest(&"restaurant", scope_id, &"lost_demand", 0.0))
	var served_ratio: float = guests / maxf(1.0, guests + lost)
	var leaves: float = float(rest.today.get("queue_leaves", 0)) + float(rest.today.get("cancelled", 0))
	var wait_penalty: float = 0.3 * (leaves / maxf(1.0, guests + leaves))
	var service01: float = clampf(
		0.55 * _effect_norm(float(effects.get("service", 0.0))) + 0.45 * served_ratio - wait_penalty, 0.0, 1.0)
	# Atmosphere + cleanliness from the interior evaluation.
	var atmosphere01: float = 0.5
	var clean01: float = 0.6
	if rest.interior_layout != null:
		var evaluation: InteriorEvaluation = RestaurantManager.interior.evaluate(rest.interior_layout)
		var crowd01: float = clampf((evaluation.throughput_mod - 0.6) / 0.55, 0.0, 1.0)
		var entertainment01: float = clampf(evaluation.entertainment / 6.0, 0.0, 1.0)
		atmosphere01 = clampf(
			0.4 * evaluation.comfort / 5.0 + 0.2 * entertainment01
			+ 0.2 * evaluation.style_coherence + 0.2 * crowd01, 0.0, 1.0)
		clean01 = clampf(
			0.7 * evaluation.condition + 0.3 * _effect_norm(float(effects.get("cleanliness", 0.0))), 0.0, 1.0)
	# Value: posted prices vs suggested fair prices.
	var overprice_sum: float = 0.0
	var priced_count: int = 0
	for entry: MenuEntry in rest.enabled_menu():
		var info: Dictionary = RestaurantManager.resolve_item(entry.dish_id)
		var fair: float = float(info.get("suggested_price", 0.0))
		if fair <= 0.0:
			continue
		overprice_sum += maxf(0.0, entry.price / fair - 1.0)
		priced_count += 1
	var value01: float = clampf(1.0 - ((overprice_sum / priced_count) if priced_count > 0 else 0.0), 0.0, 1.0)
	# Consistency: sales coefficient of variation over the window.
	var consistency01: float = 0.5
	if _analytics != null:
		var series: Array = _analytics.metric_series(&"sales", &"restaurant", scope_id, rating_math.window_days)
		if series.size() >= rating_math.min_observation_days:
			var mean: float = 0.0
			for v: float in series:
				mean += v
			mean /= series.size()
			if mean > 0.01:
				var variance: float = 0.0
				for v: float in series:
					variance += (v - mean) * (v - mean)
				var cov: float = sqrt(variance / series.size()) / mean
				consistency01 = clampf(1.0 - cov, 0.0, 1.0)
	return {
		&"food": 100.0 * food01,
		&"service": 100.0 * service01,
		&"atmosphere": 100.0 * atmosphere01,
		&"cleanliness": 100.0 * clean01,
		&"value": 100.0 * value01,
		&"consistency": 100.0 * consistency01,
	}


## operational_effect spans 0.70..1.05; 0 means nobody staffs that role.
func _effect_norm(value: float) -> float:
	if value <= 0.0:
		return 0.4
	return clampf((value - 0.70) / 0.35, 0.0, 1.0)


# --- Inspections ----------------------------------------------------------------


func _run_due_inspections(closed_day: int) -> void:
	for company: CompanyState in CompanyManager.companies:
		for rest: RestaurantState in company.restaurants:
			var state: RestaurantRatingState = ratings.get(rest.building_id)
			if state == null:
				continue
			if state.next_inspection_day <= 0:
				state.next_inspection_day = closed_day + 1 + (rest.building_id % rating_math.inspection_period_days)
			if closed_day < state.next_inspection_day:
				continue
			var rng: RandomNumberGenerator = WorkforceRng.make(&"inspection", closed_day, [rest.building_id])
			var record: Dictionary = rating_math.run_inspection(state, closed_day, rng)
			state.next_inspection_day = closed_day + rating_math.inspection_period_days
			rest.star_rating = rating_math.stars_for(state)
			_publish_inspection(company, rest, state, record)
			inspection_completed.emit(rest.building_id, record)


## Player branches' next food-guide visits, EventsPanel row shape.
func upcoming_inspections(count: int = 3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rest: RestaurantState in RestaurantManager.owned:
		var state: RestaurantRatingState = ratings.get(rest.building_id)
		if state == null or state.next_inspection_day <= 0:
			continue
		out.append({
			"title": "Food guide visit — %s" % rest.restaurant_name,
			"kind": "inspection",
			"day": state.next_inspection_day,
			"when": GameClock.month_name_for(state.next_inspection_day),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["day"]) < int(b["day"]))
	if out.size() > count:
		out.resize(count)
	return out


# --- Awards / competitions (filled by AwardEvaluator / CompetitionJudge glue) ---


func _evaluate_awards(closed_day: int, cadence: int) -> void:
	var period: int = closed_day / cadence
	var period_label: String = "Quarter %d" % period
	var active: Array = EconomyManager.tuning_value("awards.active_categories", [])
	var nominees_all: Array[Dictionary] = _build_nominees(closed_day, cadence)
	for def_id_raw: Variant in active:
		var def: AwardDef = award_defs.get(StringName(String(def_id_raw)))
		if def == null:
			continue
		var claim_key: String = "%s@%d" % [def.id, period]
		if award_claimed.has(claim_key):
			continue  # Rewards apply exactly once, across re-runs and reloads.
		var field: Array[Dictionary] = []
		for nominee: Dictionary in nominees_all:
			if evaluator.eligible(def, nominee, closed_day):
				field.append(nominee)
		var result: AwardResult = evaluator.evaluate(def, field, period, period_label, closed_day)
		if result == null:
			continue
		award_claimed[claim_key] = true
		award_results.append(result)
		_apply_award_reward(result, def, nominees_all)
		award_granted.emit(result)


## One row per live branch: rating dims + quarter-window analytics metrics.
func _build_nominees(closed_day: int, window: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for company: CompanyState in CompanyManager.companies:
		if company.is_bankrupt:
			continue
		for rest: RestaurantState in company.restaurants:
			var state: RestaurantRatingState = ratings.get(rest.building_id)
			if state == null:
				continue
			var scope_id: String = str(rest.building_id)
			var guests: float = 0.0
			var sales: float = 0.0
			var deliveries: float = 0.0
			var fail_rate: float = 0.0
			if _analytics != null:
				guests = float(_analytics.sum_window(&"restaurant", scope_id, &"guests", window))
				sales = float(_analytics.sum_window(&"restaurant", scope_id, &"sales", window))
				deliveries = float(_analytics.sum_window(&"restaurant", scope_id, &"deliveries", window))
				fail_rate = float(_analytics.latest(&"restaurant", scope_id, &"delivery_fail_rate", 0.0))
			var top_units: float = 0.0
			var top_recipe_id: StringName = &""
			var top_recipe_name: String = ""
			for sales_key: String in rest.recipe_sales:
				var units: float = float((rest.recipe_sales[sales_key] as Dictionary).get("units", 0))
				if units > top_units:
					top_units = units
					top_recipe_id = StringName(sales_key.get_slice("@", 0))
					var info: Dictionary = RestaurantManager.resolve_item(top_recipe_id)
					top_recipe_name = String(info.get("display_name", String(top_recipe_id)))
			out.append({
				"company_id": company.id,
				"building_id": rest.building_id,
				"name": rest.restaurant_name,
				"opened_day": state.opened_day,
				"stars": rest.star_rating,
				"delivery_enabled": rest.delivery_enabled,
				"dims": state.dimensions.duplicate(),
				"top_recipe_id": top_recipe_id,
				"top_recipe_name": top_recipe_name,
				"metrics": {
					&"guests": guests,
					&"sales": sales,
					&"deliveries": deliveries,
					&"delivery_reliability": 1.0 - clampf(fail_rate, 0.0, 1.0),
					&"top_recipe_units": top_units,
					&"composite": state.composite,
				},
			})
	return out


func _apply_award_reward(result: AwardResult, def: AwardDef, nominees_all: Array[Dictionary]) -> void:
	var company: CompanyState = CompanyManager.company(result.winner_company_id)
	if company == null:
		return
	if def.reward_cash > 0.0:
		company.transact(&"award_prize", def.reward_cash)
	if def.reward_reputation > 0.0:
		# Diminishing gains keep trophy leaders from running away (rich-get-richer control).
		var scale: float = 1.0
		if bool(EconomyManager.tuning_value("awards.reputation_diminishing", true)):
			scale = 1.0 / maxf(1.0, float(trophies_for(company.id)))
		var lo: float = float(EconomyManager.tuning_value("reputation.min", 1.0))
		var hi: float = float(EconomyManager.tuning_value("reputation.max", 5.0))
		company.add_reputation(def.reward_reputation * scale, lo, hi)
	if def.reward_trend_days > 0:
		for nominee: Dictionary in nominees_all:
			if int(nominee["building_id"]) == result.winner_building_id and StringName(nominee["top_recipe_id"]) != &"":
				MarketingManager.create_trend(
					StringName(nominee["top_recipe_id"]), String(nominee["top_recipe_name"]),
					def.reward_trend_days, company.id)
				break
	var headline: String = "%s wins %s (%s)!" % [result.winner_name, def.display_name, result.period_label]
	_record_event(BusinessEvent.AWARD_WON, company.id, {
		"restaurant_id": result.winner_building_id, "amount": def.reward_cash, "title": headline,
	})
	company.log_move(GameClock.day, &"award", headline)
	if company.is_player:
		EconomyManager.post_message("good", headline)
	else:
		EconomyManager.post_company_message(company.brand_color, "news", headline)


func _tick_competitions(closed_day: int) -> void:
	_announce_scheduled(closed_day)
	for comp: CompetitionState in competitions:
		match comp.status:
			&"entry":
				if closed_day >= comp.deadline_day:
					comp.status = &"locked"
					_log_comp(comp, closed_day, "Entries locked (%d participants)." % comp.entries.size())
					competition_updated.emit(comp)
			&"locked":
				if closed_day >= comp.judging_day:
					_judge_competition(comp, closed_day)
			&"judged":
				# Results stay on the podium for one day, then archive.
				comp.status = &"closed"
				competition_updated.emit(comp)


func _announce_scheduled(closed_day: int) -> void:
	for def_id: StringName in competition_defs:
		var def: CompetitionDef = competition_defs[def_id]
		if def.cadence_days <= 0 or _has_live_run(def.id):
			continue
		if (closed_day - 1) % def.cadence_days != def.cadence_offset % def.cadence_days:
			continue
		var comp: CompetitionState = _create_run(def, closed_day)
		var headline: String = "%s announced! Entries close %s." % [
			def.display_name, GameClock.month_name_for(comp.deadline_day)]
		EconomyManager.post_message("news", headline)
		_record_event(BusinessEvent.COMPETITION_ANNOUNCED, CompanyManager.player.id, {"title": headline})
		competition_updated.emit(comp)


func _create_run(def: CompetitionDef, day: int) -> CompetitionState:
	var comp: CompetitionState = CompetitionState.new()
	comp.uid = next_competition_uid
	next_competition_uid += 1
	comp.def_id = def.id
	comp.status = &"entry"
	comp.announced_day = day
	comp.seed_day = day  # Judging RNG is frozen here — reloads reproduce results.
	comp.deadline_day = day + maxi(1, def.entry_window_days)
	comp.judging_day = comp.deadline_day + maxi(1, def.judging_day_offset)
	competitions.append(comp)
	_log_comp(comp, day, "Announced — entries close day %d." % comp.deadline_day)
	return comp


## Submit or replace a company's frozen entry. The fee charges once per
## company per run; replacing an entry is free. The stored recipe is a deep
## duplicate — later edits to the source never touch it.
func enter_competition(company_id: StringName, uid: int, recipe: RecipeDef, tier: StringName = &"med") -> CommandResult:
	var comp: CompetitionState = competition_by_uid(uid)
	if comp == null:
		return CommandResult.fail(&"not_found", "That competition no longer exists.")
	if comp.status != &"entry":
		return CommandResult.fail(&"entries_locked", "Entries are locked.")
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null:
		return CommandResult.fail(&"unknown_company", "Unknown company.")
	var def: CompetitionDef = competition_defs.get(comp.def_id)
	if def == null:
		return CommandResult.fail(&"not_found", "Competition rules missing.")
	if recipe == null:
		return CommandResult.fail(&"no_recipe", "Pick a recipe to enter.")
	if def.product_type != &"" and recipe.product_type != def.product_type:
		return CommandResult.fail(&"wrong_product", "This contest wants a %s recipe." % def.product_type)
	var existing: Dictionary = comp.entry_for(company_id)
	if existing.is_empty():
		if company.cash < def.entry_fee:
			return CommandResult.fail(&"insufficient_funds", "Entry fee is $%.0f." % def.entry_fee)
		if def.entry_fee > 0.0:
			company.transact(&"competition_fee", -def.entry_fee)
		comp.entries.append({
			"company_id": company_id,
			"recipe": recipe.duplicate_recipe(),
			"tier": tier,
			"entry_day": GameClock.day,
		})
	else:
		existing["recipe"] = recipe.duplicate_recipe()
		existing["tier"] = tier
		existing["entry_day"] = GameClock.day
	_log_comp(comp, GameClock.day, "%s entered %s." % [company.display_name, recipe.display_name])
	company.log_move(GameClock.day, &"competition", "Entered %s." % _def_name(comp.def_id))
	competition_updated.emit(comp)
	return CommandResult.good({"uid": comp.uid, "frozen_version": recipe.version})


## A company drags a rival into a head-to-head recipe duel (challenge defs
## have no calendar cadence). Both sides still submit entries themselves.
func challenge_rival(challenger_id: StringName, challengee_id: StringName, def_id: StringName) -> CommandResult:
	var def: CompetitionDef = competition_defs.get(def_id)
	if def == null:
		return CommandResult.fail(&"not_found", "No such competition format.")
	var challenger: CompanyState = CompanyManager.company(challenger_id)
	var challengee: CompanyState = CompanyManager.company(challengee_id)
	if challenger == null or challengee == null or challenger_id == challengee_id:
		return CommandResult.fail(&"unknown_company", "Pick a valid rival.")
	for comp: CompetitionState in competitions:
		if comp.def_id == def_id and comp.status != &"closed" and comp.challenger_id == challenger_id:
			return CommandResult.fail(&"already_running", "That challenge is already on.")
	var run: CompetitionState = _create_run(def, GameClock.day)
	run.challenger_id = challenger_id
	run.challengee_id = challengee_id
	var headline: String = "%s challenges %s: %s!" % [
		challenger.display_name, challengee.display_name, def.display_name]
	EconomyManager.post_message("news", headline)
	_record_event(BusinessEvent.COMPETITION_ANNOUNCED, challenger_id, {"title": headline})
	_record_event(BusinessEvent.COMPETITION_ANNOUNCED, challengee_id, {"title": headline})
	challenger.log_move(GameClock.day, &"competition", headline)
	competition_updated.emit(run)
	return CommandResult.good({"uid": run.uid})


func _judge_competition(comp: CompetitionState, closed_day: int) -> void:
	var def: CompetitionDef = competition_defs.get(comp.def_id)
	if def == null or comp.entries.is_empty():
		comp.status = &"closed"
		_log_comp(comp, closed_day, "No entries — contest cancelled.")
		competition_updated.emit(comp)
		return
	judge.judge(comp, def, _score_competition_recipe,
		func(company_id: StringName) -> RandomNumberGenerator:
			return WorkforceRng.make(&"competition_judge", comp.seed_day, [comp.def_id, company_id]))
	comp.status = &"judged"
	_log_comp(comp, closed_day, "Judged — %s wins." % _company_name(comp.winner_company_id))
	_apply_competition_rewards(comp, def, closed_day)
	competition_updated.emit(comp)


## Average target-segment appeal from the deterministic recipe scorer.
func _score_competition_recipe(recipe: RecipeDef, tier: StringName, segments: Array) -> float:
	var scored: Dictionary = RecipeManager.score(recipe, tier)
	if segments.is_empty():
		return float(scored.get("overall", 0.5))
	var by_segment: Dictionary = scored.get("by_segment", {})
	var total: float = 0.0
	for segment: Variant in segments:
		total += float(by_segment.get(StringName(segment), 0.5))
	return total / segments.size()


func _apply_competition_rewards(comp: CompetitionState, def: CompetitionDef, closed_day: int) -> void:
	if comp.reward_applied or comp.winner_company_id == &"":
		return
	comp.reward_applied = true
	var company: CompanyState = CompanyManager.company(comp.winner_company_id)
	if company == null:
		return
	if def.reward_cash > 0.0:
		company.transact(&"competition_prize", def.reward_cash)
	if def.reward_reputation > 0.0:
		var scale: float = 1.0
		if bool(EconomyManager.tuning_value("awards.reputation_diminishing", true)):
			scale = 1.0 / maxf(1.0, float(trophies_for(company.id) + 1))
		var lo: float = float(EconomyManager.tuning_value("reputation.min", 1.0))
		var hi: float = float(EconomyManager.tuning_value("reputation.max", 5.0))
		company.add_reputation(def.reward_reputation * scale, lo, hi)
	var winner_row: Dictionary = comp.results[0] if not comp.results.is_empty() else {}
	var medal: AwardResult = AwardResult.new()
	medal.award_id = StringName("competition_%s" % comp.def_id)
	medal.display_name = def.display_name
	medal.kind = &"medal"
	medal.period = comp.uid
	medal.period_label = "Day %d" % closed_day
	medal.day = closed_day
	medal.winner_company_id = comp.winner_company_id
	medal.winner_building_id = -1
	medal.winner_name = company.display_name
	medal.nominees = comp.results.duplicate(true)
	medal.explanation = "Won %s with %s (score %.2f, judging range ±%d%%)." % [
		def.display_name, String(winner_row.get("recipe_name", "?")),
		float(winner_row.get("total", 0.0)), int(float(winner_row.get("noise_range", 0.05)) * 100.0)]
	medal.reward = {
		"cash": def.reward_cash, "reputation": def.reward_reputation,
		"trend_days": def.reward_trend_days,
	}
	award_results.append(medal)
	award_granted.emit(medal)
	if def.reward_trend_days > 0:
		var entry: Dictionary = comp.entry_for(comp.winner_company_id)
		var recipe: RecipeDef = entry.get("recipe")
		if recipe != null:
			MarketingManager.create_trend(recipe.id, recipe.display_name, def.reward_trend_days, company.id)
	var headline: String = "%s wins the %s!" % [company.display_name, def.display_name]
	for row: Dictionary in comp.results:
		var row_company: StringName = StringName(row["company_id"])
		_record_event(BusinessEvent.COMPETITION_RESULT, row_company, {
			"amount": 1.0 if row_company == comp.winner_company_id else 0.0,
			"title": headline,
		})
	company.log_move(closed_day, &"competition", headline)
	if company.is_player:
		EconomyManager.post_message("good", headline)
	else:
		EconomyManager.post_company_message(company.brand_color, "news", headline)
		if not comp.entry_for(CompanyManager.player.id).is_empty():
			EconomyManager.post_message("alert", "You placed #%d in the %s." % [
				_player_rank(comp), def.display_name])


func _player_rank(comp: CompetitionState) -> int:
	for row: Dictionary in comp.results:
		if StringName(row["company_id"]) == CompanyManager.player.id:
			return int(row.get("rank", 0))
	return 0


func _log_comp(comp: CompetitionState, day: int, text: String) -> void:
	comp.event_log.append({"day": day, "text": text})
	while comp.event_log.size() > 20:
		comp.event_log.remove_at(0)


func _def_name(def_id: StringName) -> String:
	var def: CompetitionDef = competition_defs.get(def_id)
	return def.display_name if def != null else String(def_id)


func _company_name(company_id: StringName) -> String:
	var company: CompanyState = CompanyManager.company(company_id)
	return company.display_name if company != null else String(company_id)


# --- Read surface ----------------------------------------------------------------


func rating_for(building_id: int) -> RestaurantRatingState:
	return ratings.get(building_id)


func next_star_blockers(building_id: int) -> Array[Dictionary]:
	var state: RestaurantRatingState = ratings.get(building_id)
	if state == null:
		return []
	return rating_math.blockers(state)


func results_for(company_id: StringName) -> Array[AwardResult]:
	var out: Array[AwardResult] = []
	for result: AwardResult in award_results:
		if result.winner_company_id == company_id:
			out.append(result)
	return out


func trophies_for(company_id: StringName) -> int:
	return results_for(company_id).size()


## Upcoming competition beats for the events panel: entry deadlines and
## judging days of live runs, plus the next scheduled announcements.
func upcoming_competition_events(count: int = 3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var today: int = GameClock.day
	for comp: CompetitionState in competitions:
		var def: CompetitionDef = competition_defs.get(comp.def_id)
		var title: String = def.display_name if def != null else String(comp.def_id)
		if (comp.status == &"announced" or comp.status == &"entry") and comp.deadline_day >= today:
			out.append({
				"title": "%s — entries close" % title, "kind": "competition",
				"day": comp.deadline_day, "when": GameClock.month_name_for(comp.deadline_day),
			})
		elif comp.status == &"locked" and comp.judging_day >= today:
			out.append({
				"title": "%s — judging" % title, "kind": "competition",
				"day": comp.judging_day, "when": GameClock.month_name_for(comp.judging_day),
			})
	for def_id: StringName in competition_defs:
		var def: CompetitionDef = competition_defs[def_id]
		if def.cadence_days <= 0 or _has_live_run(def.id):
			continue
		var cycle_pos: int = (today - 1) % def.cadence_days
		var wait_days: int = (def.cadence_offset - cycle_pos + def.cadence_days) % def.cadence_days
		var announce_day: int = today + wait_days
		out.append({
			"title": "%s — announced" % def.display_name, "kind": "competition",
			"day": announce_day, "when": GameClock.month_name_for(announce_day),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["day"]) < int(b["day"]))
	if out.size() > count:
		out.resize(count)
	return out


func _has_live_run(def_id: StringName) -> bool:
	for comp: CompetitionState in competitions:
		if comp.def_id == def_id and comp.status != &"closed":
			return true
	return false


func active_competitions() -> Array[CompetitionState]:
	var out: Array[CompetitionState] = []
	for comp: CompetitionState in competitions:
		if comp.status != &"closed":
			out.append(comp)
	return out


func competition_by_uid(uid: int) -> CompetitionState:
	for comp: CompetitionState in competitions:
		if comp.uid == uid:
			return comp
	return null


# --- News / events ----------------------------------------------------------------


func _publish_inspection(company: CompanyState, rest: RestaurantState, state: RestaurantRatingState, record: Dictionary) -> void:
	var score: int = int(record["score"])
	var title: String = "Food guide inspected %s: %d/100" % [rest.restaurant_name, score]
	_record_event(BusinessEvent.INSPECTION, company.id, {
		"restaurant_id": rest.building_id,
		"amount": 1.0 if bool(record["passed"]) else -1.0,
		"title": title,
	})
	company.log_move(GameClock.day, &"inspection", title)
	if bool(record["raised"]):
		var star_title: String = "%s certified at %d stars!" % [rest.restaurant_name, state.star_ceiling]
		_record_event(BusinessEvent.STAR_GAINED, company.id, {
			"restaurant_id": rest.building_id, "amount": float(state.star_ceiling), "title": star_title,
		})
		if company.is_player:
			EconomyManager.post_message("good", star_title)
		else:
			EconomyManager.post_company_message(company.brand_color, "news", star_title)
	elif company.is_player:
		var tone: String = "good" if bool(record["passed"]) else "alert"
		EconomyManager.post_message(tone, title)


func _publish_star_warning(company: CompanyState, rest: RestaurantState, state: RestaurantRatingState) -> void:
	if not company.is_player:
		return
	EconomyManager.post_message("alert",
		"Quality warning at %s — hold this up and you lose a star (%d-star status at risk)." % [rest.restaurant_name, state.star_ceiling])


func _publish_star_loss(company: CompanyState, rest: RestaurantState, state: RestaurantRatingState) -> void:
	var title: String = "%s dropped to %d stars." % [rest.restaurant_name, state.star_ceiling]
	_record_event(BusinessEvent.STAR_LOST, company.id, {
		"restaurant_id": rest.building_id, "amount": float(state.star_ceiling), "title": title,
	})
	company.log_move(GameClock.day, &"star_loss", title)
	if company.is_player:
		EconomyManager.post_message("alert", title)
	else:
		EconomyManager.post_company_message(company.brand_color, "news", title)


func _record_event(ev_type: StringName, company_id: StringName, fields: Dictionary) -> void:
	if _analytics != null and _analytics.has_method("record_event"):
		_analytics.record_event(ev_type, company_id, fields)


## Root-relative lookup: absolute /root/... paths throw from nodes that sit
## outside the active scene tree in --script mode (sim_harness discipline).
func _autoload_node(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(NodePath(node_name))


# --- State bookkeeping ----------------------------------------------------------------


func _ensure_rating_states(opened_day: int) -> void:
	for company: CompanyState in CompanyManager.companies:
		for rest: RestaurantState in company.restaurants:
			if not ratings.has(rest.building_id):
				ratings[rest.building_id] = _seed_state(company, rest, opened_day)


## Seed from the branch's current public stars (legacy mirror of company
## reputation) so migrated and freshly opened branches start where they stand.
func _seed_state(company: CompanyState, rest: RestaurantState, opened_day: int) -> RestaurantRatingState:
	var state: RestaurantRatingState = RestaurantRatingState.new()
	state.building_id = rest.building_id
	state.company_id = company.id
	state.star_ceiling = clampi(int(rest.star_rating), 1, 5)
	state.composite = clampf(rest.star_rating, 1.0, 5.0)
	var dims: Dictionary = {}
	for key: StringName in RestaurantRatingState.DIMENSION_KEYS:
		dims[key] = clampf(rest.star_rating / 5.0 * 100.0, 0.0, 100.0)
	state.dimensions = dims
	state.opened_day = maxi(1, opened_day)
	state.next_inspection_day = state.opened_day + 1 + (rest.building_id % rating_math.inspection_period_days)
	return state


func _load_defs() -> void:
	award_defs.clear()
	for res: Resource in _load_dir(AWARDS_DIR):
		if res is AwardDef:
			award_defs[(res as AwardDef).id] = res
	competition_defs.clear()
	for res: Resource in _load_dir(COMPETITIONS_DIR):
		if res is CompetitionDef:
			competition_defs[(res as CompetitionDef).id] = res


func _load_dir(dir_path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for file: String in dir.get_files():
		if file.ends_with(".tres") or file.ends_with(".res"):
			var res: Resource = load("%s/%s" % [dir_path, file])
			if res != null:
				out.append(res)
	return out


# --- Save / load ----------------------------------------------------------------


func write_save(save: SaveGame) -> void:
	save.awards_schema_version = SCHEMA_VERSION
	var states: Array[RestaurantRatingState] = []
	for building_id: int in ratings:
		states.append(ratings[building_id])
	save.rating_states = states
	save.award_results = award_results.duplicate()
	save.award_claimed_keys = award_claimed.duplicate()
	save.competitions = competitions.duplicate()
	save.competition_next_uid = next_competition_uid


func restore_from_save(save: SaveGame) -> void:
	ratings.clear()
	award_results = []
	award_claimed = {}
	competitions = []
	next_competition_uid = 1
	if save.awards_schema_version <= 0:
		return  # Pre-v10 section absent — _ensure_rating_states reseeds.
	for state: RestaurantRatingState in save.rating_states:
		ratings[state.building_id] = state
	for result: AwardResult in save.award_results:
		award_results.append(result)
	award_claimed = save.award_claimed_keys.duplicate()
	for comp: CompetitionState in save.competitions:
		competitions.append(comp)
	next_competition_uid = maxi(1, save.competition_next_uid)
