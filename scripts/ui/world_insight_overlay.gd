class_name WorldInsightOverlay
extends Control
## Screen-space route and citizen-thought layer projected over the 3D city.

const MAX_THOUGHTS: int = 8
const REFRESH_INTERVAL: float = 0.12
const ROUTE_COLOR: Color = Color("#f05a32")
const ROUTE_SHADOW: Color = Color(0.20, 0.10, 0.05, 0.70)
const DESTINATION_COLOR: Color = Color("#ffd54a")
## Route tint per cosmetic fleet type (matches minimap + pin colors).
const VEHICLE_COLORS: Dictionary = {
	&"scooter": Color("#3d8fd8"), &"car": Color("#e08a2d"),
	&"truck": Color("#e08a2d"), &"walker": Color("#3f9b45"),
}

var insights_enabled: bool = false
var _selected: Node = null
var _accum: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SelectionManager.entity_selected.connect(_on_selected)
	SelectionManager.selection_cleared.connect(_on_cleared)


func set_insights_enabled(enabled: bool) -> void:
	insights_enabled = enabled
	queue_redraw()


func _on_selected(_info: Dictionary, entity: Node) -> void:
	_selected = entity
	queue_redraw()


func _on_cleared() -> void:
	_selected = null
	queue_redraw()


func _process(delta: float) -> void:
	_accum += delta
	if _accum < REFRESH_INTERVAL:
		return
	_accum = 0.0
	if _selected != null and not is_instance_valid(_selected):
		_selected = null
	queue_redraw()


func _draw() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	if insights_enabled:
		_draw_all_delivery_routes(camera)
	_draw_selected_route(camera)
	_draw_thoughts(camera)


## With CITY INSIGHTS on, every in-flight delivery shows a faint route so
## the whole delivery operation is readable at a glance.
func _draw_all_delivery_routes(camera: Camera3D) -> void:
	for building_id: int in DeliveryManager.rosters:
		for slot: Dictionary in DeliveryManager.rosters[building_id]:
			var node: Node = slot["node"]
			if not is_instance_valid(node) or node == _selected:
				continue
			if not node.has_method("is_idle") or node.is_idle():
				continue
			var points: PackedVector2Array = _project_route(camera, node.remaining_route_points())
			if points.size() < 2:
				continue
			var color: Color = _vehicle_color(node)
			color.a = 0.45
			draw_polyline(points, color, 2.5, true)
			draw_circle(points[0], 5.0, color)


func _vehicle_color(node: Node) -> Color:
	var vehicle: Variant = node.get("vehicle_type")
	if vehicle == null and node.has_method("is_company_delivery"):
		var driver: Variant = node.get("delivery_driver")
		if driver != null and is_instance_valid(driver):
			vehicle = driver.get("vehicle_type")
	return VEHICLE_COLORS.get(vehicle, ROUTE_COLOR)


func _project_route(camera: Camera3D, route: PackedVector3Array) -> PackedVector2Array:
	var screen_points: PackedVector2Array = PackedVector2Array()
	for world_point: Vector3 in route:
		if camera.is_position_behind(world_point):
			continue
		screen_points.append(camera.unproject_position(world_point + Vector3.UP * 0.35))
	return screen_points


func _draw_selected_route(camera: Camera3D) -> void:
	if not is_instance_valid(_selected):
		return
	var route: PackedVector3Array = PackedVector3Array()
	var selected_is_delivery: bool = false
	if _selected.has_method("is_company_delivery"):
		selected_is_delivery = bool(_selected.is_company_delivery())
	if _selected is Driver:
		selected_is_delivery = true
	if not selected_is_delivery or not _selected.has_method("remaining_route_points"):
		return
	route = _selected.remaining_route_points()
	if route.size() < 2:
		return
	var screen_points: PackedVector2Array = _project_route(camera, route)
	if screen_points.size() < 2:
		return
	var color: Color = _vehicle_color(_selected)
	# Solid near segment fades into a dashed "still to drive" remainder.
	draw_polyline(screen_points, ROUTE_SHADOW, 8.0, true)
	var solid_count: int = maxi(2, screen_points.size() / 3)
	draw_polyline(screen_points.slice(0, solid_count), color, 4.5, true)
	for i: int in range(solid_count - 1, screen_points.size() - 1):
		draw_dashed_line(screen_points[i], screen_points[i + 1], color, 3.5, 9.0, true, true)
	# Chevron dot on the driver's live position.
	draw_circle(screen_points[0], 9.0, Color("#fff2cf"))
	draw_circle(screen_points[0], 6.0, color)
	# Destination flag.
	var destination: Vector2 = screen_points[screen_points.size() - 1]
	draw_circle(destination, 13.0, ROUTE_SHADOW)
	draw_circle(destination, 9.0, DESTINATION_COLOR)
	draw_circle(destination, 4.0, color)
	var pole_top: Vector2 = destination + Vector2(0, -26)
	draw_line(destination, pole_top, ROUTE_SHADOW, 3.0, true)
	draw_colored_polygon(PackedVector2Array([
		pole_top, pole_top + Vector2(16, 5), pole_top + Vector2(0, 10),
	]), color)


func _draw_thoughts(camera: Camera3D) -> void:
	var shown: int = 0
	if insights_enabled:
		for citizen_id: int in DemandManager.restaurant_intents:
			if shown >= MAX_THOUGHTS:
				break
			var intent: Dictionary = DemandManager.restaurant_intents[citizen_id]
			var citizen: Node = intent.get("citizen")
			if not is_instance_valid(citizen) or not citizen is Node3D:
				continue
			if _draw_citizen_thought(camera, citizen):
				shown += 1
	if is_instance_valid(_selected) and _selected is Citizen:
		_draw_citizen_thought(camera, _selected)


func _draw_citizen_thought(camera: Camera3D, citizen: Node) -> bool:
	var world_pos: Vector3 = (citizen as Node3D).global_position + Vector3.UP * 2.4
	if camera.is_position_behind(world_pos):
		return false
	var screen_pos: Vector2 = camera.unproject_position(world_pos)
	if screen_pos.x < 340.0 or screen_pos.x > size.x - 410.0:
		return false
	if screen_pos.y < 76.0 or screen_pos.y > size.y - 196.0:
		return false
	var thought: String = String(citizen.call("thought_text")) if citizen.has_method("thought_text") else String(citizen.get("goal_desc"))
	if thought.length() > 54:
		thought = thought.left(51) + "…"
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 15
	var text_size: Vector2 = font.get_string_size(thought, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var bubble_size: Vector2 = Vector2(text_size.x + 24.0, 34.0)
	var bubble_rect: Rect2 = Rect2(screen_pos - Vector2(bubble_size.x * 0.5, bubble_size.y + 12.0), bubble_size)
	var panel: StyleBoxFlat = StyleBoxFlat.new()
	panel.bg_color = Color(1.0, 0.96, 0.82, 0.96)
	panel.border_color = Color("#9c5b27")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(10)
	draw_style_box(panel, bubble_rect)
	draw_string(font, bubble_rect.position + Vector2(12.0, 23.0), thought, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#4a2d19"))
	draw_circle(screen_pos - Vector2(0.0, 6.0), 5.0, Color(1.0, 0.96, 0.82, 0.96))
	return true
