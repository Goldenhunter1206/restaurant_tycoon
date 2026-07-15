class_name ManagerApproval
extends Resource
## Persistent approval-inbox item produced by an approval-mode policy.

@export var schema_version: int = 1
@export var uid: String = ""
@export var assignment_uid: String = ""
@export var company_id: StringName = &""
@export var branch_building_id: int = -1
@export var category: StringName = &""
@export var command_id: StringName = &""
@export var command_arguments: Dictionary = {}
@export var evidence: Array[String] = []
@export var expected_impact: String = ""
@export var exact_cost: float = 0.0
@export var created_window: int = -1
@export var deadline_window: int = -1
@export var status: StringName = &"pending"
@export var idempotency_key: String = ""
@export var explanation: String = ""
@export var edited_arguments: Dictionary = {}
@export var resolved_window: int = -1
@export var resolved_by: String = ""


func is_pending(current_window: int) -> bool:
	return status == &"pending" and current_window <= deadline_window


func mark_resolved(new_status: StringName, actor_id: String, window: int) -> void:
	status = new_status
	resolved_by = actor_id
	resolved_window = window
