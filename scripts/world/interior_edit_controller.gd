class_name InteriorEditController
extends Node3D
## In-scene half of the interior editor: converts mouse rays to grid cells,
## renders the ghost preview / grid overlay / selection highlights and applies
## place / move / rotate / sell / duplicate / recolor operations to the DRAFT
## layout owned by the InteriorEditor UI. Nothing here touches the live sim —
## committing goes through RestaurantManager.edit_interior().

signal draft_changed
signal selection_changed(instance_ids: Array[int])
signal hover_changed(text: String)

const GHOST_VALID: Color = Color(0.42, 0.86, 0.35, 0.6)
const GHOST_INVALID: Color = Color(0.94, 0.33, 0.22, 0.6)
const SELECT_COLOR: Color = Color(1.0, 0.78, 0.15, 0.35)
const KITCHEN_COLOR: Color = Color(0.98, 0.6, 0.11, 0.14)
const GRID_COLOR: Color = Color(0.25, 0.16, 0.08, 0.35)

var draft: InteriorLayoutState = null

var _service: InteriorLayoutService = null
var _camera: Camera3D = null
## Catalog def selected for placement; null = selection/move tool.
var _place_def: FurnitureDef = null
var _place_rotation: int = 0
var _place_variant: StringName = &""
var _selected: Array[int] = []
## Instance being dragged with its original cell, or empty.
var _dragging: int = 0
var _drag_from: Vector2i = Vector2i.ZERO
var _hover_cell: Vector2i = Vector2i(-1, -1)

var _ghost: Node3D = null
var _ghost_scene_path: String = ""
var _grid: MeshInstance3D = null
var _kitchen_tint: MeshInstance3D = null
var _select_boxes: Node3D = null
var _scene_cache: Dictionary = {}


func setup(service: InteriorLayoutService, camera: Camera3D, edit_draft: InteriorLayoutState) -> void:
	_service = service
	_camera = camera
	draft = edit_draft
	_build_grid_overlay()
	_select_boxes = Node3D.new()
	_select_boxes.name = "SelectBoxes"
	add_child(_select_boxes)


func set_place_def(def: FurnitureDef, variant: StringName = &"") -> void:
	## Entering placement mode clears any selection.
	_place_def = def
	_place_variant = variant
	_set_selection([] as Array[int])
	_refresh_ghost_model()


func clear_tool() -> void:
	_place_def = null
	_clear_ghost()


func selected_ids() -> Array[int]:
	return _selected.duplicate()


## For UI-side draft mutations (finishes, repairs) that bypass handle_input.
func notify_draft_changed() -> void:
	draft_changed.emit()


# --- Input (forwarded by RestaurantInteriorView while editing) ---------------


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		_on_mouse_moved()
		return _dragging != 0
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			return _on_left_press(mb.shift_pressed)
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			return _on_left_release()
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# Right click cancels placement / selection.
			if _place_def != null:
				clear_tool()
				return true
			if not _selected.is_empty():
				_set_selection([] as Array[int])
				return true
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		return _on_key(event as InputEventKey)
	return false


func _on_key(key: InputEventKey) -> bool:
	match key.keycode:
		KEY_R:
			if _place_def != null:
				_place_rotation = (_place_rotation + 90) % 360
				_update_ghost()
			else:
				_rotate_selected()
			return true
		KEY_DELETE, KEY_BACKSPACE:
			_sell_selected()
			return true
		KEY_D:
			_duplicate_selected()
			return true
		KEY_V:
			_cycle_variant_selected()
			return true
	return false


func _on_left_press(additive: bool) -> bool:
	if _hover_cell.x < 0:
		return false
	if _place_def != null:
		_try_place()
		return true
	# Selection / start of a move drag.
	var hit: PlacedFurnitureState = _item_at(_hover_cell)
	if hit == null:
		if not additive:
			_set_selection([] as Array[int])
		return false
	if additive:
		var ids: Array[int] = _selected.duplicate()
		if ids.has(hit.instance_id):
			ids.erase(hit.instance_id)
		else:
			ids.append(hit.instance_id)
		_set_selection(ids)
	else:
		if not _selected.has(hit.instance_id):
			_set_selection([hit.instance_id] as Array[int])
		_dragging = hit.instance_id
		_drag_from = hit.cell
	return true


func _on_left_release() -> bool:
	if _dragging == 0:
		return false
	_dragging = 0
	return true


