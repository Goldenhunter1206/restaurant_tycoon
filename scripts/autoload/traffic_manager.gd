extends Node
## Owns signal phase controllers, the vehicle pool (private cars,
## service vehicles, through traffic) and pedestrian crossing gates.

enum Phase { NS_GREEN, NS_YELLOW, ALL_RED_1, EW_GREEN, EW_YELLOW, ALL_RED_2 }

const PHASE_DURATIONS: Array[float] = [9.0, 2.0, 1.0, 9.0, 2.0, 1.0]
const CYCLE_LENGTH: float = 24.0

const N: int = 1
const S: int = 2
const E: int = 4
const W: int = 8

## Ambient traffic targets.
const THROUGH_TRAFFIC_COUNT: int = 8
## Spatial hash cell for car-following lookups; > the 14 m check radius
## so a 3x3 cell scan always covers it.
const GRID_CELL: float = 16.0
const SERVICE_VEHICLES: Array = [
	["police", 2], ["taxi", 4], ["ambulance", 1], ["icecream", 2], ["post", 2],
]

const VEHICLE_DIR: String = "res://Cartoon City Massive Megapack/gLTF 2/Vehicles/"
const KIND_MODELS := {
	"police": ["Police Car/Car_Police_1_A_1.gltf", "Police Car/Car_Police_2_A_1.gltf"],
	"taxi": ["Taxi/Taxi_1.gltf", "Taxi/Taxi_2.gltf", "Taxi/Taxi_3.gltf"],
	"ambulance": ["Other/Ambulance_1_A.gltf", "Other/Ambulance_2_A.gltf"],
	"icecream": ["IceCream Truck/IceTruck_1_A.gltf", "IceCream Truck/IceTruck_1_C.gltf"],
	"post": ["Post Car/PostCar_1_A.gltf", "Post Car/PostCar_1_C.gltf"],
}

var vehicles: Array[Node] = []

var _grid: Dictionary = {}

var _sim_time: float = 0.0
var _vehicle_scene: PackedScene
var _civilian_models: Array[String] = []
var _model_rng := RandomNumberGenerator.new()
var _initialized: bool = false


func _process(delta: float) -> void:
	_sim_time += delta * float(GameClock.speed)
	_rebuild_grid()


func _rebuild_grid() -> void:
	## Car-following only cares about cars ON the road: parked cars sit
	## at the curb, off-lane, and must not trigger phantom braking.
	_grid.clear()
	for car: Vehicle in vehicles:
		if not car.visible or car.state != Vehicle.VState.DRIVING:
			continue
		var pos := car.global_position
		var cell := Vector2i(floori(pos.x / GRID_CELL), floori(pos.z / GRID_CELL))
		if not _grid.has(cell):
			_grid[cell] = []
		(_grid[cell] as Array).append(car)


func initialize() -> void:
	## Called by City.gd (deferred) once the world is registered.
	if _initialized:
		return
	_initialized = true
	_model_rng.seed = 313131
	_vehicle_scene = load("res://scenes/agents/Vehicle.tscn")
	if _vehicle_scene == null:
		push_warning("TrafficManager: Vehicle.tscn missing; traffic disabled")
		return
	_collect_civilian_models()
	_spawn_service_fleet()
	_spawn_through_traffic()


func _collect_civilian_models() -> void:
	for n in range(1, 21):
		var dir := DirAccess.open(VEHICLE_DIR + "Car %d" % n)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".gltf"):
				_civilian_models.append(VEHICLE_DIR + "Car %d/" % n + f)
	if _civilian_models.is_empty():
		_civilian_models.append(VEHICLE_DIR + "Taxi/Taxi_1.gltf")


func model_path_for(kind: String) -> String:
	if KIND_MODELS.has(kind):
		var options: Array = KIND_MODELS[kind]
		return VEHICLE_DIR + options[_model_rng.randi_range(0, options.size() - 1)]
	return _civilian_models[_model_rng.randi_range(0, _civilian_models.size() - 1)]


# --- Signals ----------------------------------------------------------

func phase_for(inter_id: int) -> Phase:
	var offset := float((inter_id * 7) % int(CYCLE_LENGTH))
	var t := fmod(_sim_time + offset, CYCLE_LENGTH)
	var acc := 0.0
	for p in range(PHASE_DURATIONS.size()):
		acc += PHASE_DURATIONS[p]
		if t < acc:
			return p as Phase
	return Phase.NS_GREEN


func can_vehicle_pass(inter_id: int, heading: int) -> bool:
	var graph: RoadGraph = CityData.road_graph
	var rec := graph.get_intersection(inter_id)
	if rec.is_empty() or not rec["signalized"]:
		return true
	var phase := phase_for(inter_id)
	if heading == N or heading == S:
		return phase == Phase.NS_GREEN
	return phase == Phase.EW_GREEN


func can_pedestrian_cross(side_edge: int) -> bool:
	var graph: RoadGraph = CityData.road_graph
	var inter_id := graph.side_crossing[side_edge]
	if inter_id < 0:
		return true
	var rec := graph.get_intersection(inter_id)
	if rec.is_empty() or not rec["signalized"]:
		return true
	var phase := phase_for(inter_id)
	# Crossing a NS road conflicts with NS car traffic -> walk on EW green.
	if graph.side_cross_axis[side_edge] == RoadGraph.AXIS_NS:
		return phase == Phase.EW_GREEN
	return phase == Phase.NS_GREEN


