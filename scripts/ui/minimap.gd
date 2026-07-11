class_name Minimap
extends Control
## Top-down city minimap. The city is static, so it is rendered ONCE at boot
## through a temporary orthographic SubViewport sharing the main World3D,
## then displayed as a plain texture. Owned restaurants are drawn as pins;
## clicking flies the RTS camera to that spot.
##
## Management layers are pure _draw() overlays over the baked texture —
## never rebaked per frame (the static city is the perf ceiling).

enum Layer { NONE, DEMAND, COVERAGE, ROUTES, ZONING }

const BAKE_SIZE: int = 512
const PIN_COLOR: Color = Color("#d8452e")
const PIN_RING: Color = Color("#fff2cf")
const CAM_COLOR: Color = Color("#2e5d9b")

const ZONING_COLORS: Dictionary = {
	"D": Color("#8a6cc9"), "C": Color("#4d86c9"), "I": Color("#8d8d8d"),
	"R": Color("#d8b13a"), "N": Color("#9cc069"), "P": Color("#c9a06c"),
	"K": Color("#57a05a"), "G": Color("#57a05a"), "X": Color("#d8863a"),
}

const ROUTE_COLORS: Dictionary = {
	&"scooter": Color("#3d8fd8"), &"car": Color("#e08a2d"),
	&"truck": Color("#e08a2d"), &"walker": Color("#3f9b45"),
}

var layer: Layer = Layer.NONE

var _texture: ImageTexture
var _bounds_min: Vector2 = Vector2.ZERO
var _bounds_max: Vector2 = Vector2(500, 500)
var _baked: bool = false
var _pin_tex: Texture2D
## Cached [block world Rect2, district code] pairs for zoning/demand fills.
var _blocks: Array[Array] = []
## Normalized citizen-home density per block index (demand heat).
var _block_density: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	custom_minimum_size = Vector2(280, 190)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var assets: GDScript = load("res://scripts/ui/ui_assets.gd")
	_pin_tex = assets.pin(&"pizza")
	RestaurantManager.restaurant_purchased.connect(func(_r: RestaurantState) -> void: queue_redraw())
	_compute_bounds()
	_bake.call_deferred()


func set_layer(new_layer: Layer) -> void:
	layer = new_layer
	if layer in [Layer.ZONING, Layer.DEMAND] and _blocks.is_empty():
		_build_block_cache()
	if layer == Layer.DEMAND and _block_density.is_empty():
		_build_density_cache()
	queue_redraw()


func legend_text() -> String:
	match layer:
		Layer.DEMAND:
			return "Demand heat: brighter red = more residents in reach"
		Layer.COVERAGE:
			return "Green circles = delivery reach of your restaurants"
		Layer.ROUTES:
			return "Live delivery routes (blue scooter · orange car)"
		Layer.ZONING:
			return "Zoning: purple downtown · blue commercial · grey industrial · green suburbs"
	return ""


func _process(_delta: float) -> void:
	# Cheap: redraw pins + camera dot; the city texture itself is static.
	if _baked and visible:
		queue_redraw()


func _draw() -> void:
	var rect: Rect2 = _display_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#dcc998"))
	if _texture != null:
		draw_texture_rect(_texture, rect, false)
	match layer:
		Layer.ZONING:
			_draw_blocks(false)
		Layer.DEMAND:
			_draw_blocks(true)
		Layer.COVERAGE:
			_draw_coverage()
		Layer.ROUTES:
			_draw_routes()
	# Camera position indicator.
	var rig: Node3D = _camera_rig()
	if rig != null:
		var p: Vector2 = _world_to_map(rig.global_position)
		draw_circle(p, 5.0, Color(CAM_COLOR, 0.4))
		draw_circle(p, 2.5, CAM_COLOR)
	# Restaurant pins.
	for rest: RestaurantState in RestaurantManager.owned:
		var pin: Vector2 = _world_to_map(rest.door_pos)
		if _pin_tex != null:
			var pin_size: Vector2 = Vector2(22, 22)
			draw_texture_rect(_pin_tex, Rect2(pin - Vector2(pin_size.x * 0.5, pin_size.y), pin_size), false)
		else:
			draw_circle(pin + Vector2(0, 1), 6.5, Color(0, 0, 0, 0.25))
			draw_circle(pin, 6.0, PIN_RING)
			draw_circle(pin, 4.2, PIN_COLOR)


