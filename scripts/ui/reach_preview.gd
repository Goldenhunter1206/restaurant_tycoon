class_name ReachPreview
extends Control
## Stylized "live reach preview" mini-map for the Marketing screen: green
## ground plane, an orange reach glow per coverage center and a red pin per
## advertised spot. Pure _draw() over static bounds — it never bakes or
## touches the real minimap viewport.

const GROUND_DARK: Color = Color("#4A8535")
const GROUND_LIT: Color = Color("#7FBF63")
const GLOW: Color = Color("#F99A1C")
const PIN: Color = Color("#EA4A2F")

var _centers: Array[Vector3] = []
var _radius_m: float = 0.0
var _citywide: bool = false
var _bounds_min: Vector2 = Vector2.ZERO
var _bounds_max: Vector2 = Vector2(800, 800)
var _bounds_ready: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(0, 150)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Update what the preview shows; pass citywide=true for city-scope channels.
func show_reach(centers: Array[Vector3], radius_m: float, citywide: bool) -> void:
	_centers = centers
	_radius_m = radius_m
	_citywide = citywide
	queue_redraw()


func _draw() -> void:
	_ensure_bounds()
	# Ground plane with a soft lit patch (design: radial 35%/40%).
	draw_rect(Rect2(Vector2.ZERO, size), GROUND_DARK)
	var lit_center: Vector2 = Vector2(size.x * 0.35, size.y * 0.4)
	for i: int in range(4, 0, -1):
		var t: float = i / 4.0
		draw_circle(lit_center, size.x * 0.45 * t, Color(GROUND_LIT, 0.16))
	if _citywide:
		draw_rect(Rect2(Vector2.ZERO, size), Color(GLOW, 0.22))
	for center: Vector3 in _centers:
		var p: Vector2 = _world_to_map(center)
		if not _citywide and _radius_m > 0.0:
			var radius_px: float = _radius_m / (_bounds_max.x - _bounds_min.x) * size.x
			for i: int in range(5, 0, -1):
				var t: float = i / 5.0
				draw_circle(p, radius_px * t, Color(GLOW, 0.5 * (1.0 - t) + 0.08))
		draw_circle(p, 7.0, Color(1, 1, 1, 0.9))
		draw_circle(p, 5.0, PIN)


func _ensure_bounds() -> void:
	if _bounds_ready or CityData.buildings.is_empty():
		return
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for info: Dictionary in CityData.buildings.values():
		var pos: Vector3 = info.get("position", Vector3.ZERO)
		lo = Vector2(minf(lo.x, pos.x), minf(lo.y, pos.z))
		hi = Vector2(maxf(hi.x, pos.x), maxf(hi.y, pos.z))
	if lo.x < hi.x:
		_bounds_min = lo
		_bounds_max = hi
		_bounds_ready = true


func _world_to_map(world: Vector3) -> Vector2:
	var span: Vector2 = _bounds_max - _bounds_min
	if span.x <= 0.0 or span.y <= 0.0:
		return size * 0.5
	return Vector2(
		(world.x - _bounds_min.x) / span.x * size.x,
		(world.z - _bounds_min.y) / span.y * size.y)
