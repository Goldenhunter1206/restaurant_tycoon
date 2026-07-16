class_name ScenarioManager
extends Node
## Runtime authority for scenario initialization, objective evaluation, timed
## events, tutorial observations, side missions, failure, results, and restart.

signal scenario_initialized(definition: ScenarioDef)
signal objective_updated(objective_id: StringName, state: ObjectiveState)
signal objective_resolved(objective_id: StringName, state: ObjectiveState)
signal side_mission_offered(objective_id: StringName, definition: ObjectiveDef)
signal tutorial_prompted(objective_id: StringName, allow_skip: bool, allow_reset: bool)
signal scenario_completed(result: ScenarioResultSnapshot)
signal scenario_failed(result: ScenarioResultSnapshot)
signal runtime_changed()

const RECONCILE_MINUTES: int = 30
const REQUIRED_OBJECTIVE_POINTS: float = 1000.0
const OPTIONAL_OBJECTIVE_POINTS: float = 750.0

var catalog: ScenarioCatalog
var campaign_manager: CampaignManager
var registry: ObjectiveMetricRegistry
var config: GameSessionConfig
var definition: ScenarioDef
var state: ScenarioState
var result: ScenarioResultSnapshot

var _definition_data: Dictionary = {}
var _objective_defs: Dictionary = {}
var _objective_data: Dictionary = {}
var _resolved_rewards: Array[Dictionary] = []
var _initialized: bool = false
var _signals_connected: bool = false
var _reconcile_queued: bool = false
var _start_total_minutes: int = 0


func setup(content_catalog: ScenarioCatalog, progression: CampaignManager) -> void:
	catalog = content_catalog
	campaign_manager = progression
	var registry_script: GDScript = load("res://scripts/campaign/objective_metric_registry.gd")
	registry = registry_script.new() as ObjectiveMetricRegistry
	_register_builtin_metrics()
	var known_rivals: Array[StringName] = []
	var content_errors: Array[String] = catalog.validate_content(
		registry.metric_ids(), known_rivals)
	if not content_errors.is_empty():
		push_error("ScenarioManager: invalid scenario content: %s" % str(content_errors))
	_connect_runtime_signals()


func initialize(session_config: GameSessionConfig, saved_state: Dictionary = {},
		saved_result: Dictionary = {}) -> bool:
	config = session_config
	if config == null or catalog == null:
		push_error("ScenarioManager: setup and a session config are required")
		return false
	_definition_data = catalog.scenario(config.scenario_id)
	if _definition_data.is_empty():
		push_error("ScenarioManager: unknown scenario %s" % config.scenario_id)
		return false
	var scenario_script: Script = load("res://scripts/data/scenario_def.gd") as Script
	definition = scenario_script.call("from_dict", _definition_data) as ScenarioDef
	_build_objective_definitions()
	_resolved_rewards.clear()
	result = null
	if not saved_state.is_empty() and StringName(String(saved_state.get(
			"scenario_id", ""))) == definition.id:
		var state_script: Script = load("res://scripts/data/scenario_state.gd") as Script
		state = state_script.call("from_dict", saved_state) as ScenarioState
		_start_total_minutes = int(state.progress_snapshots.get(
			"start_total_minutes", GameClock.total_minutes()))
	else:
		state = _create_state()
		_start_total_minutes = GameClock.total_minutes()
		state.progress_snapshots["start_total_minutes"] = _start_total_minutes
		state.completion_state = &"active"
	if not saved_result.is_empty() and StringName(String(saved_result.get(
			"scenario_id", ""))) == definition.id:
		var result_script: Script = load(
			"res://scripts/data/scenario_result_snapshot.gd") as Script
		result = result_script.call("from_dict", saved_result) as ScenarioResultSnapshot
	_initialized = true
	_apply_capability_restrictions()
	_activate_available_objectives()
	_process_scripted_events()
	reconcile()
	scenario_initialized.emit(definition)
	if state.is_terminal() and result != null:
		if result.outcome == &"success":
			scenario_completed.emit(result)
		else:
			scenario_failed.emit(result)
	runtime_changed.emit()
	return true


