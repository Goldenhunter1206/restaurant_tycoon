class_name Sparkline
extends Control
## Tiny line chart for daily sales history (last 14 days).

var values: PackedFloat32Array = PackedFloat32Array()

const LINE_COLOR: Color = Color("#3f9b45")
const FILL_COLOR: Color = Color(0.25, 0.61, 0.27, 0.15)
const GRID_COLOR: Color = Color(0.54, 0.35, 0.17, 0.25)


func _ready() -> void:
	custom_minimum_size = Vector2(120, 42)


func set_values(new_values: Array) -> void:
	values = PackedFloat32Array(new_values)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#faf0d8"))
	draw_rect(Rect2(Vector2.ZERO, size), GRID_COLOR, false, 1.0)
	if values.size() < 2:
		draw_string(get_theme_default_font(), Vector2(6, size.y * 0.6),
			"collecting data…", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8a7150"))
		return
	# Range starts at [0, 1] so all-positive data keeps its zero baseline;
	# negative values (e.g. profit) extend the range downward instead of
	# drawing outside the widget.
	var lo: float = 0.0
	var hi: float = 1.0
	for v: float in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var span: float = maxf(hi - lo, 0.001)
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in values.size():
		points.append(Vector2(
			4.0 + float(i) / float(values.size() - 1) * (size.x - 8.0),
			size.y - 5.0 - (values[i] - lo) / span * (size.y - 12.0)))
	if lo < 0.0:
		var zero_y: float = size.y - 5.0 - (0.0 - lo) / span * (size.y - 12.0)
		draw_line(Vector2(4.0, zero_y), Vector2(size.x - 4.0, zero_y), GRID_COLOR, 1.0)
	var fill: PackedVector2Array = points.duplicate()
	fill.append(Vector2(points[points.size() - 1].x, size.y - 2.0))
	fill.append(Vector2(points[0].x, size.y - 2.0))
	draw_colored_polygon(fill, FILL_COLOR)
	draw_polyline(points, LINE_COLOR, 2.0, true)
	for p: Vector2 in points:
		draw_circle(p, 2.0, LINE_COLOR)
