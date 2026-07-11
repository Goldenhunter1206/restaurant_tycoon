class_name Minimap
extends Control
## Top-down city minimap. The city is static, so it is rendered ONCE at boot
## through a temporary orthographic SubViewport sharing the main World3D,
## then displayed as a plain texture. Owned restaurants are drawn as pins;
## clicking flies the RTS camera to that spot.

const BAKE_SIZE: int = 512
const PIN_COLOR: Color = Color("#d8452e")
const PIN_RING: Color = Color("#fff2cf")
const CAM_COLOR: Color = Color("#2e5d9b")

var _texture: ImageTexture
var _bounds_min: Vector2 = Vector2.ZERO
var _bounds_max: Vector2 = Vector2(500, 500)
var _baked: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(280, 200)
	mouse_filter = Control.MOUSE_FILTER_STOP
	RestaurantManager.restaurant_purchased.connect(func(_r: RestaurantState) -> void: queue_redraw())
	_compute_bounds()
	_bake.call_deferred()


func _process(_delta: float) -> void:
	# Cheap: redraw pins + camera dot; the city texture itself is static.
	if _baked and visible:
		queue_redraw()


func _draw() -> void:
	var rect: Rect2 = _display_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#dcc998"))
	if _texture != null:
		draw_texture_rect(_texture, rect, false)
	# Camera position indicator.
	var rig: Node3D = _camera_rig()
	if rig != null:
		var p: Vector2 = _world_to_map(rig.global_position)
		draw_circle(p, 5.0, Color(CAM_COLOR, 0.4))
		draw_circle(p, 2.5, CAM_COLOR)
	# Restaurant pins.
	for rest: RestaurantState in RestaurantManager.owned:
		var pin: Vector2 = _world_to_map(rest.door_pos)
		draw_circle(pin + Vector2(0, 1), 6.5, Color(0, 0, 0, 0.25))
		draw_circle(pin, 6.0, PIN_RING)
		draw_circle(pin, 4.2, PIN_COLOR)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var world: Vector3 = _map_to_world(event.position)
		var rig: Node3D = _camera_rig()
		if rig != null:
			rig.global_position = Vector3(world.x, rig.global_position.y, world.z)
		accept_event()


# --- Coordinate mapping -----------------------------------------------------


## Largest rect inside the control that keeps the world's aspect ratio.
func _display_rect() -> Rect2:
	var span: Vector2 = _bounds_max - _bounds_min
	if span.x <= 0.0 or span.y <= 0.0:
		return Rect2(Vector2.ZERO, size)
	var scale_factor: float = minf(size.x / span.x, size.y / span.y)
	var display: Vector2 = span * scale_factor
	return Rect2((size - display) * 0.5, display)


func _world_to_map(world: Vector3) -> Vector2:
	var rect: Rect2 = _display_rect()
	var span: Vector2 = _bounds_max - _bounds_min
	return rect.position + Vector2(
		(world.x - _bounds_min.x) / span.x * rect.size.x,
		(world.z - _bounds_min.y) / span.y * rect.size.y)


func _map_to_world(map_pos: Vector2) -> Vector3:
	var rect: Rect2 = _display_rect()
	var span: Vector2 = _bounds_max - _bounds_min
	var local: Vector2 = (map_pos - rect.position) / rect.size
	return Vector3(
		_bounds_min.x + clampf(local.x, 0.0, 1.0) * span.x,
		0.0,
		_bounds_min.y + clampf(local.y, 0.0, 1.0) * span.y)


func _compute_bounds() -> void:
	if CityData.buildings.is_empty():
		return
	var lo: Vector2 = Vector2(1e9, 1e9)
	var hi: Vector2 = Vector2(-1e9, -1e9)
	for id: int in CityData.buildings:
		var pos: Vector3 = CityData.get_building(id).get("position", Vector3.ZERO)
		lo = lo.min(Vector2(pos.x, pos.z))
		hi = hi.max(Vector2(pos.x, pos.z))
	var margin: Vector2 = (hi - lo) * 0.06
	_bounds_min = lo - margin
	_bounds_max = hi + margin


# --- One-time bake -----------------------------------------------------------


func _bake() -> void:
	var span: Vector2 = _bounds_max - _bounds_min
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(BAKE_SIZE, int(BAKE_SIZE * span.y / span.x))
	viewport.own_world_3d = false
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var cam: Camera3D = Camera3D.new()
	viewport.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Orthographic "size" is the vertical extent; match world Z span.
	cam.size = span.y
	cam.far = 900.0
	var center: Vector2 = (_bounds_min + _bounds_max) * 0.5
	cam.global_position = Vector3(center.x, 400.0, center.y)
	# Look straight down with -Z of the camera pointing at world +Z so the
	# map reads north-up: rotate -90 deg around X.
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	_texture = ImageTexture.create_from_image(image)
	# Restore the main camera before removing the temporary one.
	var main_cam: Camera3D = _main_camera()
	if main_cam != null:
		main_cam.current = true
	viewport.queue_free()
	_baked = true
	queue_redraw()


func _camera_rig() -> Node3D:
	return get_tree().current_scene.get_node_or_null("CameraRig")


func _main_camera() -> Camera3D:
	var rig: Node3D = _camera_rig()
	if rig != null:
		return rig.get_node_or_null("Camera3D")
	return null
