extends Node
## Global game time. At speed 1, one real minute equals one game hour,
## so a full day passes in 24 real minutes.

signal minute_ticked(day: int, hour: int, minute: int)
signal hour_changed(day: int, hour: int)
signal speed_changed(new_speed: int)
signal day_changed(day: int)

const GAME_HOURS_PER_REAL_SECOND: float = 1.0 / 60.0
const SPEEDS: Array[int] = [0, 1, 4, 16]

## Presentation calendar: 14-day months, 12 months per year.
const DAYS_PER_MONTH: int = 14
const MONTH_NAMES: Array[String] = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

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
		day_changed.emit(day)
	var hour: int = int(game_hours)
	var minute: int = int(fmod(game_hours, 1.0) * 60.0)
	if hour != _last_emitted_hour:
		_last_emitted_hour = hour
		hour_changed.emit(day, hour)
	if minute != _last_emitted_minute:
		_last_emitted_minute = minute
		minute_ticked.emit(day, hour, minute)


func total_minutes() -> int:
	## Absolute game minute since day 1, 00:00. Sim timers diff this value so
	## they stay correct when minute_ticked skips minutes at high speed.
	return (day - 1) * 1440 + int(game_hours * 60.0)


func set_speed(new_speed: int) -> void:
	if new_speed in SPEEDS and new_speed != speed:
		speed = new_speed
		speed_changed.emit(speed)


func time_string() -> String:
	var hour: int = int(game_hours)
	var minute: int = int(fmod(game_hours, 1.0) * 60.0)
	return "%02d:%02d" % [hour, minute]


func time_string_ampm() -> String:
	var hour: int = int(game_hours)
	var minute: int = int(fmod(game_hours, 1.0) * 60.0)
	var suffix: String = "AM" if hour < 12 else "PM"
	var display_hour: int = hour % 12
	if display_hour == 0:
		display_hour = 12
	return "%d:%02d %s" % [display_hour, minute, suffix]


func month_index_for(a_day: int) -> int:
	return ((a_day - 1) / DAYS_PER_MONTH) % 12


func month_name_for(a_day: int) -> String:
	return MONTH_NAMES[month_index_for(a_day)]


func day_of_month() -> int:
	return (day - 1) % DAYS_PER_MONTH + 1


func year() -> int:
	return (day - 1) / (DAYS_PER_MONTH * 12) + 1


func quarter() -> int:
	return month_index_for(day) / 3 + 1


func date_string() -> String:
	return "%s %d, Year %d" % [month_name_for(day), day_of_month(), year()]


func is_between(start_hour: float, end_hour: float) -> bool:
	## Handles ranges that wrap past midnight, e.g. is_between(22.0, 6.0).
	if start_hour <= end_hour:
		return game_hours >= start_hour and game_hours < end_hour
	return game_hours >= start_hour or game_hours < end_hour
