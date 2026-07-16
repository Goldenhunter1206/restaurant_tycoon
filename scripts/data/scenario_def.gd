class_name ScenarioDef
extends Resource
## Authored city/scenario setup. Mutable progress belongs in ScenarioState.

const CURRENT_SCHEMA_VERSION: int = 1
static var _objective_def_script: Script = load(
	"res://scripts/data/objective_def.gd"
) as Script

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var id: StringName = &""
@export var campaign_id: StringName = &""
@export var chapter_id: StringName = &""
@export var city_id: StringName = &""
@export var title: String = ""
@export var intro: Dictionary = {}
@export var starting_state: Dictionary = {}
@export var rivals: Array[Dictionary] = []
@export var objectives: Array[Resource] = []
@export var time_limit_days: float = -1.0
@export var events: Array[Dictionary] = []
@export var restrictions: Dictionary = {}
@export var outcomes: Dictionary = {}
@export var next_scenario: Dictionary = {}


func objective_by_id(objective_id: StringName) -> Resource:
	for objective: Resource in objectives:
		if objective != null and StringName(objective.get("id")) == objective_id:
			return objective
	return null


func to_dict() -> Dictionary:
	var objective_data: Array[Dictionary] = []
	for objective: Resource in objectives:
		if objective != null and objective.has_method("to_dict"):
			objective_data.append(objective.call("to_dict") as Dictionary)
	return {
		"schema_version": schema_version,
		"id": String(id),
		"campaign_id": String(campaign_id),
		"chapter_id": String(chapter_id),
		"city_id": String(city_id),
		"title": title,
		"intro": intro.duplicate(true),
		"starting_state": starting_state.duplicate(true),
		"rivals": _copy_dictionary_array(rivals),
		"objectives": objective_data,
		"time_limit_days": time_limit_days,
		"events": _copy_dictionary_array(events),
		"restrictions": restrictions.duplicate(true),
		"outcomes": outcomes.duplicate(true),
		"next_scenario": next_scenario.duplicate(true),
	}


static func from_dict(data: Dictionary) -> Resource:
	var definition: Variant = load("res://scripts/data/scenario_def.gd").new()
	definition.schema_version = int(data.get("schema_version", CURRENT_SCHEMA_VERSION))
	definition.id = StringName(String(data.get("id", "")))
	definition.campaign_id = StringName(String(data.get("campaign_id", "")))
	definition.chapter_id = StringName(String(data.get("chapter_id", "")))
	definition.city_id = StringName(String(data.get("city_id", "")))
	definition.title = String(data.get("title", ""))
	definition.intro = _intro_from_variant(data.get("intro", {}))
	definition.starting_state = _copy_dictionary(
		data.get("starting_state", data.get("initial_state", {}))
	)
	definition.rivals = _dictionary_array_from_variant(data.get("rivals", []))
	definition.objectives = _objectives_from_variant(data.get("objectives", []))
	definition.time_limit_days = float(data.get("time_limit_days", -1.0))
	definition.events = _dictionary_array_from_variant(
		data.get("events", data.get("scripted_events", []))
	)
	definition.restrictions = _copy_dictionary(data.get("restrictions", {}))
	definition.outcomes = _outcomes_from_data(data)
	definition.next_scenario = _next_scenario_from_data(data)
	return definition as Resource


static func _objectives_from_variant(value: Variant) -> Array[Resource]:
	var result: Array[Resource] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		if entry is Resource and (entry as Resource).get_script() == _objective_def_script:
			var objective: Resource = entry as Resource
			result.append(
				_objective_from_dict(objective.call("to_dict") as Dictionary)
			)
		elif entry is Dictionary:
			result.append(_objective_from_dict(entry as Dictionary))
	return result


static func _objective_from_dict(data: Dictionary) -> Resource:
	return _objective_def_script.call("from_dict", data) as Resource


static func _intro_from_variant(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is String or value is StringName:
		return {"body": String(value)}
	return {}


static func _outcomes_from_data(data: Dictionary) -> Dictionary:
	var value: Variant = data.get("outcomes", {})
	if value is Dictionary and not (value as Dictionary).is_empty():
		return (value as Dictionary).duplicate(true)
	var result: Dictionary = {}
	if data.has("success_outcome"):
		result["success"] = _copy_dictionary(data.get("success_outcome", {}))
	if data.has("failure_outcome"):
		result["failure"] = _copy_dictionary(data.get("failure_outcome", {}))
	return result


static func _next_scenario_from_data(data: Dictionary) -> Dictionary:
	var value: Variant = data.get("next_scenario", {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is String or value is StringName:
		return {"scenario_id": String(value)}
	var legacy_id: String = String(data.get("next_scenario_id", ""))
	if not legacy_id.is_empty():
		return {"scenario_id": legacy_id}
	return {}


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
