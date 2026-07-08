extends Node3D
## Attached to the City scene root. Registers all placed buildings into
## CityData at runtime, deriving door + curb anchors from the road graph.


func _ready() -> void:
	_register_buildings()
	PopulationManager.initialize.call_deferred()
	TrafficManager.initialize.call_deferred()


func _register_buildings() -> void:
	var graph: RoadGraph = CityData.road_graph
	var buildings := get_node("Buildings")
	for body: Node3D in buildings.get_children():
		if not body.has_meta("building_id"):
			continue
		var size: Vector3 = body.get_meta("size")
		var front_dir := body.global_transform.basis.z.normalized()
		var door_pos: Vector3 = body.global_position + front_dir * (size.z * 0.5 + 1.2)
		var info := {
			"id": int(body.get_meta("building_id")),
			"district": String(body.get_meta("district")),
			"type": String(body.get_meta("btype")),
			"family": String(body.get_meta("family")),
			"position": body.global_position,
			"door_pos": door_pos,
			"side_node": graph.nearest_side_node(door_pos) if graph else -1,
			"lane_node": graph.nearest_lane_node(door_pos) if graph else -1,
			"capacity_residents": _capacity_residents(String(body.get_meta("btype")), size),
			"capacity_workers": _capacity_workers(String(body.get_meta("btype")), size),
			"node_path": body.get_path(),
		}
		CityData.register_building(info)


func _capacity_residents(btype: String, size: Vector3) -> int:
	match btype:
		"home":
			return clampi(int(size.y / 3.0) * 2, 2, 16)
		"office", "shop":
			return 0
		_:
			return 0


func _capacity_workers(btype: String, size: Vector3) -> int:
	match btype:
		"shop":
			return clampi(int(size.x * size.z / 40.0), 2, 12)
		"office":
			return clampi(int(size.y / 3.0) * 3, 4, 40)
		"factory":
			return clampi(int(size.x * size.z / 30.0), 6, 25)
		"civic":
			return 15
		_:
			return 0
