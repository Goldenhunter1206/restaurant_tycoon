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

var kind: String = "civilian"
var state: VState = VState.PARKED
var passenger: Node = null
var goal_desc: String = "parked"

var _path: PackedInt32Array = PackedInt32Array()
var _path_idx: int = 0
var _patrol_rng := RandomNumberGenerator.new()
var _is_patrol: bool = false
var _lod_tick: int = 0
var _stopped_at_light: bool = false


func setup(vehicle_kind: String) -> void:
	kind = vehicle_kind
	name = "Vehicle_%s_%d" % [kind, randi() % 100000]


func set_model(model_path: String) -> void:
	var scene: PackedScene = load(model_path)
	if scene == null:
		return
	var model: Node3D = scene.instantiate()
	model.name = "Model"
	# Cars in this pack face +X at rest; our forward convention is +Z
	# (yaw from atan2(x, z)), so pre-rotate the mesh -90 deg.
	model.rotation_degrees = Vector3(0, -90, 0)
	add_child(model)


func _ready() -> void:
	set_meta("entity", "vehicle")
	monitoring = false


func start_trip(path: PackedInt32Array, citizen: Node) -> void:
	_path = path
	_path_idx = 0
	passenger = citizen
	state = VState.DRIVING
	visible = true
	goal_desc = "driving %s" % String(citizen.goal_desc)
	global_position = CityData.road_graph.lane_points[path[0]]


func begin_patrol(seed_value: int) -> void:
	_patrol_rng.seed = seed_value
	_is_patrol = true
	_next_patrol_leg()


func _next_patrol_leg() -> void:
	var graph: RoadGraph = CityData.road_graph
	var from_node := graph.nearest_lane_node(global_position)
	for attempt in range(8):
		var to_node := absi(_patrol_rng.randi()) % graph.lane_points.size()
		var path := graph.find_lane_path(from_node, to_node)
		if path.size() >= 4:
			_path = path
			_path_idx = 0
			state = VState.DRIVING
			goal_desc = "%s patrol" % kind
			return
	# No route found; try again next evaluation.
	state = VState.PARKED


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
	if check_neighbors and TrafficManager.vehicle_ahead_distance(self) < 5.0:
		return

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
		state = VState.PARKED
		goal_desc = "parked"
		# Pull over: shift to the curb side of the travel direction so the
		# parked car does not block the lane.
		if _path.size() >= 2:
			var prev := graph.lane_points[_path[_path.size() - 2]]
			var heading := (end_pos - prev).normalized()
			var right := Vector3(-heading.z, 0, heading.x)
			global_position = end_pos + right * 1.5
			rotation.y = atan2(heading.x, heading.z)
		var rider := passenger
		passenger = null
		rider.on_car_trip_finished(end_pos)
		return
	if _is_patrol:
		_next_patrol_leg()
	else:
		state = VState.PARKED
		goal_desc = "parked"


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
