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
## Pedestrian spatial hash: smaller cells, rebuilt every few frames.
const PED_CELL: float = 8.0
const PED_GRID_INTERVAL: int = 4
## Corridor half-widths for ahead checks (car lane is 3.2 m wide; parked
## cars sit 1.65 m off-lane and must not trigger phantom braking).
const CAR_CORRIDOR: float = 1.5
const PED_CORRIDOR: float = 1.9
const CAR_AHEAD_RANGE: float = 14.0
const PED_AHEAD_RANGE: float = 12.0
## Unsignalized crossings: a car this close and heading at the zebra
## makes waiting pedestrians hold the kerb.
const CROSSING_CAR_RANGE: float = 13.0
## Congestion-aware routing: per-edge occupancy scales the A* weight of
## the edge's end node every refresh, so new routes flow around jams.
const CONGESTION_REFRESH: float = 2.0
const CONGESTION_LOAD_FACTOR: float = 10.0
const CONGESTION_MAX_SCALE: float = 8.0
## Turn-yield rules: how far out approaching conflict traffic matters.
const YIELD_ONCOMING_RANGE: float = 17.0
const YIELD_CROSS_RANGE: float = 13.0
const YIELD_BOX_RADIUS: float = 6.0
## Opposite / right-hand-priority heading lookups (N=1 S=2 E=4 W=8).
const OPPOSITE_HEADING := {1: 2, 2: 1, 4: 8, 8: 4}
const RIGHT_OF_HEADING := {1: 8, 2: 4, 4: 1, 8: 2}

const SERVICE_VEHICLES: Array = [
	["police", 2], ["taxi", 4], ["ambulance", 1], ["icecream", 2], ["post", 2],
]

const VEHICLE_DIR: String = "res://Cartoon City Massive Megapack/gLTF/Vehicles/"
const KIND_MODELS := {
	"police": ["Police Car/Car_Police_1_A_1.gltf", "Police Car/Car_Police_2_A_1.gltf"],
	"taxi": ["Taxi/Taxi_1.gltf", "Taxi/Taxi_2.gltf", "Taxi/Taxi_3.gltf"],
	"ambulance": ["Other/Ambulance_1_A.gltf", "Other/Ambulance_2_A.gltf"],
	"icecream": ["IceCream Truck/IceTruck_1_A.gltf", "IceCream Truck/IceTruck_1_C.gltf"],
	"post": ["Post Car/PostCar_1_A.gltf", "Post Car/PostCar_1_C.gltf"],
	"supply": ["Post Car/PostCar_1_A.gltf", "IceCream Truck/IceTruck_1_A.gltf"],
}

var vehicles: Array[Node] = []
## Walking agents (citizens, ambient walkers, on-foot drivers). The grid
## build filters to visible + processing, so idle/driving states drop out.
var pedestrians: Array[Node3D] = []

var _grid: Dictionary = {}
var _ped_grid: Dictionary = {}
var _ped_grid_tick: int = 0

var _edge_load: PackedInt32Array = PackedInt32Array()
var _edge_len: PackedFloat32Array = PackedFloat32Array()
var _weighted_nodes: PackedInt32Array = PackedInt32Array()
var _congestion_timer: float = 0.0

## Curb parking slots (built from the lane graph at initialize()).
var parking: ParkingRegistry = null

var _sim_time: float = 0.0
var _vehicle_scene: PackedScene
var _civilian_models: Array[String] = []
var _model_rng := RandomNumberGenerator.new()
var _initialized: bool = false


func _process(delta: float) -> void:
	_sim_time += delta * float(GameClock.speed)
	_rebuild_grid()
	_ped_grid_tick += 1
	if _ped_grid_tick % PED_GRID_INTERVAL == 0:
		_rebuild_ped_grid()
	_congestion_timer += delta * float(GameClock.speed)
	if _congestion_timer >= CONGESTION_REFRESH:
		_congestion_timer = 0.0
		_refresh_congestion_weights()