func reset_runtime() -> void:
	_initialized = false
	definition = null
	state = null
	result = null
	_definition_data.clear()
	_objective_defs.clear()
	_objective_data.clear()
	_resolved_rewards.clear()
	_reconcile_queued = false


func register_metric(metric_id: StringName, evaluator: Callable,
		formatter: Callable = Callable(), description: String = "") -> bool:
	if registry == null:
		var registry_script: GDScript = load("res://scripts/campaign/objective_metric_registry.gd")
		registry = registry_script.new() as ObjectiveMetricRegistry
	return registry.register_metric(metric_id, evaluator, formatter, description)


func metric_value(metric_id: StringName, filters: Dictionary = {}) -> Dictionary:
	if registry == null:
		return {"ok": false, "value": 0.0, "explanation": "Registry not ready"}
	return registry.evaluate(metric_id, filters)


func objective_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if state == null:
		return rows
	for objective_state: ObjectiveState in state.objective_states:
		var objective: ObjectiveDef = _objective_defs.get(objective_state.objective_id)
		if objective == null or objective_state.lifecycle_state == &"hidden":
			continue
		rows.append({
			"id": objective.id,
			"text": objective.text,
			"metric": objective.metric,
			"operator": objective.operator,
			"target": objective.target,
			"target_text": registry.format_value(objective.metric, objective.target, objective.filters),
			"current": objective_state.current_value,
			"current_text": registry.format_value(objective.metric, objective_state.current_value, objective.filters),
			"state": objective_state.lifecycle_state,
			"optional": objective.optional,
			"accepted": objective_state.accepted,
			"deadline": objective.deadline.duplicate(true),
			"reward": objective.reward.duplicate(true),
			"explanation": String(objective_state.progress_snapshot.get("explanation", "")),
		})
	return rows


func upcoming_events(count: int = 3) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state == null:
		return events
	for value: Variant in _definition_data.get("scripted_events", _definition_data.get("events", [])):
		if value is not Dictionary:
			continue
		var event: Dictionary = value
		var event_id: StringName = StringName(String(event.get("id", "")))
		if state.fired_event_ids.has(event_id):
			continue
		var trigger: Dictionary = event.get("trigger", {})
		events.append({
			"id": event_id,
			"kind": String(event.get("action", "scenario")),
			"title": String((event.get("payload", {}) as Dictionary).get(
				"title", String(event_id).capitalize())),
			"when": _trigger_description(trigger),
		})
		if events.size() >= count:
			break
	return events


func accept_side_mission(objective_id: StringName) -> bool:
	if state == null:
		return false
	var objective_state: ObjectiveState = state.objective_state_by_id(objective_id) as ObjectiveState
	var objective: ObjectiveDef = _objective_defs.get(objective_id)
	if objective_state == null or objective == null or not objective.optional:
		return false
	if objective_state.is_terminal():
		return false
	objective_state.accepted = true
	state.accept_side_mission(objective_id)
	objective_state.transition_to(&"active", state.elapsed_time_days, "accepted")
	objective_updated.emit(objective_id, objective_state)
	reconcile()
	return true


func decline_side_mission(objective_id: StringName) -> bool:
	if state == null:
		return false
	var objective_state: ObjectiveState = state.objective_state_by_id(objective_id) as ObjectiveState
	var objective: ObjectiveDef = _objective_defs.get(objective_id)
	if objective_state == null or objective == null or not objective.optional:
		return false
	if objective_state.is_terminal():
		return false
	objective_state.transition_to(&"expired", state.elapsed_time_days, "declined")
	objective_updated.emit(objective_id, objective_state)
	objective_resolved.emit(objective_id, objective_state)
	return true


func observe_action(action_id: StringName, payload: Dictionary = {}) -> void:
	if state == null or state.is_terminal():
		return
	var actions: Dictionary = state.progress_snapshots.get("actions", {})
	actions[action_id] = int(actions.get(action_id, 0)) + 1
	state.progress_snapshots["actions"] = actions
	if not payload.is_empty():
		var action_payloads: Dictionary = state.progress_snapshots.get("action_payloads", {})
		action_payloads[action_id] = payload.duplicate(true)
		state.progress_snapshots["action_payloads"] = action_payloads
	reconcile()


