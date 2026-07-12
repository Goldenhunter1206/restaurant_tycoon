class_name StaffMember
extends Resource
## One hired employee at a restaurant. Shift length is clamped to
## staff.min/max_shift_hours tuning by RestaurantManager; pay is hourly and
## charged only for scheduled hours.

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


func attr(key: StringName) -> float:
	return clampf(float(attributes.get(key, 0.5)), 0.0, 1.0)


func daily_pay() -> float:
	return hourly_wage * shift_hours


func on_shift(hour: float) -> bool:
	var shift_end: float = shift_start + shift_hours
	if shift_end <= 24.0:
		return hour >= shift_start and hour < shift_end
	return hour >= shift_start or hour < shift_end - 24.0
