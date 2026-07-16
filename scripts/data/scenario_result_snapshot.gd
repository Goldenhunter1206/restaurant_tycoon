class_name ScenarioResultSnapshot
extends Resource
## Detached result payload. freeze() deep-copies collections before persistence.

const CURRENT_SCHEMA_VERSION: int = 1

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var frozen: bool = false
@export var result_id: StringName = &""
@export var profile_id: StringName = &""
@export var session_id: StringName = &""
@export var mode: StringName = &""
@export var campaign_id: StringName = &""
@export var scenario_id: StringName = &""
@export var city_id: StringName = &""
@export var outcome: StringName = &""
@export var score: float = 0.0
@export var score_breakdown: Dictionary = {}
@export var medal: StringName = &""
@export var elapsed_time_days: float = 0.0
@export var completed_objectives: Array[StringName] = []
@export var failed_objectives: Array[StringName] = []
@export var expired_objectives: Array[StringName] = []
@export var optional_objectives_completed: Array[StringName] = []
@export var rewards: Array[Dictionary] = []
@export var event_flags: Dictionary = {}
@export var failure_reason: String = ""
@export var completed_at_unix: int = 0
@export var config_snapshot: Dictionary = {}


func freeze() -> void:
	if frozen:
		return
	score_breakdown = score_breakdown.duplicate(true)
	completed_objectives = completed_objectives.duplicate()
	failed_objectives = failed_objectives.duplicate()
	expired_objectives = expired_objectives.duplicate()
	optional_objectives_completed = optional_objectives_completed.duplicate()
	rewards = _copy_dictionary_array(rewards)
	event_flags = event_flags.duplicate(true)
	config_snapshot = config_snapshot.duplicate(true)
	frozen = true


func is_frozen() -> bool:
	return frozen


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"frozen": frozen,
		"result_id": String(result_id),
		"profile_id": String(profile_id),
		"session_id": String(session_id),
		"mode": String(mode),
		"campaign_id": String(campaign_id),
		"scenario_id": String(scenario_id),
		"city_id": String(city_id),
		"outcome": String(outcome),
		"score": score,
		"score_breakdown": score_breakdown.duplicate(true),
		"medal": String(medal),
		"elapsed_time_days": elapsed_time_days,
		"completed_objectives": _string_name_array_to_strings(
			completed_objectives
		),
		"failed_objectives": _string_name_array_to_strings(failed_objectives),
		"expired_objectives": _string_name_array_to_strings(expired_objectives),
		"optional_objectives_completed": _string_name_array_to_strings(
			optional_objectives_completed
		),
		"rewards": _copy_dictionary_array(rewards),
		"event_flags": event_flags.duplicate(true),
		"failure_reason": failure_reason,
		"completed_at_unix": completed_at_unix,
		"config_snapshot": config_snapshot.duplicate(true),
	}


static func from_dict(
	data: Dictionary,
	freeze_result: bool = true
) -> Resource:
	var snapshot: Variant = load(
		"res://scripts/data/scenario_result_snapshot.gd"
	).new()
	snapshot.schema_version = int(data.get("schema_version", CURRENT_SCHEMA_VERSION))
	snapshot.frozen = false
	snapshot.result_id = StringName(String(data.get("result_id", "")))
	snapshot.profile_id = StringName(String(data.get("profile_id", "")))
	snapshot.session_id = StringName(String(data.get("session_id", "")))
	snapshot.mode = StringName(String(data.get("mode", "")))
	snapshot.campaign_id = StringName(String(data.get("campaign_id", "")))
	snapshot.scenario_id = StringName(String(data.get("scenario_id", "")))
	snapshot.city_id = StringName(String(data.get("city_id", "")))
	snapshot.outcome = StringName(String(data.get("outcome", "")))
	snapshot.score = float(data.get("score", 0.0))
	snapshot.score_breakdown = _copy_dictionary(data.get("score_breakdown", {}))
	snapshot.medal = StringName(String(data.get("medal", "")))
	snapshot.elapsed_time_days = maxf(
		float(data.get("elapsed_time_days", 0.0)),
		0.0
	)
	snapshot.completed_objectives = _string_name_array_from_variant(
		data.get("completed_objectives", [])
	)
	snapshot.failed_objectives = _string_name_array_from_variant(
		data.get("failed_objectives", [])
	)
	snapshot.expired_objectives = _string_name_array_from_variant(
		data.get("expired_objectives", [])
	)
	snapshot.optional_objectives_completed = _string_name_array_from_variant(
		data.get("optional_objectives_completed", [])
	)
	snapshot.rewards = _dictionary_array_from_variant(data.get("rewards", []))
	snapshot.event_flags = _copy_dictionary(data.get("event_flags", {}))
	snapshot.failure_reason = String(data.get("failure_reason", ""))
	snapshot.completed_at_unix = int(data.get("completed_at_unix", 0))
	snapshot.config_snapshot = _copy_dictionary(data.get("config_snapshot", {}))
	if freeze_result:
		snapshot.freeze()
	return snapshot as Resource


static func _copy_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


static func _copy_dictionary_array(values: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in values:
		result.append(value.duplicate(true))
	return result


static func _dictionary_array_from_variant(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result


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
