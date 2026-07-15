class_name WarehouseMarker
extends Node3D
## Floating map-pin above a company warehouse: truck pin + name label in the
## owning company's brand color. Mirrors RestaurantMarker, minus the sign
## prop and bobbing — warehouses read as steady infrastructure.

const LABEL_PIXEL_SIZE: float = 0.01

var warehouse_id: int = -1


func setup(warehouse: WarehouseState) -> void:
	warehouse_id = warehouse.id
	var info: Dictionary = CityData.get_building(warehouse.building_id)
	var top_y: float = 8.0
	var body: Node3D = null
	if info.has("node_path"):
		body = get_node_or_null(info["node_path"])
	if body != null and body.has_meta("size"):
		top_y = (body.get_meta("size") as Vector3).y + 3.0
	var base: Vector3 = Vector3(info.get("position", warehouse.world_pos))
	global_position = Vector3(base.x, 0.0, base.z)

	var brand: Color = Color("#C6883A")
	var owner_company: CompanyState = CompanyManager.company(warehouse.company_id)
	if owner_company != null:
		brand = owner_company.brand_color

	var assets: GDScript = load("res://scripts/ui/ui_assets.gd")
	var pin_tex: Texture2D = assets.pin(&"truck")
	if pin_tex != null:
		var pin: ZoomScaledPin = load("res://scripts/ui/zoom_scaled_pin.gd").new()
		pin.texture = pin_tex
		pin.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		pin.fixed_size = true
		pin.base_pixel_size = 0.0008
		pin.no_depth_test = true
		pin.render_priority = 10
		# Layer 20: overlay markers, excluded from the minimap bake camera.
		pin.layers = 1 << 19
		pin.position.y = top_y + 6.0
		if owner_company != null and not owner_company.is_player:
			pin.modulate = brand.lerp(Color.WHITE, 0.3)
		add_child(pin)

	var label: Label3D = Label3D.new()
	label.text = warehouse.display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 96
	label.pixel_size = LABEL_PIXEL_SIZE
	label.modulate = Color("#fff2cf")
	label.outline_size = 24
	label.outline_modulate = brand.darkened(0.35)
	label.position.y = top_y + 3.0
	label.no_depth_test = true
	add_child(label)
