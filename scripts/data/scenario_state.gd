class_name ScenarioState
extends Resource
## Mutable, save-safe runtime state for one scenario. Contains no Node references.

const CURRENT_SCHEMA_VERSION: int = 1

static var _objective_state_script: Script = load(
	"res://scripts/data/objective_state.gd"
) as Script

const STATE_INTRO: StringName = &"intro"
const STATE_ACTIVE: StringName = &"active"
const STATE_SUCCEEDED: StringName = &"succeeded"
const STATE_FAILED: StringName = &"failed"
const STATE_RESULTS: StringName = &"results"

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var session_id: StringName = &""
@export var campaign_id: StringName = &""
@export var scenario_id: StringName = &""
@export var city_id: StringName = &""
@export var objective_states: Array[Resource] = []
@export var progress_snapshots: Dictionary = {}
@export var accepted_side_missions: Array[StringName] = []
@export var elapsed_time_days: float = 0.0
@export var score: float = 0.0
@export var score_breakdown: Dictionary = {}
@export var completion_state: StringName = STATE_INTRO
@export var event_flags: Dictionary = {}
@export var fired_event_ids: Array[StringName] = []
@export var failure_reason: String = ""
@export var result_id: StringName = &""


func objective_state_by_id(objective_id: StringName) -> Resource:
	for objective_state: Resource in objective_states:
		if (
			objective_state != null
			and StringName(objective_state.get("objective_id")) == objective_id
		):
			return objective_state
	return null


func is_terminal() -> bool:
	return (
		completion_state == STATE_SUCCEEDED
		or completion_state == STATE_FAILED
		or completion_state == STATE_RESULTS
	)


func accept_side_mission(objective_id: StringName) -> bool:
	if objective_id == &"" or accepted_side_missions.has(objective_id):
		return false
	accepted_side_missions.append(objective_id)
	var objective_state: Resource = objective_state_by_id(objective_id)
	if objective_state != null:
		objective_state.set("accepted", true)
	return true


func mark_event_fired(event_id: StringName) -> bool:
	if event_id == &"" or fired_event_ids.has(event_id):
		return false
	fired_event_ids.append(event_id)
	event_flags[String(event_id)] = true
	return true


func to_dict() -> Dictionary:
	var objective_data: Array[Dictionary] = []
	for objective_state: Resource in objective_states:
		if objective_state != null and objective_state.has_method("to_dict"):
			objective_data.append(objective_state.call("to_dict") as Dictionary)
	return {
		"schema_version": schema_version,
		"session_id": String(session_id),
		"campaign_id": String(campaign_id),
		"scenario_id": String(scenario_id),
		"city_id": String(city_id),
		"objective_states": objective_data,
		"progress_snapshots": progress_snapshots.duplicate(true),
		"accepted_side_missions": _string_name_array_to_strings(
			accepted_side_missions
		),
		"elapsed_time_days": elapsed_time_days,
		"score": score,
		"score_breakdown": score_breakdown.duplicate(true),
		"completion_state": String(completion_state),
		"event_flags": event_flags.duplicate(true),
		"fired_event_ids": _string_name_array_to_strings(fired_event_ids),
		"failure_reason": failure_reason,
		"result_id": String(result_id),
	}


static func from_dict(data: Dictionary) -> Resource:
	var state: Variant = load("res://scripts/data/scenario_state.gd").new()
	state.schema_version = int(data.get("schema_version", CURRENT_SCHEMA_VERSION))
	state.session_id = StringName(String(data.get("session_id", "")))
	state.campaign_id = StringName(String(data.get("campaign_id", "")))
	state.scenario_id = StringName(String(data.get("scenario_id", "")))
	state.city_id = StringName(String(data.get("city_id", "")))
	state.objective_states = _objective_states_from_variant(
		data.get("objective_states", [])
	)
	state.progress_snapshots = _copy_dictionary(data.get("progress_snapshots", {}))
	state.accepted_side_missions = _string_name_array_from_variant(
		data.get("accepted_side_missions", [])
	)
	state.elapsed_time_days = maxf(float(data.get("elapsed_time_days", 0.0)), 0.0)
	state.score = float(data.get("score", 0.0))
	state.score_breakdown = _copy_dictionary(data.get("score_breakdown", {}))
	state.completion_state = StringName(
		String(data.get("completion_state", STATE_INTRO))
	)
	state.event_flags = _copy_dictionary(data.get("event_flags", {}))
	state.fired_event_ids = _string_name_array_from_variant(
		data.get("fired_event_ids", [])
	)
	state.failure_reason = String(data.get("failure_reason", ""))
	state.result_id = StringName(String(data.get("result_id", "")))
	return state as Resource


static func _objective_states_from_variant(value: Variant) -> Array[Resource]:
	var result: Array[Resource] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		if entry is Resource and (entry as Resource).get_script() == _objective_state_script:
			var objective_state: Resource = entry as Resource
			result.append(
				_objective_state_from_dict(
					objective_state.call("to_dict") as Dictionary
				)
			)
		elif entry is Dictionary:
			result.append(_objective_state_from_dict(entry as Dictionary))
	return result


static func _objective_state_from_dict(data: Dictionary) -> Resource:
	return _objective_state_script.call("from_dict", data) as Resource


static func _copy_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


static func _string_name_array_from_variant(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		result.append(StringName(String(entry)))
	return result


static func _string_name_array_to_strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(String(value))
	return result
