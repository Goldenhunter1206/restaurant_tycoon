class_name GameSessionConfig
extends Resource
## Reproducible, data-only description of a newly bootstrapped game session.

const CURRENT_SCHEMA_VERSION: int = 1

const MODE_CAMPAIGN: StringName = &"campaign"
const MODE_FREE_PLAY: StringName = &"free_play"
const MODE_TUTORIAL: StringName = &"tutorial"
const MODE_CHALLENGE: StringName = &"challenge"

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var mode: StringName = MODE_FREE_PLAY
@export var seed: int = 0
@export var city_id: StringName = &""
@export var scenario_id: StringName = &""
@export var campaign_id: StringName = &""
@export var difficulty: StringName = &"normal"
@export var difficulty_overrides: Dictionary = {}
@export var company_identity: Dictionary = {}
@export var starting_resources: Dictionary = {}
@export var rivals: Array[Dictionary] = []
@export var enabled_systems: Array[StringName] = []
@export var victory_rules: Array[Dictionary] = []


func is_known_mode() -> bool:
	return (
		mode == MODE_CAMPAIGN
		or mode == MODE_FREE_PLAY
		or mode == MODE_TUTORIAL
		or mode == MODE_CHALLENGE
	)


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"mode": String(mode),
		"seed": seed,
		"city_id": String(city_id),
		"scenario_id": String(scenario_id),
		"campaign_id": String(campaign_id),
		"difficulty": String(difficulty),
		"difficulty_overrides": difficulty_overrides.duplicate(true),
		"company_identity": company_identity.duplicate(true),
		"starting_resources": starting_resources.duplicate(true),
		"rivals": _copy_dictionary_array(rivals),
		"enabled_systems": _string_name_array_to_strings(enabled_systems),
		"victory_rules": _copy_dictionary_array(victory_rules),
	}


static func from_dict(data: Dictionary) -> Resource:
	var config: Variant = load("res://scripts/data/game_session_config.gd").new()
	config.schema_version = int(data.get("schema_version", CURRENT_SCHEMA_VERSION))
	config.mode = StringName(String(data.get("mode", MODE_FREE_PLAY)))
	config.seed = int(data.get("seed", 0))
	config.city_id = StringName(String(data.get("city_id", "")))
	config.scenario_id = StringName(String(data.get("scenario_id", "")))
	config.campaign_id = StringName(String(data.get("campaign_id", "")))
	config.difficulty = StringName(String(data.get("difficulty", "normal")))
	config.difficulty_overrides = _copy_dictionary(data.get("difficulty_overrides", {}))
	config.company_identity = _copy_dictionary(data.get("company_identity", {}))
	config.starting_resources = _copy_dictionary(data.get("starting_resources", {}))
	config.rivals = _dictionary_array_from_variant(data.get("rivals", []))
	config.enabled_systems = _string_name_array_from_variant(data.get("enabled_systems", []))
	config.victory_rules = _dictionary_array_from_variant(data.get("victory_rules", []))
	return config as Resource


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