func _on_mouse_moved() -> void:
	var cell: Vector2i = _mouse_cell()
	if cell == _hover_cell:
		return
	_hover_cell = cell
	_update_ghost()
	_update_hover_text()
	if _dragging != 0 and cell.x >= 0:
		var item: PlacedFurnitureState = draft.find(_dragging)
		if item != null and item.cell != cell:
			var def: FurnitureDef = _service.def_for(item.def_id)
			var check: Dictionary = _service.validate_place(draft, def, cell, item.rotation, [item.instance_id] as Array[int])
			if bool(check["ok"]):
				item.cell = cell
				draft_changed.emit()
				_refresh_selection_boxes()


# --- Operations ----------------------------------------------------------------


func _try_place() -> void:
	var check: Dictionary = _service.validate_place(draft, _place_def, _hover_cell, _place_rotation)
	if not bool(check["ok"]):
		hover_changed.emit(String(check["reason"]))
		return
	var item: PlacedFurnitureState = draft.add(_place_def.id, _hover_cell, _place_rotation, _place_variant)
	item.durability = _place_def.durability_max
	draft_changed.emit()
	_update_ghost()


func _rotate_selected() -> void:
	var changed: bool = false
	for id: int in _selected:
		var item: PlacedFurnitureState = draft.find(id)
		if item == null:
			continue
		var def: FurnitureDef = _service.def_for(item.def_id)
		var next_rot: int = (item.rotation + 90) % 360
		var check: Dictionary = _service.validate_place(draft, def, item.cell, next_rot, [id] as Array[int])
		if bool(check["ok"]):
			item.rotation = next_rot
			changed = true
	if changed:
		draft_changed.emit()
		_refresh_selection_boxes()


func _sell_selected() -> void:
	if _selected.is_empty():
		return
	for id: int in _selected:
		draft.remove(id)
	_set_selection([] as Array[int])
	draft_changed.emit()


func _duplicate_selected() -> void:
	var new_ids: Array[int] = []
	for id: int in _selected:
		var item: PlacedFurnitureState = draft.find(id)
		if item == null:
			continue
		var def: FurnitureDef = _service.def_for(item.def_id)
		# Probe outward for the nearest free spot.
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2)]:
			var cell: Vector2i = item.cell + offset
			var check: Dictionary = _service.validate_place(draft, def, cell, item.rotation)
			if bool(check["ok"]):
				var copy: PlacedFurnitureState = draft.add(item.def_id, cell, item.rotation, item.variant)
				copy.durability = def.durability_max
				new_ids.append(copy.instance_id)
				break
	if not new_ids.is_empty():
		_set_selection(new_ids)
		draft_changed.emit()


func _cycle_variant_selected() -> void:
	var changed: bool = false
	for id: int in _selected:
		var item: PlacedFurnitureState = draft.find(id)
		if item == null:
			continue
		var def: FurnitureDef = _service.def_for(item.def_id)
		var ids: Array[StringName] = def.variant_ids()
		if ids.size() <= 1:
			continue
		item.variant = ids[(ids.find(item.variant) + 1) % ids.size()]
		changed = true
	if changed:
		draft_changed.emit()


# --- Picking -------------------------------------------------------------------


func _mouse_cell() -> Vector2i:
	if _camera == null:
		return Vector2i(-1, -1)
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = _camera.project_ray_origin(mouse)
	var dir: Vector3 = _camera.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return Vector2i(-1, -1)
	var t: float = -origin.y / dir.y
	if t < 0.0:
		return Vector2i(-1, -1)
	var hit: Vector3 = origin + dir * t
	var cell: Vector2i = InteriorLayoutState.world_to_cell(hit)
	if draft != null and draft.in_bounds(cell):
		return cell
	return Vector2i(-1, -1)


func _item_at(cell: Vector2i) -> PlacedFurnitureState:
	for item: PlacedFurnitureState in draft.placed:
		var def: FurnitureDef = _service.def_for(item.def_id)
		if def == null:
			continue
		if draft.cells_for(item, def).has(cell):
			return item
	return null


# --- Visual helpers --------------------------------------------------------------


func _set_selection(ids: Array[int]) -> void:
	_selected = ids
	_refresh_selection_boxes()
	selection_changed.emit(_selected.duplicate())