func _rebuild_grid() -> void:
	## Includes parked cars: the corridor test in vehicle_ahead_distance
	## keeps curb-parked cars (1.65 m off-lane) from causing phantom
	## braking, while a car pulling out still sees one dead ahead.
	_grid.clear()
	for car: Vehicle in vehicles:
		if not car.visible:
			continue
		var pos := car.global_position
		var cell := Vector2i(floori(pos.x / GRID_CELL), floori(pos.z / GRID_CELL))
		if not _grid.has(cell):
			_grid[cell] = []
		(_grid[cell] as Array).append(car)


func register_pedestrian(p: Node3D) -> void:
	if not pedestrians.has(p):
		pedestrians.append(p)


func unregister_pedestrian(p: Node3D) -> void:
	pedestrians.erase(p)


func _rebuild_ped_grid() -> void:
	_ped_grid.clear()
	var stale: Array = []
	for p: Node3D in pedestrians:
		if not is_instance_valid(p):
			stale.append(p)
			continue
		if not p.visible or not p.is_processing():
			continue
		var pos := p.global_position
		var cell := Vector2i(floori(pos.x / PED_CELL), floori(pos.z / PED_CELL))
		if not _ped_grid.has(cell):
			_ped_grid[cell] = []
		(_ped_grid[cell] as Array).append(p)
	for p: Node3D in stale:
		pedestrians.erase(p)


