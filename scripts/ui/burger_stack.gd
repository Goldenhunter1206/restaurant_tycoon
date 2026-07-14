class_name BurgerStack
extends Control
## Side-on burger assembly canvas. Draws bottom bun -> ordered layers -> top
## bun from a RecipeDef's components (semantic stack_index order — never
## arbitrary transforms) plus a structure meter. Drag a layer up/down to
## reorder, double-click to remove.
##
## Keyboard alternatives (accessibility): Up/Down move the selected layer,
## Delete removes it.

signal component_selected(index: int)
signal remove_requested(index: int)
signal edit_committed

const LAYER_MIN_H: float = 12.0
const LAYER_H_PER_THICKNESS: float = 20.0
const BUN_H: float = 52.0
const STACK_W: float = 300.0

var recipe: RecipeDef = null
var selected_index: int = -1

var _dragging: bool = false
var _drag_moved: bool = false
var _drag_slot: int = -1


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(360, 360)


func set_recipe(rec: RecipeDef) -> void:
	recipe = rec
	selected_index = -1
	queue_redraw()


func is_dragging() -> bool:
	return _dragging


## Components sorted bottom -> top (ascending stack_index).
func _stack() -> Array[RecipeComponent]:
	if recipe == null:
		return []
	return recipe.sorted_stack()


func _layer_height(comp: RecipeComponent) -> float:
	return LAYER_MIN_H + comp.thickness * LAYER_H_PER_THICKNESS


## Rect of each layer, bottom-up, centered horizontally. Returns
## [{comp, index_in_components, rect}] in stack (bottom->top) order.
func _layer_rects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stack: Array[RecipeComponent] = _stack()
	var total_h: float = BUN_H * 2.0 + 6.0
	for comp: RecipeComponent in stack:
		total_h += _layer_height(comp) - 3.0
	var w: float = minf(size.x * 0.55, STACK_W)
	var x: float = (size.x - w) * 0.5
	var y: float = size.y * 0.5 + total_h * 0.5 - BUN_H
	for comp: RecipeComponent in stack:
		var h: float = _layer_height(comp)
		y -= h - 3.0
		out.append({
			"comp": comp,
			"index": recipe.components.find(comp),
			"rect": Rect2(x, y, w, h),
		})
	return out


func _draw() -> void:
	if recipe == null:
		return
	var rects: Array[Dictionary] = _layer_rects()
	var w: float = minf(size.x * 0.55, STACK_W)
	var x: float = (size.x - w) * 0.5
	var bottom_y: float = size.y * 0.5 + (_total_height() * 0.5) - BUN_H
	# Soft plate shadow ellipse.
	draw_set_transform(Vector2(x + w * 0.5, bottom_y + BUN_H + 2.0), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, w * 0.62, Color(0.23, 0.13, 0.06, 0.30))
	draw_set_transform(Vector2.ZERO)
	# Bottom bun.
	_draw_bun(Rect2(x + 4.0, bottom_y, w - 8.0, BUN_H), false)
	# Layers bottom -> top, leaving a gap at the live drag slot.
	var gap_slot: int = _drag_slot if _dragging and _drag_moved else -1
	for i: int in rects.size():
		var row: Dictionary = rects[i]
		var rect: Rect2 = row["rect"]
		if gap_slot >= 0:
			if i >= gap_slot:
				rect.position.y -= 12.0
			else:
				rect.position.y += 6.0
		_draw_layer(rect, row["comp"], int(row["index"]) == selected_index)
	# Drag insertion guide.
	if gap_slot >= 0:
		var guide_y: float = _slot_y(rects, gap_slot)
		draw_line(Vector2(x - 10.0, guide_y), Vector2(x + w + 10.0, guide_y), Color("#F5C518"), 3.0)
	# Top bun.
	var top_y: float = bottom_y
	for row: Dictionary in rects:
		top_y = minf(top_y, (row["rect"] as Rect2).position.y)
	_draw_bun(Rect2(x, top_y - BUN_H * 1.35 + 3.0, w, BUN_H * 1.35), true)
	_draw_structure_meter()


func _total_height() -> float:
	var total: float = BUN_H * 2.0 + 6.0
	for comp: RecipeComponent in _stack():
		total += _layer_height(comp) - 3.0
	return total


func _slot_y(rects: Array[Dictionary], slot: int) -> float:
	if rects.is_empty():
		return size.y * 0.5
	if slot >= rects.size():
		return (rects[rects.size() - 1]["rect"] as Rect2).position.y - 14.0
	return (rects[slot]["rect"] as Rect2).end.y + 3.0


