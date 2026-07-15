class_name AdPlacement
extends Resource
## One rentable billboard site in the world. Sites store world positions —
## never building ids, which reshuffle when the city is rebuilt. Vacant when
## owner_company is empty.

@export var id: int = -1
@export var world_pos: Vector3 = Vector3.ZERO
## District code (R/N/P/D/C/I) the site advertises into.
@export var district: String = "N"
@export var radius: float = 750.0
@export var owner_company: StringName = &""
@export var rent_per_day: float = 120.0
## Remaining rental days; 0 releases the site on the next daily charge.
@export var days_left: int = 0
## Yaw in radians for the world prop so signs face the street.
@export var yaw: float = 0.0


func vacant() -> bool:
	return owner_company == &""
