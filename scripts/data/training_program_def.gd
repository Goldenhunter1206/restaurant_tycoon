class_name TrainingProgramDef
extends Resource
## Data definition for headquarters-capacity workforce training.

@export var schema_version: int = 1
@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var role_ids: Array[StringName] = []
@export var competency_id: StringName = &""
@export var competency_gain: float = 0.1
@export var experience_gain: float = 20.0
@export var duration_hours: int = 24
@export var cost: float = 250.0
@export_range(0.0, 1.0, 0.01) var work_penalty: float = 0.35
@export var headquarters_capacity_cost: int = 1
@export var prerequisite_competencies: Dictionary = {}


func supports_role(role_id: StringName) -> bool:
	return role_ids.is_empty() or role_ids.has(role_id)
