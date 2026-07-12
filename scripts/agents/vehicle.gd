class_name Vehicle
extends Area3D
## Kinematic lane-following car. Obeys signals (stops at red stop
## lines), keeps distance to the car ahead, and either serves a citizen
## trip (private car) or patrols endlessly (service/through traffic).

enum VState { PARKED, DRIVING }

const CITY_SPEED: float = 9.0
const MOTORWAY_SPEED: float = 17.0
const ACCEL: float = 5.0            # m/s^2 pull-away
const BRAKE: float = 9.0            # m/s^2 max braking rate
const BRAKE_COMFORT: float = 5.5    # m/s^2 anticipated slowdowns (v = sqrt(2*a*d))
const TURN_SPEED: float = 4.0       # cornering speed on curved turn edges
const FOLLOW_GAP: float = 4.0       # bumper gap kept to the car ahead
const STOP_MARGIN: float = 1.2      # stop this short of a red-light node
const CREEP_SPEED: float = 2.0      # deadlock-breaking crawl
const PED_GAP: float = 2.5          # stop this short of a pedestrian ahead
const CORNER_DOT: float = 0.94      # heading kink beyond ~20 deg = slow for corner
const CURVE_SAMPLES: int = 8        # Bezier subdivisions per turn edge
const LOD_NEAR: float = 90.0
const LOD_MID: float = 220.0
const ROAD_SURFACE_Y: float = 0.319   # asphalt top in world space
const LANE_NODE_Y: float = 0.2        # y the road-graph lane nodes sit at
const CURB_PARK_OFFSET: float = 1.65  # lane-centre -> parked-car centre, toward the kerb
const YIELD_CHECK_RANGE: float = 10.0 # start right-of-way checks this close to the stop line
const YIELD_TIMEOUT_FRAMES: int = 180 # stalemate-breaker: go anyway after ~3 s of yielding

var kind: String = "civilian"
var state: VState = VState.PARKED
var passenger: Node = null
var goal_desc: String = "parked"
## Who this car belongs to, for the inspector ("Ana Silva's car", ...).
var owner_desc: String = ""
## Set only for player-owned delivery cars; remains linked while the driver is on foot.
var delivery_driver: Node = null

var _path: PackedInt32Array = PackedInt32Array()
var _path_idx: int = 0
var _patrol_rng := RandomNumberGenerator.new()
var _is_patrol: bool = false
var _center_getter: Callable = Callable()
var _lod_tick: int = 0
var _stopped_at_light: bool = false
var _blocked_frames: int = 0
var _speed: float = 0.0
## Bezier sub-waypoints smoothing the current KIND_TURN edge (empty = straight).
var _sub_points: PackedVector3Array = PackedVector3Array()
var _sub_idx: int = 0
var _curve_for_idx: int = -1
## Congestion bookkeeping: the lane edge we currently occupy (-1 = none)
## and a cooldown (in _advance calls) between mid-trip reroute attempts.
var _current_edge: int = -1
var _reroute_block: int = 0
## Curb parking: the registry slot we occupy while PARKED, and the slot
## reserved for the end of the current trip (-1 = none, legacy parking).
var _park_slot: int = -1
var _slot_pending: int = -1
var _yield_frames: int = 0


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
	tree_exiting.connect(_release_edge)
	tree_exiting.connect(_release_park_slots)


func _release_edge() -> void:
	TrafficManager.edge_left(_current_edge)
	_current_edge = -1


func start_trip(path: PackedInt32Array, citizen: Node, slot: int = -1) -> void:
	_release_park_slots()   # we leave the curb; free the old slot first
	_slot_pending = slot
	_path = path
	_path_idx = 0
	_speed = 0.0
	_blocked_frames = 0
	_curve_for_idx = -1
	_sub_points = PackedVector3Array()
	_sub_idx = 0
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


func park_in_slot(slot: int) -> void:
	## Park in a ParkingRegistry slot already reserved for this car.
	var reg: ParkingRegistry = TrafficManager.parking
	park_at(reg.slot_lane_point[slot], reg.slot_heading[slot], 0.0)
	_park_slot = slot


func _release_park_slots() -> void:
	var reg: ParkingRegistry = TrafficManager.parking
	if reg == null:
		return
	if _park_slot >= 0:
		reg.release(_park_slot, get_instance_id())
		_park_slot = -1
	if _slot_pending >= 0:
		reg.release(_slot_pending, get_instance_id())
		_slot_pending = -1


