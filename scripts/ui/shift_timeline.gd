class_name ShiftTimeline
extends Control
## One employee's daily shift on a 24h strip. Draws the open-hours band,
## hour gridlines, a "now" marker and the shift bar; the player drags the
## bar to move the shift or its right edge to resize it. Snaps to 30
## game-minutes and emits shift_changed on release.

signal shift_changed(start: float, hours: float)

const SNAP: float = 0.5
const EDGE_PX: float = 9.0

var member: StaffMember = null
var open_hour: float = 10.0
var close_hour: float = 22.0
var bar_color: Color = Color("#c0392b")

## 0 = idle, 1 = moving the bar, 2 = resizing its end.
var _drag_mode: int = 0
## Hours between the bar start and the grab point while moving.
var _grab_offset: float = 0.0
var _preview_start: float = 0.0
var _preview_hours: float = 8.0
var _min_hours: float = 2.0
var _max_hours: float = 10.0


func _ready() -> void:
	custom_minimum_size = Vector2(180, 30)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func setup(p_member: StaffMember, p_open: float, p_close: float, color: Color) -> void:
	member = p_member
	open_hour = p_open
	close_hour = p_close
	bar_color = color
	_min_hours = float(EconomyManager.tuning_value("staff.min_shift_hours", 2.0))
	_max_hours = float(EconomyManager.tuning_value("staff.max_shift_hours", 10.0))
	queue_redraw()


func is_dragging() -> bool:
	return _drag_mode != 0


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(0.0, 0.0, w, h), Color(0.0, 0.0, 0.0, 0.28))
	# Open-hours band so shifts are easy to line up with service.
	_draw_span(open_hour, wrapf(close_hour - open_hour, 0.001, 24.0), Color(1.0, 1.0, 1.0, 0.08), 0.0)
	var grid_font: Font = get_theme_default_font()
	for hour: int in range(0, 25, 2):
		var x: float = w * float(hour) / 24.0
		var strong: bool = hour % 6 == 0
		draw_line(Vector2(x, 0.0), Vector2(x, h), Color(1.0, 1.0, 1.0, 0.2 if strong else 0.08))
		if strong and hour > 0 and hour < 24:
			draw_string(grid_font, Vector2(x + 2.0, 9.0), str(hour),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 1.0, 1.0, 0.45))
	var start: float = _preview_start if _drag_mode != 0 else (member.shift_start if member != null else 0.0)
	var hours: float = _preview_hours if _drag_mode != 0 else (member.shift_hours if member != null else 0.0)
	var color: Color = bar_color if _drag_mode == 0 else bar_color.lightened(0.2)
	_draw_span(start, hours, color, 4.0)
	var label: String = "%s–%s" % [_fmt_hour(start), _fmt_hour(start + hours)]
	var font: Font = get_theme_default_font()
	var text_x: float = clampf(w * start / 24.0 + 6.0, 4.0, maxf(4.0, w - 70.0))
	draw_string(font, Vector2(text_x, h * 0.5 + 4.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(1.0, 1.0, 1.0, 0.9))
	var now_x: float = w * GameClock.game_hours / 24.0
	draw_line(Vector2(now_x, 0.0), Vector2(now_x, h), Color("#ffd54a", 0.9), 2.0)


func _draw_span(start: float, hours: float, color: Color, inset: float) -> void:
	var w: float = size.x
	var h: float = size.y
	start = wrapf(start, 0.0, 24.0)
	var first: float = minf(hours, 24.0 - start)
	draw_rect(Rect2(w * start / 24.0, inset, w * first / 24.0, h - inset * 2.0), color)
	if hours > first:
		draw_rect(Rect2(0.0, inset, w * (hours - first) / 24.0, h - inset * 2.0), color)


func _gui_input(event: InputEvent) -> void:
	if member == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_begin_drag(mb.position)
		elif _drag_mode != 0:
			_drag_mode = 0
			shift_changed.emit(_preview_start, _preview_hours)
			queue_redraw()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _drag_mode != 0:
			_update_drag(mm.position)
		else:
			_update_hover_cursor(mm.position)


func _begin_drag(pos: Vector2) -> void:
	var rel: float = wrapf(_hour_at(pos.x) - member.shift_start, 0.0, 24.0)
	if rel > member.shift_hours:
		return
	_preview_start = member.shift_start
	_preview_hours = member.shift_hours
	var edge_hours: float = EDGE_PX / maxf(size.x, 1.0) * 24.0
	if member.shift_hours - rel <= edge_hours:
		_drag_mode = 2
	else:
		_drag_mode = 1
		_grab_offset = rel
	queue_redraw()


func _update_drag(pos: Vector2) -> void:
	var hour: float = _hour_at(pos.x)
	if _drag_mode == 1:
		_preview_start = snappedf(wrapf(hour - _grab_offset, 0.0, 24.0), SNAP)
	elif _drag_mode == 2:
		var dur: float = hour - _preview_start
		if dur < 0.0:
			dur += 24.0
		_preview_hours = clampf(snappedf(dur, SNAP), _min_hours, _max_hours)
	queue_redraw()


func _update_hover_cursor(pos: Vector2) -> void:
	var rel: float = wrapf(_hour_at(pos.x) - member.shift_start, 0.0, 24.0)
	var edge_hours: float = EDGE_PX / maxf(size.x, 1.0) * 24.0
	if rel <= member.shift_hours and member.shift_hours - rel <= edge_hours:
		mouse_default_cursor_shape = Control.CURSOR_HSIZE
	elif rel <= member.shift_hours:
		mouse_default_cursor_shape = Control.CURSOR_DRAG
	else:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _hour_at(x: float) -> float:
	return clampf(x, 0.0, size.x) / maxf(size.x, 1.0) * 24.0


func _fmt_hour(hour: float) -> String:
	hour = wrapf(hour, 0.0, 24.0)
	return "%d:%02d" % [int(hour), int(roundf(fmod(hour, 1.0) * 60.0))]
