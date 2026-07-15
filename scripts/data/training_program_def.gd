class_name TrainingProgramDef
extends Resource
## Data definition for headquarters-capacity workforce training.

@export var schema_version: int = 2
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
## Depth (v2): multi-competency gains and wellbeing/throughput effects.
@export var competency_gains: Dictionary = {}
@export_range(-1.0, 1.0, 0.01) var health_effect: float = 0.0
@export_range(-1.0, 1.0, 0.01) var motivation_effect: float = 0.05
@export_range(0.0, 1.0, 0.01) var throughput_penalty: float = 0.15


func supports_role(role_id: StringName) -> bool:
	return role_ids.is_empty() or role_ids.has(role_id)


func effective_gains() -> Dictionary:
	if not competency_gains.is_empty():
		return competency_gains
	if competency_id != &"":
		return {competency_id: competency_gain}
	return {}