func _draw_bun(rect: Rect2, is_top: bool) -> void:
	var fill: Color = Color("#D89A4A") if is_top else Color("#C6883A")
	var edge: Color = Color("#8A5222")
	var radius: float = rect.size.y * (0.85 if is_top else 0.35)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(2)
	if is_top:
		style.corner_radius_top_left = int(radius)
		style.corner_radius_top_right = int(radius)
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
	else:
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = int(radius)
		style.corner_radius_bottom_right = int(radius)
	draw_style_box(style, rect)
	if is_top:
		# Subtle glossy dome highlight.
		draw_set_transform(Vector2(rect.position.x + rect.size.x * 0.36, rect.position.y + rect.size.y * 0.26), -0.12, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, rect.size.x * 0.16, Color(1.0, 0.96, 0.85, 0.28))
		draw_set_transform(Vector2.ZERO)
		# Sesame flecks.
		for i: int in 8:
			var fx: float = rect.position.x + rect.size.x * (0.16 + 0.68 * fposmod(float(i) * 0.618, 1.0))
			var fy: float = rect.position.y + rect.size.y * (0.22 + 0.42 * fposmod(float(i) * 0.382, 1.0))
			draw_set_transform(Vector2(fx, fy), 0.5 - fposmod(float(i) * 0.83, 1.0), Vector2(1.0, 0.6))
			draw_circle(Vector2.ZERO, 5.0, Color("#FBEFC9"))
			draw_set_transform(Vector2.ZERO)
	else:
		draw_rect(Rect2(rect.position.x + 6.0, rect.position.y + 4.0, rect.size.x - 12.0, 4.0), Color(1, 1, 1, 0.22))


func _draw_layer(rect: Rect2, comp: RecipeComponent, is_selected: bool) -> void:
	var ing: IngredientDef = RecipeManager.ingredient(comp.ingredient_id)
	var color: Color = ing.swatch_color if ing != null else Color("#999999")
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("#F5C518") if is_selected else color.darkened(0.45)
	style.set_border_width_all(3 if is_selected else 2)
	style.set_corner_radius_all(int(rect.size.y * 0.4))
	# Patties look wider, sauces narrower — read the stack silhouette.
	var adjusted: Rect2 = rect
	if comp.role == &"patty":
		adjusted = rect.grow_individual(10.0, 0.0, 10.0, 0.0)
	elif comp.role == &"sauce" or comp.role == &"spread":
		adjusted = rect.grow_individual(-16.0, 0.0, -16.0, 0.0)
	elif ing != null and ing.category == &"veg":
		adjusted = rect.grow_individual(6.0, 0.0, 6.0, 0.0)
	if ing != null and ing.category == &"cheese":
		_draw_cheese_layer(adjusted, color, is_selected)
	elif ing != null and ing.category == &"veg" and comp.role == &"layer" and comp.thickness <= 0.55:
		_draw_ruffle_layer(adjusted, color, is_selected)
	else:
		draw_style_box(style, adjusted)
		if comp.role == &"patty":
			draw_rect(Rect2(adjusted.position.x + 8.0, adjusted.position.y + 5.0, adjusted.size.x - 16.0, 4.0), Color(1, 1, 1, 0.12))
			draw_rect(Rect2(adjusted.position.x + 6.0, adjusted.end.y - 8.0, adjusted.size.x - 12.0, 5.0), Color(0, 0, 0, 0.25))
	if ing != null:
		# Color-independent marker glyph on the left edge.
		var glyph_pos: Vector2 = Vector2(adjusted.position.x + 14.0, adjusted.get_center().y)
		_draw_glyph(glyph_pos, 5.0, color.darkened(0.55), ing.marker_shape)
		# Repeated layers show their quantity.
		if comp.quantity > 1.0:
			draw_string(get_theme_default_font(), Vector2(adjusted.end.x - 34.0, adjusted.get_center().y + 5.0),
				"×%d" % int(comp.quantity), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color.darkened(0.6))


## Cheese slice with drippy zig-zag bottom edge (handoff clip-path look).
func _draw_cheese_layer(rect: Rect2, color: Color, is_selected: bool) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(rect.position)
	pts.append(Vector2(rect.end.x, rect.position.y))
	var teeth: int = 6
	for i: int in range(teeth, 0, -1):
		var x0: float = rect.position.x + rect.size.x * float(i) / float(teeth)
		var x1: float = rect.position.x + rect.size.x * (float(i) - 0.5) / float(teeth)
		pts.append(Vector2(x0, rect.end.y - rect.size.y * 0.35))
		pts.append(Vector2(x1, rect.end.y + rect.size.y * 0.28))
	pts.append(Vector2(rect.position.x, rect.end.y - rect.size.y * 0.35))
	draw_colored_polygon(pts, color)
	var outline: Color = Color("#F5C518") if is_selected else color.darkened(0.4)
	var closed: PackedVector2Array = pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, outline, 3.0 if is_selected else 2.0)


