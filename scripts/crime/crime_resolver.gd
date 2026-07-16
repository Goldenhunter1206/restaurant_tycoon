class_name CrimeResolver
extends RefCounted
## Pure attacker-side resolution math for feature 12. preview() is
## deterministic (no rng) and feeds both the UI review rail and AI judgment;
## resolve() consumes a caller-seeded RandomNumberGenerator
## (WorkforceRng.make(&"crime_resolve", op.seed_day, [op.uid])) so a reload
## reproduces the identical outcome. Touches no autoloads.

var equipment_success_bonus: float = 0.05  ## per crew equipment tier
var intel_success_bonus: float = 0.10  ## at full intel (level 1.0)
var alert_success_penalty: Dictionary = {&"normal": 0.0, &"elevated": 0.08, &"lockdown": 0.18}
var detect_base: float = 0.08
var detect_security_weight: float = 0.55
var detect_tier_bonus: float = 0.05  ## per tier above 1
var failure_detect_multiplier: float = 1.8
var camera_evidence_bonus: float = 0.4  ## equipment>=2 multiplies evidence
var escape_injury_base: float = 0.12
var escape_capture_base: float = 0.06
var escape_security_weight: float = 0.35


## tuning = Callable(path: String, fallback) -> Variant (EconomyManager.tuning_value).
func configure(tuning: Callable) -> void:
	equipment_success_bonus = float(tuning.call("crime.resolve.equipment_success_bonus", equipment_success_bonus))
	intel_success_bonus = float(tuning.call("crime.resolve.intel_success_bonus", intel_success_bonus))
	detect_base = float(tuning.call("crime.resolve.detect_base", detect_base))
	detect_security_weight = float(tuning.call("crime.resolve.detect_security_weight", detect_security_weight))
	camera_evidence_bonus = float(tuning.call("crime.resolve.camera_evidence_bonus", camera_evidence_bonus))
	escape_injury_base = float(tuning.call("crime.resolve.escape_injury_base", escape_injury_base))
	escape_capture_base = float(tuning.call("crime.resolve.escape_capture_base", escape_capture_base))


## ctx keys: avg_skill, equipment_tier (int), intel_level (0..1),
## security_score (0..0.95), alert_level (StringName), has_cameras (bool),
## agent_count (int). Deterministic — safe for UI preview and AI planning.
func preview(action: CrimeActionDef, ctx: Dictionary) -> Dictionary:
	var success: float = action.base_success
	success += action.skill_weight * float(ctx.get("avg_skill", 0.0))
	success += equipment_success_bonus * float(ctx.get("equipment_tier", 0))
	success += intel_success_bonus * float(ctx.get("intel_level", 0.0))
	success -= action.security_weight * float(ctx.get("security_score", 0.0))
	success -= float(alert_success_penalty.get(ctx.get("alert_level", &"normal"), 0.0))
	success = clampf(success, 0.05, 0.95)
	var detect: float = _detection_chance(action, ctx)
	var evidence_risk: float = clampf(
		action.evidence_base * (1.0 + (camera_evidence_bonus if bool(ctx.get("has_cameras", false)) else 0.0)),
		0.0, 1.0)
	return {
		"success_chance": success,
		"detection_chance": detect,
		"evidence_risk": evidence_risk,
		"heat_gain": action.heat_base,
	}


## Rolls success, live detection, evidence strength, and one escape outcome
## per agent. Returns {success, detected, evidence, agent_outcomes: Array of
## &"clean"/&"injured"/&"captured"}. Roll order is fixed — do not reorder,
## saves depend on it for reproducibility.
func resolve(action: CrimeActionDef, ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var odds: Dictionary = preview(action, ctx)
	var success: bool = rng.randf() < float(odds["success_chance"])
	var detect_chance: float = float(odds["detection_chance"])
	if not success:
		detect_chance = clampf(detect_chance * failure_detect_multiplier, 0.0, 0.95)
	var detected: bool = rng.randf() < detect_chance
	var evidence: float = action.evidence_base * rng.randf_range(0.6, 1.4)
	if bool(ctx.get("has_cameras", false)):
		evidence *= 1.0 + camera_evidence_bonus
	if detected:
		evidence *= 1.25
	evidence = clampf(evidence, 0.0, 1.0)
	var outcomes: Array[StringName] = []
	var security: float = float(ctx.get("security_score", 0.0))
	var tier_risk: float = 0.06 * float(action.tier - 1)
	for _i: int in range(int(ctx.get("agent_count", 1))):
		var roll: float = rng.randf()
		var capture_p: float = (escape_capture_base + escape_security_weight * security * 0.5 + tier_risk) if detected else 0.0
		var injury_p: float = (escape_injury_base + escape_security_weight * security + tier_risk) if (detected or not success) else 0.02
		if roll < capture_p:
			outcomes.append(&"captured")
		elif roll < capture_p + injury_p:
			outcomes.append(&"injured")
		else:
			outcomes.append(&"clean")
	return {
		"success": success,
		"detected": detected,
		"evidence": evidence,
		"agent_outcomes": outcomes,
	}


func _detection_chance(action: CrimeActionDef, ctx: Dictionary) -> float:
	var detect: float = detect_base
	detect += detect_security_weight * float(ctx.get("security_score", 0.0))
	detect += detect_tier_bonus * float(action.tier - 1)
	detect -= 0.10 * float(ctx.get("avg_skill", 0.0))
	return clampf(detect, 0.02, 0.90)
