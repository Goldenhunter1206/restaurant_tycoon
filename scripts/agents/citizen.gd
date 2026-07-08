class_name Citizen
extends Area3D
## One simulated person. Schedule FSM driven by GameClock; movement is
## kinematic waypoint-following on the sidewalk graph (walking) or
## delegated to a Vehicle (driving). LOD: far agents move analytically.

enum CState { SLEEP, COMMUTE_OUT, WORK, LEISURE_GO, LEISURE, COMMUTE_HOME, DRIVING }

const WALK_SPEED: float = 1.7
const LOD_NEAR: float = 70.0
const LOD_MID: float = 180.0
const LUNCH_HOURS: float = 0.7
## Lunch targets further than this from the workplace are swapped for a
## nearby street corner so the break stays walkable.
const LUNCH_TARGET_MAX_DIST: float = 120.0
## Trip planning: drive only when the trip is long enough to be worth the
## walk-to-car + parking overhead AND the car is near enough to fetch.
const CAR_MIN_TRIP_DIST: float = 90.0
const CAR_NEARBY_DIST: float = 70.0
const CAR_BOARD_SKIP_DIST: float = 6.0

var data: Dictionary = {}
var state: CState = CState.SLEEP
var goal_desc: String = "asleep at home"
var owned_vehicle: Node3D = null
var _walk_anim: String = "Walk_A"
var _idle_anim: String = "Idle_A"

var _path: PackedInt32Array = PackedInt32Array()
var _path_idx: int = 0
var _edge_progress: float = 0.0
var _target_pos: Vector3
var _leisure_spot: Dictionary = {}
var _vehicle: Node3D = null
var _lod_tick: int = 0
var _model: Node3D
var _anim: AnimationPlayer
var _anim_lod_paused: bool = false
var _lunch_day: int = -1
var _lunching: bool = false
var _stroll_wait: float = 0.0
var _leisure_rng: RandomNumberGenerator = null
## Multi-leg trip: a queue of {kind: "walk"|"drive", target: Vector3}.
var _trip_plan: Array[Dictionary] = []
var _trip_purpose: String = ""   # "work" | "home" | "leisure"


func setup(record: Dictionary) -> void:
	data = record
	name = "Citizen_%d" % record["id"]
	_walk_anim = ["Walk_A", "Walk_B", "Walk_C"][int(record["id"]) % 3]
	_idle_anim = ["Idle_A", "Idle_B", "LookingAround"][int(record["id"]) % 3]


func set_model(model_path: String, anim_lib: AnimationLibrary) -> void:
	## Called after add_child: attaches the character mesh and the shared
	## animation library (all characters share one armature).
	var scene: PackedScene = load(model_path)
	if scene == null:
		return
	var model: Node3D = scene.instantiate()
	model.name = "Model"
	add_child(model)
	_model = model
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visibility_range_end = 350.0
		mesh.visibility_range_end_margin = 15.0
	if _anim and anim_lib:
		if not _anim.has_animation_library(""):
			_anim.add_animation_library("", anim_lib)
		_anim.root_node = NodePath("../Model")
		_set_anim("idle")


func _ready() -> void:
	set_meta("entity", "citizen")
	monitoring = false
	GameClock.hour_changed.connect(_on_hour)
	GameClock.minute_ticked.connect(_on_minute)
	_model = get_node_or_null("Model")
	_anim = get_node_or_null("AnimationPlayer")
	var home := CityData.get_building(int(data["home_id"]))
	if home.is_empty():
		global_position = Vector3.ZERO
	else:
		global_position = home["door_pos"]
	_enter_sleep()


func _process(delta: float) -> void:
	if state in [CState.SLEEP, CState.WORK, CState.DRIVING]:
		return
	# Moving states + leisure strolling: walk with distance LOD.
	_lod_tick += 1
	var cam := get_viewport().get_camera_3d()
	var dist := 1e9
	if cam:
		dist = cam.global_position.distance_to(global_position)
	# Animation LOD: skinned pose updates dominate scaling cost, so far
	# walkers freeze their AnimationPlayer and resume on approach.
	var anim_far := dist > LOD_MID
	if anim_far != _anim_lod_paused:
		_anim_lod_paused = anim_far
		if _anim:
			if anim_far:
				_anim.pause()
			elif _anim.current_animation != "":
				_anim.play()
	if state == CState.LEISURE and _path_idx >= _path.size():
		# Between strolls: idle at the spot, then wander a nearby block.
		_stroll_wait -= delta * float(GameClock.speed)
		if _stroll_wait <= 0.0:
			_begin_stroll()
		return
	var step_frames := 1
	if dist > LOD_MID:
		step_frames = 6
	elif dist > LOD_NEAR:
		step_frames = 3
	if _lod_tick % step_frames != 0:
		return
	_advance_walk(delta * float(step_frames) * float(GameClock.speed))


