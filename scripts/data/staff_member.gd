class_name StaffMember
extends Resource
## One hired employee at a restaurant. Works at most 8 hours per day
## (shift_hours is clamped by RestaurantManager on hire).

@export var uid: int = 0
@export var type_id: StringName = &""
@export var staff_name: String = ""
@export var shift_start: float = 10.0
@export var shift_hours: float = 8.0
@export var daily_wage: float = 60.0


func on_shift(hour: float) -> bool:
	var shift_end: float = shift_start + shift_hours
	if shift_end <= 24.0:
		return hour >= shift_start and hour < shift_end
	return hour >= shift_start or hour < shift_end - 24.0