func peds_near(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var span := int(ceilf(radius / PED_CELL))
	var center := Vector2i(floori(pos.x / PED_CELL), floori(pos.z / PED_CELL))
	for cx in range(center.x - span, center.x + span + 1):
		for cz in range(center.y - span, center.y + span + 1):
			for p: Node3D in _ped_grid.get(Vector2i(cx, cz), []):
				if p.global_position.distance_to(pos) <= radius:
					out.append(p)
	return out


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
	_init_congestion()
	_init_parking()
	_spawn_service_fleet()
	_spawn_through_traffic()


func _init_congestion() -> void:
	var graph: RoadGraph = CityData.road_graph
	if graph == null:
		return
	var edges := graph.lane_from.size()
	_edge_load.resize(edges)
	_edge_load.fill(0)
	_edge_len.resize(edges)
	for e in range(edges):
		_edge_len[e] = graph.lane_points[graph.lane_from[e]].distance_to(
			graph.lane_points[graph.lane_to[e]])


func _init_parking() -> void:
	var graph: RoadGraph = CityData.road_graph
	if graph == null:
		return
	parking = ParkingRegistry.new()
	parking.build(graph)
	# The decorative ParkedCarPlacer fleet occupies real curb space:
	# mark those slots taken so dynamic cars never park inside them.
	var scene := get_tree().current_scene
	if scene == null:
		return
	var grp := scene.find_child("ParkedCars", true, false)
	if grp == null:
		return
	for child in grp.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		for i in range(mmi.multimesh.instance_count):
			var xf := mmi.global_transform * mmi.multimesh.get_instance_transform(i)
			parking.block_static_at(xf.origin)


func edge_entered(edge: int) -> void:
	if edge >= 0 and edge < _edge_load.size():
		_edge_load[edge] += 1


func edge_left(edge: int) -> void:
	if edge >= 0 and edge < _edge_load.size() and _edge_load[edge] > 0:
		_edge_load[edge] -= 1


func _refresh_congestion_weights() -> void:
	## Weight scale multiplies the cost of edges ENTERING a node, which
	## matches per-edge congestion semantics. Main-thread-only mutation
	## between queries; in-flight paths are plain arrays and unaffected.
	if _edge_load.is_empty():
		return
	var graph: RoadGraph = CityData.road_graph
	var astar := graph.lane_astar()
	var node_scale: Dictionary = {}
	for e in range(_edge_load.size()):
		var load := _edge_load[e]
		if load <= 0:
			continue
		var n := graph.lane_to[e]
		node_scale[n] = float(node_scale.get(n, 0.0)) \
			+ float(load) * CONGESTION_LOAD_FACTOR / maxf(_edge_len[e], 4.0)
	for n in _weighted_nodes:
		if not node_scale.has(n):
			astar.set_point_weight_scale(n, 1.0)
	var new_weighted := PackedInt32Array()
	for n: int in node_scale:
		astar.set_point_weight_scale(n, clampf(1.0 + float(node_scale[n]), 1.0, CONGESTION_MAX_SCALE))
		new_weighted.append(n)
	_weighted_nodes = new_weighted


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
	# Preferred: route to a reserved legal curb slot near the target and
	# stop there mid-edge (the passenger walks the final leg anyway).
	if parking != null:
		var slot := parking.reserve_near(target, 60.0, car.get_instance_id())
		if slot >= 0:
			var e := parking.slot_edge[slot]
			var path := graph.find_lane_path(from_node, graph.lane_from[e])
			if path.size() >= 1:
				path.append(graph.lane_to[e])
				car.start_trip(path, citizen, slot)
				return true
			parking.release(slot, car.get_instance_id())
	# Fallback: legacy nearest-node trip (no free slot in range).
	var to_node := graph.nearest_lane_node(target)
	var legacy_path := graph.find_lane_path(from_node, to_node)
	if legacy_path.size() < 2:
		return false
	car.start_trip(legacy_path, citizen)
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
	if not park_vehicle_near(car, door):
		car.park_at(lane_pos, heading, _park_jitter(citizen))
	car.owner_desc = "%s's car" % String(citizen.get("data")["name"])
	citizen.set("owned_vehicle", car)
	return car


func _park_jitter(citizen: Node) -> float:
	## 5 deterministic longitudinal parking slots (~a car length apart)
	## so several cars at one lane node don't stack.
	return float((int(citizen.get("data")["id"]) % 5) - 2) * 2.6


func park_vehicle_near(car: Node3D, target: Vector3) -> bool:
	## Park an idle car in the nearest free legal curb slot around target.
	## Returns false when no slot is free in range (caller falls back).
	if parking == null or car == null or not is_instance_valid(car):
		return false
	var slot := parking.reserve_near(target, 45.0, car.get_instance_id())
	if slot < 0:
		return false
	car.park_in_slot(slot)
	return true


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


func cars_near(pos: Vector3, radius: float) -> Array:
	## Vehicles within radius of pos (spatial-hash scan, includes parked).
	var out: Array = []
	var span := int(ceilf(radius / GRID_CELL))
	var center := Vector2i(floori(pos.x / GRID_CELL), floori(pos.z / GRID_CELL))
	for cx in range(center.x - span, center.x + span + 1):
		for cz in range(center.y - span, center.y + span + 1):
			for car: Node3D in _grid.get(Vector2i(cx, cz), []):
				var rel := car.global_position - pos
				rel.y = 0.0
				if rel.length() <= radius:
					out.append(car)
	return out


func heading_bit_of(dir: Vector3) -> int:
	## Dominant world axis of a travel direction -> heading bit.
	if absf(dir.z) >= absf(dir.x):
		return N if dir.z < 0.0 else S
	return E if dir.x > 0.0 else W


func must_yield(vehicle: Node3D, inter_id: int, entry_heading: int, turn_sign: float) -> bool:
	## Right-of-way at the stop line. turn_sign > 0.5 means a left turn
	## (crosses the oncoming lane). Signalized: left turns yield to
	## oncoming green traffic. Unsignalized: priority-to-the-right plus
	## the same left-turn rule. Everyone waits while a conflicting car is
	## still inside the intersection box.
	var graph: RoadGraph = CityData.road_graph
	var rec := graph.get_intersection(inter_id)
	if rec.is_empty():
		return false
	var center: Vector3 = rec["pos"]
	var signalized: bool = rec["signalized"]
	var opposite: int = OPPOSITE_HEADING.get(entry_heading, 0)
	var right_priority: int = RIGHT_OF_HEADING.get(entry_heading, 0)
	for other: Node3D in cars_near(center, YIELD_ONCOMING_RANGE):
		if other == vehicle or int(other.get("state")) != Vehicle.VState.DRIVING:
			continue
		var fwd: Vector3 = other.global_transform.basis.z
		var hb := heading_bit_of(fwd)
		if hb == entry_heading:
			continue   # same approach: queue handled by car-following
		var rel := center - other.global_position
		rel.y = 0.0
		var d := rel.length()
		var moving: bool = float(other.get("_speed")) > 0.6
		# Conflicting car still inside the box: hold the stop line. A car
		# merely waiting at its own stop line (stopped, near the box rim)
		# does not count — only movers or cars dead-centre.
		if d < YIELD_BOX_RADIUS and (moving or d < 3.5):
			return true
		var approaching: bool = d > 0.01 and fwd.dot(rel / d) > 0.6
		if not (moving and approaching):
			continue
		if turn_sign > 0.5 and hb == opposite and d < YIELD_ONCOMING_RANGE:
			return true   # left turn across an approaching oncoming car
		if not signalized and hb == right_priority and d < YIELD_CROSS_RANGE:
			return true   # unsignalized: yield to the right
	return false


func vehicle_ahead_distance(vehicle: Node3D) -> float:
	## Forward distance to the nearest vehicle inside our lane corridor.
	## The corridor test (vs the old forward cone) ignores oncoming cars
	## in the opposite lane (3.2 m lateral) and curb-parked cars (1.65 m).
	var best := 1e9
	# Vehicles steer with rotation.y = atan2(dir.x, dir.z), so their
	# travel direction is +basis.z (NOT the usual -Z convention).
	var fwd: Vector3 = vehicle.global_transform.basis.z
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var pos := vehicle.global_position
	var center := Vector2i(floori(pos.x / GRID_CELL), floori(pos.z / GRID_CELL))
	for cx in range(center.x - 1, center.x + 2):
		for cz in range(center.y - 1, center.y + 2):
			var bucket: Array = _grid.get(Vector2i(cx, cz), [])
			for other: Node3D in bucket:
				if other == vehicle:
					continue
				var rel: Vector3 = other.global_position - pos
				rel.y = 0.0
				var s := rel.dot(fwd)
				if s <= 0.3 or s >= CAR_AHEAD_RANGE:
					continue
				if absf(rel.dot(right)) > CAR_CORRIDOR:
					continue
				best = minf(best, s)
	return best


func pedestrian_ahead_distance(vehicle: Node3D) -> float:
	## Forward distance to the nearest pedestrian inside the vehicle's
	## corridor. Sidewalk walkers (>= 4 m lateral) never register; anyone
	## on a crossing or jaywalking in the lane does.
	var best := 1e9
	var fwd: Vector3 = vehicle.global_transform.basis.z
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var pos := vehicle.global_position
	var span := int(ceilf(PED_AHEAD_RANGE / PED_CELL))
	var center := Vector2i(floori(pos.x / PED_CELL), floori(pos.z / PED_CELL))
	for cx in range(center.x - span, center.x + span + 1):
		for cz in range(center.y - span, center.y + span + 1):
			for p: Node3D in _ped_grid.get(Vector2i(cx, cz), []):
				var rel: Vector3 = p.global_position - pos
				rel.y = 0.0
				var s := rel.dot(fwd)
				if s <= 0.0 or s >= PED_AHEAD_RANGE:
					continue
				if absf(rel.dot(right)) > PED_CORRIDOR:
					continue
				best = minf(best, s)
	return best


func is_crossing_safe(side_edge: int) -> bool:
	## Unsignalized crossings only: pedestrians hold the kerb while a
	## moving car is close and heading at the zebra. Signalized crossings
	## are already gated by the walk phase.
	var graph: RoadGraph = CityData.road_graph
	var inter_id := graph.side_crossing[side_edge]
	if inter_id < 0:
		return true
	var rec := graph.get_intersection(inter_id)
	if not rec.is_empty() and rec["signalized"]:
		return true
	var mid := (graph.side_points[graph.side_from[side_edge]]
		+ graph.side_points[graph.side_to[side_edge]]) * 0.5
	mid.y = 0.0
	var center := Vector2i(floori(mid.x / GRID_CELL), floori(mid.z / GRID_CELL))
	for cx in range(center.x - 1, center.x + 2):
		for cz in range(center.y - 1, center.y + 2):
			for car: Vehicle in _grid.get(Vector2i(cx, cz), []):
				if car.state != Vehicle.VState.DRIVING:
					continue
				var rel := mid - car.global_position
				rel.y = 0.0
				var d := rel.length()
				if d > CROSSING_CAR_RANGE or d < 0.01:
					continue
				if car.global_transform.basis.z.dot(rel / d) > 0.7 and float(car.get("_speed")) > 0.5:
					return false
	return true
