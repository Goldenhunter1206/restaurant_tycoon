class_name RestaurantMarker
extends Node3D
## Floating map-pin above a player-owned restaurant: a pizza sign prop from
## the megapack plus a billboard name label, with a gentle bob so owned
## locations read at a glance from RTS height.

const SIGN_GLB: String = "res://Cartoon City Massive Megapack/gLTF/Food Props/PizzaSign_2_A.glb"
const BOB_HEIGHT: float = 0.6
const BOB_SPEED: float = 2.0
## World-scale (not fixed_size): the name shrinks naturally with distance so
## it never covers the building; the zoom-scaled pin is the far-away marker.
const LABEL_PIXEL_SIZE: float = 0.01

var building_id: int = -1

var _base_y: float = 0.0
var _time: float = 0.0
var _bobber: Node3D


func setup(rest: RestaurantState) -> void:
	building_id = rest.building_id
	var info: Dictionary = CityData.get_building(rest.building_id)
	var top_y: float = 6.0
	var body: Node3D = null
	if info.has("node_path"):
		body = get_node_or_null(info["node_path"])
	if body != null and body.has_meta("size"):
		top_y = (body.get_meta("size") as Vector3).y + 3.5
	var base: Vector3 = Vector3(info.get("position", rest.door_pos))
	global_position = Vector3(base.x, 0.0, base.z)
	_base_y = top_y

	_bobber = Node3D.new()
	_bobber.position.y = top_y
	add_child(_bobber)

	var sign_scene: PackedScene = load(SIGN_GLB)
	if sign_scene != null:
		var sign: Node3D = sign_scene.instantiate()
		sign.scale = Vector3.ONE * 1.6
		_bobber.add_child(sign)

	var assets: GDScript = load("res://scripts/ui/ui_assets.gd")
	var pin_tex: Texture2D = assets.pin(&"pizza")
	if pin_tex != null:
		var pin: ZoomScaledPin = load("res://scripts/ui/zoom_scaled_pin.gd").new()
		pin.texture = pin_tex
		pin.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		pin.fixed_size = true
		pin.base_pixel_size = 0.0008
		pin.no_depth_test = true
		pin.render_priority = 10
		# Layer 20: overlay markers, excluded from the minimap bake camera
		# (fixed_size sprites would render huge into the ortho bake).
		pin.layers = 1 << 19
		pin.position.y = 6.0
		_bobber.add_child(pin)

	var label: Label3D = Label3D.new()
	label.text = rest.restaurant_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 96
	label.pixel_size = LABEL_PIXEL_SIZE
	label.modulate = Color("#fff2cf")
	label.outline_size = 24
	label.outline_modulate = Color("#8a5a2b")
	label.position.y = 3.4
	label.no_depth_test = true
	_bobber.add_child(label)


func _process(delta: float) -> void:
	_time += delta
	if _bobber != null:
		_bobber.position.y = _base_y + sin(_time * BOB_SPEED) * BOB_HEIGHT
		_bobber.rotate_y(delta * 0.8)
