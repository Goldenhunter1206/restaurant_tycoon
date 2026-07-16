class_name CrimeReconciliation
extends RefCounted
## Static acceptance suite for feature 12 (crime & sabotage).
##
## Maps to the feature-plan acceptance criteria: operations resolve
## deterministically from their stored seed (and reproduce across a re-derive),
## evidence / attribution / success / heat are four independent outcomes,
## effects expire, the enforcement ladder (fine → raid) fires on heat +
## evidence, and the v12 save section round-trips / migrates.
##
## Headless caveat (see tests/awards_reconciliation.gd): SaveGame pulls the
## CompanyState compile chain, so it is built via load().new() at run time. The
## crime data/service classes are autoload-free and safe to name.
## Run via scripts/tests/test_crime.gd.

const SG_SCRIPT: String = "res://scripts/data/save_game.gd"
const SS_SCRIPT: String = "res://scripts/data/save_system.gd"
const TMP_PATH: String = "user://test_crime_roundtrip.tres"

static var _checks: int = 0


static func run() -> Dictionary:
	_checks = 0
	var failures: Array[String] = []
	_test_resolver_determinism(failures)
	_test_outcomes_independent(failures)
	_test_preview_security_monotonic(failures)
	_test_security_score(failures)
	_test_heat_decay_and_enforcement(failures)
	_test_confidence_attribution(failures)
	_test_effect_expiry(failures)
	_test_action_mode_gating(failures)
	_test_agent_availability(failures)
	_test_state_roundtrip(failures)
	_test_migration_v12(failures)
	return {"ok": failures.is_empty(), "checks": _checks, "failures": failures}


static func _expect(cond: bool, message: String, failures: Array[String]) -> void:
	_checks += 1
	if not cond:
		failures.append(message)


# --- Builders --------------------------------------------------------------

static func _tuning() -> Callable:
	return func(_path: String, fallback: Variant) -> Variant: return fallback


static func _resolver() -> CrimeResolver:
	var r: CrimeResolver = CrimeResolver.new()
	r.configure(_tuning())
	return r


static func _action(tier: int = 1, mode: StringName = &"standard") -> CrimeActionDef:
	var def: CrimeActionDef = CrimeActionDef.new()
	def.id = &"test_action"
	def.tier = tier
	def.base_success = 0.6
	def.skill_weight = 0.25
	def.security_weight = 0.35
	def.evidence_base = 0.3
	def.heat_base = 8.0
	def.min_crime_mode = mode
	return def


## Mirrors WorkforceRng.make's keying without the tree lookup (which throws
## from a RefCounted outside the active scene tree). Determinism is what we
## test — identical keys must reproduce.
static func _seeded(domain: StringName, day: int, keys: Array) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var key: String = "%d:%s:%d" % [0, domain, day]
	for part: Variant in keys:
		key += ":" + str(part)
	rng.seed = hash(key)
	return rng


static func _ctx(security: float, skill: float = 0.5) -> Dictionary:
	return {
		"avg_skill": skill, "equipment_tier": 0, "intel_level": 0.0,
		"security_score": security, "alert_level": &"normal",
		"has_cameras": false, "agent_count": 1,
	}


# --- Tests -----------------------------------------------------------------

static func _test_resolver_determinism(failures: Array[String]) -> void:
	var resolver: CrimeResolver = _resolver()
	var def: CrimeActionDef = _action()
	var ctx: Dictionary = _ctx(0.3)
	# Same frozen seed (seed_day + op uid) reproduces the identical outcome.
	var rng_a: RandomNumberGenerator = _seeded(&"crime_resolve", 12, [7])
	var rng_b: RandomNumberGenerator = _seeded(&"crime_resolve", 12, [7])
	var out_a: Dictionary = resolver.resolve(def, ctx, rng_a)
	var out_b: Dictionary = resolver.resolve(def, ctx, rng_b)
	_expect(out_a["success"] == out_b["success"] and out_a["detected"] == out_b["detected"],
		"resolve must reproduce success/detected from the frozen seed", failures)
	_expect(is_equal_approx(float(out_a["evidence"]), float(out_b["evidence"])),
		"resolve must reproduce evidence from the frozen seed", failures)
	# A different op uid produces an independent stream.
	var rng_c: RandomNumberGenerator = _seeded(&"crime_resolve", 12, [8])
	var out_c: Dictionary = resolver.resolve(def, ctx, rng_c)
	_expect(out_c.has("agent_outcomes"), "resolve returns agent outcomes", failures)


