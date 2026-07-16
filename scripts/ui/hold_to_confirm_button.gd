class_name HoldToConfirmButton
extends Button
## Press-and-hold danger button (feature 12 underworld launch): the label
## fills red left-to-right while held; releasing before HOLD_SECONDS resets.
## Emits `confirmed` once the fill completes. Deliberate friction so a
## high-consequence operation can never be launched by a stray click.

signal confirmed

const HOLD_SECONDS: float = 0.7

var _held: bool = false
var _progress: float = 0.0
var _fired: bool = false
var _fill: StyleBoxFlat


func _ready() -> void:
	toggle_mode = false
	custom_minimum_size = Vector2(0, 52)
	BellaUi.red_button(self)
	_fill = StyleBoxFlat.new()
	_fill.bg_color = Color(1, 1, 1, 0.28)
	_fill.set_corner_radius_all(10)
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	set_process(false)


func _on_down() -> void:
	if disabled:
		return
	_held = true
	_fired = false
	set_process(true)


func _on_up() -> void:
	_held = false
	if not _fired:
		_progress = 0.0
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	if not _held:
		return
	_progress = minf(1.0, _progress + delta / HOLD_SECONDS)
	queue_redraw()
	if _progress >= 1.0 and not _fired:
		_fired = true
		_held = false
		set_process(false)
		confirmed.emit()


func _draw() -> void:
	if _progress <= 0.0:
		return
	var rect: Rect2 = Rect2(Vector2(3, 3), Vector2((size.x - 6) * _progress, size.y - 6))
	draw_style_box(_fill, rect)
