class_name RestaurantPanel
extends PanelContainer
## Right-side panel: selected restaurant overview + the action-button grid.
## The minimap slot at the top is filled in by the minimap feature.

signal action_pressed(screen_id: StringName, building_id: int)

const ACTIONS: Array[Array] = [
	["🏗", "Build", &"build"],
	["👥", "Staff", &"staff"],
	["🍕", "Recipes", &"recipes"],
	["📣", "Marketing", &"marketing"],
	["🛵", "Deliveries", &"deliveries"],
	["🚚", "Suppliers", &"suppliers"],
	["📊", "Reports", &"reports"],
	["💵", "Finances", &"finances"],
]

var selected_building_id: int = -1

var minimap_slot: PanelContainer
var _selector: OptionButton
var _title: Label
var _stars: Label
var _status: Label
var _overview: Label
var _spark: Sparkline
var _profile: Label


func _ready() -> void:
	custom_minimum_size = Vector2(300, 0)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	add_child(box)

	minimap_slot = PanelContainer.new()
	minimap_slot.add_theme_stylebox_override("panel", TycoonTheme.inner_box(Color("#dcc998")))
	minimap_slot.custom_minimum_size = Vector2(280, 160)
	minimap_slot.add_child(Minimap.new())
	box.add_child(minimap_slot)

	_selector = OptionButton.new()
	_selector.clip_text = true
	_selector.fit_to_longest_item = false
	_selector.item_selected.connect(_on_selector_changed)
	box.add_child(_selector)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_title)

	var status_row: HBoxContainer = HBoxContainer.new()
	_stars = Label.new()
	_stars.add_theme_color_override("font_color", Color("#f2b01e"))
	status_row.add_child(_stars)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_row.add_child(_status)
	box.add_child(status_row)

	var overview_panel: PanelContainer = PanelContainer.new()
	overview_panel.add_theme_stylebox_override("panel", TycoonTheme.inner_box())
	overview_panel.size_flags_horizontal = Control.SIZE_FILL
	var overview_box: VBoxContainer = VBoxContainer.new()
	overview_panel.add_child(overview_box)
	_overview = Label.new()
	_overview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overview.add_theme_font_size_override("font_size", 12)
	overview_box.add_child(_overview)
	_spark = Sparkline.new()
	_spark.custom_minimum_size = Vector2(120, 34)
	overview_box.add_child(_spark)
	_profile = Label.new()
	_profile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_profile.add_theme_font_size_override("font_size", 12)
	overview_box.add_child(_profile)
	box.add_child(overview_panel)

	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for action: Array in ACTIONS:
		var btn: Button = Button.new()
		btn.text = "%s\n%s" % [action[0], action[1]]
		btn.custom_minimum_size = Vector2(62, 46)
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(func() -> void:
			action_pressed.emit(action[2], selected_building_id))
		grid.add_child(btn)
	box.add_child(grid)

	RestaurantManager.restaurant_purchased.connect(_on_purchased)
	RestaurantManager.restaurant_updated.connect(_on_updated)
	_rebuild_selector()


func refresh() -> void:
	var rest: RestaurantState = RestaurantManager.by_building.get(selected_building_id)
	if rest == null:
		_title.text = "No restaurant selected"
		_stars.text = ""
		_status.text = ""
		_overview.text = "Buy a location via the Build button."
		return
	_title.text = "🍕 %s" % rest.restaurant_name
	_stars.text = "%s %.1f" % [TycoonTheme.stars_text(EconomyManager.reputation), EconomyManager.reputation]
	var open_now: bool = rest.is_open(GameClock.game_hours)
	_status.text = "● Open" if open_now else "○ Closed"
	_status.add_theme_color_override(
		"font_color", Color("#2e7d32") if open_now else Color("#c0392b"))
	var rents: Dictionary = EconomyManager.tuning_value("rent.daily_by_district", {})
	_overview.text = "Hours %02d:00–%02d:00\nRent $%.0f/day  ·  Tables %d/%d\nSales today $%.0f  ·  Guests %d\nDeliveries now %d  ·  Cancelled %d" % [
		int(rest.open_hour), int(rest.close_hour),
		float(rents.get(rest.district, 120.0)),
		rest.tables_occupied, rest.table_count,
		float(rest.today.get("sales", 0.0)), int(rest.today.get("guests", 0)),
		rest.active_deliveries, int(rest.today.get("cancelled", 0)),
	]
	_spark.set_values(rest.sales_history)
	_profile.text = _profile_text(rest)


func _profile_text(rest: RestaurantState) -> String:
	var by_cat: Dictionary = rest.today.get("by_category", {})
	if by_cat.is_empty():
		return "No sales yet today."
	var total: int = 0
	for count: int in by_cat.values():
		total += count
	var parts: PackedStringArray = PackedStringArray()
	for category: StringName in by_cat:
		parts.append("%s %d%%" % [String(category), int(by_cat[category]) * 100 / maxi(total, 1)])
	return "Selling: " + ", ".join(parts)


func _rebuild_selector() -> void:
	_selector.clear()
	for rest: RestaurantState in RestaurantManager.owned:
		_selector.add_item(rest.restaurant_name)
		_selector.set_item_metadata(_selector.item_count - 1, rest.building_id)
	_selector.visible = _selector.item_count > 1
	if selected_building_id < 0 and _selector.item_count > 0:
		selected_building_id = _selector.get_item_metadata(0)
	refresh()


func _on_selector_changed(index: int) -> void:
	selected_building_id = _selector.get_item_metadata(index)
	refresh()


func _on_purchased(_rest: RestaurantState) -> void:
	_rebuild_selector()


func _on_updated(building_id: int) -> void:
	if building_id == selected_building_id:
		refresh()