static func _test_outcomes_independent(failures: Array[String]) -> void:
	var resolver: CrimeResolver = _resolver()
	var def: CrimeActionDef = _action()
	var ctx: Dictionary = _ctx(0.5)
	# Across many seeded runs, evidence accrues even when the op fails, proving
	# evidence is independent of success.
	var evidence_on_failure: bool = false
	var success_seen: bool = false
	var failure_seen: bool = false
	for i: int in range(60):
		var rng: RandomNumberGenerator = _seeded(&"crime_resolve", 1, [i])
		var out: Dictionary = resolver.resolve(def, ctx, rng)
		if bool(out["success"]):
			success_seen = true
		else:
			failure_seen = true
			if float(out["evidence"]) > 0.0:
				evidence_on_failure = true
	_expect(success_seen and failure_seen, "resolver must produce both successes and failures", failures)
	_expect(evidence_on_failure, "evidence must accrue even on failed operations", failures)
	# preview keeps the three risks as distinct quantities.
	var odds: Dictionary = resolver.preview(def, ctx)
	_expect(odds.has("success_chance") and odds.has("detection_chance") and odds.has("evidence_risk"),
		"preview exposes success, detection and evidence separately", failures)


static func _test_preview_security_monotonic(failures: Array[String]) -> void:
	var resolver: CrimeResolver = _resolver()
	var def: CrimeActionDef = _action()
	var soft: float = float(resolver.preview(def, _ctx(0.1))["success_chance"])
	var hard: float = float(resolver.preview(def, _ctx(0.8))["success_chance"])
	_expect(soft > hard, "higher target security must lower success chance", failures)
	var soft_detect: float = float(resolver.preview(def, _ctx(0.1))["detection_chance"])
	var hard_detect: float = float(resolver.preview(def, _ctx(0.8))["detection_chance"])
	_expect(hard_detect > soft_detect, "higher target security must raise detection", failures)


static func _test_security_score(failures: Array[String]) -> void:
	var svc: SecurityService = SecurityService.new()
	svc.configure(_tuning())
	var sec: SecurityState = SecurityState.new()
	var bare: float = svc.security_score(sec, 0.0)
	sec.equipment_level = 2
	var equipped: float = svc.security_score(sec, 0.0)
	var guarded: float = svc.security_score(sec, 0.8)
	_expect(equipped > bare, "equipment must raise the security score", failures)
	_expect(guarded > equipped, "guards must raise the security score", failures)
	sec.equipment_level = 3
	sec.alert_level = &"lockdown"
	_expect(svc.security_score(sec, 1.0) <= 0.95, "security score is clamped to 0.95", failures)
	_expect(svc.alert_penalty(sec) > 0.0, "lockdown carries a demand penalty", failures)


static func _test_heat_decay_and_enforcement(failures: Array[String]) -> void:
	var heat_svc: HeatService = HeatService.new()
	heat_svc.configure(_tuning())
	var state: CompanyHeatState = CompanyHeatState.new()
	var def: CrimeActionDef = _action()
	state.heat = 30.0
	heat_svc.decay(state)
	_expect(state.heat < 30.0, "heat must decay over a day", failures)
	# No evidence → no enforcement even at high heat.
	state.heat = 90.0
	_expect(StringName(heat_svc.enforcement_check(state)["action"]) == &"none",
		"heat alone (no evidence) must not trigger enforcement", failures)
	# Enough heat + evidence → a fine, then a raid as both climb.
	state.evidence.append({"strength": 0.8})
	state.heat = 45.0
	_expect(StringName(heat_svc.enforcement_check(state)["action"]) == &"fine",
		"heat + evidence over the fine threshold triggers a fine", failures)
	state.evidence.append({"strength": 1.0})
	state.heat = 80.0
	_expect(StringName(heat_svc.enforcement_check(state)["action"]) == &"raid",
		"high heat + strong evidence triggers a raid", failures)
	var _unused: CrimeActionDef = def


static func _test_confidence_attribution(failures: Array[String]) -> void:
	var heat_svc: HeatService = HeatService.new()
	heat_svc.configure(_tuning())
	var low: float = heat_svc.confidence(0.3, 0, false)
	var with_cams: float = heat_svc.confidence(0.3, 3, false)
	var with_police: float = heat_svc.confidence(0.3, 3, true)
	_expect(with_cams > low, "surveillance must raise attribution confidence", failures)
	_expect(with_police > with_cams, "police involvement must raise confidence further", failures)
	_expect(not heat_svc.attribution_known(0.1), "weak evidence stays anonymous", failures)
	_expect(heat_svc.attribution_known(0.9), "strong evidence names the attacker", failures)