func _advance_walk(scaled_delta: float) -> void:
	if _path_idx >= _path.size():
		_arrive()
		return
	var graph: RoadGraph = CityData.road_graph
	var target := graph.side_points[_path[_path_idx]]
	# Crossing gate: wait for walk phase at signalized crossings.
	if _path_idx > 0:
		var edge := _crossing_edge(_path[_path_idx - 1], _path[_path_idx])
		if edge >= 0 and not TrafficManager.can_pedestrian_cross(edge):
			_set_anim("idle")
			return
	_set_anim("walk")
	var to_target := target - global_position
	to_target.y = 0
	var dist := to_target.length()
	var step := WALK_SPEED * scaled_delta
	if step >= dist:
		global_position = Vector3(target.x, target.y, target.z)
		_path_idx += 1
	else:
		global_position += to_target.normalized() * step
		if to_target.length_squared() > 0.01:
			var yaw := atan2(to_target.x, to_target.z)
			rotation.y = lerp_angle(rotation.y, yaw, 0.3)


func _crossing_edge(from_id: int, to_id: int) -> int:
	var graph: RoadGraph = CityData.road_graph
	for e: int in graph.side_edges(from_id):
		if graph.side_crossing[e] >= 0 and graph.side_other_end(e, from_id) == to_id:
			return e
	return -1


func _arrive() -> void:
	match state:
		CState.COMMUTE_OUT, CState.COMMUTE_HOME, CState.LEISURE_GO:
			# A walk leg finished: board the car, or reach the destination.
			_advance_trip_leg()
		CState.LEISURE:
			# Stroll leg finished: idle a while, then wander again.
			_set_anim("idle")
			_stroll_wait = _stroll_rng().randf_range(15.0, 45.0)
		_:
			pass


func _on_hour(_day: int, _hour: int) -> void:
	_evaluate_schedule()


func _on_minute(_day: int, _hour: int, _minute: int) -> void:
	# Only cheap checks per minute; the hour handler does the real work.
	if state == CState.SLEEP or state == CState.WORK or state == CState.LEISURE:
		_evaluate_schedule()


func _evaluate_schedule() -> void:
	var h: float = GameClock.game_hours
	var wake: float = data["wake_hour"]
	var work_start: float = data["work_start"]
	var work_end: float = fmod(work_start + data["work_hours"], 24.0)
	var home_h: float = data["home_hour"]
	var employed: bool = data["job_type"] != "none"
	match state:
		CState.SLEEP:
			if GameClock.is_between(wake, work_start) and employed:
				_start_commute_out()
			elif not employed and GameClock.is_between(wake + 3.0, home_h):
				_start_leisure()
		CState.WORK:
			if not GameClock.is_between(work_start, work_end):
				_start_leisure()
			elif int(data["work_id"]) >= 0 and _lunch_day != GameClock.day:
				var lunch := _lunch_window()
				if GameClock.is_between(lunch.x, lunch.y):
					_start_lunch()
		CState.LEISURE:
			if _lunching:
				var lunch := _lunch_window()
				if not GameClock.is_between(lunch.x, lunch.y):
					_end_lunch()
			elif GameClock.is_between(home_h, wake):
				_start_commute_home()
		_:
			pass


func _start_commute_out() -> void:
	_plan_trip(_work_target_pos(), "work")


func _enter_work() -> void:
	state = CState.WORK
	goal_desc = "working (%s)" % String(data["job_type"])
	visible = false
	_set_sim_active(false)


func _start_leisure() -> void:
	_lunching = false
	var spots: Array = data["leisure_spots"]
	if spots.is_empty():
		_start_commute_home()
		return
	# Seeded per-citizen stream (the car decision depends on the pick, so
	# it must be deterministic, not the global randi()).
	_leisure_spot = spots[_stroll_rng().randi_range(0, spots.size() - 1)]
	_plan_trip(_leisure_spot["pos"], "leisure")


func _start_commute_home() -> void:
	_lunching = false
	var home := CityData.get_building(int(data["home_id"]))
	_plan_trip(home.get("door_pos", global_position), "home")


func _enter_sleep() -> void:
	state = CState.SLEEP
	goal_desc = "asleep at home"
	visible = false
	var home := CityData.get_building(int(data["home_id"]))
	if not home.is_empty():
		global_position = home["door_pos"]
	_set_sim_active(false)


