extends SceneTree
## Headless unit tests for workforce depth (v8): deterministic RNG, training
## throughput penalty, multi-competency training gains, role skill weighting,
## interview-gated candidate info, and new-field resource round-trip.
## Run: godot --headless --script res://scripts/tests/test_workforce.gd

var _failures: int = 0


func _initialize() -> void:
	_test_rng_determinism()
	_test_operational_effect_training()
	_test_effective_gains()
	_test_weighted_competencies()
	_test_shown_competency()
	_test_resource_roundtrip()
	if _failures == 0:
		print("PASS test_workforce: all scenarios OK")
		quit(0)
	else:
		printerr("FAIL test_workforce: %d failure(s)" % _failures)
		quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("  FAIL: %s" % label)


func _test_rng_determinism() -> void:
	var a: RandomNumberGenerator = WorkforceRng.make(&"resign", 5, [12, 7])
	var b: RandomNumberGenerator = WorkforceRng.make(&"resign", 5, [12, 7])
	var seq_a: Array = [a.randf(), a.randf(), a.randf()]
	var seq_b: Array = [b.randf(), b.randf(), b.randf()]
	_check(seq_a == seq_b, "identical (domain,day,keys) -> identical stream")
	_check(WorkforceRng.make(&"resign", 5, [12, 7]).seed != WorkforceRng.make(&"market", 5, [12, 7]).seed,
		"domain changes the seed")
	_check(WorkforceRng.make(&"resign", 5, [12, 7]).seed != WorkforceRng.make(&"resign", 6, [12, 7]).seed,
		"day changes the seed")
	_check(WorkforceRng.make(&"resign", 5, [12, 7]).seed != WorkforceRng.make(&"resign", 5, [12, 8]).seed,
		"keys change the seed")


func _test_operational_effect_training() -> void:
	var m: StaffMember = StaffMember.new()
	m.competencies = {&"service": 1.0}
	m.energy = 1.0
	m.health = 1.0
	m.motivation = 1.0
	m.satisfaction = 1.0
	m.fatigue = 0.0
	m.stress = 0.0
	var full: float = m.operational_effect(&"service")
	m.active_training_penalty = 0.3
	var trained: float = m.operational_effect(&"service")
	_check(trained < full, "training penalty reduces operational effect")
	_check(full <= 1.05 and trained >= 0.70, "operational effect stays within safety bounds")


func _test_effective_gains() -> void:
	var p: TrainingProgramDef = TrainingProgramDef.new()
	p.competency_id = &"speed"
	p.competency_gain = 0.08
	_check(p.effective_gains() == {&"speed": 0.08}, "single-competency fallback")
	p.competency_gains = {&"speed": 0.05, &"consistency": 0.03}
	_check(p.effective_gains().size() == 2, "multi-competency gains used when set")


func _test_weighted_competencies() -> void:
	var d: StaffTypeDef = StaffTypeDef.new()
	d.competency_keys = [&"a", &"b"] as Array[StringName]
	_check(d.weighted_competencies().size() == 2, "falls back to competency_keys")
	d.skill_weights = {&"a": 1.5}
	_check(d.weighted_competencies() == {&"a": 1.5}, "uses explicit skill_weights")


func _test_shown_competency() -> void:
	var c: JobCandidate = JobCandidate.new()
	c.competencies = {&"service": 0.9}
	c.revealed_competencies = {&"service": 0.4}
	c.interview_state = &"unseen"
	_check(is_equal_approx(c.shown_competency(&"service"), 0.4), "hidden candidate shows revealed estimate")
	c.interview_state = &"interviewed"
	_check(is_equal_approx(c.shown_competency(&"service"), 0.9), "interviewed candidate shows true skill")


func _test_resource_roundtrip() -> void:
	var m: StaffMember = StaffMember.new()
	m.staff_name = "Test"
	m.loyalty = 0.7
	m.desired_wage = 12.5
	m.home_building_id = 42
	m.resignation_committed_day = 3
	m.goals = [{&"kind": &"skill", &"completed": false}]
	var path: String = "user://__wf_test_member.tres"
	ResourceSaver.save(m, path)
	var loaded: StaffMember = load(path) as StaffMember
	_check(loaded != null, "member resource loads")
	if loaded != null:
		_check(is_equal_approx(loaded.loyalty, 0.7), "loyalty persists")
		_check(loaded.home_building_id == 42, "home_building_id persists")
		_check(loaded.resignation_committed_day == 3, "resignation_committed_day persists")
		_check(loaded.goals.size() == 1, "goals persist")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
