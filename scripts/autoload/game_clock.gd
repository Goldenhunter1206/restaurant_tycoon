extends Node
## Global game time. At speed 1, one real minute equals one game hour,
## so a full day passes in 24 real minutes.

signal minute_ticked(day: int, hour: int, minute: int)
signal hour_changed(day: int, hour: int)
signal speed_changed(new_speed: int)

const GAME_HOURS_PER_REAL_SECOND: float = 1.0 / 60.0
const SPEEDS: Array[int] = [0, 1, 4, 16]

var day: int = 1
var game_hours: float = 7.0
var speed: int = 1

var _last_emitted_minute: int = -1
var _last_emitted_hour: int = -1


func _process(delta: float) -> void:
	if speed == 0:
		return
	game_hours += delta * GAME_HOURS_PER_REAL_SECOND * float(speed)
	if game_hours >= 24.0:
		game_hours -= 24.0
		day += 1
	var hour: int = int(game_hours)
	var minute: int = int(fmod(game_hours, 1.0) * 60.0)
	if hour != _last_emitted_hour:
		_last_emitted_hour = hour
		hour_changed.emit(day, hour)
	if minute != _last_emitted_minute:
		_last_emitted_minute = minute
		minute_ticked.emit(day, hour, minute)


func set_speed(new_speed: int) -> void:
	if new_speed in SPEEDS and new_speed != speed:
		speed = new_speed
		speed_changed.emit(speed)


func time_string() -> String:
	var hour: int = int(game_hours)
	var minute: int = int(fmod(game_hours, 1.0) * 60.0)
	return "%02d:%02d" % [hour, minute]


func is_between(start_hour: float, end_hour: float) -> bool:
	## Handles ranges that wrap past midnight, e.g. is_between(22.0, 6.0).
	if start_hour <= end_hour:
		return game_hours >= start_hour and game_hours < end_hour
	return game_hours >= start_hour or game_hours < end_hour