func _work_target_pos() -> Vector3:
	var wp := CityData.get_building(int(data["work_id"]))
	if wp.is_empty():
		return global_position
	return wp["door_pos"]


func _walk_to(target: Vector3) -> void:
	var graph: RoadGraph = CityData.road_graph
	var from_node := graph.nearest_side_node(global_position)
	var to_node := graph.nearest_side_node(target)
	_path = graph.find_side_path(from_node, to_node)
	_path_idx = 0
	_target_pos = target
	if _path.is_empty():
		# Unreachable: snap to destination (keeps the schedule consistent).
		global_position = target


func on_car_trip_finished(at_pos: Vector3) -> void:
	global_position = at_pos
	_vehicle = null
	visible = true
	_set_sim_active(true)
	_advance_trip_leg()   # runs the queued final walk leg to the door


# --- Trip planning (walk / drive multi-leg) ---------------------------

func _plan_trip(target: Vector3, purpose: String, force_walk: bool = false) -> void:
	## Builds the leg queue for a trip and starts the first leg. Driving
	## is: walk to the car -> drive -> walk the final leg to the door.
	_trip_purpose = purpose
	_trip_plan.clear()
	if not force_walk and _should_take_car(target, purpose):
		if global_position.distance_to(owned_vehicle.global_position) > CAR_BOARD_SKIP_DIST:
			_trip_plan.append({"kind": "walk", "target": owned_vehicle.global_position})
		_trip_plan.append({"kind": "drive", "target": target})
		_trip_plan.append({"kind": "walk", "target": target})
	else:
		_trip_plan.append({"kind": "walk", "target": target})
	_advance_trip_leg()


func _should_take_car(target: Vector3, purpose: String) -> bool:
	# Home trips ALWAYS collect the car (unless it's already home) so it
	# ends the day at the house — otherwise a car left at work while the
	# owner walks to a nearby lunch/leisure spot would strand overnight.
	if purpose == "home":
		return _should_fetch_car_home(target)
	return _should_drive(target)


func _should_fetch_car_home(home_target: Vector3) -> bool:
	if not data["owns_car"]:
		return false
	var car := _ensure_car()
	if car == null or not is_instance_valid(car):
		return false
	if int(car.get("state")) != Vehicle.VState.PARKED:
		return false
	# Already parked at home -> just walk in; otherwise go fetch it.
	return car.global_position.distance_to(home_target) > CAR_NEARBY_DIST


func _should_drive(target: Vector3) -> bool:
	if not data["owns_car"]:
		return false
	var car := _ensure_car()
	if car == null or not is_instance_valid(car):
		return false
	if int(car.get("state")) != Vehicle.VState.PARKED:
		return false
	if global_position.distance_to(target) < CAR_MIN_TRIP_DIST:
		return false
	return global_position.distance_to(car.global_position) <= CAR_NEARBY_DIST


func _ensure_car() -> Node3D:
	if owned_vehicle != null and is_instance_valid(owned_vehicle):
		return owned_vehicle
	owned_vehicle = TrafficManager.spawn_citizen_car(self)
	return owned_vehicle


func _advance_trip_leg() -> void:
	if _trip_plan.is_empty():
		_finish_trip_purpose()
		return
	var leg: Dictionary = _trip_plan.pop_front()
	if leg["kind"] == "drive":
		if TrafficManager.request_car_trip(self, owned_vehicle, leg["target"]):
			state = CState.DRIVING
			_vehicle = owned_vehicle
			goal_desc = "driving %s" % _purpose_noun()
			visible = false
			_set_sim_active(false)
			return
		# No drivable route: walk the rest of the way (leg target is the
		# final destination, so nothing is lost).
		_trip_plan.clear()
	_start_walk_leg(leg["target"])


func _start_walk_leg(target: Vector3) -> void:
	state = _walk_state()
	goal_desc = _leg_goal()
	visible = true
	_set_sim_active(true)
	_walk_to(target)


func _finish_trip_purpose() -> void:
	match _trip_purpose:
		"work":
			_enter_work()
		"home":
			_enter_sleep()
		_:
			state = CState.LEISURE
			goal_desc = "on lunch break" if _lunching else "enjoying %s" % String(_leisure_spot.get("kind", "a spot"))
			_set_anim("idle")
			_stroll_wait = _stroll_rng().randf_range(15.0, 45.0)


func _walk_state() -> CState:
	match _trip_purpose:
		"work":
			return CState.COMMUTE_OUT
		"home":
			return CState.COMMUTE_HOME
		_:
			return CState.LEISURE_GO


