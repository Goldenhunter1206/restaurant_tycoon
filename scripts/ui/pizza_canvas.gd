class_name PizzaCanvas
extends Control
## Top-down pizza assembly canvas. Draws the crust, sauce/cheese coverage and
## topping clusters from a RecipeDef's components (normalized coordinates, so
## recipes are resolution independent) and lets the player place, select and
## drag toppings. Modeled on ShiftTimeline: _draw + _gui_input state machine,
## live preview via queue_redraw, edit_committed on release.
##
## Keyboard alternatives (accessibility): arrows move the selected topping,
## +/- change its spread, Delete removes it.

signal component_selected(index: int)
signal place_requested(norm_pos: Vector2)
signal remove_requested(index: int)
signal edit_committed

const GOLDEN_ANGLE: float = 2.399963
## Max normalized offset from center so toppings stay on the cheese.
const PLACE_LIMIT: float = 0.78

var recipe: RecipeDef = null
var selected_index: int = -1
## Ingredient id armed in the browser; click places it. Empty = select mode.
var armed_ingredient: StringName = &""

var _dragging: bool = false
var _drag_moved: bool = false


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


func _pizza_radius() -> float:
	var scale_mult: float = 1.0
	if recipe != null:
		var base_def: RecipeBaseDef = RecipeManager.base(recipe.base_id)
		if base_def != null:
			scale_mult = base_def.size_scale
	return minf(size.x, size.y) * 0.44 * scale_mult


func _center() -> Vector2:
	return size * 0.5


func _to_px(norm: Vector2) -> Vector2:
	return _center() + (norm - Vector2(0.5, 0.5)) * 2.0 * _pizza_radius()


func _to_norm(px: Vector2) -> Vector2:
	return (px - _center()) / (2.0 * _pizza_radius()) + Vector2(0.5, 0.5)


func _draw() -> void:
	var c: Vector2 = _center()
	var r: float = _pizza_radius()
	var light: Vector2 = Vector2(-r * 0.05, -r * 0.07)  # light from top-left
	# Board shadow.
	draw_circle(c + Vector2(0, r * 0.045), r + 6.0, Color(0.23, 0.13, 0.06, 0.32))
	# Crust: layered rings fake the radial gradient of the handoff.
	draw_circle(c, r, Color("#8A5222"))
	draw_circle(c, r * 0.985, Color("#B87A2E"))
	draw_circle(c, r * 0.945, Color("#D89A4A"))
	draw_circle(c + light, r * 0.90, Color("#E7B15C"))
	if recipe == null:
		return
	# Coverage layers first (sauce below cheese below toppings).
	for i: int in recipe.components.size():
		var comp: RecipeComponent = recipe.components[i]
		if comp.role == &"sauce" or comp.role == &"spread":
			_draw_coverage(i, comp, r, 0.86)
	for i: int in recipe.components.size():
		var comp: RecipeComponent = recipe.components[i]
		if comp.role == &"cheese":
			_draw_coverage(i, comp, r, 0.80)
	for i: int in recipe.components.size():
		var comp: RecipeComponent = recipe.components[i]
		if comp.role != &"sauce" and comp.role != &"spread" and comp.role != &"cheese":
			_draw_topping_cluster(i, comp, r)


func _draw_coverage(index: int, comp: RecipeComponent, r: float, max_frac: float) -> void:
	var ing: IngredientDef = RecipeManager.ingredient(comp.ingredient_id)
	if ing == null:
		return
	var frac: float = clampf(comp.radius, 0.2, 1.0) * max_frac
	var c: Vector2 = _center()
	var light: Vector2 = Vector2(-r * 0.03, -r * 0.045)
	if comp.role == &"cheese":
		# Cheese: warm base, lit center, deterministic mottle spots.
		draw_circle(c, r * frac, Color("#E9C86A"))
		draw_circle(c + light, r * frac * 0.96, Color("#F1D98C"))
		draw_circle(c + light * 2.0, r * frac * 0.8, Color("#F7E5AC"))
		for i: int in 7:
			var angle: float = float(i) * GOLDEN_ANGLE
			var dist: float = r * frac * 0.72 * sqrt((float(i) + 0.5) / 7.0)
			var p: Vector2 = c + Vector2.from_angle(angle) * dist
			draw_circle(p, r * 0.045, Color(1.0, 1.0, 0.94, 0.35) if i % 2 == 0 else Color(0.91, 0.78, 0.42, 0.5))
	else:
		# Sauce/spread: deep base with a lit inner disc.
		var deep: Color = ing.swatch_color.darkened(0.18)
		draw_circle(c, r * frac, deep)
		draw_circle(c + light, r * frac * 0.94, ing.swatch_color)
	if index == selected_index:
		draw_arc(c, r * frac + 3.0, 0.0, TAU, 64, Color("#F5C518"), 3.0)


