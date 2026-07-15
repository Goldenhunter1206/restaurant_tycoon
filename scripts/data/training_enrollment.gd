class_name TrainingEnrollment
extends Resource
## Persistent, exactly-once training queue entry.

@export var schema_version: int = 1
@export var uid: String = ""
@export var company_id: StringName = &""
@export var branch_building_id: int = -1
@export var staff_uid: int = -1
@export var program_id: StringName = &""
@export var status: StringName = &"queued"
@export var queued_window: int = -1
@export var started_window: int = -1
@export var completes_window: int = -1
@export var completed_window: int = -1
@export var cost_paid: float = 0.0
@export var work_penalty: float = 0.0
@export var completion_key: String = ""
@export var completion_applied: bool = false


func is_active(current_window: int) -> bool:
	return status == &"active" and current_window < completes_window


func ready_to_complete(current_window: int) -> bool:
	return status == &"active" and not completion_applied and current_window >= completes_window
