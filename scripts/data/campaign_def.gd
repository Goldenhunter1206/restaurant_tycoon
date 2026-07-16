class_name CampaignDef
extends Resource
## Authored campaign graph. Runtime progress belongs in PlayerProfileState.

const CURRENT_SCHEMA_VERSION: int = 1

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""
@export var narrative: Dictionary = {}
@export var chapters: Array[Dictionary] = []
@export var unlock_rules: Array[Dictionary] = []
@export var persistent_rewards: Array[Dictionary] = []
@export var completion_scoring: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"id": String(id),
		"title": title,
		"description": description,
		"narrative": narrative.duplicate(true),
		"chapters": _copy_dictionary_array(chapters),
		"unlock_rules": _copy_dictionary_array(unlock_rules),
		"persistent_rewards": _copy_dictionary_array(persistent_rewards),
		"completion_scoring": completion_scoring.duplicate(true),
	}


static func from_dict(data: Dictionary) -> Resource:
	var definition: Variant = load("res://scripts/data/campaign_def.gd").new()
	definition.schema_version = int(data.get("schema_version", CURRENT_SCHEMA_VERSION))
	definition.id = StringName(String(data.get("id", "")))
	definition.title = String(data.get("title", ""))
	definition.description = String(data.get("description", ""))
	definition.narrative = _copy_dictionary(data.get("narrative", {}))
	definition.chapters = _dictionary_array_from_variant(data.get("chapters", []))
	definition.unlock_rules = _dictionary_array_from_variant(data.get("unlock_rules", []))
	definition.persistent_rewards = _dictionary_array_from_variant(
		data.get("persistent_rewards", [])
	)
	definition.completion_scoring = _copy_dictionary(data.get("completion_scoring", {}))
	return definition as Resource


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
