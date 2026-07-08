class_name TimeHud
extends Control
## Dev HUD: clock, day counter and speed buttons (pause/1x/4x/16x).
## Builds its own controls at runtime — it is a debug/dev surface.

var _clock_label: Label
var _speed_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	add_child(panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_clock_label = Label.new()
	_clock_label.custom_minimum_size = Vector2(150, 0)
	box.add_child(_clock_label)
	for speed in GameClock.SPEEDS:
		var btn := Button.new()
		btn.text = "❚❚" if speed == 0 else "%dx" % speed
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_speed_pressed.bind(speed))
		box.add_child(btn)
		_speed_buttons[speed] = btn
	GameClock.speed_changed.connect(_sync_buttons)
	_sync_buttons(GameClock.speed)


func _process(_delta: float) -> void:
	_clock_label.text = "Day %d   %s" % [GameClock.day, GameClock.time_string()]


func _on_speed_pressed(speed: int) -> void:
	GameClock.set_speed(speed)
	_sync_buttons(speed)


func _sync_buttons(active_speed: int) -> void:
	for speed: int in _speed_buttons:
		_speed_buttons[speed].button_pressed = speed == active_speed
