class_name Vehicle
extends Area3D
## Kinematic lane-following car. Obeys signals (stops at red stop
## lines), keeps distance to the car ahead, and either serves a citizen
## trip (private car) or patrols endlessly (service/through traffic).

enum VState { PARKED, DRIVING }

const CITY_SPEED: float = 9.0
const MOTORWAY_SPEED: float = 17.0
const LOD_NEAR: float = 90.0
const LOD_MID: float = 220.0
const ROAD_SURFACE_Y: float = 0.319   # asphalt top in world space
const LANE_NODE_Y: float = 0.2        # y the road-graph lane nodes sit at
const CURB_PARK_OFFSET: float = 1.65  # lane-centre -> parked-car centre, toward the kerb

var kind: String = "civilian"
var state: VState = VState.PARKED
var passenger: Node = null
var goal_desc: String = "parked"

var _path: PackedInt32Array = PackedInt32Array()
var _path_idx: int = 0
var _patrol_rng := RandomNumberGenerator.new()
var _is_patrol: bool = false
var _center_getter: Callable = Callable()
var _lod_tick: int = 0
var _stopped_at_light: bool = false
var _blocked_frames: int = 0


func setup(vehicle_kind: String) -> void:
	kind = vehicle_kind
	name = "Vehicle_%s_%d" % [kind, randi() % 100000]


func set_model(model_path: String) -> void:
	var scene: PackedScene = load(model_path)
	if scene == null:
		return
	var model: Node3D = scene.instantiate()
	model.name = "Model"
	# Cars in this pack face -X at rest; our forward convention is +Z
	# (yaw from atan2(x, z)), so pre-rotate the mesh +90 deg.
	model.rotation_degrees = Vector3(0, 90, 0)
	# Ground the wheels on the asphalt: the lane nodes we follow sit at
	# LANE_NODE_Y, the road surface is higher, and the car origin is min_y
	# above the wheels. (Yaw-only rotation above leaves min_y unchanged.)
	model.position.y = ROAD_SURFACE_Y - LANE_NODE_Y - _model_lowest_y(model, Transform3D.IDENTITY)
	add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 350.0
		mesh.visibility_range_end_margin = 15.0


func _model_lowest_y(node: Node, accum: Transform3D) -> float:
	## Lowest mesh point relative to the model origin, so set_model can drop
	## the wheels onto the road surface regardless of the car variant.
	var local := accum
	if node is Node3D:
		local = accum * (node as Node3D).transform
	var lowest := INF
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		lowest = ((local * (node as MeshInstance3D).mesh.get_aabb()) as AABB).position.y
	for c in node.get_children():
		lowest = minf(lowest, _model_lowest_y(c, local))
	return 0.0 if lowest == INF else lowest


func _ready() -> void:
	set_meta("entity", "vehicle")
	monitoring = false
	set_process(false)


func start_trip(path: PackedInt32Array, citizen: Node) -> void:
	_path = path
	_path_idx = 0
	passenger = citizen
	state = VState.DRIVING
	set_process(true)
	visible = true
	goal_desc = "driving %s" % String(citizen.goal_desc)
	# Pull out of the parking spot naturally; only snap when the car is
	# nowhere near the route start (legacy spawn paths).
	var spawn: Vector3 = CityData.road_graph.lane_points[path[0]]
	if global_position.distance_to(spawn) > 10.0:
		global_position = spawn


func park_at(lane_pos: Vector3, heading: Vector3, jitter: float) -> void:
	## Curb-side parking: shift off the lane so the car does not block
	## traffic, with a longitudinal slot so cars at one node don't stack.
	state = VState.PARKED
	goal_desc = "parked"
	set_process(false)
	var right := Vector3(-heading.z, 0, heading.x)
	global_position = lane_pos + right * CURB_PARK_OFFSET + heading * jitter
	rotation.y = atan2(heading.x, heading.z)


func begin_patrol(seed_value: int) -> void:
	_patrol_rng.seed = seed_value
	_is_patrol = true
	_next_patrol_leg()


func begin_local_patrol(seed_value: int, center_getter: Callable) -> void:
	## Ambient traffic: patrol legs stay within a ring around a moving
	## center (the camera), so density concentrates where the player looks.
	_center_getter = center_getter
	begin_patrol(seed_value)


func retarget(pos: Vector3) -> void:
	## Recycle an ambient car that drifted out of range: teleport and
	## start a fresh leg.
	global_position = pos
	_next_patrol_leg()


