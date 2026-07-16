class_name PoliceStationState
extends Resource
## One police station: a deterministic city anchor with a finite pool of
## response units. units_busy_until holds one absolute game-minute per unit
## (0 = idle); dispatch picks the earliest-free unit at the nearest station.

@export var station_id: int = 0
@export var building_id: int = -1
@export var position: Vector3 = Vector3.ZERO
@export var unit_count: int = 2
@export var units_busy_until: Array[int] = []


func ensure_units() -> void:
	while units_busy_until.size() < unit_count:
		units_busy_until.append(0)


func free_unit_index(now_minutes: int) -> int:
	ensure_units()
	for i: int in range(units_busy_until.size()):
		if units_busy_until[i] <= now_minutes:
			return i
	return -1


func available_units(now_minutes: int) -> int:
	ensure_units()
	var free: int = 0
	for busy_until: int in units_busy_until:
		if busy_until <= now_minutes:
			free += 1
	return free
