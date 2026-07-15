class_name StaffMember
extends Resource
## Persistent employee shared by every workforce role.

@export var schema_version: int = 2
@export var uid: int = 0
@export var type_id: StringName = &""
@export var staff_name: String = ""
@export var shift_start: float = 10.0
@export var shift_hours: float = 8.0
## Legacy pre-v2 field, only read during save migration.
@export var daily_wage: float = 60.0
@export var hourly_wage: float = 0.0
## StringName -> float 0..1, keys defined per role in StaffTypeDef.attribute_keys.
@export var attributes: Dictionary = {}
@export var experience: float = 0.0
@export var competencies: Dictionary = {}
@export_range(0.0, 1.0, 0.01) var energy: float = 1.0
@export_range(0.0, 1.0, 0.01) var fatigue: float = 0.0
@export_range(0.0, 1.0, 0.01) var health: float = 1.0
@export_range(0.0, 1.0, 0.01) var motivation: float = 0.75
@export_range(0.0, 1.0, 0.01) var satisfaction: float = 0.75
@export_range(0.0, 1.0, 0.01) var stress: float = 0.15
@export var traits: Array[StringName] = []
@export var attendance_history: Array[Dictionary] = []
@export var absence_until_day: int = -1
@export var training_history: Array[Dictionary] = []
@export var employment_history: Array[Dictionary] = []
@export var contract_type: StringName = &"permanent"
@export var contract_start_day: int = 0
@export var contract_end_day: int = -1
@export var guaranteed_weekly_hours: float = 0.0
@export var overtime_allowed: bool = true
@export var maximum_overtime_hours: float = 8.0
@export var availability_by_weekday: Dictionary = {}
@export var schedule_template_id: String = ""
@export var schedule_overrides: Dictionary = {}
@export var current_branch_building_id: int = -1
@export var manager_relationships: Dictionary = {}
@export var resignation_risk: float = 0.0
@export var resignation_warning_day: int = -1
@export var employment_status: StringName = &"active"
@export var last_condition_update_window: int = -1


func attr(key: StringName) -> float:
	return clampf(float(attributes.get(key, 0.5)), 0.0, 1.0)


func competency(key: StringName) -> float:
	return clampf(float(competencies.get(key, attr(key))), 0.0, 1.0)


func daily_pay() -> float:
	return hourly_wage * shift_hours


func on_shift(hour: float) -> bool:
	var shift_end: float = shift_start + shift_hours
	if shift_end <= 24.0:
		return hour >= shift_start and hour < shift_end
	return hour >= shift_start or hour < shift_end - 24.0


func is_absent(day: int) -> bool:
	return absence_until_day >= day


func is_available(weekday: int) -> bool:
	if availability_by_weekday.is_empty():
		return true
	return bool(availability_by_weekday.get(weekday, false))


func condition_score() -> float:
	var positive := (energy + health + motivation + satisfaction) * 0.25
	var pressure := (fatigue + stress) * 0.5
	return clampf(positive - pressure * 0.35, 0.0, 1.0)


func operational_effect(competency_id: StringName) -> float:
	var skill := competency(competency_id)
	var readiness := condition_score()
	return clampf(0.75 + skill * 0.2 + readiness * 0.1, 0.70, 1.05)


func add_experience(amount: float) -> void:
	experience = maxf(0.0, experience + amount)


func relationship_with(manager_uid: int) -> float:
	return clampf(float(manager_relationships.get(manager_uid, 0.5)), 0.0, 1.0)
