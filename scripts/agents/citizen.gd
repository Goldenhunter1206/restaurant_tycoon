class_name Citizen
extends Area3D
## One simulated person. Schedule FSM driven by GameClock; movement is
## kinematic waypoint-following on the sidewalk graph (walking) or
## delegated to a Vehicle (driving). LOD: far agents move analytically.

enum CState { SLEEP, COMMUTE_OUT, WORK, LEISURE_GO, LEISURE, COMMUTE_HOME, DRIVING }

const WALK_SPEED: float = 1.7
const LOD_NEAR: float = 70.0
const LOD_MID: float = 180.0

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
	if state == CState.LEISURE:
		return
	# Moving states: walk along the sidewalk path with distance LOD.
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
		CState.COMMUTE_OUT:
			_enter_work()
		CState.LEISURE_GO:
			state = CState.LEISURE
			goal_desc = "enjoying %s" % String(_leisure_spot.get("kind", "a spot"))
			_set_anim("idle")
		CState.COMMUTE_HOME:
			_enter_sleep()
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
		CState.LEISURE:
			if GameClock.is_between(home_h, wake):
				_start_commute_home()
		_:
			pass


func _start_commute_out() -> void:
	if data["owns_car"] and _request_car_trip(_work_target_pos()):
		state = CState.DRIVING
		goal_desc = "driving to work"
		return
	state = CState.COMMUTE_OUT
	goal_desc = "walking to work"
	_walk_to(_work_target_pos())
	visible = true


func _enter_work() -> void:
	state = CState.WORK
	goal_desc = "working (%s)" % String(data["job_type"])
	visible = false


func _start_leisure() -> void:
	var spots: Array = data["leisure_spots"]
	if spots.is_empty():
		_start_commute_home()
		return
	_leisure_spot = spots[randi() % spots.size()]
	state = CState.LEISURE_GO
	goal_desc = "heading to %s" % String(_leisure_spot.get("kind", "?"))
	visible = true
	_walk_to(_leisure_spot["pos"])


func _start_commute_home() -> void:
	var home := CityData.get_building(int(data["home_id"]))
	if data["owns_car"] and _request_car_trip(home.get("door_pos", global_position)):
		state = CState.DRIVING
		goal_desc = "driving home"
		return
	state = CState.COMMUTE_HOME
	goal_desc = "walking home"
	visible = true
	_walk_to(home.get("door_pos", global_position))


func _enter_sleep() -> void:
	state = CState.SLEEP
	goal_desc = "asleep at home"
	visible = false
	var home := CityData.get_building(int(data["home_id"]))
	if not home.is_empty():
		global_position = home["door_pos"]


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


func _request_car_trip(target: Vector3) -> bool:
	var vehicle := TrafficManager.request_citizen_trip(self, target)
	if vehicle == null:
		return false
	_vehicle = vehicle
	visible = false
	return true


func on_car_trip_finished(at_pos: Vector3) -> void:
	global_position = at_pos
	_vehicle = null
	visible = true
	match state:
		CState.DRIVING:
			if goal_desc == "driving to work":
				_enter_work()
			else:
				_enter_sleep()
		_:
			pass


func _set_anim(kind: String) -> void:
	if _anim == null:
		return
	var target := _walk_anim if kind == "walk" else _idle_anim
	if _anim.has_animation(target) and _anim.current_animation != target:
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
