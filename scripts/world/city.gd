extends Node3D
## Attached to the City scene root. Registers all placed buildings into
## CityData at runtime, deriving door + curb anchors from the road graph.


func _ready() -> void:
	_register_buildings()
	PopulationManager.initialize.call_deferred()
	TrafficManager.initialize.call_deferred()
	# Tycoon layer — after buildings and citizens are registered. CompanyManager
	# must connect day_changed before RestaurantManager so daily costs charge
	# before restaurant history rolls over.
	EconomyManager.initialize.call_deferred()
	CompanyManager.initialize.call_deferred()
	get_node("/root/HeadquartersManager").call_deferred("initialize")
	MarketingManager.initialize.call_deferred()
	# Analytics closes daily buckets AFTER CompanyManager's day handler (books
	# closed, ranks snapshotted) but BEFORE RestaurantManager resets rest.today,
	# so it must connect day_changed between the two.
	get_node("/root/AnalyticsManager").call_deferred("initialize")
	RestaurantManager.initialize.call_deferred()
	SupplyManager.initialize.call_deferred()
	DemandManager.initialize.call_deferred()
	DeliveryManager.initialize.call_deferred()
	get_node("/root/StaffManager").call_deferred("initialize")
	get_node("/root/BranchCommandRouter").call_deferred("initialize")
	get_node("/root/ManagementManager").call_deferred("initialize")
	CompanyManager.start_ai.call_deferred()


func _register_buildings() -> void:
	var graph: RoadGraph = CityData.road_graph
	var buildings := get_node("Buildings")
	for body: Node3D in buildings.get_children():
		if not body.has_meta("building_id"):
			continue
		var size: Vector3 = body.get_meta("size")
		# The entrance is usually on a side face, so the bake stores the true front
		# direction; fall back to basis.z for anything without it.
		var front_dir: Vector3 = body.get_meta("front_dir", body.global_transform.basis.z)
		front_dir = front_dir.normalized()
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