func _refresh_selection_boxes() -> void:
	if _select_boxes == null:
		return
	for child: Node in _select_boxes.get_children():
		child.queue_free()
	for id: int in _selected:
		var item: PlacedFurnitureState = draft.find(id)
		if item == null:
			continue
		var def: FurnitureDef = _service.def_for(item.def_id)
		var size: Vector2i = def.footprint_cells(item.rotation)
		var box: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(float(size.x), 0.1, float(size.y))
		box.mesh = mesh
		box.material_override = _flat_material(SELECT_COLOR)
		box.position = InteriorLayoutState.cell_to_world(item.cell, size) + Vector3(0.0, 0.06, 0.0)
		_select_boxes.add_child(box)


func _refresh_ghost_model() -> void:
	_clear_ghost()
	if _place_def == null:
		return
	var path: String = _place_def.scene_for_variant(_place_variant)
	var packed: PackedScene = _scene_cache.get(path)
	if packed == null:
		packed = load(path)
		_scene_cache[path] = packed
	if packed == null:
		return
	_ghost = Node3D.new()
	_ghost.name = "Ghost"
	var mesh: Node3D = packed.instantiate()
	mesh.position.y = _place_def.mount_y
	_ghost.add_child(mesh)
	add_child(_ghost)
	_ghost_scene_path = path
	_update_ghost()


func _update_ghost() -> void:
	if _ghost == null or _place_def == null:
		return
	if _hover_cell.x < 0:
		_ghost.visible = false
		return
	_ghost.visible = true
	var size: Vector2i = _place_def.footprint_cells(_place_rotation)
	_ghost.position = InteriorLayoutState.cell_to_world(_hover_cell, size)
	_ghost.rotation.y = deg_to_rad(float(_place_rotation))
	var check: Dictionary = _service.validate_place(draft, _place_def, _hover_cell, _place_rotation)
	var tint: Color = GHOST_VALID if bool(check["ok"]) else GHOST_INVALID
	_apply_ghost_tint(_ghost, tint)
	hover_changed.emit("" if bool(check["ok"]) else String(check["reason"]))


func _update_hover_text() -> void:
	if _place_def != null or _hover_cell.x < 0:
		return
	var item: PlacedFurnitureState = _item_at(_hover_cell)
	if item == null:
		hover_changed.emit("")
		return
	var def: FurnitureDef = _service.def_for(item.def_id)
	hover_changed.emit("%s · condition %d%%" % [def.display_name, int(item.condition() * 100.0)])


func _apply_ghost_tint(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _flat_material(tint)
	for child: Node in node.get_children():
		_apply_ghost_tint(child, tint)


func _clear_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_scene_path = ""


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _build_grid_overlay() -> void:
	var lines: ImmediateMesh = ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var x0: float = InteriorLayoutState.ORIGIN_X
	var z0: float = InteriorLayoutState.ORIGIN_Z
	var x1: float = x0 + float(draft.grid_cols) * InteriorLayoutState.CELL_SIZE
	var z1: float = z0 + float(draft.grid_rows) * InteriorLayoutState.CELL_SIZE
	for col: int in range(draft.grid_cols + 1):
		var x: float = x0 + float(col) * InteriorLayoutState.CELL_SIZE
		lines.surface_add_vertex(Vector3(x, 0.03, z0))
		lines.surface_add_vertex(Vector3(x, 0.03, z1))
	for row: int in range(draft.grid_rows + 1):
		var z: float = z0 + float(row) * InteriorLayoutState.CELL_SIZE
		lines.surface_add_vertex(Vector3(x0, 0.03, z))
		lines.surface_add_vertex(Vector3(x1, 0.03, z))
	lines.surface_end()
	_grid = MeshInstance3D.new()
	_grid.name = "GridOverlay"
	_grid.mesh = lines
	_grid.material_override = _flat_material(GRID_COLOR)
	add_child(_grid)
	# Kitchen zone tint.
	for rect: Rect2i in draft.kitchen_rects:
		var plane: MeshInstance3D = MeshInstance3D.new()
		var quad: PlaneMesh = PlaneMesh.new()
		quad.size = Vector2(float(rect.size.x), float(rect.size.y))
		plane.mesh = quad
		plane.material_override = _flat_material(KITCHEN_COLOR)
		plane.position = Vector3(
			InteriorLayoutState.ORIGIN_X + (float(rect.position.x) + float(rect.size.x) * 0.5),
			0.02,
			InteriorLayoutState.ORIGIN_Z + (float(rect.position.y) + float(rect.size.y) * 0.5))
		plane.name = "KitchenTint"
		add_child(plane)
