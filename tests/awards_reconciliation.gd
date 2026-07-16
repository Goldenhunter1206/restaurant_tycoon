class_name AwardsReconciliation
extends RefCounted
## Static acceptance suite for feature 11 (ratings, awards, competitions).
##
## Maps to the feature-plan acceptance criteria: stars need sustained quality
## plus an inspection (no instant jumps, no reload gains), star loss runs the
## warn/drop hysteresis, judging is deterministic from the frozen seed,
## entries are immune to later recipe edits, award scores reproduce from their
## stored breakdowns, and the v10 save section round-trips / migrates.
##
## Headless caveat (see tests/analytics_reconciliation.gd): SaveGame pulls the
## CompanyState compile chain, so it is built via load().new() at run time.
## The awards data/service classes are autoload-free and safe to name.
## Run via scripts/tests/test_awards.gd.

const SG_SCRIPT: String = "res://scripts/data/save_game.gd"
const SS_SCRIPT: String = "res://scripts/data/save_system.gd"
const TMP_PATH: String = "user://test_awards_roundtrip.tres"

static var _checks: int = 0


static func run() -> Dictionary:
	_checks = 0
	var failures: Array[String] = []
	_test_star_gating(failures)
	_test_star_loss_hysteresis(failures)
	_test_rating_reload_stability(failures)
	_test_blockers(failures)
	_test_judging_deterministic(failures)
	_test_frozen_entry_immunity(failures)
	_test_award_reproducibility(failures)
	_test_award_eligibility(failures)
	_test_state_roundtrip(failures)
	_test_migration_v10(failures)
	return {"ok": failures.is_empty(), "checks": _checks, "failures": failures}


static func _expect(cond: bool, message: String, failures: Array[String]) -> void:
	_checks += 1
	if not cond:
		failures.append(message)


# --- Builders -------------------------------------------------------------------


static func _service() -> RatingService:
	return RatingService.new()  # tuned defaults; configure() untested here


static func _state(ceiling: int = 3) -> RestaurantRatingState:
	var state: RestaurantRatingState = RestaurantRatingState.new()
	state.building_id = 100
	state.company_id = &"player"
	state.star_ceiling = ceiling
	state.composite = float(ceiling)
	return state


static func _dims(value: float) -> Dictionary:
	var out: Dictionary = {}
	for key: StringName in RestaurantRatingState.DIMENSION_KEYS:
		out[key] = value
	return out


static func _recipe(id: StringName, ingredients: Array, product: StringName = &"pizza") -> RecipeDef:
	var rec: RecipeDef = RecipeDef.new()
	rec.id = id
	rec.display_name = String(id).capitalize()
	rec.product_type = product
	for ing: StringName in ingredients:
		var component: RecipeComponent = RecipeComponent.new()
		component.ingredient_id = ing
		rec.components.append(component)
	rec.cached_cost = 4.0
	rec.suggested_price = 8.0
	return rec


static func _competition_def() -> CompetitionDef:
	var def: CompetitionDef = CompetitionDef.new()
	def.id = &"test_cup"
	def.display_name = "Test Cup"
	def.product_type = &"pizza"
	def.target_demographics = [&"students"]
	def.constraints = {"max_cost": 5.0}
	def.judging = {"recipe": 0.6, "compliance": 0.25, "novelty": 0.15, "noise_range": 0.05}
	return def


static func _competition_state(def: CompetitionDef, seed_day: int) -> CompetitionState:
	var comp: CompetitionState = CompetitionState.new()
	comp.uid = 1
	comp.def_id = def.id
	comp.seed_day = seed_day
	comp.status = &"locked"
	return comp


## Deterministic stand-in for RecipeManager.score: keyed off component count.
static func _scorer(recipe: RecipeDef, _tier: StringName, _segments: Array) -> float:
	return clampf(0.3 + 0.1 * recipe.components.size(), 0.0, 1.0)


# --- Ratings ---------------------------------------------------------------------


static func _test_star_gating(failures: Array[String]) -> void:
	var service: RatingService = _service()
	var state: RestaurantRatingState = _state(3)
	# Three great days: composite climbs but public stars stay under 4.0 and
	# no inspection means no ceiling movement.
	for day: int in [1, 2, 3]:
		service.sample(state, day, _dims(92.0))
	_expect(state.composite > 4.0, "high dims push composite above 4 (got %.2f)" % state.composite, failures)
	_expect(service.stars_for(state) < 4.0, "stars capped below 4.0 without certification", failures)
	_expect(state.star_ceiling == 3, "ceiling unchanged without inspection", failures)
	# Early inspection: quality not yet sustained -> no raise even on a top score.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var early: Dictionary = service.run_inspection(state, 3, rng)
	_expect(state.star_ceiling == 3, "inspection before sustain window cannot raise the ceiling", failures)
	_expect(bool(early["passed"]), "holding the current tier counts as a pass", failures)
	# Sustain long enough, then inspect again -> exactly one tier up.
	for day: int in range(4, 4 + service.min_days_at_level):
		service.sample(state, day, _dims(92.0))
	rng.seed = 42
	var later: Dictionary = service.run_inspection(state, 9, rng)
	_expect(bool(later["raised"]) and state.star_ceiling == 4,
		"sustained quality + inspection raises exactly one tier (ceiling %d)" % state.star_ceiling, failures)
	_expect(service.stars_for(state) < 5.0, "stars still capped by the new ceiling", failures)


