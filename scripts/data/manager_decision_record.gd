class_name ManagerDecisionRecord
extends Resource
## Auditable manager decision with alternatives and delayed outcome evaluation.

@export var schema_version: int = 1
@export var uid: String = ""
@export var assignment_uid: String = ""
@export var company_id: StringName = &""
@export var branch_building_id: int = -1
@export var manager_employee_uid: int = -1
@export var decision_window: int = -1
@export var category: StringName = &""
@export var observation_uid: String = ""
@export var alternatives: Array[Dictionary] = []
@export var selected_command: StringName = &""
@export var selected_arguments: Dictionary = {}
@export var expected_result: Dictionary = {}
@export var explanation: String = ""
@export var estimated_cost: float = 0.0
@export var actual_cost: float = 0.0
@export var command_result_code: StringName = &""
@export var permission_category: StringName = &"recommend"
@export var idempotency_key: String = ""
@export var undo_token: String = ""
@export var reversible: bool = false
@export var overridden: bool = false
@export var override_command_uid: String = ""
@export var evaluation_due_window: int = -1
@export var evaluation_status: StringName = &"pending"
@export var actual_result: Dictionary = {}


func can_undo(current_window: int) -> bool:
	return reversible and not undo_token.is_empty() and evaluation_status != &"undone" and current_window <= evaluation_due_window


func record_evaluation(result: Dictionary) -> void:
	actual_result = result.duplicate(true)
	evaluation_status = &"evaluated"
