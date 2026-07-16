class_name RtsCamera
extends Node3D
## Pizza-Connection-style RTS camera rig. WASD/edge pan, wheel zoom,
## Q/E rotate, R/F tilt. Attach to CameraRig (child Camera3D expected).
## Clicking a citizen or car enters a strict chase-cam follow mode; Esc,
## right-click, or clicking empty ground returns to the free RTS view.

const PAN_SPEED: float = 60.0
const EDGE_MARGIN: float = 8.0
const ZOOM_MIN: float = 6.0
const ZOOM_MAX: float = 520.0
const ZOOM_STEP: float = 1.12
const TILT_MIN: float = 25.0
const TILT_MAX: float = 80.0

## Chase-cam follow tuning.
const FOLLOW_DIST_START: float = 9.0
const FOLLOW_DIST_MIN: float = 4.0
const FOLLOW_DIST_MAX: float = 25.0
const FOLLOW_HEIGHT: float = 4.0
const FOLLOW_LERP: float = 8.0
const FOLLOW_LOOK_UP: float = 1.2

var zoom_dist: float = 90.0
var yaw_deg: float = 0.0
var tilt_deg: float = 52.0

## Follow mode: the selected agent (Citizen/Vehicle) to chase, or null
## for the normal free RTS camera.
var _follow: Node3D = null
var _follow_dist: float = FOLLOW_DIST_START

var _last_mouse_pos: Vector2 = Vector2.INF
var _mouse_idle_time: float = 999.0
var _movement_observed: bool = false

@onready var _cam: Camera3D = get_node("Camera3D")


func _ready() -> void:
	position = Vector3(280, 0, 300)
	_cam.near = 0.1
	_apply()
	SelectionManager.entity_selected.connect(_on_entity_selected)
	SelectionManager.selection_cleared.connect(_stop_follow)


func _process(delta: float) -> void:
	# Follow mode overrides all free-camera input while a target is chased.
	if _follow != null:
		if is_instance_valid(_follow):
			_follow_update(delta)
		else:
			_stop_follow()
		return
	var previous_position: Vector3 = position
	var previous_yaw: float = yaw_deg
	var previous_tilt: float = tilt_deg
	var move := Vector2.ZERO
	if _pressed(&"cam_pan_up", [KEY_W, KEY_UP]):
		move.y -= 1.0
	if _pressed(&"cam_pan_down", [KEY_S, KEY_DOWN]):
		move.y += 1.0
	if _pressed(&"cam_pan_left", [KEY_A, KEY_LEFT]):
		move.x -= 1.0
	if _pressed(&"cam_pan_right", [KEY_D, KEY_RIGHT]):
		move.x += 1.0
	var vp := get_viewport()
	var mouse := vp.get_mouse_position()
	if mouse.distance_squared_to(_last_mouse_pos) > 1.0:
		_mouse_idle_time = 0.0
		_last_mouse_pos = mouse
	else:
		_mouse_idle_time += delta
	var size := vp.get_visible_rect().size
	# Edge pan only for an actively-moved mouse in a focused window, so a
	# parked cursor (or automated testing) never drifts the camera.
	if get_window().has_focus() and _mouse_idle_time < 1.0 \
			and mouse.x >= 0.0 and mouse.y >= 0.0 and mouse.x <= size.x and mouse.y <= size.y:
		if mouse.x < EDGE_MARGIN:
			move.x -= 1.0
		elif mouse.x > size.x - EDGE_MARGIN:
			move.x += 1.0
		if mouse.y < EDGE_MARGIN:
			move.y -= 1.0
		elif mouse.y > size.y - EDGE_MARGIN:
			move.y += 1.0
	if _pressed(&"cam_rotate_ccw", [KEY_Q]):
		yaw_deg += 70.0 * delta
	if _pressed(&"cam_rotate_cw", [KEY_E]):
		yaw_deg -= 70.0 * delta
	if _pressed(&"cam_tilt_up", [KEY_R]):
		tilt_deg = clampf(tilt_deg + 40.0 * delta, TILT_MIN, TILT_MAX)
	if _pressed(&"cam_tilt_down", [KEY_F]):
		tilt_deg = clampf(tilt_deg - 40.0 * delta, TILT_MIN, TILT_MAX)
	if move != Vector2.ZERO:
		var speed := PAN_SPEED * (zoom_dist / 90.0)
		# Pan axes come from the rig's ACTUAL basis so W is always screen-up
		# and D screen-right at any yaw (hand-rolled sin/cos here used to
		# mirror the axes once the camera was rotated).
		var fwd := -transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := transform.basis.x
		right.y = 0.0
		right = right.normalized()
		position += (right * move.x - fwd * move.y) * speed * delta
		position.x = clampf(position.x, -120.0, 820.0)
		position.z = clampf(position.z, -120.0, 900.0)
	_apply()
	if position != previous_position or not is_equal_approx(yaw_deg, previous_yaw) \
			or not is_equal_approx(tilt_deg, previous_tilt):
		_observe_camera_movement()


