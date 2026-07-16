extends SceneTree
## Headless contract tests for campaign catalogs, deterministic session data,
## objective operators/lifecycles, frozen results, and idempotent progression.
## Run: godot --headless --path . --script res://scripts/tests/test_campaign_modes.gd

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_test_catalog()
	_test_session_round_trip()
	_test_objective_lifecycle()
	_test_scenario_state_round_trip()
	_test_result_freeze()
	_test_profile_commit_ledger()
	_test_operators()
	if _failures.is_empty():
		print("PASS test_campaign_modes: %d checks OK" % _checks)
		quit(0)
		return
	printerr("FAIL test_campaign_modes: %d failure(s)" % _failures.size())
	for message: String in _failures:
		printerr("  FAIL: %s" % message)
	quit(1)


func _test_catalog() -> void:
	var catalog_script: GDScript = load("res://scripts/campaign/scenario_catalog.gd")
	var catalog: RefCounted = catalog_script.new() as RefCounted
	_check(bool(catalog.call("load_all")), "catalogs load without link errors")
	_check((catalog.get("cities") as Dictionary).size() == 3, "three city definitions load")
	_check((catalog.get("scenarios") as Dictionary).size() == 8, "eight scenarios load")
	_check((catalog.get("campaigns") as Dictionary).size() == 1, "one campaign loads")
	var metrics: Array[StringName] = [
		&"cash", &"profit_today", &"reputation", &"restaurant_count",
		&"deliveries", &"awards", &"day", &"action",
	]
	var rivals: Array[StringName] = [
		&"alto", &"bella2", &"nonna", &"pronto", &"slice", &"swift",
	]
	var validation: Array = catalog.call("validate_content", metrics, rivals)
	_check(validation.is_empty(), "catalog metrics, rivals, and prerequisites validate: %s" % str(validation))
	_check(StringName(catalog.call("next_scenario_id", &"bella_vista_rise",
		&"campaign_riverside_opening")) == &"campaign_harbor_rush",
		"campaign chapter order resolves")
	_check((catalog.call("scenarios_for_mode", &"challenge") as Array).size() == 3,
		"three challenge fixtures are discoverable")


func _test_session_round_trip() -> void:
	var script: GDScript = load("res://scripts/data/game_session_config.gd")
	var config: Resource = script.new() as Resource
	config.set("mode", &"challenge")
	config.set("seed", 424242)
	config.set("city_id", &"harbor_quarter")
	config.set("scenario_id", &"challenge_delivery_dash")
	config.set("difficulty", &"hard")
	config.set("company_identity", {"display_name": "Bella Test", "brand_color": "#EA4A2F"})
	config.set("starting_resources", {"cash": 9000, "reputation": 3.0})
	var encoded: Dictionary = config.call("to_dict")
	var restored: Resource = script.call("from_dict", encoded) as Resource
	_check(int(restored.get("seed")) == 424242, "session seed round-trips")
	_check(StringName(restored.get("scenario_id")) == &"challenge_delivery_dash",
		"session scenario round-trips")
	_check((restored.call("to_dict") as Dictionary) == encoded,
		"session configuration serialization is deterministic")


func _test_objective_lifecycle() -> void:
	var script: GDScript = load("res://scripts/data/objective_state.gd")
	var state: Resource = script.new() as Resource
	_check(bool(state.call("transition_to", &"revealed", 0.0, "offered")),
		"hidden objective can reveal")
	_check(bool(state.call("transition_to", &"active", 0.1, "accepted")),
		"revealed objective can activate")
	_check(bool(state.call("transition_to", &"completed", 1.0, "target_reached")),
		"active objective can complete")
	_check(bool(state.call("is_terminal")), "completed objective is terminal")
	_check(not bool(state.call("transition_to", &"active", 2.0, "invalid")),
		"terminal objective cannot reactivate")


func _test_scenario_state_round_trip() -> void:
	var state_script: GDScript = load("res://scripts/data/scenario_state.gd")
	var objective_script: GDScript = load("res://scripts/data/objective_state.gd")
	var scenario_state: Resource = state_script.new() as Resource
	var objective_state: Resource = objective_script.new() as Resource
	objective_state.set("objective_id", &"cash_goal")
	objective_state.set("lifecycle_state", &"active")
	(scenario_state.get("objective_states") as Array).append(objective_state)
	scenario_state.set("scenario_id", &"sandbox_free_play")
	scenario_state.set("completion_state", &"succeeded")
	var restored: Resource = state_script.call(
		"from_dict", scenario_state.call("to_dict")) as Resource
	_check(bool(restored.call("is_terminal")), "succeeded scenario is terminal after load")
	_check((restored.get("objective_states") as Array).size() == 1,
		"objective state survives scenario round-trip")


func _test_result_freeze() -> void:
	var script: GDScript = load("res://scripts/data/scenario_result_snapshot.gd")
	var snapshot: Resource = script.new() as Resource
	snapshot.set("result_id", &"result-one")
	(snapshot.get("completed_objectives") as Array).append(&"cash_goal")
	snapshot.call("freeze")
	_check(bool(snapshot.call("is_frozen")), "result snapshot freezes")
	var restored: Resource = script.call("from_dict", snapshot.call("to_dict")) as Resource
	_check(bool(restored.call("is_frozen")), "frozen result survives round-trip")
	_check((restored.get("completed_objectives") as Array).has(&"cash_goal"),
		"frozen result retains objective evidence")


func _test_profile_commit_ledger() -> void:
	var script: GDScript = load("res://scripts/data/player_profile_state.gd")
	var profile: Resource = script.new() as Resource
	_check(bool(profile.call("commit_result_id", &"result-one")),
		"first profile result commit succeeds")
	_check(not bool(profile.call("commit_result_id", &"result-one")),
		"duplicate profile result commit is rejected")
	profile.call("record_scenario_completion", &"challenge_delivery_dash", 6100.0, &"silver")
	profile.call("record_scenario_completion", &"challenge_delivery_dash", 5900.0, &"bronze")
	_check(float((profile.get("best_scores") as Dictionary).get(
		"challenge_delivery_dash", 0.0)) == 6100.0, "best score cannot regress")
	_check(String((profile.get("medals") as Dictionary).get(
		"challenge_delivery_dash", "")) == "silver", "medal cannot regress")


func _test_operators() -> void:
	var script: GDScript = load("res://scripts/campaign/scenario_manager.gd")
	_check(bool(script.call("operator_satisfied", 10.0, &">=", 10.0)), ">= operator")
	_check(bool(script.call("operator_satisfied", 4.0, &"<=", 5.0)), "<= operator")
	_check(bool(script.call("operator_satisfied", 3.0, &"==", 3.0)), "== operator")
	_check(bool(script.call("operator_satisfied", 2.0, &"gte", 2.0)), "gte alias")
	_check(not bool(script.call("operator_satisfied", 2.0, &">", 2.0)),
		"strict greater-than operator")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
