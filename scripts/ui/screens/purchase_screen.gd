extends TycoonScreen
## Buy new restaurant locations: browse commercial buildings around the city
## with district-based pricing, buy, and jump the camera to a candidate.

const DISTRICT_LABELS: Dictionary = {
	"D": "Downtown", "C": "Commercial", "R": "Rich suburb",
	"N": "Suburb", "P": "Outskirts", "I": "Industrial",
}

var _list: VBoxContainer
var _owned_list: VBoxContainer


func screen_title() -> String:
	return "Locations & Expansion"


func screen_icon() -> StringName:
	return &"hammer"


func _build() -> void:
	add_section("Your restaurants")
	_owned_list = add_scroll_list()
	add_section("Locations for sale (price depends on neighbourhood)")
	_list = add_scroll_list()


func refresh() -> void:
	for child: Node in _owned_list.get_children():
		child.queue_free()
	for rest: RestaurantState in RestaurantManager.owned:
		var line: Label = Label.new()
		line.text = "🍕 %s — %s district, %d tables" % [
			rest.restaurant_name,
			DISTRICT_LABELS.get(rest.district, rest.district),
			rest.table_count,
		]
		_owned_list.add_child(line)

	for child: Node in _list.get_children():
		child.queue_free()
	var candidates: Array[Dictionary] = RestaurantManager.purchasable_buildings()
	var shown: int = 0
	for info: Dictionary in candidates:
		_list.add_child(_make_candidate_row(info))
		shown += 1
		if shown >= 40:
			break


func _make_candidate_row(info: Dictionary) -> Control:
	var row: PanelContainer = make_row()
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)
	var label: Label = Label.new()
	var district: String = String(info.get("district", "?"))
	label.text = "🏢 #%d — %s" % [int(info["id"]), DISTRICT_LABELS.get(district, district)]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)
	var price: float = float(info["price"])
	var price_label: Label = Label.new()
	price_label.text = "$%.0f" % price
	price_label.add_theme_color_override(
		"font_color",
		Color("#2e7d32") if EconomyManager.can_afford(price) else Color("#c0392b"))
	box.add_child(price_label)
	var view_btn: Button = Button.new()
	view_btn.text = "View"
	view_btn.pressed.connect(func() -> void: _fly_to(info))
	box.add_child(view_btn)
	var buy_btn: Button = Button.new()
	buy_btn.text = "Buy"
	buy_btn.disabled = not EconomyManager.can_afford(price)
	buy_btn.pressed.connect(func() -> void:
		if RestaurantManager.purchase(int(info["id"])):
			refresh())
	box.add_child(buy_btn)
	return row


func _fly_to(info: Dictionary) -> void:
	var rig: Node3D = get_tree().current_scene.get_node_or_null("CameraRig")
	if rig != null:
		rig.global_position = Vector3(info.get("position", Vector3.ZERO))
