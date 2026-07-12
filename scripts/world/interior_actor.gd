class_name InteriorActor
extends Node3D
## A purely visual person inside the restaurant interior view.
## A projection puppet: the interior view tells it where to walk, sit or
## stand and what to carry; it never reads or writes sim state itself.
## Movement scales with GameClock.speed, capped so 16x reads as "busy"
## rather than teleporting; speed 0 freezes both motion and animation.

const WALK_SPEED: float = 1.8
const VISUAL_SPEED_CAP: float = 6.0
const TURN_LERP: float = 0.3
const TAG_HEIGHT: float = 2.15
const SIT_SINK: float = 0.35
const POSE_SINK: float = 0.43

const WALK_ANIMS: Array[String] = ["Walk_A", "Walk_B", "Walk_C"]
const IDLE_ANIMS: Array[String] = ["Idle_A", "Idle_B", "LookingAround"]

var display_name: String = ""

var _model: Node3D = null
var _anim: AnimationPlayer = null
var _carry: Node3D = null
var _carried: Node3D = null
var _tag: Label3D = null
var _waypoints: Array[Vector3] = []
var _on_arrived: Callable = Callable()
var _seated: bool = false
var _sit_posed: bool = false
var _sit_drop: float = 0.0
var _speed_mult: float = 1.0
var _walk_anim: String = "Walk_A"
var _idle_anim: String = "Idle_A"


func setup(model_path: String, name_text: String, variant_seed: int = 0) -> void:
	display_name = name_text
	_walk_anim = WALK_ANIMS[absi(variant_seed) % WALK_ANIMS.size()]
	_idle_anim = IDLE_ANIMS[absi(variant_seed) % IDLE_ANIMS.size()]
	var scene: PackedScene = load(model_path)
	if scene != null:
		_model = scene.instantiate()
		_model.name = "Model"
		# Characters face -Z at rest; travel convention is +Z.
		_model.rotation_degrees = Vector3(0, 180, 0)
		add_child(_model)
		for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_anim = AnimationPlayer.new()
	_anim.name = "AnimationPlayer"
	add_child(_anim)
	var lib: AnimationLibrary = PopulationManager.animation_library()
	if lib != null and not _anim.has_animation_library(""):
		_anim.add_animation_library("", lib)
	_anim.root_node = NodePath("../Model")
	_carry = Node3D.new()
	_carry.name = "Carry"
	_carry.position = Vector3(0.0, 1.15, 0.35)
	add_child(_carry)
	_tag = Label3D.new()
	_tag.name = "NameTag"
	_tag.text = name_text
	_tag.position = Vector3(0.0, TAG_HEIGHT, 0.0)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.font_size = 48
	_tag.pixel_size = 0.004
	_tag.outline_size = 12
	_tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	add_child(_tag)
	_play(_idle_anim)


func set_tag(text: String) -> void:
	if _tag != null:
		_tag.text = text


func walk_along(points: Array[Vector3], on_arrived: Callable = Callable(), speed_mult: float = 1.0) -> void:
	if _seated:
		stand()
	_waypoints = points.duplicate()
	_on_arrived = on_arrived
	_speed_mult = maxf(speed_mult, 0.1)
	if _waypoints.is_empty():
		_finish_walk()
	else:
		_play(_walk_anim)


func is_walking() -> bool:
	return not _waypoints.is_empty()


func finish_walk_now() -> void:
	## Catch-up rule: snap to the current goal and fire the arrival callback,
	## so a new destination can start from a consistent state.
	if _waypoints.is_empty():
		return
	var goal: Vector3 = _waypoints[_waypoints.size() - 1]
	_waypoints.clear()
	global_position = goal
	_finish_walk()


func snap_to(pos: Vector3, yaw: float = NAN) -> void:
	_waypoints.clear()
	_on_arrived = Callable()
	if _seated:
		stand()
	global_position = pos
	if not is_nan(yaw):
		rotation.y = yaw
	_play(_idle_anim)


func set_carried(prop: Node3D) -> void:
	clear_carried()
	_carried = prop
	_carry.add_child(prop)


func take_carried() -> Node3D:
	## Detach the carried prop without freeing it; caller reparents it.
	if _carried == null:
		return null
	var prop: Node3D = _carried
	_carried = null
	_carry.remove_child(prop)
	return prop


func clear_carried() -> void:
	if _carried != null:
		_carried.queue_free()
		_carried = null


func sit(seat: Transform3D) -> void:
	_waypoints.clear()
	_on_arrived = Callable()
	global_transform = seat
	_seated = true
	if _anim != null:
		_play(_idle_anim)
		_anim.advance(0.0)
		_anim.pause()
	_sit_posed = _apply_sit_pose()
	# Posed: drop the pelvis onto the chair seat. Unposed rig: sink so the
	# chair and table occlude the legs instead.
	_sit_drop = POSE_SINK if _sit_posed else SIT_SINK
	position.y -= _sit_drop
	if not _sit_posed and _anim != null:
		_play(_idle_anim)


func stand() -> void:
	if not _seated:
		return
	_seated = false
	if _sit_posed:
		var skel: Skeleton3D = _skeleton()
		if skel != null:
			skel.reset_bone_poses()
		_sit_posed = false
	position.y += _sit_drop
	_sit_drop = 0.0
	if _anim != null:
		_anim.play(_idle_anim)


func _process(delta: float) -> void:
	var clock_speed: float = clampf(float(GameClock.speed), 0.0, VISUAL_SPEED_CAP)
	if _anim != null and not _seated:
		_anim.speed_scale = 0.0 if clock_speed <= 0.0 else 1.0
	if _waypoints.is_empty() or clock_speed <= 0.0:
		return
	var target: Vector3 = _waypoints[0]
	var to_target: Vector3 = target - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	var step: float = WALK_SPEED * _speed_mult * clock_speed * delta
	if step >= dist:
		global_position = Vector3(target.x, target.y, target.z)
		_waypoints.pop_front()
		if _waypoints.is_empty():
			_finish_walk()
	else:
		global_position += to_target.normalized() * step
		if to_target.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(to_target.x, to_target.z), TURN_LERP)


func _finish_walk() -> void:
	_play(_idle_anim)
	var done: Callable = _on_arrived
	_on_arrived = Callable()
	if done.is_valid():
		done.call()


func _play(anim_name: String) -> void:
	if _anim == null:
		return
	if not _anim.has_animation(anim_name):
		return
	if _anim.current_animation != anim_name or not _anim.is_playing():
		_anim.play(anim_name)


func _skeleton() -> Skeleton3D:
	if _model == null:
		return null
	var found: Array[Node] = _model.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if not found.is_empty() else null


func _apply_sit_pose() -> bool:
	## Procedural sit: no Sit animation exists in the shared library, so with
	## the AnimationPlayer paused we bend hips ~-85° and knees ~+85°.
	var skel: Skeleton3D = _skeleton()
	if skel == null:
		return false
	var bent: int = 0
	for i: int in skel.get_bone_count():
		var bone: String = skel.get_bone_name(i).to_lower().replace("_", "").replace(".", "")
		var angle: float = 0.0
		if bone.contains("upperleg") or bone.contains("thigh") or bone.contains("upleg"):
			angle = -85.0
		elif bone.contains("lowerleg") or bone.contains("shin") or bone.contains("calf") or bone.contains("knee"):
			angle = 85.0
		else:
			continue
		var pose: Quaternion = skel.get_bone_pose_rotation(i)
		skel.set_bone_pose_rotation(i, pose * Quaternion(Vector3.RIGHT, deg_to_rad(angle)))
		bent += 1
	return bent >= 4