func skip_tutorial_step(objective_id: StringName = &"") -> bool:
	if config == null or config.mode != &"tutorial" or state == null:
		return false
	var objective_state: ObjectiveState = state.objective_state_by_id(objective_id) as ObjectiveState
	if objective_state == null:
		for candidate: ObjectiveState in state.objective_states:
			var candidate_def: ObjectiveDef = _objective_defs.get(candidate.objective_id)
			if candidate_def != null and not candidate_def.optional \
					and candidate.lifecycle_state == &"active":
				objective_state = candidate
				break
	if objective_state == null or objective_state.is_terminal():
		return false
	objective_state.reward_applied = true
	objective_state.transition_to(&"completed", state.elapsed_time_days, "skipped")
	objective_resolved.emit(objective_state.objective_id, objective_state)
	_activate_available_objectives()
	_check_completion()
	return true


func reset_tutorial() -> bool:
	if config == null or config.mode != &"tutorial":
		return false
	return initialize(config, {})


func reconcile() -> void:
	_reconcile_queued = false
	if not _initialized or state == null or state.is_terminal():
		return
	state.elapsed_time_days = maxf(0.0, float(
		GameClock.total_minutes() - _start_total_minutes) / 1440.0)
	_process_scripted_events()
	_activate_available_objectives()
	for objective_state: ObjectiveState in state.objective_states:
		if objective_state.lifecycle_state != &"active":
			continue
		_evaluate_objective(objective_state)
		if state.is_terminal():
			break
	if not state.is_terminal():
		_check_failure_outcomes()
	if not state.is_terminal():
		_check_completion()
	runtime_changed.emit()


func fail(reason: String, consequence: Dictionary = {}) -> void:
	if state == null or state.is_terminal():
		return
	state.failure_reason = reason
	state.completion_state = &"failed"
	_apply_consequence(consequence)
	_freeze_result(&"failure")
	GameClock.set_speed(0)
	scenario_failed.emit(result)
	runtime_changed.emit()


func continue_in_free_play() -> void:
	if state == null or not state.is_terminal():
		return
	state.completion_state = &"results"
	GameClock.set_speed(1)
	runtime_changed.emit()


func session_state_dict() -> Dictionary:
	return state.to_dict() if state != null else {}


func result_dict() -> Dictionary:
	return result.to_dict() if result != null else {}


func _create_state() -> ScenarioState:
	var state_script: GDScript = load("res://scripts/data/scenario_state.gd")
	var scenario_state: ScenarioState = state_script.new() as ScenarioState
	scenario_state.session_id = StringName("%s-%s" % [
		definition.id, str(abs(config.seed if config.seed != 0 else randi()))])
	scenario_state.campaign_id = definition.campaign_id
	scenario_state.scenario_id = definition.id
	scenario_state.city_id = definition.city_id
	scenario_state.completion_state = &"intro"
	scenario_state.progress_snapshots["starting_values"] = config.starting_resources.duplicate(true)
	for objective_id: StringName in _objective_defs:
		var objective: ObjectiveDef = _objective_defs[objective_id]
		var objective_state_script: GDScript = load("res://scripts/data/objective_state.gd")
		var objective_state: ObjectiveState = objective_state_script.new() as ObjectiveState
		objective_state.objective_id = objective.id
		objective_state.target_value = objective.target
		objective_state.lifecycle_state = objective.initial_state
		if objective_state.lifecycle_state == &"":
			objective_state.lifecycle_state = &"hidden" if objective.starts_hidden() else &"active"
		objective_state.accepted = not objective.optional
		scenario_state.objective_states.append(objective_state)
	return scenario_state