static func _test_effect_expiry(failures: Array[String]) -> void:
	var sec: SecurityState = SecurityState.new()
	sec.active_effects.append({"kind": &"demand_debuff", "magnitude": 0.2, "until_day": 5})
	sec.active_effects.append({"kind": &"demand_debuff", "magnitude": 0.1, "until_day": 2})
	_expect(is_equal_approx(sec.effect_total(&"demand_debuff", 2), 0.3),
		"effect_total sums all effects still active on the day", failures)
	_expect(is_equal_approx(sec.effect_total(&"demand_debuff", 4), 0.2),
		"expired effects drop out of effect_total", failures)
	sec.prune_effects(4)
	_expect(sec.active_effects.size() == 1, "prune_effects removes expired rows", failures)


static func _test_action_mode_gating(failures: Array[String]) -> void:
	var nuisance: CrimeActionDef = _action(1, &"standard")
	var violent: CrimeActionDef = _action(3, &"ruthless")
	_expect(nuisance.allowed_in_mode(&"standard"), "standard actions run in standard mode", failures)
	_expect(nuisance.allowed_in_mode(&"ruthless"), "standard actions run in ruthless mode", failures)
	_expect(not violent.allowed_in_mode(&"standard"), "violent actions are barred from standard mode", failures)
	_expect(violent.allowed_in_mode(&"ruthless"), "violent actions run in ruthless mode", failures)


static func _test_agent_availability(failures: Array[String]) -> void:
	var agent: CriminalAgentState = CriminalAgentState.new()
	_expect(agent.is_available(5), "a fresh idle agent is available", failures)
	agent.incarcerated_until_day = 10
	_expect(not agent.is_available(5), "a jailed agent is unavailable", failures)
	_expect(agent.is_available(10), "the agent frees up once the sentence ends", failures)
	agent.incarcerated_until_day = 0
	agent.assignment_op_uid = 3
	_expect(not agent.is_available(5), "an assigned agent is unavailable", failures)


static func _test_state_roundtrip(failures: Array[String]) -> void:
	var save: Resource = load(SG_SCRIPT).new()
	save.crime_schema_version = 1
	var agent: CriminalAgentState = CriminalAgentState.new()
	agent.uid = 42
	agent.role = &"enforcer"
	agent.skill = 0.66
	save.crime_agents = [agent] as Array[CriminalAgentState]
	var op: CrimeOperationState = CrimeOperationState.new()
	op.uid = 7
	op.action_id = &"graffiti"
	op.seed_day = 12
	op.evidence = 0.4
	op.outcome_applied = true
	save.crime_operations = [op] as Array[CrimeOperationState]
	var heat_state: CompanyHeatState = CompanyHeatState.new()
	heat_state.company_id = &"player"
	heat_state.heat = 33.0
	save.crime_heat_states = [heat_state] as Array[CompanyHeatState]
	save.crime_intel = {"intel": {"player": {"pronto": 20}}, "cooldowns": {}}
	save.crime_op_next_uid = 8
	var err: int = ResourceSaver.save(save, TMP_PATH)
	_expect(err == OK, "crime save section writes without error", failures)
	var loaded: Resource = ResourceLoader.load(TMP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(loaded != null and loaded.crime_operations.size() == 1,
		"crime operations survive the save/load roundtrip", failures)
	if loaded != null and loaded.crime_operations.size() == 1:
		var op2: CrimeOperationState = loaded.crime_operations[0]
		_expect(op2.uid == 7 and op2.seed_day == 12 and op2.outcome_applied,
			"operation seed and once-only guard round-trip intact", failures)
	if loaded != null and loaded.crime_agents.size() == 1:
		_expect((loaded.crime_agents[0] as CriminalAgentState).role == &"enforcer",
			"crew role round-trips", failures)
	if loaded != null:
		_expect(int(loaded.crime_op_next_uid) == 8, "next-uid counter round-trips", failures)


static func _test_migration_v12(failures: Array[String]) -> void:
	var save: Resource = load(SG_SCRIPT).new()
	save.save_version = 11
	save.crime_schema_version = 0
	var system: Object = load(SS_SCRIPT)
	system.call("_migrate_v12", save)
	_expect(int(save.crime_schema_version) == 1, "migration marks the crime section present", failures)
	_expect(int(save.save_version) == 12, "migration bumps the save version to 12", failures)