func _draw_topping_cluster(index: int, comp: RecipeComponent, r: float) -> void:
	var ing: IngredientDef = RecipeManager.ingredient(comp.ingredient_id)
	if ing == null:
		return
	var count: int = maxi(1, roundi(comp.quantity * 3.0))
	var center_px: Vector2 = _to_px(comp.pos)
	var spread_px: float = comp.radius * r
	var sprite_r: float = maxf(7.0, r * 0.055) * comp.scale
	if ing.category == &"meat":
		sprite_r *= 1.35
	for i: int in count:
		var angle: float = float(i) * GOLDEN_ANGLE + comp.rotation
		var dist: float = spread_px * sqrt((float(i) + 0.5) / float(count))
		var p: Vector2 = center_px + Vector2.from_angle(angle) * dist
		# Keep sprites visually on the pie.
		var from_center: Vector2 = p - _center()
		if from_center.length() > r * 0.86:
			p = _center() + from_center.normalized() * r * 0.86
		# Soft contact shadow under each sprite sells the "laid on top" look.
		draw_circle(p + Vector2(1.5, 2.5), sprite_r * 1.02, Color(0.35, 0.18, 0.08, 0.25))
		_draw_marker(p, sprite_r, ing.swatch_color, ing.marker_shape, angle)
	if index == selected_index:
		draw_arc(center_px, maxf(spread_px, sprite_r) + 8.0, 0.0, TAU, 48, Color("#F5C518"), 3.0)


## Shape doubles as the color-independent ingredient marker.
func _draw_marker(p: Vector2, radius: float, color: Color, shape: StringName, rot: float) -> void:
	var outline: Color = color.darkened(0.45)
	match shape:
		&"ring":
			draw_circle(p, radius, outline)
			draw_circle(p, radius * 0.78, color)
			draw_circle(p, radius * 0.38, outline.lightened(0.25))
		&"square":
			var half: float = radius * 0.9
			var pts: PackedVector2Array = PackedVector2Array()
			for corner: Vector2 in [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]:
				pts.append(p + corner.rotated(rot))
			draw_colored_polygon(pts, color)
			pts.append(pts[0])
			draw_polyline(pts, outline, 2.0)
		&"triangle":
			var pts2: PackedVector2Array = PackedVector2Array()
			for k: int in 3:
				pts2.append(p + Vector2.from_angle(rot + float(k) * TAU / 3.0) * radius)
			draw_colored_polygon(pts2, color)
			pts2.append(pts2[0])
			draw_polyline(pts2, outline, 2.0)
		_:
			draw_circle(p, radius, outline)
			draw_circle(p, radius * 0.85, color)
			draw_circle(p + Vector2(-radius * 0.28, -radius * 0.3), radius * 0.28, color.lightened(0.28))


func _gui_input(event: InputEvent) -> void:
	if recipe == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				if mb.double_click:
					if selected_index >= 0:
						remove_requested.emit(selected_index)
					return
				_on_press(mb.position)
			else:
				if _dragging:
					_dragging = false
					if _drag_moved:
						edit_committed.emit()
					queue_redraw()
	elif event is InputEventMouseMotion and _dragging:
		var comp: RecipeComponent = _selected_component()
		if comp != null:
			var norm: Vector2 = _to_norm((event as InputEventMouseMotion).position)
			var offset: Vector2 = (norm - Vector2(0.5, 0.5)).limit_length(PLACE_LIMIT * 0.5)
			comp.pos = Vector2(0.5, 0.5) + offset
			_drag_moved = true
			queue_redraw()
	elif event is InputEventKey and event.pressed:
		_on_key(event)


func _on_press(p: Vector2) -> void:
	var hit: int = _component_at(p)
	if armed_ingredient != &"" and hit < 0:
		var norm: Vector2 = _to_norm(p)
		if (norm - Vector2(0.5, 0.5)).length() <= PLACE_LIMIT * 0.5 + 0.08:
			place_requested.emit(norm)
		return
	selected_index = hit
	component_selected.emit(hit)
	if hit >= 0:
		var comp: RecipeComponent = recipe.components[hit]
		if comp.role != &"sauce" and comp.role != &"spread" and comp.role != &"cheese":
			_dragging = true
			_drag_moved = false
	queue_redraw()


func _component_at(p: Vector2) -> int:
	var r: float = _pizza_radius()
	var best: int = -1
	var best_dist: float = INF
	for i: int in recipe.components.size():
		var comp: RecipeComponent = recipe.components[i]
		if comp.role == &"sauce" or comp.role == &"spread" or comp.role == &"cheese":
			continue
		var dist: float = p.distance_to(_to_px(comp.pos))
		var reach: float = maxf(comp.radius * r, 26.0)
		if dist <= reach and dist < best_dist:
			best_dist = dist
			best = i
	return best


func _on_key(event: InputEventKey) -> void:
	var comp: RecipeComponent = _selected_component()
	if comp == null:
		return
	var step: Vector2 = Vector2.ZERO
	match event.keycode:
		KEY_LEFT: step = Vector2(-0.02, 0)
		KEY_RIGHT: step = Vector2(0.02, 0)
		KEY_UP: step = Vector2(0, -0.02)
		KEY_DOWN: step = Vector2(0, 0.02)
		KEY_EQUAL, KEY_KP_ADD:
			comp.radius = clampf(comp.radius + 0.04, 0.05, 1.0)
		KEY_MINUS, KEY_KP_SUBTRACT:
			comp.radius = clampf(comp.radius - 0.04, 0.05, 1.0)
		KEY_R:
			comp.rotation = wrapf(comp.rotation + 0.35, 0.0, TAU)
		KEY_DELETE, KEY_BACKSPACE:
			remove_requested.emit(selected_index)
			return
		_:
			return
	if step != Vector2.ZERO:
		var offset: Vector2 = (comp.pos + step - Vector2(0.5, 0.5)).limit_length(PLACE_LIMIT * 0.5)
		comp.pos = Vector2(0.5, 0.5) + offset
	accept_event()
	edit_committed.emit()
	queue_redraw()


func _selected_component() -> RecipeComponent:
	if recipe == null or selected_index < 0 or selected_index >= recipe.components.size():
		return null
	return recipe.components[selected_index]