func _build_objective_definitions() -> void:
	_objective_defs.clear()
	_objective_data.clear()
	var records: Array = []
	records.append_array(_definition_data.get("objectives", []))
	records.append_array(_definition_data.get("side_missions", []))
	for value: Variant in records:
		if value is not Dictionary:
			continue
		var data: Dictionary = (value as Dictionary).duplicate(true)
		var victory_rule: StringName = StringName(String(data.get("victory_rule", "")))
		if config != null and config.mode == &"free_play" and victory_rule != &"" \
				and not _free_play_rule_enabled(victory_rule):
			continue
		if String(data.get("kind", "required")) == "optional":
			data["optional"] = true
		var objective_script: Script = load("res://scripts/data/objective_def.gd") as Script
		var objective: ObjectiveDef = objective_script.call("from_dict", data) as ObjectiveDef
		if objective.id == &"":
			continue
		_objective_defs[objective.id] = objective
		_objective_data[objective.id] = data


func _activate_available_objectives() -> void:
	for objective_state: ObjectiveState in state.objective_states:
		if objective_state.is_terminal() or objective_state.lifecycle_state == &"active":
			continue
		var objective: ObjectiveDef = _objective_defs.get(objective_state.objective_id)
		if objective == null or not _prerequisites_complete(objective):
			continue
		var data: Dictionary = _objective_data.get(objective.id, {})
		var accept_required: bool = bool(data.get("accept_required", objective.optional))
		if objective.optional and accept_required and not objective_state.accepted:
			if objective_state.lifecycle_state == &"hidden" and int(data.get("offer_day", 0)) <= GameClock.day:
				objective_state.transition_to(&"revealed", state.elapsed_time_days, "available")
				objective_updated.emit(objective.id, objective_state)
			continue
		objective_state.accepted = true
		objective_state.transition_to(&"active", state.elapsed_time_days, "prerequisites_complete")
		objective_updated.emit(objective.id, objective_state)


func _evaluate_objective(objective_state: ObjectiveState) -> void:
	var objective: ObjectiveDef = _objective_defs.get(objective_state.objective_id)
	if objective == null:
		return
	var objective_data: Dictionary = _objective_data.get(objective.id, {})
	if String(objective_data.get("evaluation", "")) == "at_scenario_completion":
		return
	var metric: Dictionary = registry.evaluate(objective.metric, objective.filters)
	objective_state.current_value = float(metric.get("value", 0.0))
	objective_state.progress_snapshot = metric.duplicate(true)
	objective_state.progress_snapshot["target"] = objective.target
	objective_updated.emit(objective.id, objective_state)
	if _deadline_missed(objective):
		objective_state.transition_to(&"expired", state.elapsed_time_days, "deadline")
		_apply_failure_consequence(objective, objective_state)
		objective_resolved.emit(objective.id, objective_state)
		if not objective.optional:
			fail("Objective expired: %s" % objective.text, objective.failure_consequence)
		return
	var satisfied: bool = operator_satisfied(
		objective_state.current_value, objective.operator, objective.target,
		objective.metric == &"action")
	if objective.maintain_duration > 0.0:
		if satisfied:
			objective_state.maintain_elapsed += float(RECONCILE_MINUTES) / 1440.0
			satisfied = objective_state.maintain_elapsed >= objective.maintain_duration
		else:
			objective_state.maintain_elapsed = 0.0
	if not satisfied:
		return
	objective_state.transition_to(&"completed", state.elapsed_time_days, "target_reached")
	_apply_reward(objective, objective_state)
	objective_resolved.emit(objective.id, objective_state)
	_activate_available_objectives()


func _deadline_missed(objective: ObjectiveDef) -> bool:
	if objective.deadline.is_empty():
		return false
	var metric_id: StringName = StringName(String(objective.deadline.get("metric", "day")))
	var deadline_metric: Dictionary = registry.evaluate(metric_id,
		objective.deadline.get("filters", {}))
	var value: float = float(deadline_metric.get("value", 0.0))
	var operator: StringName = StringName(String(objective.deadline.get("operator", "<=")))
	var target: float = float(objective.deadline.get("target", 0.0))
	return not operator_satisfied(value, operator, target)


func _prerequisites_complete(objective: ObjectiveDef) -> bool:
	for prerequisite: StringName in objective.prerequisites:
		var prerequisite_state: ObjectiveState = state.objective_state_by_id(prerequisite) as ObjectiveState
		if prerequisite_state == null or prerequisite_state.lifecycle_state != &"completed":
			return false
	return true


