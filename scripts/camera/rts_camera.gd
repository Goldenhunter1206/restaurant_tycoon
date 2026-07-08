class_name RtsCamera
extends Node3D
## Pizza-Connection-style RTS camera rig. WASD/edge pan, wheel zoom,
## Q/E rotate, R/F tilt. Attach to CameraRig (child Camera3D expected).

const PAN_SPEED: float = 60.0
const EDGE_MARGIN: float = 8.0
const ZOOM_MIN: float = 12.0
const ZOOM_MAX: float = 420.0
const ZOOM_STEP: float = 1.12
const TILT_MIN: float = 25.0
const TILT_MAX: float = 80.0

var zoom_dist: float = 90.0
var yaw_deg: float = 0.0
var tilt_deg: float = 52.0

var _last_mouse_pos: Vector2 = Vector2.INF
var _mouse_idle_time: float = 999.0

@onready var _cam: Camera3D = get_node("Camera3D")


func _ready() -> void:
	position = Vector3(280, 0, 300)
	_apply()


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
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
	if Input.is_physical_key_pressed(KEY_Q):
		yaw_deg += 70.0 * delta
	if Input.is_physical_key_pressed(KEY_E):
		yaw_deg -= 70.0 * delta
	if Input.is_physical_key_pressed(KEY_R):
		tilt_deg = clampf(tilt_deg + 40.0 * delta, TILT_MIN, TILT_MAX)
	if Input.is_physical_key_pressed(KEY_F):
		tilt_deg = clampf(tilt_deg - 40.0 * delta, TILT_MIN, TILT_MAX)
	if move != Vector2.ZERO:
		var speed := PAN_SPEED * (zoom_dist / 90.0)
		var yaw_rad := deg_to_rad(yaw_deg)
		var fwd := Vector3(sin(yaw_rad), 0, -cos(yaw_rad))
		var right := Vector3(cos(yaw_rad), 0, sin(yaw_rad))
		position += (right * move.x + fwd * -move.y) * speed * delta
		position.x = clampf(position.x, -120.0, 820.0)
		position.z = clampf(position.z, -120.0, 900.0)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_dist = clampf(zoom_dist / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_dist = clampf(zoom_dist * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)


func _apply() -> void:
	rotation_degrees = Vector3(0, yaw_deg, 0)
	var tilt_rad := deg_to_rad(tilt_deg)
	_cam.position = Vector3(0, zoom_dist * sin(tilt_rad), zoom_dist * cos(tilt_rad))
	_cam.rotation_degrees = Vector3(-tilt_deg, 0, 0)
