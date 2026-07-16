class_name SecurityService
extends RefCounted
## Pure defender-side math for feature 12. Touches no autoloads:
## CrimeManager gathers live guard coverage from StaffManager and passes it
## in, keeping this class headless-testable (tests/crime_reconciliation.gd).

const ALERT_LEVELS: Array[StringName] = [&"normal", &"elevated", &"lockdown"]

var equipment_bonus: float = 0.12  ## security score per equipment level
var guard_weight: float = 0.5  ## weight of the staff security aggregate
var alert_score_bonus: Dictionary = {&"normal": 0.0, &"elevated": 0.10, &"lockdown": 0.20}
var alert_demand_penalty: Dictionary = {&"normal": 0.0, &"elevated": 0.03, &"lockdown": 0.10}
var counterintel_base: float = 0.25
var counterintel_per_equipment: float = 0.12


## tuning = Callable(path: String, fallback) -> Variant (EconomyManager.tuning_value).
func configure(tuning: Callable) -> void:
	equipment_bonus = float(tuning.call("crime.security.equipment_bonus", equipment_bonus))
	guard_weight = float(tuning.call("crime.security.guard_weight", guard_weight))
	counterintel_base = float(tuning.call("crime.security.counterintel_base", counterintel_base))
	counterintel_per_equipment = float(tuning.call(
		"crime.security.counterintel_per_equipment", counterintel_per_equipment))


## Overall defensive posture, 0..0.95. guard_effect is the staff security
## aggregate for guards on shift (0..1 from StaffManager.role_effects_for).
func security_score(security: SecurityState, guard_effect: float) -> float:
	var score: float = 0.05
	score += guard_weight * clampf(guard_effect, 0.0, 1.0)
	score += equipment_bonus * float(security.equipment_level)
	score += float(alert_score_bonus.get(security.alert_level, 0.0))
	return clampf(score, 0.0, 0.95)


## UI breakdown rows for the Coverage tab: [{key, label, value 0..1}].
func coverage_breakdown(security: SecurityState, guard_effect: float) -> Array[Dictionary]:
	return [
		{"key": &"guards", "label": "Guards on shift", "value": clampf(guard_weight * guard_effect, 0.0, 1.0)},
		{"key": &"equipment", "label": "Security equipment", "value": clampf(equipment_bonus * float(security.equipment_level), 0.0, 1.0)},
		{"key": &"alert", "label": "Alert posture", "value": float(alert_score_bonus.get(security.alert_level, 0.0))},
	]


## Weak points shown in the Coverage tab and consumed by scouting intel.
func vulnerabilities(security: SecurityState, guard_effect: float) -> Array[StringName]:
	var out: Array[StringName] = []
	if guard_effect <= 0.01:
		out.append(&"no_guards")
	if security.equipment_level <= 0:
		out.append(&"no_equipment")
	elif security.equipment_level < 2:
		out.append(&"no_cameras")
	if security.alert_level == &"normal" and security.last_incident_day >= 0:
		out.append(&"low_alert")
	if security.insurance_level <= 0:
		out.append(&"uninsured")
	return out


## Demand multiplier penalty for the alert posture (the opportunity cost of
## lockdown). Returned as a 0..1 fraction the demand hook subtracts.
func alert_penalty(security: SecurityState) -> float:
	return float(alert_demand_penalty.get(security.alert_level, 0.0))


## Chance one counterintel sweep uncovers one live plot against the company.
func counterintel_chance(security: SecurityState) -> float:
	return clampf(
		counterintel_base + counterintel_per_equipment * float(security.equipment_level),
		0.05, 0.9)