func _check_completion() -> void:
	var has_required: bool = false
	for objective_state: ObjectiveState in state.objective_states:
		var objective: ObjectiveDef = _objective_defs.get(objective_state.objective_id)
		if objective == null or objective.optional:
			continue
		has_required = true
		if objective_state.lifecycle_state != &"completed":
			return
	if not has_required:
		return
	_resolve_completion_only_objectives()
	state.completion_state = &"succeeded"
	_freeze_result(&"success")
	GameClock.set_speed(0)
	scenario_completed.emit(result)
	runtime_changed.emit()


func _check_failure_outcomes() -> void:
	if definition.time_limit_days > 0.0 and state.elapsed_time_days > definition.time_limit_days:
		fail("Scenario deadline reached")
		return
	var failures: Array = definition.outcomes.get("failure", [])
	for value: Variant in failures:
		if value is not Dictionary:
			continue
		var failure_data: Dictionary = value
		var condition: Dictionary = failure_data.get("condition", {})
		if _condition_satisfied(condition):
			fail(String(failure_data.get("summary", failure_data.get("title", "Scenario failed"))),
				failure_data.get("consequence", {}))
			return


func _freeze_result(outcome: StringName) -> void:
	var result_script: GDScript = load("res://scripts/data/scenario_result_snapshot.gd")
	result = result_script.new() as ScenarioResultSnapshot
	result.result_id = StringName("%s-%s-%s" % [
		definition.id, state.session_id, str(Time.get_unix_time_from_system())])
	result.profile_id = campaign_manager.profile.profile_id if campaign_manager != null \
		and campaign_manager.profile != null else &"local"
	result.session_id = state.session_id
	result.mode = config.mode
	result.campaign_id = definition.campaign_id
	result.scenario_id = definition.id
	result.city_id = definition.city_id
	result.outcome = outcome
	result.elapsed_time_days = state.elapsed_time_days
	result.failure_reason = state.failure_reason
	result.completed_at_unix = int(Time.get_unix_time_from_system())
	result.event_flags = state.event_flags.duplicate(true)
	result.config_snapshot = config.to_dict()
	for objective_state: ObjectiveState in state.objective_states:
		var objective: ObjectiveDef = _objective_defs.get(objective_state.objective_id)
		if objective == null:
			continue
		match objective_state.lifecycle_state:
			&"completed":
				result.completed_objectives.append(objective.id)
				if objective.optional:
					result.optional_objectives_completed.append(objective.id)
			&"failed":
				result.failed_objectives.append(objective.id)
			&"expired":
				result.expired_objectives.append(objective.id)
	result.rewards = _resolved_rewards.duplicate(true)
	_score_result(result)
	result.freeze()
	state.score = result.score
	state.score_breakdown = result.score_breakdown.duplicate(true)
	state.result_id = result.result_id
	if campaign_manager != null:
		var campaign_definition: Dictionary = catalog.campaign(definition.campaign_id) \
			if definition.campaign_id != &"" else {}
		campaign_manager.commit_result(result, _definition_data, campaign_definition)


func _score_result(snapshot: ScenarioResultSnapshot) -> void:
	var breakdown: Dictionary = {}
	var score_value: float = 0.0
	for objective_state: ObjectiveState in state.objective_states:
		if objective_state.lifecycle_state != &"completed":
			continue
		var objective: ObjectiveDef = _objective_defs.get(objective_state.objective_id)
		if objective == null:
			continue
		var points: float = OPTIONAL_OBJECTIVE_POINTS if objective.optional else REQUIRED_OBJECTIVE_POINTS
		breakdown[String(objective.id)] = points
		score_value += points
	for value: Variant in _definition_data.get("score_components", []):
		if value is not Dictionary:
			continue
		var component: Dictionary = value
		if not _condition_satisfied(component):
			continue
		var points: float = float(component.get("points", 0.0))
		breakdown[String(component.get("label", component.get("id", "Score bonus")))] = points
		score_value += points
	snapshot.score = score_value
	snapshot.score_breakdown = breakdown
	var possible: float = maxf(score_value, _maximum_score())
	var ratio: float = score_value / possible if possible > 0.0 else 0.0
	if ratio >= 0.8:
		snapshot.medal = &"gold"
	elif ratio >= 0.6:
		snapshot.medal = &"silver"
	elif ratio >= 0.4:
		snapshot.medal = &"bronze"


