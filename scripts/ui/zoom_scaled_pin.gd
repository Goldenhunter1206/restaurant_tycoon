class_name ZoomScaledPin
extends Sprite3D
## Screen-constant billboard pin whose pixel_size shrinks as the camera gets
## close, so the marker never covers the object it points at, while staying
## clamped to a readable size when zoomed far out. Works off camera distance
## (not RtsCamera zoom_dist) so it behaves in chase-cam follow mode too.

const DIST_REF: float = 200.0
const MIN_FRAC: float = 0.40

@export var base_pixel_size: float = 0.0008


static func factor(cam: Camera3D, pos: Vector3) -> float:
	return clampf(cam.global_position.distance_to(pos) / DIST_REF, MIN_FRAC, 1.0)


func _process(_delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		pixel_size = base_pixel_size * factor(cam, global_position)
