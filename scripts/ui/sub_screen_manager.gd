class_name SubScreenManager
extends Control
## Modal overlay hosting one management screen at a time. Screens register
## as GDScript classes in SCREENS — adding a screen is one dictionary entry.

const SCREENS: Dictionary = {
	&"recipes": preload("res://scripts/ui/screens/menu_screen.gd"),
	&"staff": preload("res://scripts/ui/screens/staff_screen.gd"),
	&"finances": preload("res://scripts/ui/screens/finances_screen.gd"),
	&"deliveries": preload("res://scripts/ui/screens/delivery_screen.gd"),
	&"build": preload("res://scripts/ui/screens/purchase_screen.gd"),
	&"marketing": preload("res://scripts/ui/screens/stub_screen.gd"),
	&"suppliers": preload("res://scripts/ui/screens/stub_screen.gd"),
	&"reports": preload("res://scripts/ui/screens/stub_screen.gd"),
	&"rankings": preload("res://scripts/ui/screens/stub_screen.gd"),
}

var _active: TycoonScreen
var _dimmer: ColorRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dimmer = ColorRect.new()
	_dimmer.color = Color(0.0, 0.0, 0.0, 0.35)
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dimmer.visible = false
	_dimmer.gui_input.connect(_on_dimmer_input)
	add_child(_dimmer)


func open(screen_id: StringName, building_id: int) -> void:
	close()
	var script: GDScript = SCREENS.get(screen_id)
	if script == null:
		return
	_active = script.new()
	if _active.has_method("set_screen_id"):
		_active.set_screen_id(screen_id)
	_dimmer.visible = true
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_active)
	_active.setup(building_id)
	_active.closed.connect(close)
	_active.set_anchors_preset(Control.PRESET_CENTER)
	_active.reset_size.call_deferred()
	_center_active.call_deferred()
	_animate_open.call_deferred()


func close() -> void:
	if is_instance_valid(_active):
		_active.queue_free()
	_active = null
	_dimmer.visible = false
	_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Nav-bar "CITY MAP" behaviour: close whatever modal is open.
func close_active() -> void:
	close()


func _animate_open() -> void:
	if not is_instance_valid(_active):
		return
	_active.pivot_offset = _active.size * 0.5
	_active.scale = Vector2(0.92, 0.92)
	_active.modulate = Color(1, 1, 1, 0)
	_dimmer.modulate = Color(1, 1, 1, 0)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_active, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_active, "modulate:a", 1.0, 0.12)
	tween.tween_property(_dimmer, "modulate:a", 1.0, 0.12)


func is_open() -> bool:
	return is_instance_valid(_active)


func refresh_active() -> void:
	if is_instance_valid(_active):
		_active.refresh()


func _center_active() -> void:
	if is_instance_valid(_active):
		_active.position = (size - _active.size) * 0.5


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
