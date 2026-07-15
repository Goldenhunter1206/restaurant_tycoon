class_name UpgradeProjectState
extends Resource
## One paid headquarters project. Completion state makes load processing safe.

@export var id: int = 0
@export var kind: StringName = &""
@export var target_id: StringName = &""
@export var target_building_id: int = -1
@export var from_level: int = 0
@export var to_level: int = 0
@export var start_minute: int = 0
@export var end_minute: int = 0
@export var paid_amount: float = 0.0
@export var paused: bool = false
@export var paused_at_minute: int = 0
@export var blockers: Array[String] = []
@export var completion_applied: bool = false


func progress_at(now_minute: int) -> float:
	var duration: int = maxi(1, end_minute - start_minute)
	var current: int = paused_at_minute if paused else now_minute
	return clampf(float(current - start_minute) / float(duration), 0.0, 1.0)


func remaining_minutes(now_minute: int) -> int:
	var current: int = paused_at_minute if paused else now_minute
	return maxi(0, end_minute - current)
