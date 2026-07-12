extends TycoonScreen
## Recipe/menu editor: per dish enable, quality tier and price, with live
## cost + margin readout.

var _rows: Dictionary = {}
var _slots_label: Label
var _buy_button: Button


func screen_title() -> String:
	return "Recipes & Menu"


func screen_icon() -> StringName:
	return &"pizza"


func _build() -> void:
	add_section("Tick a dish to sell it. Quality changes ingredient cost and reputation.")
	add_section("Each dish needs a kitchen station and costs daily prep — pick what this district actually eats.")
	var slots_row: HBoxContainer = HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 10)
	_slots_label = Label.new()
	_slots_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_label.add_theme_color_override("font_color", Color("#8a5a2b"))
	slots_row.add_child(_slots_label)
	_buy_button = Button.new()
	_buy_button.pressed.connect(func() -> void:
		RestaurantManager.buy_menu_slot(building_id)
		refresh())
	slots_row.add_child(_buy_button)
	_content.add_child(slots_row)
	var list: VBoxContainer = add_scroll_list()
	var rest: RestaurantState = restaurant()
	if rest == null:
		return
	for entry: MenuEntry in rest.menu:
		var def: DishDef = RestaurantManager.dish(entry.dish_id)
		if def == null:
			continue
		list.add_child(_make_dish_row(entry, def))


func refresh() -> void:
	var rest: RestaurantState = restaurant()
	if rest == null:
		return
	_refresh_slots(rest)
	for dish_id: StringName in _rows:
		var entry: MenuEntry = null
		for candidate: MenuEntry in rest.menu:
			if candidate.dish_id == dish_id:
				entry = candidate
				break
		if entry == null:
			continue
		var row: Dictionary = _rows[dish_id]
		var checkbox: CheckBox = row["enabled"]
		checkbox.set_pressed_no_signal(entry.enabled)
		# Kitchen full: the remaining dishes need a free station first.
		var full: bool = rest.enabled_dish_count() >= rest.menu_slots
		checkbox.disabled = full and not entry.enabled
		checkbox.tooltip_text = "All kitchen stations are in use." if checkbox.disabled else ""
		(row["price"] as SpinBox).set_value_no_signal(entry.price)
		_select_tier(row["tier"] as OptionButton, entry.tier)
		_update_margin(dish_id)


func _refresh_slots(rest: RestaurantState) -> void:
	if _slots_label == null:
		return
	_slots_label.text = "Kitchen stations: %d/%d used · menu upkeep $%.0f/day" % [
		rest.enabled_dish_count(), rest.menu_slots, RestaurantManager.menu_upkeep_for(rest)]
	var max_slots: int = int(EconomyManager.tuning_value("menu.max_slots", 8))
	if rest.menu_slots >= max_slots:
		_buy_button.text = "Kitchen full"
		_buy_button.disabled = true
	else:
		_buy_button.text = "Add station ($%.0f)" % RestaurantManager.menu_slot_price(rest)
		_buy_button.disabled = false


func _make_dish_row(entry: MenuEntry, def: DishDef) -> Control:
	var row: PanelContainer = make_row()
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)

	var enabled: CheckBox = CheckBox.new()
	enabled.button_pressed = entry.enabled
	box.add_child(enabled)

	var name_label: Label = Label.new()
	name_label.text = def.display_name
	name_label.custom_minimum_size.x = 150
	box.add_child(name_label)

	var prep: Label = Label.new()
	prep.text = "⏱ %d min" % int(def.base_prep_minutes)
	prep.add_theme_color_override("font_color", Color("#8a7150"))
	box.add_child(prep)

	var tier_select: OptionButton = OptionButton.new()
	for tier: QualityTier in def.tiers:
		tier_select.add_item("%s ($%.2f)" % [tier.display_name, tier.ingredient_cost])
		tier_select.set_item_metadata(tier_select.item_count - 1, tier.tier)
	_select_tier(tier_select, entry.tier)
	box.add_child(tier_select)

	var price: SpinBox = SpinBox.new()
	price.min_value = 0.5
	price.max_value = 99.0
	price.step = 0.5
	price.prefix = "$"
	price.value = entry.price
	box.add_child(price)

	var margin: Label = Label.new()
	margin.custom_minimum_size.x = 110
	box.add_child(margin)

	_rows[entry.dish_id] = {
		"enabled": enabled, "tier": tier_select, "price": price, "margin": margin,
	}
	var apply: Callable = func(_arg: Variant = null) -> void:
		_apply_row(entry.dish_id)
		refresh()   # re-sync checkboxes: the manager may reject over-cap enables
	enabled.toggled.connect(apply)
	price.value_changed.connect(apply)
	tier_select.item_selected.connect(apply)
	_update_margin(entry.dish_id)
	return row


func _apply_row(dish_id: StringName) -> void:
	var row: Dictionary = _rows[dish_id]
	var tier_select: OptionButton = row["tier"]
	var tier: StringName = tier_select.get_item_metadata(tier_select.selected)
	RestaurantManager.set_menu_entry(
		building_id, dish_id,
		(row["price"] as SpinBox).value, tier,
		(row["enabled"] as CheckBox).button_pressed)
	_update_margin(dish_id)


func _update_margin(dish_id: StringName) -> void:
	var row: Dictionary = _rows[dish_id]
	var def: DishDef = RestaurantManager.dish(dish_id)
	var tier_select: OptionButton = row["tier"]
	if def == null or tier_select.selected < 0:
		return
	var tier: QualityTier = def.tier_by_id(tier_select.get_item_metadata(tier_select.selected))
	if tier == null:
		return
	var price: float = (row["price"] as SpinBox).value
	var margin: float = price - tier.ingredient_cost
	var label: Label = row["margin"]
	label.text = "profit $%.2f · $%.0f/day" % [margin, RestaurantManager.dish_upkeep(def, tier.tier)]
	label.add_theme_color_override(
		"font_color", Color("#2e7d32") if margin > 0.0 else Color("#c0392b"))


func _select_tier(tier_select: OptionButton, tier: StringName) -> void:
	for i: int in tier_select.item_count:
		if tier_select.get_item_metadata(i) == tier:
			tier_select.select(i)
			return