## Ruffled leaf layer (lettuce &c.) with a zig-zag bottom edge.
func _draw_ruffle_layer(rect: Rect2, color: Color, is_selected: bool) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(rect.position)
	pts.append(Vector2(rect.end.x, rect.position.y))
	var waves: int = 8
	for i: int in range(waves, 0, -1):
		var x0: float = rect.position.x + rect.size.x * float(i) / float(waves)
		var x1: float = rect.position.x + rect.size.x * (float(i) - 0.5) / float(waves)
		pts.append(Vector2(x0, rect.end.y - rect.size.y * 0.3))
		pts.append(Vector2(x1, rect.end.y + rect.size.y * 0.22))
	pts.append(Vector2(rect.position.x, rect.end.y - rect.size.y * 0.3))
	draw_colored_polygon(pts, color)
	# Alternating stripe shading like the handoff's repeating gradient.
	for i: int in 4:
		var sx: float = rect.position.x + rect.size.x * (0.12 + 0.22 * float(i))
		draw_rect(Rect2(sx, rect.position.y + 2.0, rect.size.x * 0.09, rect.size.y * 0.55), color.darkened(0.12))
	var outline: Color = Color("#F5C518") if is_selected else color.darkened(0.4)
	var closed: PackedVector2Array = pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, outline, 3.0 if is_selected else 2.0)


func _draw_glyph(p: Vector2, r: float, color: Color, shape: StringName) -> void:
	match shape:
		&"ring":
			draw_arc(p, r, 0.0, TAU, 16, color, 2.5)
		&"square":
			draw_rect(Rect2(p - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), color)
		&"triangle":
			var pts: PackedVector2Array = PackedVector2Array()
			for k: int in 3:
				pts.append(p + Vector2.from_angle(-PI / 2.0 + float(k) * TAU / 3.0) * (r + 1.0))
			draw_colored_polygon(pts, color)
		_:
			draw_circle(p, r, color)


func _draw_structure_meter() -> void:
	var meter_h: float = minf(size.y * 0.6, 300.0)
	var meter: Rect2 = Rect2(24.0, (size.y - meter_h) * 0.5, 14.0, meter_h)
	var back: StyleBoxFlat = StyleBoxFlat.new()
	back.bg_color = Color("#E8D3A8")
	back.border_color = Color("#B89A6A")
	back.set_border_width_all(2)
	back.set_corner_radius_all(7)
	draw_style_box(back, meter)
	var value: float = recipe.cached_structure
	var fill_color: Color = Color("#6FB63A")
	var label: String = "Stable"
	if value < 0.45:
		fill_color = Color("#EA4A2F")
		label = "Collapsing"
	elif value < 0.7:
		fill_color = Color("#E0A80E")
		label = "Wobbly"
	var fill_h: float = meter.size.y * clampf(value, 0.02, 1.0)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(6)
	draw_style_box(fill, Rect2(meter.position.x + 2.0, meter.end.y - fill_h + 2.0, meter.size.x - 4.0, fill_h - 4.0))
	draw_string(get_theme_default_font(), Vector2(10.0, meter.position.y - 10.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fill_color.darkened(0.3))


func _gui_input(event: InputEvent) -> void:
	if recipe == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				var hit: int = _layer_at(mb.position)
				if mb.double_click:
					if hit >= 0:
						remove_requested.emit(hit)
					return
				selected_index = hit
				component_selected.emit(hit)
				if hit >= 0:
					_dragging = true
					_drag_moved = false
					_drag_slot = _slot_for_y(mb.position.y)
				queue_redraw()
			elif _dragging:
				_dragging = false
				if _drag_moved:
					_commit_reorder()
				_drag_slot = -1
				queue_redraw()
	elif event is InputEventMouseMotion and _dragging:
		var slot: int = _slot_for_y((event as InputEventMouseMotion).position.y)
		if slot != _drag_slot:
			_drag_slot = slot
			_drag_moved = true
		queue_redraw()
	elif event is InputEventKey and event.pressed:
		_on_key(event)


func _layer_at(p: Vector2) -> int:
	for row: Dictionary in _layer_rects():
		if (row["rect"] as Rect2).grow(4.0).has_point(p):
			return int(row["index"])
	return -1


## Stack slot (0 = just above the bottom bun) for a mouse height.
func _slot_for_y(y: float) -> int:
	var rects: Array[Dictionary] = _layer_rects()
	for i: int in rects.size():
		if y > (rects[i]["rect"] as Rect2).get_center().y:
			return i
	return rects.size()


func _commit_reorder() -> void:
	if selected_index < 0 or selected_index >= recipe.components.size():
		return
	var moved: RecipeComponent = recipe.components[selected_index]
	var order: Array[RecipeComponent] = _stack()
	order.erase(moved)
	var slot: int = clampi(_drag_slot, 0, order.size())
	order.insert(slot, moved)
	for i: int in order.size():
		order[i].stack_index = i
	edit_committed.emit()


func _on_key(event: InputEventKey) -> void:
	if selected_index < 0 or selected_index >= recipe.components.size():
		return
	var comp: RecipeComponent = recipe.components[selected_index]
	match event.keycode:
		KEY_UP, KEY_DOWN:
			var order: Array[RecipeComponent] = _stack()
			var at: int = order.find(comp)
			var to: int = at + (1 if event.keycode == KEY_UP else -1)
			if to < 0 or to >= order.size():
				return
			var other: RecipeComponent = order[to]
			var tmp: int = comp.stack_index
			comp.stack_index = other.stack_index
			other.stack_index = tmp
			accept_event()
			edit_committed.emit()
			queue_redraw()
		KEY_DELETE, KEY_BACKSPACE:
			accept_event()
			remove_requested.emit(selected_index)
