class_name RatingService
extends RefCounted
## Pure rating math for feature 11 — rolling dimension windows, composite
## score, inspection-certified star ceiling with hysteresis, blockers, and
## food-guide inspection scoring. Touches no autoloads: AwardsManager gathers
## raw dimension inputs from the sim and passes them in, keeping this class
## headless-testable (see tests/awards_reconciliation.gd).

const HISTORY_CAP: int = 180
const INSPECTION_CAP: int = 24
## Food-guide weighting: hygiene and food dominate the visit score.
const INSPECTION_BIAS: Dictionary = {
	&"food": 0.30, &"cleanliness": 0.30, &"service": 0.15,
	&"atmosphere": 0.10, &"value": 0.05, &"consistency": 0.10,
}

var window_days: int = 14
var min_observation_days: int = 5
var weights: Dictionary = {
	&"food": 0.28, &"service": 0.22, &"atmosphere": 0.16,
	&"cleanliness": 0.16, &"value": 0.12, &"consistency": 0.06,
}
var rise_hysteresis: float = 0.2
var loss_hysteresis: float = 0.5
var min_days_at_level: int = 5
var warn_days: int = 3
var loss_days: int = 7
var level_floors: Dictionary = {2: 45.0, 3: 58.0, 4: 70.0, 5: 84.0}
var inspection_level_floor: Dictionary = {1: 30.0, 2: 45.0, 3: 58.0, 4: 72.0, 5: 86.0}
var inspection_leniency: float = 4.0
var inspection_period_days: int = 28


## tuning = Callable(path: String, fallback) -> Variant (EconomyManager.tuning_value).
func configure(tuning: Callable) -> void:
	window_days = maxi(1, int(tuning.call("rating.window_days", window_days)))
	min_observation_days = maxi(1, int(tuning.call("rating.min_observation_days", min_observation_days)))
	rise_hysteresis = float(tuning.call("rating.rise_hysteresis", rise_hysteresis))
	loss_hysteresis = float(tuning.call("rating.loss_hysteresis", loss_hysteresis))
	min_days_at_level = maxi(1, int(tuning.call("rating.min_days_at_level", min_days_at_level)))
	warn_days = maxi(1, int(tuning.call("rating.warn_days", warn_days)))
	loss_days = maxi(warn_days + 1, int(tuning.call("rating.loss_days", loss_days)))
	inspection_period_days = maxi(2, int(tuning.call("inspection.period_days", inspection_period_days)))
	inspection_leniency = maxf(0.0, float(tuning.call("inspection.leniency", inspection_leniency)))
	weights = _name_keyed(tuning.call("rating.weights", {}), weights)
	level_floors = _int_keyed(tuning.call("rating.level_floors", {}), level_floors)
	inspection_level_floor = _int_keyed(tuning.call("inspection.level_floor", {}), inspection_level_floor)


## Record one day's raw dimension sample and refresh reported values.
## `inputs` = {dim: 0..100 raw for the closed day}. Returns
## {composite, stars, rise_ready, star_lost, warned_now} — the caller owns
## news, events, and pushing `stars` into RestaurantState.star_rating.
func sample(state: RestaurantRatingState, day: int, inputs: Dictionary) -> Dictionary:
	state.samples.append({"day": day, "dims": inputs.duplicate()})
	while state.samples.size() > window_days:
		state.samples.remove_at(0)
	var reported: Dictionary = {}
	for key: StringName in RestaurantRatingState.DIMENSION_KEYS:
		var total: float = 0.0
		var n: int = 0
		for row: Dictionary in state.samples:
			var dims: Dictionary = row.get("dims", {})
			if dims.has(key):
				total += float(dims[key])
				n += 1
		reported[key] = (total / n) if n > 0 else 50.0
	state.dimensions = reported
	state.composite = composite_of(reported)
	var outcome: Dictionary = _update_ceiling(state)
	var stars: float = stars_for(state)
	state.history.append({
		"day": day, "composite": state.composite, "stars": stars,
		"dimensions": reported.duplicate(),
	})
	while state.history.size() > HISTORY_CAP:
		state.history.remove_at(0)
	outcome["stars"] = stars
	outcome["composite"] = state.composite
	return outcome


func composite_of(dims: Dictionary) -> float:
	var acc: float = 0.0
	var weight_sum: float = 0.0
	for key: StringName in weights:
		acc += float(weights[key]) * float(dims.get(key, 50.0)) / 100.0
		weight_sum += float(weights[key])
	if weight_sum > 0.0:
		acc /= weight_sum
	return 1.0 + 4.0 * acc


