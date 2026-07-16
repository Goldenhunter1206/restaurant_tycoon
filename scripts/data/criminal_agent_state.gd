class_name CriminalAgentState
extends Resource
## One recruited underworld crew member. Crew are deliberately NOT
## StaffMembers — recruitment and capacity are explicit (feature-12 spec)
## and gated by the crime.crew_capacity capability.

@export var uid: int = 0
@export var company_id: StringName = &""
@export var role: StringName = &"punk"  ## courier punk enforcer gangster
@export var display_name: String = ""
@export_range(0.0, 1.0) var skill: float = 0.4
@export_range(0.0, 1.0) var loyalty: float = 0.6
@export_range(0.0, 1.0) var readiness: float = 1.0
@export var equipment_tier: int = 0
@export var daily_wage: float = 40.0
@export var hired_day: int = 0
@export var assignment_op_uid: int = -1  ## -1 = idle
@export var incarcerated_until_day: int = 0
@export var recovering_until_day: int = 0


func is_incarcerated(day: int) -> bool:
	return day < incarcerated_until_day


func is_recovering(day: int) -> bool:
	return day < recovering_until_day


func is_available(day: int) -> bool:
	return assignment_op_uid < 0 and not is_incarcerated(day) and not is_recovering(day)


func status_label(day: int) -> String:
	if is_incarcerated(day):
		return "Jailed"
	if is_recovering(day):
		return "Recovering"
	if assignment_op_uid >= 0:
		return "On assignment"
	return "Idle"