func park_at(lane_pos: Vector3, heading: Vector3, jitter: float) -> void:
	## Curb-side parking: shift off the lane so the car does not block
	## traffic, with a longitudinal slot so cars at one node don't stack.
	state = VState.PARKED
	goal_desc = "parked"
	set_process(false)
	_speed = 0.0
	_curve_for_idx = -1
	_release_edge()
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
			_curve_for_idx = -1
			_sub_points = PackedVector3Array()
			_sub_idx = 0
			state = VState.DRIVING
			set_process(true)
			goal_desc = "%s patrol" % kind
			return
	# No route found; try again next evaluation.
	state = VState.PARKED
	set_process(false)
	_release_edge()


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
	_advance(delta * float(step_frames) * float(GameClock.speed), dist < LOD_MID, step_frames)


func _advance(scaled_delta: float, check_neighbors: bool, step_frames: int = 1) -> void:
	if _path_idx >= _path.size() - 1:
		_finish_trip()
		return
	var graph: RoadGraph = CityData.road_graph
	var from_id := _path[_path_idx]
	var to_id := _path[_path_idx + 1]
	var node_target := graph.lane_points[to_id]
	var edge := graph.lane_edge_between(from_id, to_id)
	if edge != _current_edge:
		TrafficManager.edge_left(_current_edge)
		TrafficManager.edge_entered(edge)
		_current_edge = edge
		_yield_frames = 0
	if _reroute_block > 0:
		_reroute_block -= 1
	_ensure_turn_curve(graph, edge)
	var dist_to_node := _remaining_edge_distance(node_target)

	# --- target speed: cruise capped by corners, lights, cars ahead --------
	var cruise := CITY_SPEED
	if edge >= 0 and graph.lane_kind[edge] == RoadGraph.KIND_MOTORWAY:
		cruise = MOTORWAY_SPEED
	if _curve_for_idx == _path_idx and not _sub_points.is_empty():
		cruise = minf(cruise, TURN_SPEED)
	elif _path_idx + 2 < _path.size():
		# Approaching a heading kink at the next node: arrive at TURN_SPEED.
		var cur_dir := node_target - graph.lane_points[from_id]
		cur_dir.y = 0.0
		var nxt_dir := graph.lane_points[_path[_path_idx + 2]] - node_target
		nxt_dir.y = 0.0
		if cur_dir.length_squared() > 0.01 and nxt_dir.length_squared() > 0.01 \
				and cur_dir.normalized().dot(nxt_dir.normalized()) < CORNER_DOT:
			cruise = minf(cruise, sqrt(TURN_SPEED * TURN_SPEED + 2.0 * BRAKE_COMFORT * dist_to_node))

	var target_speed := cruise
	# Red light / right-of-way: come to rest STOP_MARGIN short of the
	# stop-line node.
	_stopped_at_light = false
	if edge >= 0 and graph.lane_enters[edge] >= 0:
		var inter := graph.lane_enters[edge]
		var entry_heading := graph.lane_enter_heading[edge]
		var hold := not TrafficManager.can_vehicle_pass(inter, entry_heading)
		if not hold and dist_to_node < YIELD_CHECK_RANGE:
			# Green (or unsignalized): still yield to conflicting traffic
			# before committing to the intersection.
			if TrafficManager.must_yield(self, inter, entry_heading, _turn_sign_ahead(graph)):
				_yield_frames += 1
				hold = _yield_frames < YIELD_TIMEOUT_FRAMES
			else:
				_yield_frames = 0
		if hold:
			var stop_d := maxf(dist_to_node - STOP_MARGIN, 0.0)
			target_speed = minf(target_speed, sqrt(2.0 * BRAKE_COMFORT * stop_d))
			_stopped_at_light = stop_d < 0.5
	# Path end: roll gently to the final node.
	if _path_idx + 2 >= _path.size():
		target_speed = minf(target_speed, sqrt(2.0 * BRAKE_COMFORT * dist_to_node) + 0.8)
	# Reserved curb slot on the final edge: roll to a stop abreast of it,
	# then swing into the slot (never park mid-intersection again).
	if _slot_pending >= 0 and _path_idx + 2 >= _path.size():
		var reg: ParkingRegistry = TrafficManager.parking
		var rem := (reg.slot_lane_point[_slot_pending] - global_position).dot(reg.slot_heading[_slot_pending])
		if rem <= 0.2:
			_finish_trip()
			return
		target_speed = minf(target_speed, sqrt(2.0 * BRAKE_COMFORT * maxf(rem - 0.2, 0.0)) + 0.5)
	# Car ahead: keep FOLLOW_GAP; blocked too long -> creep through to break
	# junction deadlocks (normal queues drain from the front before that).
	if check_neighbors:
		var gap := TrafficManager.vehicle_ahead_distance(self)
		var follow := INF
		if gap < 900.0:
			follow = sqrt(2.0 * BRAKE_COMFORT * maxf(gap - FOLLOW_GAP, 0.0))
		if follow < 0.3:
			_blocked_frames += 1
			# Blocked a while: try a congestion-aware detour before creeping.
			if _blocked_frames == 45 and _reroute_block <= 0:
				_try_reroute(graph)
			if _blocked_frames >= 90:
				follow = CREEP_SPEED
		else:
			_blocked_frames = 0
		target_speed = minf(target_speed, follow)
		# Pedestrians on the roadway ahead: always yield, never creep through.
		var ped_gap := TrafficManager.pedestrian_ahead_distance(self)
		if ped_gap < 900.0:
			target_speed = minf(target_speed, sqrt(2.0 * BRAKE_COMFORT * maxf(ped_gap - PED_GAP, 0.0)))

	var rate := ACCEL if target_speed > _speed else BRAKE
	_speed = move_toward(_speed, target_speed, rate * scaled_delta)
	if _speed <= 0.001:
		return

	# --- move, carrying the step remainder across waypoints ----------------
	var step := _speed * scaled_delta
	var move_dir := global_transform.basis.z
	var guard := 0
	while step > 0.0 and guard < 32:
		guard += 1
		var wp := _next_waypoint(graph)
		var seg := wp - global_position
		seg.y = 0.0
		var d := seg.length()
		if d <= 0.001:
			if not _consume_waypoint(graph):
				return
			continue
		if step < d:
			move_dir = seg / d
			global_position += move_dir * step
			break
		move_dir = seg / d
		global_position = wp
		step -= d
		if not _consume_waypoint(graph):
			return
	if move_dir.length_squared() > 0.01:
		var yaw := atan2(move_dir.x, move_dir.z)
		# Stride-invariant smoothing: same convergence whatever the LOD stride.
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - pow(0.65, float(step_frames)))


