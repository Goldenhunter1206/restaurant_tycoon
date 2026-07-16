class_name PlayerProfileState
extends Resource
## Mutable progression shared across sessions. Contains no Node references.

const CURRENT_SCHEMA_VERSION: int = 1

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var profile_id: StringName = &"default"
@export var completed_scenarios: Array[StringName] = []
@export var best_scores: Dictionary = {}
@export var medals: Dictionary = {}
@export var campaign_progress: Dictionary = {}
@export var unlocked_campaigns: Array[StringName] = []
@export var unlocked_scenarios: Array[StringName] = []
@export var unlocked_cities: Array[StringName] = []
@export var unlocked_content: Array[StringName] = []
@export var tutorial_state: Dictionary = {}
@export var preferences: Dictionary = {}
@export var committed_result_ids: Array[StringName] = []


func has_completed_scenario(scenario_id: StringName) -> bool:
	return completed_scenarios.has(scenario_id)


func record_scenario_completion(
	scenario_id: StringName,
	score_value: float,
	medal_value: StringName = &""
) -> void:
	if scenario_id == &"":
		return
	_append_unique(completed_scenarios, scenario_id)
	var key: String = String(scenario_id)
	if not best_scores.has(key) or score_value > float(best_scores[key]):
		best_scores[key] = score_value
	var previous_medal: StringName = StringName(String(medals.get(key, "")))
	if _medal_rank(medal_value) > _medal_rank(previous_medal):
		medals[key] = String(medal_value)


func has_committed_result(result_id: StringName) -> bool:
	return committed_result_ids.has(result_id)


func commit_result_id(result_id: StringName) -> bool:
	if result_id == &"" or has_committed_result(result_id):
		return false
	committed_result_ids.append(result_id)
	return true


func unlock_campaign(campaign_id: StringName) -> bool:
	return _append_unique(unlocked_campaigns, campaign_id)


func unlock_scenario(scenario_id: StringName) -> bool:
	return _append_unique(unlocked_scenarios, scenario_id)


func unlock_city(city_id: StringName) -> bool:
	return _append_unique(unlocked_cities, city_id)


func unlock_content(content_id: StringName) -> bool:
	return _append_unique(unlocked_content, content_id)


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"profile_id": String(profile_id),
		"completed_scenarios": _string_name_array_to_strings(completed_scenarios),
		"best_scores": best_scores.duplicate(true),
		"medals": medals.duplicate(true),
		"campaign_progress": campaign_progress.duplicate(true),
		"unlocked_campaigns": _string_name_array_to_strings(unlocked_campaigns),
		"unlocked_scenarios": _string_name_array_to_strings(unlocked_scenarios),
		"unlocked_cities": _string_name_array_to_strings(unlocked_cities),
		"unlocked_content": _string_name_array_to_strings(unlocked_content),
		"tutorial_state": tutorial_state.duplicate(true),
		"preferences": preferences.duplicate(true),
		"committed_result_ids": _string_name_array_to_strings(
			committed_result_ids
		),
	}


static func from_dict(data: Dictionary) -> Resource:
	var state: Variant = load("res://scripts/data/player_profile_state.gd").new()
	state.schema_version = int(data.get("schema_version", CURRENT_SCHEMA_VERSION))
	state.profile_id = StringName(String(data.get("profile_id", "default")))
	state.completed_scenarios = _string_name_array_from_variant(
		data.get("completed_scenarios", [])
	)
	state.best_scores = _copy_dictionary(data.get("best_scores", {}))
	state.medals = _copy_dictionary(data.get("medals", {}))
	state.campaign_progress = _copy_dictionary(data.get("campaign_progress", {}))
	state.unlocked_campaigns = _string_name_array_from_variant(
		data.get("unlocked_campaigns", [])
	)
	state.unlocked_scenarios = _string_name_array_from_variant(
		data.get("unlocked_scenarios", [])
	)
	state.unlocked_cities = _string_name_array_from_variant(
		data.get("unlocked_cities", [])
	)
	state.unlocked_content = _string_name_array_from_variant(
		data.get("unlocked_content", [])
	)
	state.tutorial_state = _copy_dictionary(data.get("tutorial_state", {}))
	state.preferences = _copy_dictionary(data.get("preferences", {}))
	state.committed_result_ids = _string_name_array_from_variant(
		data.get("committed_result_ids", [])
	)
	state._deduplicate_ids()
	return state as Resource


func _deduplicate_ids() -> void:
	completed_scenarios = _unique_string_names(completed_scenarios)
	unlocked_campaigns = _unique_string_names(unlocked_campaigns)
	unlocked_scenarios = _unique_string_names(unlocked_scenarios)
	unlocked_cities = _unique_string_names(unlocked_cities)
	unlocked_content = _unique_string_names(unlocked_content)
	committed_result_ids = _unique_string_names(committed_result_ids)


static func _append_unique(values: Array[StringName], value: StringName) -> bool:
	if value == &"" or values.has(value):
		return false
	values.append(value)
	return true


static func _medal_rank(medal_value: StringName) -> int:
	match medal_value:
		&"bronze":
			return 1
		&"silver":
			return 2
		&"gold":
			return 3
		_:
			return 0


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


static func _unique_string_names(values: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: StringName in values:
		_append_unique(result, value)
	return result
