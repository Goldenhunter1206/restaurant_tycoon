class_name ManagerAssignment
extends Resource
## Versioned link between a manager employee and a branch policy.

@export var schema_version: int = 1
@export var uid: String = ""
@export var company_id: StringName = &""
@export var branch_building_id: int = -1
@export var manager_employee_uid: int = -1
@export var policy_uid: String = ""
@export var active: bool = true
@export var paused_reason: String = ""
@export var founder_assistance: bool = false
@export var assigned_day: int = 0
@export var assignment_salary: float = 0.0
@export var cooldown_until_by_category: Dictionary = {}
@export var local_overrides: Dictionary = {}
@export var last_decision_window: int = -1
@export var last_evaluated_day: int = -1


func is_paused() -> bool:
	return not active or not paused_reason.is_empty()


func cooldown_until(category: StringName) -> int:
	return int(cooldown_until_by_category.get(category, -1))


func set_cooldown(category: StringName, until_window: int) -> void:
	cooldown_until_by_category[category] = until_window
