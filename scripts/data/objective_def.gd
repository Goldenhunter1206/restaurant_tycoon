class_name ObjectiveDef
extends Resource
## Authored, registry-driven objective definition with no runtime references.

const CURRENT_SCHEMA_VERSION: int = 1

const OPERATOR_GREATER_OR_EQUAL: StringName = &"gte"
const OPERATOR_LESS_OR_EQUAL: StringName = &"lte"
const OPERATOR_EQUAL: StringName = &"eq"
const VISIBILITY_VISIBLE: StringName = &"visible"
const VISIBILITY_HIDDEN: StringName = &"hidden"
const INITIAL_HIDDEN: StringName = &"hidden"
const INITIAL_REVEALED: StringName = &"revealed"
const INITIAL_ACTIVE: StringName = &"active"

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var id: StringName = &""
@export_multiline var text: String = ""
@export var metric: StringName = &""
@export var operator: StringName = OPERATOR_GREATER_OR_EQUAL
@export var target: float = 0.0
@export var filters: Dictionary = {}
@export var deadline: Dictionary = {}
@export var visibility: StringName = VISIBILITY_VISIBLE
@export var initial_state: StringName = INITIAL_ACTIVE
@export var reward: Dictionary = {}
@export var failure_consequence: Dictionary = {}
@export var prerequisites: Array[StringName] = []
@export var maintain_duration: float = 0.0
@export var optional: bool = false


func starts_hidden() -> bool:
	return visibility == VISIBILITY_HIDDEN or initial_state == INITIAL_HIDDEN


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"id": String(id),
		"text": text,
		"metric": String(metric),
		"operator": String(operator),
		"target": target,
		"filters": filters.duplicate(true),
		"deadline": deadline.duplicate(true),
		"visibility": String(visibility),
		"initial_state": String(initial_state),
		"reward": reward.duplicate(true),
		"failure_consequence": failure_consequence.duplicate(true),
		"prerequisites": _string_name_array_to_strings(prerequisites),
		"maintain_duration": maintain_duration,
		"optional": optional,
	}


static func from_dict(data: Dictionary) -> Resource:
	var definition: Variant = load("res://scripts/data/objective_def.gd").new()
	definition.schema_version = int(data.get("schema_version", CURRENT_SCHEMA_VERSION))
	definition.id = StringName(String(data.get("id", "")))
	definition.text = String(data.get("text", ""))
	definition.metric = StringName(String(data.get("metric", "")))
	definition.operator = StringName(String(data.get("operator", OPERATOR_GREATER_OR_EQUAL)))
	definition.target = float(data.get("target", 0.0))
	definition.filters = _copy_dictionary(data.get("filters", {}))
	definition.deadline = _copy_dictionary(data.get("deadline", {}))
	var initial_state_value: StringName = StringName(
		String(data.get("initial_state", INITIAL_ACTIVE))
	)
	if bool(data.get("hidden", false)):
		initial_state_value = INITIAL_HIDDEN
	definition.initial_state = initial_state_value
	var default_visibility: StringName = (
		VISIBILITY_HIDDEN if initial_state_value == INITIAL_HIDDEN else VISIBILITY_VISIBLE
	)
	definition.visibility = StringName(
		String(data.get("visibility", default_visibility))
	)
	definition.reward = _copy_dictionary(data.get("reward", {}))
	definition.failure_consequence = _copy_dictionary(
		data.get("failure_consequence", {})
	)
	definition.prerequisites = _string_name_array_from_variant(
		data.get("prerequisites", [])
	)
	definition.maintain_duration = maxf(float(data.get("maintain_duration", 0.0)), 0.0)
	var default_optional: bool = String(data.get("kind", "")) == "optional"
	definition.optional = bool(data.get("optional", default_optional))
	return definition as Resource


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