static func _test_star_loss_hysteresis(failures: Array[String]) -> void:
	var service: RatingService = _service()
	var state: RestaurantRatingState = _state(4)
	# Fill the window at target level first so the drop is a real regression.
	for day: int in [1, 2]:
		service.sample(state, day, _dims(75.0))
	var warned_day: int = -1
	var lost_day: int = -1
	for day: int in range(3, 3 + service.loss_days + service.window_days):
		var outcome: Dictionary = service.sample(state, day, _dims(15.0))
		if bool(outcome["warned_now"]) and warned_day < 0:
			warned_day = day
		if bool(outcome["star_lost"]) and lost_day < 0:
			lost_day = day
			break
	_expect(warned_day > 0, "sustained degradation warns first", failures)
	_expect(lost_day > warned_day, "star loss only after the warning window", failures)
	_expect(state.star_ceiling == 3, "ceiling dropped exactly one tier", failures)


static func _test_rating_reload_stability(failures: Array[String]) -> void:
	var service: RatingService = _service()
	var state: RestaurantRatingState = _state(3)
	for day: int in [1, 2, 3, 4]:
		service.sample(state, day, _dims(70.0))
	var stars_before: float = service.stars_for(state)
	var err: Error = ResourceSaver.save(state, TMP_PATH)
	_expect(err == OK, "rating state serializes", failures)
	var reloaded: RestaurantRatingState = ResourceLoader.load(TMP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(reloaded != null and absf(service.stars_for(reloaded) - stars_before) < 0.0001,
		"reload reproduces identical stars (no reload gains)", failures)
	_expect(reloaded.samples.size() == state.samples.size(), "sample window survives reload", failures)


static func _test_blockers(failures: Array[String]) -> void:
	var service: RatingService = _service()
	var state: RestaurantRatingState = _state(3)
	service.sample(state, 1, _dims(55.0))
	var gaps: Array[Dictionary] = service.blockers(state)
	var has_dimension: bool = false
	var has_sustain: bool = false
	var has_inspection: bool = false
	for gap: Dictionary in gaps:
		match StringName(gap["kind"]):
			&"dimension": has_dimension = true
			&"sustain": has_sustain = true
			&"inspection": has_inspection = true
	_expect(has_dimension and has_sustain and has_inspection,
		"blockers name dimension gaps, the sustain window, and the inspection", failures)
	state.star_ceiling = 5
	_expect(service.blockers(state).is_empty(), "no blockers at the top tier", failures)


# --- Competitions ------------------------------------------------------------------


static func _test_judging_deterministic(failures: Array[String]) -> void:
	var def: CompetitionDef = _competition_def()
	var judge: CompetitionJudge = CompetitionJudge.new()
	var results: Array = []
	for attempt: int in 2:
		var comp: CompetitionState = _competition_state(def, 17)
		comp.entries.append({"company_id": &"player", "recipe": _recipe(&"r_a", [&"tomato", &"basil"]), "tier": &"med", "entry_day": 15})
		comp.entries.append({"company_id": &"pronto", "recipe": _recipe(&"r_b", [&"tomato", &"bacon", &"onion"]), "tier": &"med", "entry_day": 15})
		judge.judge(comp, def, _scorer, func(company_id: StringName) -> RandomNumberGenerator:
			return WorkforceRng.make(&"competition_judge", comp.seed_day, [def.id, company_id]))
		results.append(comp.results)
	_expect(results[0].size() == 2, "both entries judged", failures)
	var identical: bool = str(results[0]) == str(results[1])
	_expect(identical, "same seed_day judges bit-identically (anti save-scum)", failures)
	var winner_total: float = float(results[0][0]["total"])
	var runner_total: float = float(results[0][1]["total"])
	_expect(winner_total >= runner_total and int(results[0][0]["rank"]) == 1,
		"results ranked by total", failures)
	for row: Dictionary in results[0]:
		for component: String in ["recipe_score", "compliance", "novelty", "noise", "noise_range", "total", "rank"]:
			if not row.has(component):
				_expect(false, "result row missing component %s" % component, failures)
				return
	_expect(true, "every scoring component disclosed per entry", failures)


static func _test_frozen_entry_immunity(failures: Array[String]) -> void:
	var source: RecipeDef = _recipe(&"r_mut", [&"tomato", &"basil"])
	var frozen: RecipeDef = source.duplicate_recipe()
	var extra: RecipeComponent = RecipeComponent.new()
	extra.ingredient_id = &"pineapple"
	source.components.append(extra)
	source.display_name = "Renamed After Entry"
	source.version = 2
	_expect(frozen.components.size() == 2, "frozen entry keeps its component list", failures)
	_expect(frozen.display_name != source.display_name, "frozen entry keeps its name", failures)
	_expect(frozen.version == 1, "frozen entry keeps its version", failures)


# --- Awards ---------------------------------------------------------------------


static func _nominee(company: StringName, building: int, food: float, guests: float, opened: int = 1) -> Dictionary:
	var dims: Dictionary = _dims(60.0)
	dims[&"food"] = food
	return {
		"company_id": company, "building_id": building, "name": "Branch %d" % building,
		"opened_day": opened, "stars": 3.5, "delivery_enabled": true,
		"dims": dims, "top_recipe_id": &"", "top_recipe_name": "",
		"metrics": {&"guests": guests, &"sales": guests * 20.0, &"composite": 3.5},
	}


static func _test_award_reproducibility(failures: Array[String]) -> void:
	var def: AwardDef = AwardDef.new()
	def.id = &"test_premium"
	def.display_name = "Test Premium"
	def.scoring = {&"food": 0.7, &"guests": 0.3}
	def.tiebreak_metric = &"guests"
	var evaluator: AwardEvaluator = AwardEvaluator.new()
	var field: Array[Dictionary] = [
		_nominee(&"player", 100, 90.0, 400.0),
		_nominee(&"pronto", 101, 70.0, 600.0),
		_nominee(&"nonna", 102, 50.0, 200.0),
	]
	var result: AwardResult = evaluator.evaluate(def, field, 1, "Quarter 1", 42)
	_expect(result != null and result.winner_company_id == &"player",
		"highest weighted nominee wins", failures)
	# Reproduce every nominee's score from its stored breakdown alone.
	var reproducible: bool = true
	for row: Dictionary in result.nominees:
		var recomputed: float = 0.0
		var breakdown: Dictionary = row["breakdown"]
		for comp: Variant in breakdown:
			var part: Dictionary = breakdown[comp]
			recomputed += float(part["weight"]) * float(part["normalized"])
		if absf(recomputed - float(row["score"])) > 0.0001:
			reproducible = false
	_expect(reproducible, "award scores reproduce exactly from stored breakdowns", failures)


static func _test_award_eligibility(failures: Array[String]) -> void:
	var def: AwardDef = AwardDef.new()
	def.eligibility = {"min_guests": 100, "max_age_days": 84}
	var evaluator: AwardEvaluator = AwardEvaluator.new()
	_expect(not evaluator.eligible(def, _nominee(&"a", 1, 60.0, 50.0), 42),
		"min_guests filters quiet branches", failures)
	_expect(evaluator.eligible(def, _nominee(&"a", 1, 60.0, 150.0, 10), 42),
		"active young branch is eligible", failures)
	_expect(not evaluator.eligible(def, _nominee(&"a", 1, 60.0, 150.0, 1), 200),
		"max_age_days filters established branches (newcomer rule)", failures)


# --- Persistence ------------------------------------------------------------------


static func _test_state_roundtrip(failures: Array[String]) -> void:
	var def: CompetitionDef = _competition_def()
	var comp: CompetitionState = _competition_state(def, 17)
	comp.entries.append({"company_id": &"pronto", "recipe": _recipe(&"r_rt", [&"tomato"]), "tier": &"med", "entry_day": 15})
	CompetitionJudge.new().judge(comp, def, _scorer, func(company_id: StringName) -> RandomNumberGenerator:
		return WorkforceRng.make(&"competition_judge", comp.seed_day, [def.id, company_id]))
	var err: Error = ResourceSaver.save(comp, TMP_PATH)
	_expect(err == OK, "competition state serializes (nested frozen RecipeDef)", failures)
	var reloaded: CompetitionState = ResourceLoader.load(TMP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if reloaded == null:
		_expect(false, "competition state reloads", failures)
		return
	var entry_recipe: RecipeDef = reloaded.entry_for(&"pronto").get("recipe")
	_expect(entry_recipe != null and entry_recipe.id == &"r_rt",
		"frozen entry recipe survives save/load", failures)
	# Semantic comparison: .tres text serialization rounds float tails (~1e-8)
	# and reorders dictionary keys; the stored outcome must stay identical.
	var rows_match: bool = reloaded.results.size() == comp.results.size()
	if rows_match:
		for i: int in comp.results.size():
			var before: Dictionary = comp.results[i]
			var after: Dictionary = reloaded.results[i]
			if StringName(after["company_id"]) != StringName(before["company_id"]) \
					or int(after["rank"]) != int(before["rank"]) \
					or absf(float(after["total"]) - float(before["total"])) > 0.0001 \
					or after.keys().size() != before.keys().size():
				rows_match = false
	_expect(rows_match, "judged results survive save/load unchanged", failures)
	_expect(reloaded.winner_company_id == comp.winner_company_id,
		"winner survives save/load", failures)


static func _test_migration_v10(failures: Array[String]) -> void:
	var save: Resource = load(SG_SCRIPT).new()
	save.set("save_version", 9)
	save.set("awards_schema_version", 0)
	var save_system: GDScript = load(SS_SCRIPT)
	save_system._migrate_v10(save)
	_expect(int(save.get("save_version")) == 10, "migration bumps save_version to 10", failures)
	_expect(int(save.get("awards_schema_version")) == 1, "migration marks the awards section", failures)
