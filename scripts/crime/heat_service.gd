class_name HeatService
extends RefCounted
## Pure police/heat stub math for feature 12 — heat accrual and decay,
## evidence → attribution confidence, investigation timing, and the
## fine/raid enforcement ladder. Feature 13 (government) will absorb this.
## Touches no autoloads.

var decay_per_day: float = 1.5
var fine_threshold: float = 40.0
var raid_threshold: float = 75.0
var min_evidence_fine: float = 0.6
var min_evidence_raid: float = 1.5
var fine_base: float = 1500.0
var fine_per_evidence: float = 2000.0
var fine_heat_relief: float = 25.0
var raid_heat_relief: float = 50.0
var raid_freeze_days: int = 5
var incarceration_days: int = 10
var investigation_days_base: int = 4
var investigation_days_per_tier: int = 2
var confidence_base_weight: float = 0.4
var confidence_per_surveillance: float = 0.15
var confidence_police_bonus: float = 0.3
var attribution_threshold: float = 0.55  ## confidence needed to name the attacker


## tuning = Callable(path: String, fallback) -> Variant (EconomyManager.tuning_value).
func configure(tuning: Callable) -> void:
	decay_per_day = float(tuning.call("crime.heat.decay_per_day", decay_per_day))
	fine_threshold = float(tuning.call("crime.heat.fine_threshold", fine_threshold))
	raid_threshold = float(tuning.call("crime.heat.raid_threshold", raid_threshold))
	min_evidence_fine = float(tuning.call("crime.heat.min_evidence_fine", min_evidence_fine))
	min_evidence_raid = float(tuning.call("crime.heat.min_evidence_raid", min_evidence_raid))
	fine_base = float(tuning.call("crime.heat.fine_base", fine_base))
	fine_per_evidence = float(tuning.call("crime.heat.fine_per_evidence", fine_per_evidence))
	raid_freeze_days = int(tuning.call("crime.heat.raid_freeze_days", raid_freeze_days))
	incarceration_days = int(tuning.call("crime.heat.incarceration_days", incarceration_days))
	investigation_days_base = int(tuning.call("crime.heat.investigation_days_base", investigation_days_base))
	attribution_threshold = float(tuning.call("crime.heat.attribution_threshold", attribution_threshold))


func accrue(heat_state: CompanyHeatState, action: CrimeActionDef, detected: bool) -> void:
	var gain: float = action.heat_base * (1.5 if detected else 1.0)
	heat_state.heat = clampf(heat_state.heat + gain, 0.0, 100.0)


func decay(heat_state: CompanyHeatState) -> void:
	heat_state.heat = maxf(0.0, heat_state.heat - decay_per_day)


## How sure the victim/police are about who did it. surveillance = victim
## equipment level (cameras), police_involved = police were called or an
## investigation ran.
func confidence(evidence_strength: float, surveillance: int, police_involved: bool) -> float:
	var factor: float = confidence_base_weight
	factor += confidence_per_surveillance * float(surveillance)
	if police_involved:
		factor += confidence_police_bonus
	return clampf(evidence_strength * factor, 0.0, 1.0)


func attribution_known(confidence_value: float) -> bool:
	return confidence_value >= attribution_threshold


func investigation_duration(action_tier: int, police_involved: bool) -> int:
	var days: int = investigation_days_base + investigation_days_per_tier * (action_tier - 1)
	if police_involved:
		days = maxi(1, days - 2)
	return days


## Enforcement ladder against an attacker. Returns
## {action: &"none"|&"fine"|&"raid", fine: float}. Heat relief on
## enforcement is the natural cooldown — no extra timers needed.
func enforcement_check(heat_state: CompanyHeatState) -> Dictionary:
	var total_evidence: float = heat_state.evidence_total()
	if heat_state.heat >= raid_threshold and total_evidence >= min_evidence_raid:
		return {"action": &"raid", "fine": fine_amount(total_evidence)}
	if heat_state.heat >= fine_threshold and total_evidence >= min_evidence_fine:
		return {"action": &"fine", "fine": fine_amount(total_evidence)}
	return {"action": &"none", "fine": 0.0}


func fine_amount(total_evidence: float) -> float:
	return fine_base + fine_per_evidence * total_evidence


func apply_fine_relief(heat_state: CompanyHeatState) -> void:
	heat_state.heat = maxf(0.0, heat_state.heat - fine_heat_relief)


func apply_raid_relief(heat_state: CompanyHeatState) -> void:
	heat_state.heat = maxf(0.0, heat_state.heat - raid_heat_relief)
