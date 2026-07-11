class_name AmbientWalker
extends Node3D
## Camera-local set dressing: a pooled pedestrian that wanders sidewalk
## edges near the camera. Not part of the simulated population and not
## selectable (plain Node3D, no Area3D). AmbientLife owns the pool and
## recycles walkers that drift too far from the camera.

const WALK_SPEED_MIN: float = 1.4
const WALK_SPEED_MAX: float = 1.9
const LOD_NEAR: float = 70.0
const LOD_MID: float = 180.0

var active: bool = false

var _speed: float = 1.7
var _walk_anim: String = "Walk_A"
var _idle_anim: String = "Idle_A"
var _path: PackedInt32Array = PackedInt32Array()
var _path_idx: int = 0
var _node_id: int = -1
var _lod_tick: int = 0
var _anim_lod_paused: bool = false
var _rng := RandomNumberGenerator.new()
var _lane_off: float = 0.0
var _anim: AnimationPlayer
var _model: Node3D


func _ready() -> void:
	visible = false
	set_process(false)


func setup(model_path: String, anim_lib: AnimationLibrary, seed_value: int) -> void:
	## Same model-attach pattern as Citizen.set_model, incl. the shadow
	## and visibility-range overrides (skinned extras must stay cheap).
	_rng.seed = seed_value
	_speed = _rng.randf_range(WALK_SPEED_MIN, WALK_SPEED_MAX)
	_lane_off = PedSteering.lane_offset_for(seed_value)
	TrafficManager.register_pedestrian(self)
	_walk_anim = ["Walk_A", "Walk_B", "Walk_C"][absi(seed_value) % 3]
	_idle_anim = ["Idle_A", "Idle_B", "LookingAround"][absi(seed_value) % 3]
	_anim = get_node_or_null("AnimationPlayer")
	var scene: PackedScene = load(model_path)
	if scene == null:
		return
	var model: Node3D = scene.instantiate()
	model.name = "Model"
	# Characters face -Z at rest; our travel convention is +Z
	# (yaw from atan2(x, z)), so pre-rotate the mesh 180 deg.
	model.rotation_degrees = Vector3(0, 180, 0)
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


func activate(at_node: int) -> void:
	var graph: RoadGraph = CityData.road_graph
	if at_node < 0 or at_node >= graph.side_points.size():
		return
	_node_id = at_node
	global_position = graph.side_points[at_node]
	_path = PackedInt32Array()
	_path_idx = 0
	active = true
	visible = true
	set_process(true)
	_extend_path()


func retarget(at_node: int) -> void:
	## Recycle: teleport to a fresh ring node and keep wandering.
	activate(at_node)


func deactivate() -> void:
	active = false
	visible = false
	set_process(false)
	if _anim:
		_anim.pause()


func _process(delta: float) -> void:
	_lod_tick += 1
	var cam := get_viewport().get_camera_3d()
	var dist := 1e9
	if cam:
		dist = cam.global_position.distance_to(global_position)
	var anim_far := dist > LOD_MID
	if anim_far != _anim_lod_paused:
		_anim_lod_paused = anim_far
		if _anim:
			if anim_far:
				_anim.pause()
			elif _anim.current_animation != "":
				_anim.play()
	var step_frames := 1
	if dist > LOD_MID:
		step_frames = 6
	elif dist > LOD_NEAR:
		step_frames = 3
	if _lod_tick % step_frames != 0:
		return
	_advance_walk(delta * float(step_frames) * float(GameClock.speed), dist < LOD_NEAR)


func _advance_walk(scaled_delta: float, near_cam: bool = false) -> void:
	if _path_idx >= _path.size():
		_extend_path()
		if _path.is_empty():
			return
	var graph: RoadGraph = CityData.road_graph
	var target := PedSteering.offset_target(
		graph.side_points[_path[_path_idx]], global_position, _lane_off)
	# Crossing gate: signalized crossings wait for the walk phase, plain
	# ones wait until no car is bearing down on the zebra.
	var from_node := _path[_path_idx - 1] if _path_idx > 0 else _node_id
	if from_node >= 0:
		var edge := _crossing_edge(from_node, _path[_path_idx])
		if edge >= 0 and (not TrafficManager.can_pedestrian_cross(edge)
				or not TrafficManager.is_crossing_safe(edge)):
			_set_anim("idle")
			return
	_set_anim("walk")
	# Light separation from nearby walkers (near camera, every 2nd step).
	if near_cam and (_lod_tick & 1) == 0:
		var push := PedSteering.lateral_avoid(self)
		if push != Vector3.ZERO:
			global_position += push * minf(scaled_delta * 2.0, 1.0)
	var to_target := target - global_position
	to_target.y = 0
	var dist := to_target.length()
	var step := _speed * scaled_delta
	if step >= dist:
		global_position = target
		_node_id = _path[_path_idx]
		_path_idx += 1
	else:
		global_position += to_target.normalized() * step
		if to_target.length_squared() > 0.01:
			var yaw := atan2(to_target.x, to_target.z)
			rotation.y = lerp_angle(rotation.y, yaw, 0.3)


func _extend_path() -> void:
	## Continuous wander: chain 3-6 adjacent sidewalk edges, avoiding
	## immediate backtracking where possible.
	var graph: RoadGraph = CityData.road_graph
	_path = PackedInt32Array()
	_path_idx = 0
	var current := _node_id
	var prev := -1
	for k in range(_rng.randi_range(3, 6)):
		var edges: Array = graph.side_edges(current)
		if edges.is_empty():
			break
		var next := -1
		for attempt in range(4):
			var e: int = edges[_rng.randi_range(0, edges.size() - 1)]
			var other := graph.side_other_end(e, current)
			if other != prev or edges.size() == 1:
				next = other
				break
		if next < 0:
			next = graph.side_other_end(edges[0], current)
		_path.append(next)
		prev = current
		current = next


func _crossing_edge(from_id: int, to_id: int) -> int:
	var graph: RoadGraph = CityData.road_graph
	for e: int in graph.side_edges(from_id):
		if graph.side_crossing[e] >= 0 and graph.side_other_end(e, from_id) == to_id:
			return e
	return -1


func _set_anim(kind: String) -> void:
	if _anim == null or _anim_lod_paused:
		return
	var target := _walk_anim if kind == "walk" else _idle_anim
	if not _anim.has_animation(target):
		return
	if _anim.current_animation != target or not _anim.is_playing():
		_anim.play(target)