func _draw_blocks(demand: bool) -> void:
	for i: int in _blocks.size():
		var entry: Array = _blocks[i]
		var world_rect: Rect2 = entry[0]
		var district: String = entry[1]
		var top_left: Vector2 = _world_to_map(Vector3(world_rect.position.x, 0, world_rect.position.y))
		var bottom_right: Vector2 = _world_to_map(Vector3(world_rect.end.x, 0, world_rect.end.y))
		var map_rect: Rect2 = Rect2(top_left, bottom_right - top_left)
		if demand:
			var density: float = _block_density[i] if i < _block_density.size() else 0.0
			if density <= 0.01:
				continue
			var heat: Color = Color("#3f9b45").lerp(Color("#f2c522"), clampf(density * 2.0, 0.0, 1.0))
			if density > 0.5:
				heat = Color("#f2c522").lerp(Color("#d8452e"), clampf((density - 0.5) * 2.0, 0.0, 1.0))
			heat.a = 0.28 + density * 0.34
			draw_rect(map_rect, heat)
		else:
			var color: Color = ZONING_COLORS.get(district, Color("#888888"))
			color.a = 0.42
			draw_rect(map_rect, color)


func _draw_coverage() -> void:
	var radius_m: float = float(EconomyManager.tuning_value("distance.delivery_max_m", 600.0))
	var rect: Rect2 = _display_rect()
	var span: Vector2 = _bounds_max - _bounds_min
	var radius_px: float = radius_m / span.x * rect.size.x
	for rest: RestaurantState in RestaurantManager.owned:
		var center: Vector2 = _world_to_map(rest.door_pos)
		draw_circle(center, radius_px, Color(0.25, 0.61, 0.27, 0.16))
		draw_arc(center, radius_px, 0.0, TAU, 48, Color("#3f9b45"), 1.5, true)


func _draw_routes() -> void:
	for building_id: int in DeliveryManager.rosters:
		for slot: Dictionary in DeliveryManager.rosters[building_id]:
			var node: Node = slot["node"]
			if not is_instance_valid(node) or not node.has_method("is_idle") or node.is_idle():
				continue
			var points: PackedVector3Array = node.remaining_route_points()
			if points.size() < 2:
				continue
			var vehicle: StringName = node.get("vehicle_type") if node.get("vehicle_type") != null else &"scooter"
			var color: Color = ROUTE_COLORS.get(vehicle, Color("#3d8fd8"))
			var map_points: PackedVector2Array = PackedVector2Array()
			for p: Vector3 in points:
				map_points.append(_world_to_map(p))
			draw_polyline(map_points, color, 2.0, true)
			draw_circle(map_points[0], 4.0, Color("#fff2cf"))
			draw_circle(map_points[0], 2.8, color)
			draw_circle(map_points[map_points.size() - 1], 3.0, Color(color, 0.7))


func _build_block_cache() -> void:
	_blocks.clear()
	for bj: int in CityBuilder.BLOCKS:
		for bi: int in CityBuilder.BLOCKS:
			var x0: float = CityBuilder.line_x(bi)
			var z0: float = CityBuilder.line_z(bj)
			var x1: float = CityBuilder.line_x(bi + 1)
			var z1: float = CityBuilder.line_z(bj + 1)
			_blocks.append([Rect2(x0, z0, x1 - x0, z1 - z0), CityBuilder.district(bi, bj)])


func _build_density_cache() -> void:
	if _blocks.is_empty():
		_build_block_cache()
	var counts: PackedFloat32Array = PackedFloat32Array()
	counts.resize(_blocks.size())
	var peak: float = 1.0
	for cd: Dictionary in PopulationManager.citizens_data:
		var home: Dictionary = CityData.get_building(int(cd.get("home_id", -1)))
		if home.is_empty():
			continue
		var pos: Vector3 = home.get("position", Vector3.ZERO)
		for i: int in _blocks.size():
			var world_rect: Rect2 = _blocks[i][0]
			if world_rect.has_point(Vector2(pos.x, pos.z)):
				counts[i] += 1.0
				peak = maxf(peak, counts[i])
				break
	for i: int in counts.size():
		counts[i] /= peak
	_block_density = counts


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
	# Skip layer 20 (world overlay markers) — fixed_size pin sprites would
	# render at constant screen size, i.e. huge, into the ortho bake.
	cam.cull_mask = cam.cull_mask & ~(1 << 19)
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
