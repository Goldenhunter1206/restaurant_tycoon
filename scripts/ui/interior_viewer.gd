class_name InteriorViewer
extends Control
## Fullscreen takeover that renders the live RestaurantInterior scene in an
## isolated SubViewport (own World3D, so city lighting/DayNight never bleeds
## in). While open it hides the tycoon HUD and freezes city camera/selection
## input; everything is restored in _exit_tree so even an abnormal close
## cannot strand the city controls. The GameClock is never touched — this is
## a live window onto the running sim.

const INTERIOR_SCENE: String = "res://scenes/restaurant/RestaurantInterior.tscn"

var hud: Control = null

var _viewport: SubViewport = null
var _view: Node3D = null
var _clock_label: Label = null
var _speed_buttons: Dictionary = {}
var _camera_rig: Node3D = null
var _root_3d_was_disabled: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = TycoonTheme.build()

	var container: SubViewportContainer = SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_viewport)

	_build_top_bar()
	_capture_city_input()
	GameClock.minute_ticked.connect(_on_minute)
	GameClock.speed_changed.connect(_on_speed_changed)
	_on_speed_changed(GameClock.speed)
	_refresh_clock()


func _exit_tree() -> void:
	_release_city_input()
	if GameClock.minute_ticked.is_connected(_on_minute):
		GameClock.minute_ticked.disconnect(_on_minute)
	if GameClock.speed_changed.is_connected(_on_speed_changed):
		GameClock.speed_changed.disconnect(_on_speed_changed)


func setup(building_id: int) -> void:
	var packed: PackedScene = load(INTERIOR_SCENE)
	if packed == null:
		close()
		return
	_view = packed.instantiate()
	_viewport.add_child(_view)
	_view.view_invalidated.connect(close)
	_view.setup(building_id)
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	var title: Label = get_node_or_null("TopBar/Row/Title")
	if title != null and rest != null:
		title.text = rest.restaurant_name


func close() -> void:
	queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


# --- UI -----------------------------------------------------------------------


func _build_top_bar() -> void:
	var bar: PanelContainer = PanelContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 12.0
	bar.offset_right = -12.0
	bar.offset_top = 10.0
	bar.offset_bottom = 62.0
	bar.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
	add_child(bar)
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)

	var back: Button = Button.new()
	back.text = "← BACK TO CITY"
	back.custom_minimum_size = Vector2(170, 40)
	TycoonTheme.apply_orange(back)
	back.pressed.connect(close)
	row.add_child(back)

	var title: Label = Label.new()
	title.name = "Title"
	title.text = "RESTAURANT"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(title)

	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 20)
	row.add_child(_clock_label)

	var speed_box: HBoxContainer = HBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 5)
	for entry: Array in [["⏸", 0], ["▶", 1], ["⏩", 4], ["⏭", 16]]:
		var btn: Button = Button.new()
		btn.text = String(entry[0])
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(42, 40)
		TycoonTheme.apply_orange(btn)
		var speed: int = int(entry[1])
		btn.pressed.connect(func() -> void: GameClock.set_speed(speed))
		speed_box.add_child(btn)
		_speed_buttons[speed] = btn
	row.add_child(speed_box)


func _on_minute(_day: int, _hour: int, _minute: int) -> void:
	_refresh_clock()


func _refresh_clock() -> void:
	if _clock_label != null:
		_clock_label.text = GameClock.time_string_ampm()


func _on_speed_changed(speed: int) -> void:
	for value: int in _speed_buttons:
		(_speed_buttons[value] as Button).set_pressed_no_signal(value == speed)


# --- City input capture ---------------------------------------------------------


func _capture_city_input() -> void:
	## RtsCamera polls Input in _process, which no Control can block — it
	## must be switched off explicitly while the interior is open.
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		_camera_rig = scene_root.get_node_or_null("CameraRig")
	if _camera_rig != null:
		_camera_rig.set_process(false)
		_camera_rig.set_process_input(false)
		_camera_rig.set_process_unhandled_input(false)
	SelectionManager.set_process_unhandled_input(false)
	if hud != null:
		hud.visible = false
	var root_viewport: Viewport = get_viewport()
	if root_viewport != null:
		_root_3d_was_disabled = root_viewport.disable_3d
		root_viewport.disable_3d = true


func _release_city_input() -> void:
	if is_instance_valid(_camera_rig):
		_camera_rig.set_process(true)
		_camera_rig.set_process_input(true)
		_camera_rig.set_process_unhandled_input(true)
	SelectionManager.set_process_unhandled_input(true)
	if is_instance_valid(hud):
		hud.visible = true
	var root_viewport: Viewport = get_viewport()
	if root_viewport != null:
		root_viewport.disable_3d = _root_3d_was_disabled
