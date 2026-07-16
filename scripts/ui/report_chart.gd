class_name ReportChart
extends Control
## Report chart shell — a bar series with an optional compare overlay line and
## clickable event annotations, drawn in the Bella Vista style (parchment plate,
## wood bars, gold "latest", red anomaly tags). Mirrors the Sparkline custom-_draw
## pattern. Clicking a bar emits bar_clicked(index) so the screen can open the
## events that explain that day.

signal bar_clicked(index: int)

const BAR: Color = Color("#C6883A")        # wood
const BAR_LAST: Color = Color("#F5C518")   # gold — the most recent bucket
const BAR_ANNOTATED: Color = Color("#EA4A2F")
const OVERLAY: Color = Color("#3AA6D6")    # compare line
const PLATE: Color = Color("#FEF8E4")
const GRID: Color = Color(0.54, 0.35, 0.17, 0.22)
const INK: Color = Color("#4A2A18")
const MUTED: Color = Color("#8a7150")

var _values: PackedFloat32Array = PackedFloat32Array()
var _labels: Array = []
var _overlay: PackedFloat32Array = PackedFloat32Array()
var _annotations: Array = []  # [{index:int, label:String, tone:StringName}]
var _hover: int = -1


func _ready() -> void:
	custom_minimum_size = Vector2(0, 150)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_series(values: Array, labels: Array = []) -> void:
	_values = PackedFloat32Array(values)
	_labels = labels
	queue_redraw()


func set_overlay(values: Array) -> void:
	_overlay = PackedFloat32Array(values)
	queue_redraw()


func set_annotations(annotations: Array) -> void:
	_annotations = annotations
	queue_redraw()


func clear() -> void:
	_values = PackedFloat32Array()
	_overlay = PackedFloat32Array()
	_annotations = []
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PLATE)
	draw_rect(Rect2(Vector2.ZERO, size), GRID, false, 1.0)
	var font: Font = get_theme_default_font()
	if _values.size() == 0:
		draw_string(font, Vector2(10, size.y * 0.5), "Collecting data — check back at midnight.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MUTED)
		return
	var pad_l: float = 8.0
	var pad_r: float = 8.0
	var pad_t: float = 22.0  # room for annotation tags
	var pad_b: float = 18.0  # room for x labels
	var plot := Rect2(pad_l, pad_t, size.x - pad_l - pad_r, size.y - pad_t - pad_b)
	var lo: float = 0.0
	var hi: float = 0.001
	for v: float in _values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	for v: float in _overlay:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var span: float = maxf(hi - lo, 0.001)
	var n: int = _values.size()
	var slot: float = plot.size.x / float(n)
	var bar_w: float = maxf(3.0, slot * 0.66)
	var base_y: float = plot.position.y + plot.size.y - (0.0 - lo) / span * plot.size.y
	# zero baseline for negative series
	if lo < 0.0:
		draw_line(Vector2(plot.position.x, base_y), Vector2(plot.end.x, base_y), GRID, 1.0)
	var annotated: Dictionary = {}
	for a: Dictionary in _annotations:
		annotated[int(a.get("index", -1))] = a
	for i: int in n:
		var cx: float = plot.position.x + slot * (float(i) + 0.5)
		var v: float = _values[i]
		var top_y: float = plot.position.y + plot.size.y - (v - lo) / span * plot.size.y
		var color: Color = BAR
		if annotated.has(i):
			color = BAR_ANNOTATED
		elif i == n - 1:
			color = BAR_LAST
		if i == _hover:
			color = color.lightened(0.12)
		var y0: float = minf(top_y, base_y)
		var y1: float = maxf(top_y, base_y)
		draw_rect(Rect2(cx - bar_w * 0.5, y0, bar_w, maxf(1.0, y1 - y0)), color)
	# compare overlay line
	if _overlay.size() >= 2:
		var pts: PackedVector2Array = PackedVector2Array()
		var m: int = mini(_overlay.size(), n)
		for i: int in m:
			var cx: float = plot.position.x + slot * (float(i) + 0.5)
			var oy: float = plot.position.y + plot.size.y - (_overlay[i] - lo) / span * plot.size.y
			pts.append(Vector2(cx, oy))
		draw_polyline(pts, OVERLAY, 2.0, true)
		for p: Vector2 in pts:
			draw_circle(p, 2.5, OVERLAY)
	# annotation tags
	for i: int in annotated:
		if i < 0 or i >= n:
			continue
		var a: Dictionary = annotated[i]
		var cx: float = plot.position.x + slot * (float(i) + 0.5)
		var text: String = String(a.get("label", "!"))
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 10.0
		var tag := Rect2(clampf(cx - tw * 0.5, 2.0, size.x - tw - 2.0), 3.0, tw, 15.0)
		draw_rect(tag, BAR_ANNOTATED, true)
		draw_string(font, Vector2(tag.position.x + 5.0, tag.position.y + 11.5), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)
	# x labels (first, middle, last to avoid clutter)
	if not _labels.is_empty():
		for idx: int in [0, n / 2, n - 1]:
			if idx < 0 or idx >= _labels.size():
				continue
			var cx: float = plot.position.x + slot * (float(idx) + 0.5)
			var txt: String = str(_labels[idx])
			var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(font, Vector2(cx - w * 0.5, size.y - 5.0), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, MUTED)


func _gui_input(event: InputEvent) -> void:
	if _values.size() == 0:
		return
	if event is InputEventMouseMotion:
		var idx: int = _index_at((event as InputEventMouseMotion).position.x)
		if idx != _hover:
			_hover = idx
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var idx: int = _index_at(mb.position.x)
			if idx >= 0:
				bar_clicked.emit(idx)


func _index_at(mx: float) -> int:
	var pad_l: float = 8.0
	var pad_r: float = 8.0
	var plot_w: float = size.x - pad_l - pad_r
	if plot_w <= 0.0 or _values.size() == 0:
		return -1
	var slot: float = plot_w / float(_values.size())
	var idx: int = int((mx - pad_l) / slot)
	return clampi(idx, 0, _values.size() - 1)