func _leg_goal() -> String:
	# A pending drive leg means this walk fetches the car.
	for leg: Dictionary in _trip_plan:
		if leg["kind"] == "drive":
			return "walking to their car"
	match _trip_purpose:
		"work":
			return "walking to work"
		"home":
			return "walking home"
		_:
			return "heading to %s" % String(_leisure_spot.get("kind", "?"))


func _purpose_noun() -> String:
	match _trip_purpose:
		"work":
			return "to work"
		"home":
			return "home"
		_:
			return "to %s" % String(_leisure_spot.get("kind", "?"))


func _lunch_window() -> Vector2:
	## Deterministic per-citizen lunch slot staggered over a 1.5 h band
	## (golden-ratio hash of the id; no population RNG stream draws).
	var start := fmod(float(data["work_start"]) + 3.5 + fposmod(float(data["id"]) * 0.618, 1.5), 24.0)
	return Vector2(start, fmod(start + LUNCH_HOURS, 24.0))


func _start_lunch() -> void:
	_lunch_day = GameClock.day
	_lunching = true
	var work_pos := _work_target_pos()
	var spot := _nearest_leisure_spot(work_pos)
	if spot.is_empty() or Vector2(spot["pos"].x - work_pos.x, spot["pos"].z - work_pos.z).length() > LUNCH_TARGET_MAX_DIST:
		spot = _corner_spot_near(work_pos)
	_leisure_spot = spot
	# Lunch is always on foot (short, near the workplace) so the car
	# stays parked at the work curb for the evening commute.
	_plan_trip(spot["pos"], "leisure", true)
	goal_desc = "on lunch break"


func _end_lunch() -> void:
	_lunching = false
	_plan_trip(_work_target_pos(), "work", true)
	goal_desc = "returning to work"


func _nearest_leisure_spot(from_pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1e18
	for s: Dictionary in data["leisure_spots"]:
		var d: float = from_pos.distance_squared_to(s["pos"])
		if d < best_d:
			best_d = d
			best = s
	return best


func _corner_spot_near(anchor: Vector3) -> Dictionary:
	## Fallback target: a sidewalk node within a short walk.
	var graph: RoadGraph = CityData.road_graph
	var nodes := graph.side_nodes_near(anchor, 15.0, 55.0)
	if nodes.is_empty():
		return {"kind": "doorstep", "pos": anchor}
	var pick := nodes[_stroll_rng().randi_range(0, nodes.size() - 1)]
	return {"kind": "street corner", "pos": graph.side_points[pick]}


func _begin_stroll() -> void:
	var graph: RoadGraph = CityData.road_graph
	var anchor: Vector3 = _leisure_spot.get("pos", global_position)
	var nodes := graph.side_nodes_near(anchor, 15.0, 55.0)
	if nodes.is_empty():
		_stroll_wait = _stroll_rng().randf_range(15.0, 45.0)
		return
	var target: Vector3 = graph.side_points[nodes[_stroll_rng().randi_range(0, nodes.size() - 1)]]
	goal_desc = "strolling near %s" % String(_leisure_spot.get("kind", "town"))
	_walk_to(target)


func _stroll_rng() -> RandomNumberGenerator:
	## Separate deterministic stream per citizen; never touches the
	## population generation RNG.
	if _leisure_rng == null:
		_leisure_rng = RandomNumberGenerator.new()
		_leisure_rng.seed = PopulationManager.POPULATION_SEED ^ (int(data["id"]) * 2654435761)
	return _leisure_rng


func _set_sim_active(active: bool) -> void:
	## Idle states neither move nor animate; schedule transitions stay
	## alive via GameClock signals.
	set_process(active)
	if not active and _anim:
		_anim.pause()


func _set_anim(kind: String) -> void:
	if _anim == null or _anim_lod_paused:
		return
	var target := _walk_anim if kind == "walk" else _idle_anim
	if not _anim.has_animation(target):
		return
	if _anim.current_animation != target or not _anim.is_playing():
		_anim.play(target)


func inspect_info() -> Dictionary:
	var home := CityData.get_building(int(data["home_id"]))
	var work := CityData.get_building(int(data["work_id"]))
	return {
		"kind": "citizen",
		"name": data["name"],
		"state": CState.keys()[state],
		"goal": goal_desc,
		"home": "#%d %s (%s)" % [data["home_id"], home.get("family", "?"), home.get("district", "?")],
		"job": "%s%s" % [data["job_type"], "" if work.is_empty() else " at #%d" % data["work_id"]],
		"shift": data["shift"],
		"owns_car": data["owns_car"],
		"wake": "%.1f" % data["wake_hour"],
		"work_start": "%.1f" % data["work_start"],
		"home_hour": "%.1f" % data["home_hour"],
		"position": global_position,
	}