## Action-aware key check: uses the rebindable input map when the action
## exists, otherwise falls back to raw physical keys.
func _pressed(action: StringName, fallback_keys: Array) -> bool:
	if InputMap.has_action(action):
		return Input.is_action_pressed(action)
	for key: Key in fallback_keys:
		if Input.is_physical_key_pressed(key):
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if _follow != null:
		# In follow mode the wheel adjusts chase distance; right-click or
		# Esc drops back to the free camera.
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_follow_dist = clampf(_follow_dist / ZOOM_STEP, FOLLOW_DIST_MIN, FOLLOW_DIST_MAX)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_follow_dist = clampf(_follow_dist * ZOOM_STEP, FOLLOW_DIST_MIN, FOLLOW_DIST_MAX)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_stop_follow()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_stop_follow()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_dist = clampf(zoom_dist / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_observe_camera_movement()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_dist = clampf(zoom_dist * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_observe_camera_movement()


func _observe_camera_movement() -> void:
	if _movement_observed:
		return
	_movement_observed = true
	GameSetup.observe_action(&"camera_moved")


func _apply() -> void:
	rotation_degrees = Vector3(0, yaw_deg, 0)
	var tilt_rad := deg_to_rad(tilt_deg)
	_cam.position = Vector3(0, zoom_dist * sin(tilt_rad), zoom_dist * cos(tilt_rad))
	_cam.rotation_degrees = Vector3(-tilt_deg, 0, 0)


# --- Chase-cam follow -------------------------------------------------

func _on_entity_selected(info: Dictionary, entity: Node) -> void:
	## Clicking a citizen/vehicle follows it; a building (or anything else)
	## leaves/skips follow mode.
	var kind := String(info.get("kind", ""))
	if (kind == "citizen" or kind == "vehicle") and entity is Node3D:
		_start_follow(entity)
	else:
		_stop_follow()


func _start_follow(node: Node3D) -> void:
	_follow = node
	_follow_dist = FOLLOW_DIST_START
	# Collapse the child camera onto the rig so the rig transform IS the
	# camera; _follow_update then drives the rig directly with look_at.
	_cam.transform = Transform3D.IDENTITY


func _stop_follow() -> void:
	if _follow == null:
		return
	_follow = null
	# Resume free RTS control from wherever the chase cam ended up, so the
	# hand-off is not jarring.
	yaw_deg = rotation_degrees.y
	position.x = clampf(position.x, -120.0, 820.0)
	position.z = clampf(position.z, -120.0, 900.0)
	_apply()


func _active_follow_node() -> Node3D:
	## A citizen who is driving is frozen/invisible while its car carries
	## the motion — chase the car instead.
	if _follow is Citizen:
		var c := _follow as Citizen
		if c.state == Citizen.CState.DRIVING and is_instance_valid(c.owned_vehicle):
			return c.owned_vehicle
	return _follow


func _follow_update(delta: float) -> void:
	var n := _active_follow_node()
	if n == null or not is_instance_valid(n):
		_stop_follow()
		return
	# Agent heading is local +Z; sit behind it and a little above.
	var fwd := n.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0, 0, 1)
	fwd = fwd.normalized()
	var target := n.global_position - fwd * _follow_dist + Vector3.UP * FOLLOW_HEIGHT
	global_position = global_position.lerp(target, 1.0 - exp(-FOLLOW_LERP * delta))
	look_at(n.global_position + Vector3.UP * FOLLOW_LOOK_UP, Vector3.UP)
