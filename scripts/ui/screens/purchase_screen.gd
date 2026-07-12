extends TycoonScreen
## Lease new restaurant locations: browse commercial buildings around the city
## (signing fee + daily rent, district-based), buy rented locations outright,
## and jump the camera to a candidate.

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
	custom_minimum_size = Vector2(640, 460)
	add_section("Your restaurants")
	_owned_list = add_scroll_list()
	add_section("Locations for lease (sign for a fee, then pay daily rent)")
	_list = add_scroll_list()


func refresh() -> void:
	for child: Node in _owned_list.get_children():
		child.queue_free()
	for rest: RestaurantState in RestaurantManager.owned:
		_owned_list.add_child(_make_owned_row(rest))

	for child: Node in _list.get_children():
		child.queue_free()
	var candidates: Array[Dictionary] = RestaurantManager.purchasable_buildings()
	var shown: int = 0
	for info: Dictionary in candidates:
		_list.add_child(_make_candidate_row(info))
		shown += 1
		if shown >= 40:
			break


func _make_owned_row(rest: RestaurantState) -> Control:
	var row: PanelContainer = make_row()
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)
	var line: Label = Label.new()
	line.text = "🍕 %s — %s district, %d tables" % [
		rest.restaurant_name,
		DISTRICT_LABELS.get(rest.district, rest.district),
		rest.table_count,
	]
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(line)
	var status: Label = Label.new()
	if rest.owned_outright:
		status.text = "Owned"
		status.add_theme_color_override("font_color", Color("#2e7d32"))
	else:
		var rents: Dictionary = EconomyManager.tuning_value("rent.daily_by_district", {})
		status.text = "Rented — $%.0f/day" % float(rents.get(rest.district, 120.0))
		status.add_theme_color_override("font_color", Color("#8a7150"))
	box.add_child(status)
	if not rest.owned_outright:
		var value: float = rest.property_value if rest.property_value > 0.0 else RestaurantManager.price_for(rest.building_id)
		var buyout_btn: Button = Button.new()
		buyout_btn.text = "Buy out ($%.0f)" % value
		buyout_btn.tooltip_text = "Pay the full property value once; this location stops paying rent forever."
		buyout_btn.disabled = not EconomyManager.can_afford(value)
		buyout_btn.pressed.connect(func() -> void:
			if RestaurantManager.buyout(rest.building_id):
				refresh())
		box.add_child(buyout_btn)
	return row


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
	var building_id: int = int(info["id"])
	var fee: float = RestaurantManager.signing_fee_for(building_id)
	var rents: Dictionary = EconomyManager.tuning_value("rent.daily_by_district", {})
	var rent: float = float(rents.get(district, 120.0))
	var price_label: Label = Label.new()
	price_label.text = "Sign $%.0f · then $%.0f/day" % [fee, rent]
	price_label.add_theme_color_override(
		"font_color",
		Color("#2e7d32") if EconomyManager.can_afford(fee) else Color("#c0392b"))
	box.add_child(price_label)
	var view_btn: Button = Button.new()
	view_btn.text = "View"
	view_btn.pressed.connect(func() -> void: _fly_to(info))
	box.add_child(view_btn)
	var buy_btn: Button = Button.new()
	buy_btn.text = "Sign lease"
	buy_btn.disabled = not EconomyManager.can_afford(fee)
	buy_btn.pressed.connect(func() -> void:
		if RestaurantManager.purchase(building_id):
			refresh())
	box.add_child(buy_btn)
	return row


func _fly_to(info: Dictionary) -> void:
	var rig: Node3D = get_tree().current_scene.get_node_or_null("CameraRig")
	if rig != null:
		rig.global_position = Vector3(info.get("position", Vector3.ZERO))