## Public stars: merit composite capped just below the next uncertified tier.
func stars_for(state: RestaurantRatingState) -> float:
	return clampf(state.composite, 1.0, float(state.star_ceiling) + 0.99)


## Deterministic food-guide visit. `rng` must come seeded from the caller
## (WorkforceRng.make(&"inspection", day, [building_id])) so a reload
## reproduces the identical outcome. Raising the ceiling additionally
## requires the sustain streak (days_at_target) — quality must be held, not
## spiked for one visit.
func run_inspection(state: RestaurantRatingState, day: int, rng: RandomNumberGenerator) -> Dictionary:
	var score: float = 0.0
	var breakdown: Dictionary = {}
	for key: StringName in INSPECTION_BIAS:
		var dim_value: float = float(state.dimensions.get(key, 50.0))
		breakdown[key] = dim_value
		score += float(INSPECTION_BIAS[key]) * dim_value
	var leniency: float = rng.randf_range(-inspection_leniency, inspection_leniency)
	score = clampf(score + leniency, 0.0, 100.0)
	var level: int = 1
	for lvl: int in [2, 3, 4, 5]:
		if score >= float(inspection_level_floor.get(lvl, 101.0)):
			level = lvl
	var passed: bool = level >= state.star_ceiling
	var raised: bool = false
	if level > state.star_ceiling and state.days_at_target >= min_days_at_level:
		state.star_ceiling = mini(state.star_ceiling + 1, 5)  # one tier per visit
		state.days_at_target = 0
		raised = true
	elif not passed:
		state.warned = true
	var record: Dictionary = {
		"day": day, "score": score, "level": level, "passed": passed,
		"raised": raised, "leniency": leniency, "breakdown": breakdown,
	}
	state.inspections.append(record)
	while state.inspections.size() > INSPECTION_CAP:
		state.inspections.remove_at(0)
	return record


## Concrete "to reach the next star" guidance, worst dimension gaps first.
func blockers(state: RestaurantRatingState) -> Array[Dictionary]:
	if state.star_ceiling >= 5:
		return []
	var target: int = state.star_ceiling + 1
	var floor_value: float = float(level_floors.get(target, 101.0))
	var gaps: Array[Dictionary] = []
	for key: StringName in RestaurantRatingState.DIMENSION_KEYS:
		var value: float = float(state.dimensions.get(key, 50.0))
		if value < floor_value:
			gaps.append({
				"kind": &"dimension", "dimension": key,
				"value": value, "needed": floor_value,
			})
	gaps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["needed"]) - float(a["value"]) > float(b["needed"]) - float(b["value"]))
	if state.days_at_target < min_days_at_level:
		gaps.append({
			"kind": &"sustain",
			"days": state.days_at_target, "needed_days": min_days_at_level,
		})
	gaps.append({"kind": &"inspection", "next_day": state.next_inspection_day})
	return gaps


## Rise readiness is tracked daily; the raise itself happens at inspection.
func _update_ceiling(state: RestaurantRatingState) -> Dictionary:
	var out: Dictionary = {"rise_ready": false, "star_lost": false, "warned_now": false}
	var next_level: int = state.star_ceiling + 1
	if next_level <= 5 and state.composite >= float(next_level) - rise_hysteresis:
		state.days_at_target += 1
	else:
		state.days_at_target = 0
	out["rise_ready"] = state.days_at_target >= min_days_at_level
	if state.star_ceiling > 1 and state.composite < float(state.star_ceiling) - loss_hysteresis:
		state.loss_countdown += 1
		if state.loss_countdown >= loss_days:
			state.star_ceiling -= 1
			state.loss_countdown = 0
			state.warned = false
			out["star_lost"] = true
		elif state.loss_countdown >= warn_days and not state.warned:
			state.warned = true
			out["warned_now"] = true
	else:
		state.loss_countdown = 0
		state.warned = false
	return out


func _name_keyed(raw: Variant, fallback: Dictionary) -> Dictionary:
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		var out: Dictionary = {}
		for key: Variant in raw:
			out[StringName(String(key))] = float(raw[key])
		return out
	return fallback


func _int_keyed(raw: Variant, fallback: Dictionary) -> Dictionary:
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		var out: Dictionary = {}
		for key: Variant in raw:
			out[int(String(key))] = float(raw[key])
		return out
	return fallback