func _next_waypoint(graph: RoadGraph) -> Vector3:
	if _curve_for_idx == _path_idx and _sub_idx < _sub_points.size():
		return _sub_points[_sub_idx]
	return graph.lane_points[_path[_path_idx + 1]]


## Advance past the current waypoint. Returns false when the trip ended.
func _consume_waypoint(graph: RoadGraph) -> bool:
	if _curve_for_idx == _path_idx and _sub_idx < _sub_points.size():
		_sub_idx += 1
		return true
	_path_idx += 1
	if _path_idx >= _path.size() - 1:
		_finish_trip()
		return false
	var e := graph.lane_edge_between(_path[_path_idx], _path[_path_idx + 1])
	_ensure_turn_curve(graph, e)
	return true


## Distance left on the current edge (along the curve when one is active).
func _remaining_edge_distance(node_target: Vector3) -> float:
	if _curve_for_idx == _path_idx and _sub_idx < _sub_points.size():
		var d := 0.0
		var prev := global_position
		for k in range(_sub_idx, _sub_points.size()):
			d += Vector2(prev.x - _sub_points[k].x, prev.z - _sub_points[k].z).length()
			prev = _sub_points[k]
		d += Vector2(prev.x - node_target.x, prev.z - node_target.z).length()
		return d
	var seg := node_target - global_position
	seg.y = 0.0
	return seg.length()


## Lazily build a quadratic-Bezier sub-path for the turn edge at _path_idx.
## Control point = XZ intersection of the entry and (reversed) exit rays;
## straight-through intersections (parallel rays) keep the straight edge.
func _ensure_turn_curve(graph: RoadGraph, edge: int) -> void:
	if _curve_for_idx == _path_idx:
		return
	_curve_for_idx = _path_idx
	_sub_points = PackedVector3Array()
	_sub_idx = 0
	if edge < 0 or graph.lane_kind[edge] != RoadGraph.KIND_TURN:
		return
	var p0 := graph.lane_points[_path[_path_idx]]
	var p2 := graph.lane_points[_path[_path_idx + 1]]
	var dir_in := p2 - p0
	if _path_idx > 0:
		dir_in = p0 - graph.lane_points[_path[_path_idx - 1]]
	dir_in.y = 0.0
	var dir_out := p2 - p0
	if _path_idx + 2 < _path.size():
		dir_out = graph.lane_points[_path[_path_idx + 2]] - p2
	dir_out.y = 0.0
	if dir_in.length_squared() < 0.01 or dir_out.length_squared() < 0.01:
		return
	var c := _ray_intersect_xz(p0, dir_in.normalized(), p2, dir_out.normalized())
	if not c.is_finite():
		return
	# Degenerate near-parallel rays put the apex absurdly far out; keep straight.
	if c.distance_to(p0) > 12.0 or c.distance_to(p2) > 12.0:
		return
	for k in range(1, CURVE_SAMPLES):
		var t := float(k) / float(CURVE_SAMPLES)
		_sub_points.append(p0.lerp(c, t).lerp(c.lerp(p2, t), t))