func _maximum_score() -> float:
	var total: float = float(_objective_defs.size()) * REQUIRED_OBJECTIVE_POINTS
	for objective_id: StringName in _objective_defs:
		if (_objective_defs[objective_id] as ObjectiveDef).optional:
			total -= REQUIRED_OBJECTIVE_POINTS - OPTIONAL_OBJECTIVE_POINTS
	for value: Variant in _definition_data.get("score_components", []):
		if value is Dictionary:
			total += float((value as Dictionary).get("points", 0.0))
	return total


func _resolve_completion_only_objectives() -> void:
	for objective_state: ObjectiveState in state.objective_states:
		if objective_state.lifecycle_state != &"active":
			continue
		var objective: ObjectiveDef = _objective_defs.get(objective_state.objective_id)
		var objective_data: Dictionary = _objective_data.get(objective_state.objective_id, {})
		if objective == null or String(objective_data.get("evaluation", "")) \
				!= "at_scenario_completion":
			continue
		var metric: Dictionary = registry.evaluate(objective.metric, objective.filters)
		objective_state.current_value = float(metric.get("value", 0.0))
		objective_state.progress_snapshot = metric.duplicate(true)
		if operator_satisfied(objective_state.current_value, objective.operator,
				objective.target, objective.metric == &"action"):
			objective_state.transition_to(&"completed", state.elapsed_time_days, "scenario_complete")
			_apply_reward(objective, objective_state)
		else:
			objective_state.transition_to(&"expired", state.elapsed_time_days, "target_not_met")
			_apply_failure_consequence(objective, objective_state)
		objective_resolved.emit(objective.id, objective_state)


func _free_play_rule_enabled(rule_id: StringName) -> bool:
	for value: Variant in config.victory_rules:
		if value is Dictionary and StringName(String((value as Dictionary).get("id", ""))) == rule_id:
			return bool((value as Dictionary).get("enabled", true))
	return false


func _process_scripted_events() -> void:
	if state == null:
		return
	for value: Variant in _definition_data.get("scripted_events", _definition_data.get("events", [])):
		if value is not Dictionary:
			continue
		var event: Dictionary = value
		var event_id: StringName = StringName(String(event.get("id", "")))
		if event_id == &"" or state.fired_event_ids.has(event_id):
			continue
		if not _condition_satisfied(event.get("trigger", {})):
			continue
		state.mark_event_fired(event_id)
		var action: StringName = StringName(String(event.get("action", "message")))
		var payload: Dictionary = event.get("payload", {})
		match action:
			&"offer_side_mission":
				_offer_side_mission(StringName(String(payload.get("side_mission_id", ""))))
			&"tutorial_prompt":
				tutorial_prompted.emit(
					StringName(String(payload.get("objective_id", ""))),
					bool(payload.get("allow_skip", true)),
					bool(payload.get("allow_reset", true)))
			&"message":
				EconomyManager.post_message("info", "%s — %s" % [
					payload.get("title", "Scenario update"), payload.get("body", "")])
			_:
				EconomyManager.post_message("info", String(payload.get(
					"body", "Scenario event: %s" % event_id)))
		state.event_flags[event_id] = true


func _offer_side_mission(objective_id: StringName) -> void:
	var objective: ObjectiveDef = _objective_defs.get(objective_id)
	var objective_state: ObjectiveState = state.objective_state_by_id(objective_id) as ObjectiveState
	if objective == null or objective_state == null or objective_state.is_terminal():
		return
	objective_state.transition_to(&"revealed", state.elapsed_time_days, "offered")
	objective_updated.emit(objective_id, objective_state)
	side_mission_offered.emit(objective_id, objective)