# --- Vehicle pool ------------------------------------------------------

func request_car_trip(citizen: Node, car: Node3D, target: Vector3) -> bool:
	## Routes the citizen's car FROM ITS ACTUAL POSITION (parked at some
	## curb) to the lane node nearest the target. Returns false when no
	## drivable path exists (citizen walks instead).
	if car == null or not is_instance_valid(car):
		return false
	var graph: RoadGraph = CityData.road_graph
	var from_node := graph.nearest_lane_node(car.global_position)
	var to_node := graph.nearest_lane_node(target)
	var path := graph.find_lane_path(from_node, to_node)
	if path.size() < 2:
		return false
	car.start_trip(path, citizen)
	return true


func spawn_citizen_car(citizen: Node) -> Node3D:
	## Spawns the citizen's private car parked at the curb near their
	## home door. Called batched at init for every owner.
	if _vehicle_scene == null:
		_vehicle_scene = load("res://scenes/agents/Vehicle.tscn")
		if _vehicle_scene == null:
			return null
	if _civilian_models.is_empty():
		_collect_civilian_models()   # guard if init order ever changes
	var graph: RoadGraph = CityData.road_graph
	var home := CityData.get_building(int(citizen.get("data")["home_id"]))
	var door: Vector3 = home.get("door_pos", citizen.global_position)
	var node := graph.nearest_lane_node(door)
	var lane_pos := graph.lane_points[node]
	var heading := Vector3.FORWARD
	var out_edges: Array = graph.lane_out_edges(node)
	if not out_edges.is_empty():
		var e: int = out_edges[0]
		heading = (graph.lane_points[graph.lane_to[e]] - lane_pos).normalized()
	var car := _spawn_vehicle("private", lane_pos)
	car.park_at(lane_pos, heading, _park_jitter(citizen))
	citizen.set("owned_vehicle", car)
	return car


func _park_jitter(citizen: Node) -> float:
	## 5 deterministic longitudinal parking slots (~a car length apart)
	## so several cars at one lane node don't stack.
	return float((int(citizen.get("data")["id"]) % 5) - 2) * 2.6


func request_route(vehicle: Node3D, from_pos: Vector3, to_pos: Vector3) -> PackedInt32Array:
	var graph: RoadGraph = CityData.road_graph
	var from_node := graph.nearest_lane_node(from_pos)
	var to_node := graph.nearest_lane_node(to_pos)
	return graph.find_lane_path(from_node, to_node)


func random_lane_point(rng_val: int) -> Vector3:
	var graph: RoadGraph = CityData.road_graph
	var idx := absi(rng_val) % graph.lane_points.size()
	return graph.lane_points[idx]


func _spawn_service_fleet() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 555777
	for svc: Array in SERVICE_VEHICLES:
		for k in range(svc[1]):
			var pos := random_lane_point(rng.randi())
			var car := _spawn_vehicle(svc[0], pos)
			car.begin_patrol(rng.randi())


func _spawn_through_traffic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 888999
	for k in range(THROUGH_TRAFFIC_COUNT):
		var pos := random_lane_point(rng.randi())
		var car := _spawn_vehicle("civilian", pos)
		car.begin_patrol(rng.randi())


func spawn_ambient_car(pos: Vector3) -> Node3D:
	## Pool member for AmbientLife: a civilian car registered in the
	## vehicle list (car-following sees it) but steered locally.
	if _vehicle_scene == null:
		return null
	return _spawn_vehicle("civilian", pos)


func _spawn_vehicle(kind: String, pos: Vector3) -> Node3D:
	var car: Node3D = _vehicle_scene.instantiate()
	car.setup(kind)
	var parent := get_tree().current_scene.get_node("Agents/Vehicles")
	parent.add_child(car)
	car.set_model(model_path_for(kind))
	car.global_position = pos
	vehicles.append(car)
	return car


func vehicle_ahead_distance(vehicle: Node3D) -> float:
	## Distance to the nearest other vehicle roughly ahead of us.
	## Scans only the 3x3 spatial-hash cells around the caller.
	var best := 1e9
	# Vehicles steer with rotation.y = atan2(dir.x, dir.z), so their
	# travel direction is +basis.z (NOT the usual -Z convention).
	var fwd: Vector3 = vehicle.global_transform.basis.z
	var pos := vehicle.global_position
	var center := Vector2i(floori(pos.x / GRID_CELL), floori(pos.z / GRID_CELL))
	for cx in range(center.x - 1, center.x + 2):
		for cz in range(center.y - 1, center.y + 2):
			var bucket: Array = _grid.get(Vector2i(cx, cz), [])
			for other: Node3D in bucket:
				if other == vehicle:
					continue
				var rel: Vector3 = other.global_position - pos
				var dist := rel.length()
				if dist > 14.0 or dist < 0.01:
					continue
				if rel.normalized().dot(fwd) > 0.75:
					best = minf(best, dist)
	return best