func _next_patrol_leg() -> void:
	var graph: RoadGraph = CityData.road_graph
	var from_node := graph.nearest_lane_node(global_position)
	var ring := PackedInt32Array()
	if _center_getter.is_valid():
		ring = graph.lane_nodes_near(_center_getter.call(), 60.0, 220.0)
	for attempt in range(8):
		var to_node := -1
		if not ring.is_empty():
			to_node = ring[absi(_patrol_rng.randi()) % ring.size()]
		else:
			to_node = absi(_patrol_rng.randi()) % graph.lane_points.size()
		var path := graph.find_lane_path(from_node, to_node)
		if path.size() >= 4:
			_path = path
			_path_idx = 0
			state = VState.DRIVING
			set_process(true)
			goal_desc = "%s patrol" % kind
			return
	# No route found; try again next evaluation.
	state = VState.PARKED
	set_process(false)


func _process(delta: float) -> void:
	if state != VState.DRIVING:
		return
	_lod_tick += 1
	var cam := get_viewport().get_camera_3d()
	var dist := 1e9
	if cam:
		dist = cam.global_position.distance_to(global_position)
	var step_frames := 1
	if dist > LOD_MID:
		step_frames = 6
	elif dist > LOD_NEAR:
		step_frames = 3
	if _lod_tick % step_frames != 0:
		return
	_advance(delta * float(step_frames) * float(GameClock.speed), dist < LOD_MID)


func _advance(scaled_delta: float, check_neighbors: bool) -> void:
	if _path_idx >= _path.size() - 1:
		_finish_trip()
		return
	var graph: RoadGraph = CityData.road_graph
	var from_id := _path[_path_idx]
	var to_id := _path[_path_idx + 1]
	var target := graph.lane_points[to_id]
	var to_target := target - global_position
	to_target.y = 0
	var dist := to_target.length()

	# Red-light check: the current edge may end on a stop line.
	var edge := graph.lane_edge_between(from_id, to_id)
	if edge >= 0 and graph.lane_enters[edge] >= 0 and dist < 3.0:
		if not TrafficManager.can_vehicle_pass(graph.lane_enters[edge], graph.lane_enter_heading[edge]):
			_stopped_at_light = true
			return
	_stopped_at_light = false

	# Car-following: brake if someone is close ahead (only near camera).
	# A car blocked too long creeps through to break a deadlock (two cars
	# in each other's cone at a junction) — normal queues drain from the
	# front and never reach the timeout.
	if check_neighbors and TrafficManager.vehicle_ahead_distance(self) < 5.0:
		_blocked_frames += 1
		if _blocked_frames < 90:
			return
	else:
		_blocked_frames = 0

	var speed := CITY_SPEED
	if edge >= 0 and graph.lane_kind[edge] == RoadGraph.KIND_MOTORWAY:
		speed = MOTORWAY_SPEED
	var step := speed * scaled_delta
	if step >= dist:
		global_position = target
		_path_idx += 1
	else:
		global_position += to_target.normalized() * step
	if to_target.length_squared() > 0.04:
		var yaw := atan2(to_target.x, to_target.z)
		rotation.y = lerp_angle(rotation.y, yaw, 0.35)


func _finish_trip() -> void:
	if passenger != null:
		var graph: RoadGraph = CityData.road_graph
		var end_pos := graph.lane_points[_path[_path.size() - 1]] if _path.size() > 0 else global_position
		var jitter := float((int(passenger.get("data")["id"]) % 5) - 2) * 2.6
		if _path.size() >= 2:
			var prev := graph.lane_points[_path[_path.size() - 2]]
			var heading := (end_pos - prev).normalized()
			park_at(end_pos, heading, jitter)
		else:
			state = VState.PARKED
			goal_desc = "parked"
			set_process(false)
		var rider := passenger
		passenger = null
		# Hand the rider the car's actual parked spot (curb + slot), not
		# the lane node — they exit beside the car, not mid-lane.
		rider.on_car_trip_finished(global_position)
		return
	if _is_patrol:
		_next_patrol_leg()
	else:
		state = VState.PARKED
		goal_desc = "parked"
		set_process(false)


func inspect_info() -> Dictionary:
	return {
		"kind": "vehicle",
		"vehicle_kind": kind,
		"state": VState.keys()[state],
		"goal": goal_desc,
		"stopped_at_light": _stopped_at_light,
		"passenger": passenger.data["name"] if passenger != null else "none",
		"position": global_position,
	}