func _apply_reward(objective: ObjectiveDef, objective_state: ObjectiveState) -> void:
	if objective_state.reward_applied:
		return
	objective_state.reward_applied = true
	var reward: Dictionary = objective.reward
	var cash: float = float(reward.get("cash", 0.0))
	if not is_zero_approx(cash):
		EconomyManager.transact(&"scenario_reward", cash)
	var reputation: float = float(reward.get("reputation", 0.0))
	if not is_zero_approx(reputation):
		EconomyManager.add_reputation(reputation)
	var snapshot: Dictionary = reward.duplicate(true)
	snapshot["objective_id"] = objective.id
	_resolved_rewards.append(snapshot)
	EconomyManager.post_message("good", "Objective complete: %s" % objective.text)


func _apply_failure_consequence(objective: ObjectiveDef,
		objective_state: ObjectiveState) -> void:
	if objective_state.failure_consequence_applied:
		return
	objective_state.failure_consequence_applied = true
	_apply_consequence(objective.failure_consequence)


func _apply_consequence(consequence: Dictionary) -> void:
	var cash: float = float(consequence.get("cash", 0.0))
	if not is_zero_approx(cash):
		EconomyManager.transact(&"scenario_consequence", cash)
	var reputation: float = float(consequence.get("reputation", 0.0))
	if not is_zero_approx(reputation):
		EconomyManager.add_reputation(reputation)
	var message: String = String(consequence.get("message", ""))
	if not message.is_empty():
		EconomyManager.post_message("alert", message)


func _apply_capability_restrictions() -> void:
	if CompanyManager.player == null:
		return
	var restrictions: Dictionary = definition.restrictions
	var disabled: Array = restrictions.get("disabled_systems", [])
	var hints: Dictionary = {}
	for value: Variant in disabled:
		hints[StringName(String(value))] = "Disabled by scenario: %s" % definition.title
	CapabilityRegistry.set_lock_hints(
		CompanyManager.player.id, &"scenario_restrictions", hints)


func _connect_runtime_signals() -> void:
	if _signals_connected:
		return
	_signals_connected = true
	GameClock.minute_ticked.connect(_on_minute_ticked)
	GameClock.day_changed.connect(func(_day: int) -> void: _queue_reconcile())
	EconomyManager.cash_changed.connect(func(_cash: float) -> void: _queue_reconcile())
	EconomyManager.reputation_changed.connect(func(_value: float) -> void: _queue_reconcile())
	EconomyManager.bankrupt.connect(func() -> void: fail("Bankruptcy"))
	RestaurantManager.restaurant_purchased.connect(func(_rest: RestaurantState) -> void:
		observe_action(&"location_acquired")
		_queue_reconcile())
	RestaurantManager.restaurant_updated.connect(func(_building_id: int) -> void: _queue_reconcile())
	DeliveryManager.delivery_completed.connect(func(_order: FoodOrder, _success: bool) -> void:
		_queue_reconcile())
	var awards_manager: Node = get_node_or_null("/root/AwardsManager")
	if awards_manager != null:
		awards_manager.award_granted.connect(
			func(_award: AwardResult) -> void: _queue_reconcile())
	CompanyManager.rival_bankrupt.connect(func(_company: CompanyState) -> void: _queue_reconcile())
	var command_router: Node = get_node_or_null("/root/BranchCommandRouter")
	if command_router != null:
		command_router.command_executed.connect(_on_command_executed)


func _on_minute_ticked(_day: int, _hour: int, minute: int) -> void:
	if minute % RECONCILE_MINUTES == 0:
		reconcile()


func _on_command_executed(command_id: StringName, command_result: CommandResult,
		_actor_context: Dictionary) -> void:
	if not command_result.ok:
		return
	match command_id:
		&"menu.set_entry", &"set_menu_entry", &"menu_price":
			observe_action(&"menu_price_changed")
		&"staff.set_schedule", &"set_shift", &"staff_schedule":
			observe_action(&"staff_schedule_changed")
		&"restaurant.set_hours", &"set_hours", &"opening_hours":
			observe_action(&"restaurant_opened")
	_queue_reconcile()


func _queue_reconcile() -> void:
	if _reconcile_queued:
		return
	_reconcile_queued = true
	reconcile.call_deferred()