## Intersection of ray (p0, d0) with the line through p2 along d2, in XZ.
## Returns Vector3.INF when parallel or behind the entry point.
func _ray_intersect_xz(p0: Vector3, d0: Vector3, p2: Vector3, d2: Vector3) -> Vector3:
	var denom := d0.x * d2.z - d0.z * d2.x
	if absf(denom) < 0.05:
		return Vector3.INF
	var t := ((p2.x - p0.x) * d2.z - (p2.z - p0.z) * d2.x) / denom
	if t <= 0.1:
		return Vector3.INF
	return p0 + d0 * t


## Signed turn direction at the node we are approaching: > 0.5 = left
## turn (crosses the oncoming lane), < -0.5 = right, ~0 = straight.
func _turn_sign_ahead(graph: RoadGraph) -> float:
	if _path_idx + 2 >= _path.size():
		return 0.0
	var here := graph.lane_points[_path[_path_idx]]
	var node := graph.lane_points[_path[_path_idx + 1]]
	var next := graph.lane_points[_path[_path_idx + 2]]
	var in_dir := node - here
	in_dir.y = 0.0
	var out_dir := next - node
	out_dir.y = 0.0
	if in_dir.length_squared() < 0.01 or out_dir.length_squared() < 0.01:
		return 0.0
	in_dir = in_dir.normalized()
	out_dir = out_dir.normalized()
	return in_dir.z * out_dir.x - in_dir.x * out_dir.z


## Re-path from the next node to the destination through the congestion-
## weighted A*; splice only when the detour actually diverges. A trip
## with a reserved curb slot must still finish on the slot's edge, so
## the detour targets that edge's start and re-appends its end.
func _try_reroute(graph: RoadGraph) -> void:
	_reroute_block = 360
	if _path_idx + 2 >= _path.size():
		return
	var goal := _path[_path.size() - 1]
	var slot_tail := -1
	if _slot_pending >= 0:
		var slot_e: int = TrafficManager.parking.slot_edge[_slot_pending]
		goal = graph.lane_from[slot_e]
		slot_tail = graph.lane_to[slot_e]
	var alt := graph.find_lane_path(_path[_path_idx + 1], goal)
	if alt.size() < 2 or alt[1] == _path[_path_idx + 2]:
		return
	if slot_tail >= 0:
		alt.append(slot_tail)
	var new_path := PackedInt32Array()
	new_path.append(_path[_path_idx])
	new_path.append_array(alt)
	_path = new_path
	_path_idx = 0
	_curve_for_idx = -1
	_sub_points = PackedVector3Array()
	_sub_idx = 0


func _finish_trip() -> void:
	var parked_in_slot := false
	if _slot_pending >= 0 and TrafficManager.parking != null:
		var slot := _slot_pending
		_slot_pending = -1
		park_in_slot(slot)
		parked_in_slot = true
	if passenger != null:
		if not parked_in_slot:
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
		return
	if not parked_in_slot:
		state = VState.PARKED
		goal_desc = "parked"
		set_process(false)


func is_company_delivery() -> bool:
	return is_instance_valid(delivery_driver)


func remaining_route_points() -> PackedVector3Array:
	if is_company_delivery() and delivery_driver is Driver:
		var driver_state: int = int(delivery_driver.get("state"))
		if driver_state not in [Driver.DState.DRIVING_OUT, Driver.DState.DRIVING_BACK]:
			return delivery_driver.remaining_route_points()
	var points: PackedVector3Array = PackedVector3Array()
	points.append(global_position)
	if _path.is_empty():
		return points
	var graph: RoadGraph = CityData.road_graph
	for i: int in range(clampi(_path_idx, 0, _path.size()), _path.size()):
		points.append(graph.lane_points[_path[i]])
	return points


func inspect_info() -> Dictionary:
	var info: Dictionary = {
		"kind": "vehicle",
		"vehicle_kind": kind,
		"owner": owner_desc if not owner_desc.is_empty() else "city fleet",
		"state": VState.keys()[state],
		"goal": goal_desc,
		"stopped_at_light": _stopped_at_light,
		"passenger": passenger.data["name"] if passenger != null else "none",
		"position": global_position,
		"our_delivery_car": is_company_delivery(),
	}
	if is_company_delivery() and delivery_driver.has_method("delivery_snapshot"):
		info.merge(delivery_driver.delivery_snapshot(), true)
	return info
