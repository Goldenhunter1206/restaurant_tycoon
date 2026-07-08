extends Node
## Click-to-inspect: raycasts on left click and routes the picked
## citizen / vehicle / building to the DevInspector UI.

signal entity_selected(info: Dictionary, entity: Node)
signal selection_cleared

var selected: Node = null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pick(event.position)


func _pick(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var space := cam.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 2000.0)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		selected = null
		selection_cleared.emit()
		return
	var node: Node = hit["collider"]
	if node.has_meta("entity") and node.has_method("inspect_info"):
		selected = node
		entity_selected.emit(node.inspect_info(), node)
	elif node.has_meta("building_id"):
		selected = node
		entity_selected.emit(_building_info(node), node)
	else:
		selected = null
		selection_cleared.emit()


func current_info() -> Dictionary:
	if selected == null or not is_instance_valid(selected):
		return {}
	if selected.has_method("inspect_info"):
		return selected.inspect_info()
	if selected.has_meta("building_id"):
		return _building_info(selected)
	return {}


func _building_info(node: Node) -> Dictionary:
	var b_id := int(node.get_meta("building_id"))
	var info := CityData.get_building(b_id)
	var residents := []
	var workers := []
	for rec: Dictionary in PopulationManager.citizens_data:
		if int(rec["home_id"]) == b_id:
			residents.append(rec["name"])
		if int(rec["work_id"]) == b_id:
			workers.append(rec["name"])
	return {
		"kind": "building",
		"id": b_id,
		"district": info.get("district", node.get_meta("district")),
		"type": info.get("type", node.get_meta("btype")),
		"family": info.get("family", ""),
		"capacity_residents": info.get("capacity_residents", 0),
		"capacity_workers": info.get("capacity_workers", 0),
		"residents": ", ".join(residents) if residents.size() > 0 else "none",
		"workers": ", ".join(workers) if workers.size() > 0 else "none",
	}