func _register_builtin_metrics() -> void:
	register_metric(&"cash", func(_filters: Dictionary) -> Variant:
		return {"value": EconomyManager.cash, "explanation": "Current company cash"},
		_format_currency, "Current company cash")
	register_metric(&"profit_today", func(_filters: Dictionary) -> Variant:
		return {"value": EconomyManager.profit_today(), "explanation": "Today's live profit"},
		_format_currency, "Today's profit")
	register_metric(&"reputation", func(_filters: Dictionary) -> Variant:
		return {"value": EconomyManager.reputation, "explanation": "Company reputation"},
		_format_decimal, "Company reputation")
	register_metric(&"restaurant_count", func(_filters: Dictionary) -> Variant:
		return {"value": float(RestaurantManager.owned.size()), "explanation": "Owned restaurants"},
		_format_integer, "Owned restaurants")
	register_metric(&"deliveries", func(_filters: Dictionary) -> Variant:
		var starting: float = _starting_metric_value("deliveries")
		return {"value": starting + float(DeliveryManager.total_delivered), "explanation": "Completed deliveries"},
		_format_integer, "Completed deliveries")
	register_metric(&"awards", func(_filters: Dictionary) -> Variant:
		var count: int = _award_count()
		return {"value": _starting_metric_value("awards") + float(count), "explanation": "Awards won"},
		_format_integer, "Awards won")
	register_metric(&"day", func(_filters: Dictionary) -> Variant:
		return {"value": float(GameClock.day), "explanation": "Current game day"},
		_format_integer, "Current day")
	register_metric(&"action", _evaluate_action_metric, _format_integer,
		"Observed tutorial actions")


func _evaluate_action_metric(filters: Dictionary) -> Variant:
	var actions: Dictionary = state.progress_snapshots.get("actions", {}) if state != null else {}
	var action_id: StringName = StringName(String(filters.get("action_id", "")))
	if action_id != &"":
		return {
			"value": float(actions.get(action_id, 0)),
			"explanation": "Observed action: %s" % String(action_id).replace("_", " "),
		}
	var total: int = 0
	for value: Variant in actions.values():
		total += int(value)
	return {"value": float(total), "explanation": "Observed tutorial actions"}


func _award_count() -> int:
	if CompanyManager.player == null:
		return 0
	var awards_manager: Node = get_node_or_null("/root/AwardsManager")
	return int(awards_manager.call("trophies_for", CompanyManager.player.id)) \
		if awards_manager != null else 0


func _starting_metric_value(metric_id: StringName) -> float:
	if state == null:
		return 0.0
	var values: Dictionary = state.progress_snapshots.get("starting_values", {})
	return float(values.get(String(metric_id), values.get(metric_id, 0.0)))


func _condition_satisfied(condition: Dictionary) -> bool:
	if condition.is_empty():
		return false
	var metric_id: StringName = StringName(String(condition.get("metric", "")))
	var metric: Dictionary = registry.evaluate(metric_id, condition.get("filters", {}))
	return operator_satisfied(
		float(metric.get("value", 0.0)),
		StringName(String(condition.get("operator", ">="))),
		float(condition.get("target", 0.0)),
		metric_id == &"action")


func _trigger_description(trigger: Dictionary) -> String:
	if trigger.is_empty():
		return "Soon"
	var metric_id: String = String(trigger.get("metric", "day"))
	var operator: String = String(trigger.get("operator", "=="))
	var target: float = float(trigger.get("target", 0.0))
	if metric_id == "day":
		return "Day %d" % int(target)
	return "%s %s %.0f" % [metric_id.replace("_", " ").capitalize(), operator, target]


static func operator_satisfied(value: float, operator: StringName, target: float,
		discrete_at_least: bool = false) -> bool:
	match operator:
		&">=", &"gte":
			return value >= target
		&"<=", &"lte":
			return value <= target
		&">":
			return value > target
		&"<":
			return value < target
		&"==", &"=", &"eq":
			return value >= target if discrete_at_least else is_equal_approx(value, target)
		&"!=":
			return not is_equal_approx(value, target)
	return false


func _format_currency(value: float, _filters: Dictionary) -> String:
	return "$%.0f" % value


func _format_decimal(value: float, _filters: Dictionary) -> String:
	return "%.1f" % value


func _format_integer(value: float, _filters: Dictionary) -> String:
	return "%d" % int(round(value))
