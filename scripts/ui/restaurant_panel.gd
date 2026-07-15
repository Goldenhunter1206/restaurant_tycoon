class_name RestaurantPanel
extends PanelContainer
## Right rail: district header, minimap with tool strip + data layers,
## restaurant status, customer profile, business overview / live operations,
## and the 2x4 icon action grid. Backed by RestaurantManager snapshots.

signal action_pressed(screen_id: StringName, building_id: int)

const ACTIONS: Array[Array] = [
	[&"hammer", "Build", &"build"],
	[&"people", "Staff", &"staff"],
	[&"pizza", "Recipes", &"recipes"],
	[&"megaphone", "Marketing", &"marketing"],
	[&"scooter", "Deliveries", &"deliveries"],
	[&"truck", "Suppliers", &"suppliers"],
	[&"chart_bars", "Reports", &"reports"],
	[&"coin", "Finances", &"finances"],
	[&"store", "Visit", &"interior"],
]

const PROFILE_COLS: Array[Array] = [
	[&"teens", &"teen", "Teens"],
	[&"students", &"student", "Students"],
	[&"workers", &"worker", "Workers"],
	[&"families", &"family", "Families"],
	[&"seniors", &"senior", "Seniors"],
]

var selected_building_id: int = -1

var minimap_slot: PanelContainer
var _assets: GDScript = load("res://scripts/ui/ui_assets.gd")
var _minimap: Minimap
var _layer_menu: PopupMenu
var _legend: Label
var _district: Label
var _selector: OptionButton
var _title_row: HBoxContainer
var _title: Label
var _stars_slot: HBoxContainer
var _status: Label
var _overview_tab: Button
var _operations_tab: Button
var _content_panel: PanelContainer
var _profile_title: Label
var _profile_box: HBoxContainer
var _biz_title: Label
var _biz_grid: GridContainer
var _content: RichTextLabel
var _spark: Sparkline
var _spark_caption: Label
var _bottleneck_action: Button
var _show_operations: bool = false
var _bottleneck_screen: StringName = &""


func _ready() -> void:
	custom_minimum_size = Vector2(374, 0)
	add_theme_stylebox_override("panel", TycoonTheme.wood_frame_lg_box())
	var inner: PanelContainer = PanelContainer.new()
	inner.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	add_child(inner)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size.x = 340.0
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 7)
	scroll.add_child(box)

	_district = Label.new()
	_district.text = "CITY DISTRICT"
	_district.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_district.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_TITLE)
	_district.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	box.add_child(_district)

	var map_row: HBoxContainer = HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 5)
	box.add_child(map_row)
	minimap_slot = PanelContainer.new()
	minimap_slot.add_theme_stylebox_override("panel", TycoonTheme.inner_box(Color("#d8c68e")))
	minimap_slot.custom_minimum_size = Vector2(300, 190)
	minimap_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_minimap = Minimap.new()
	minimap_slot.add_child(_minimap)
	map_row.add_child(minimap_slot)

	var tools: VBoxContainer = VBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	map_row.add_child(tools)
	_tool_button(tools, &"zoom_in", "Zoom in", func() -> void: _nudge_zoom(1.0 / 1.35))
	_tool_button(tools, &"zoom_out", "Zoom out", func() -> void: _nudge_zoom(1.35))
	_tool_button(tools, &"magnifier", "Center on restaurant", _center_on_restaurant)
	var layers_btn: Button = _tool_button(tools, &"layers", "Map layers", Callable())
	_layer_menu = PopupMenu.new()
	add_child(_layer_menu)
	for entry: Array in [
		["City", Minimap.Layer.NONE], ["Demand", Minimap.Layer.DEMAND],
		["Coverage", Minimap.Layer.COVERAGE], ["Routes", Minimap.Layer.ROUTES],
		["Zoning", Minimap.Layer.ZONING], ["Marketing", Minimap.Layer.MARKETING],
	]:
		_layer_menu.add_radio_check_item(entry[0], entry[1])
	_layer_menu.set_item_checked(0, true)
	_layer_menu.id_pressed.connect(_on_layer_picked)
	layers_btn.pressed.connect(func() -> void:
		_layer_menu.popup(Rect2i(Vector2i(layers_btn.get_screen_position()) + Vector2i(-140, 34), Vector2i(140, 0))))

	_legend = Label.new()
	_legend.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
	_legend.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_legend.visible = false
	box.add_child(_legend)

	_selector = OptionButton.new()
	_selector.clip_text = true
	_selector.fit_to_longest_item = false
	_selector.item_selected.connect(_on_selector_changed)
	box.add_child(_selector)

	_title_row = HBoxContainer.new()
	_title_row.add_theme_constant_override("separation", 6)
	box.add_child(_title_row)
	_title_row.add_child(_assets.icon_rect(&"store", 20))
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_TITLE)
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_row.add_child(_title)
	_stars_slot = HBoxContainer.new()
	_title_row.add_child(_stars_slot)

	var status_row: HBoxContainer = HBoxContainer.new()
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_status)
	box.add_child(status_row)

	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 5)
	_overview_tab = _tab_button("Overview", false)
	_operations_tab = _tab_button("Operations", true)
	tabs.add_child(_overview_tab)
	tabs.add_child(_operations_tab)
	box.add_child(tabs)

	_content_panel = PanelContainer.new()
	_content_panel.add_theme_stylebox_override("panel", TycoonTheme.inner_box())
	_content_panel.custom_minimum_size.y = 304.0
	var content_box: VBoxContainer = VBoxContainer.new()
	content_box.add_theme_constant_override("separation", 5)
	_content_panel.add_child(content_box)

	_profile_title = _section_label(content_box, "CUSTOMER PROFILE")
	_profile_box = HBoxContainer.new()
	_profile_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_profile_box.add_theme_constant_override("separation", 10)
	content_box.add_child(_profile_box)

	_biz_title = _section_label(content_box, "BUSINESS OVERVIEW")
	_biz_grid = GridContainer.new()
	_biz_grid.columns = 2
	_biz_grid.add_theme_constant_override("h_separation", 16)
	_biz_grid.add_theme_constant_override("v_separation", 3)
	content_box.add_child(_biz_grid)

	_content = RichTextLabel.new()
	_content.bbcode_enabled = true
	_content.fit_content = true
	_content.custom_minimum_size = Vector2(310, 214)
	_content.add_theme_font_size_override("normal_font_size", 13)
	content_box.add_child(_content)

	_spark_caption = _section_label(content_box, "SALES (10 DAYS)")
	_spark = Sparkline.new()
	_spark.custom_minimum_size = Vector2(300, 42)
	content_box.add_child(_spark)
	_bottleneck_action = Button.new()
	_bottleneck_action.visible = false
	_bottleneck_action.pressed.connect(_on_bottleneck_action)
	content_box.add_child(_bottleneck_action)
	box.add_child(_content_panel)

	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for action: Array in ACTIONS:
		var btn: Button = Button.new()
		btn.text = String(action[1])
		var tex: Texture2D = _assets.icon(action[0])
		if tex != null:
			btn.icon = tex
			btn.expand_icon = true
			btn.add_theme_constant_override("icon_max_width", 26)
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.custom_minimum_size = Vector2(79, 66)
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_stylebox_override("normal", TycoonTheme.action_tile_box())
		btn.tooltip_text = String(action[1])
		btn.pressed.connect(func() -> void:
			action_pressed.emit(action[2], selected_building_id))
		var anim: GDScript = load("res://scripts/ui/ui_anim.gd")
		anim.hover_pop(btn)
		grid.add_child(btn)
	box.add_child(grid)

	RestaurantManager.restaurant_purchased.connect(_on_purchased)
	RestaurantManager.restaurant_updated.connect(_on_updated)
	DemandManager.restaurant_intent_changed.connect(_on_intent_changed)
	SelectionManager.entity_selected.connect(_on_entity_selected)
	_rebuild_selector()


func _section_label(parent: Control, text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	parent.add_child(label)
	return label


func _tool_button(parent: Control, icon_name: StringName, tip: String, on_press: Callable) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(34, 34)
	btn.tooltip_text = tip
	_assets.icon_button(btn, icon_name, 20)
	if btn.icon == null:
		btn.text = tip.left(1)
	TycoonTheme.apply_orange(btn)
	if not on_press.is_null():
		btn.pressed.connect(on_press)
	parent.add_child(btn)
	return btn


func _tab_button(label: String, operations: bool) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void:
		_show_operations = operations
		refresh())
	return button


func _nudge_zoom(factor: float) -> void:
	var rig: Node3D = get_tree().current_scene.get_node_or_null("CameraRig")
	if rig == null:
		return
	var current: float = float(rig.get("zoom_dist"))
	rig.set("zoom_dist", clampf(current * factor, RtsCamera.ZOOM_MIN, RtsCamera.ZOOM_MAX))


func _center_on_restaurant() -> void:
	var rest: RestaurantState = RestaurantManager.by_building.get(selected_building_id)
	var rig: Node3D = get_tree().current_scene.get_node_or_null("CameraRig")
	if rest == null or rig == null:
		return
	rig.global_position = Vector3(rest.door_pos.x, rig.global_position.y, rest.door_pos.z)


func _on_layer_picked(id: int) -> void:
	for index: int in _layer_menu.item_count:
		_layer_menu.set_item_checked(index, _layer_menu.get_item_id(index) == id)
	_minimap.set_layer(id as Minimap.Layer)
	_legend.text = _minimap.legend_text()
	_legend.visible = not _legend.text.is_empty()


func refresh() -> void:
	_overview_tab.set_pressed_no_signal(not _show_operations)
	_operations_tab.set_pressed_no_signal(_show_operations)
	var rest: RestaurantState = RestaurantManager.by_building.get(selected_building_id)
	if rest == null:
		_title.text = "No restaurant selected"
		_clear(_stars_slot)
		_status.text = ""
		_set_overview_visible(false)
		_content.visible = true
		_content.text = "Buy a location via the Build button."
		_bottleneck_action.visible = false
		return
	_district.text = "%s DISTRICT" % _district_name(rest.district).to_upper()
	_title.text = rest.restaurant_name
	_clear(_stars_slot)
	_stars_slot.add_child(TycoonTheme.star_row(EconomyManager.reputation, 14))
	var open_now: bool = rest.is_open(GameClock.game_hours)
	_status.text = "Status: %s   ·   Hours %02d:00–%02d:00" % [
		"Open" if open_now else "Closed", int(rest.open_hour), int(rest.close_hour)]
	_status.add_theme_color_override("font_color",
		Color("#2e7d32") if open_now else Color("#c0392b"))
	if _show_operations:
		_render_operations(rest)
	else:
		_render_overview(rest)


func _set_overview_visible(shown: bool) -> void:
	_profile_title.visible = shown
	_profile_box.visible = shown
	_biz_title.visible = shown
	_biz_grid.visible = shown
	_spark.visible = shown
	_spark_caption.visible = shown


func _clear(node: Control) -> void:
	for child: Node in node.get_children():
		child.queue_free()


func _render_overview(rest: RestaurantState) -> void:
	_content_panel.add_theme_stylebox_override("panel", TycoonTheme.inner_box())
	_bottleneck_action.visible = false
	_content.visible = false
	_set_overview_visible(true)

	_clear(_profile_box)
	var profile: Dictionary = DemandManager.customer_profile(rest.building_id)
	for col: Array in PROFILE_COLS:
		var cell: VBoxContainer = VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_theme_constant_override("separation", 1)
		var icon: TextureRect = _assets.icon_rect(col[1], 24)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(icon)
		var pct: Label = Label.new()
		pct.text = "%d%%" % int(roundf(float(profile.get(col[0], 0.0)) * 100.0))
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pct.add_theme_font_size_override("font_size", 13)
		cell.add_child(pct)
		var cap: Label = Label.new()
		cap.text = String(col[2])
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_size_override("font_size", 10)
		cap.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		cell.add_child(cap)
		_profile_box.add_child(cell)

	_clear(_biz_grid)
	var rents: Dictionary = EconomyManager.tuning_value("rent.daily_by_district", {})
	var guests: int = int(rest.today.get("guests", 0))
	var traffic: String = "Low"
	if guests >= 18 or rest.district in ["D", "C"]:
		traffic = "High"
	elif guests >= 8 or rest.district in ["N", "I"]:
		traffic = "Medium"
	var sales: float = float(rest.today.get("sales", 0.0))
	var expenses: float = float(rest.today.get("expenses", 0.0))
	if rest.owned_outright:
		_biz_row(&"rent", "Rent", "Owned — none", TycoonTheme.PALETTE["good"])
	else:
		_biz_row(&"rent", "Rent", "$%s/day" % TycoonHud._fmt(float(rents.get(rest.district, 120.0))), TycoonTheme.PALETTE["text"])
	_biz_row(&"traffic", "Traffic", traffic, TycoonTheme.PALETTE["good"] if traffic == "High" else TycoonTheme.PALETTE["text"])
	_biz_row(&"banknotes", "Sales Today", "$%s" % TycoonHud._fmt(sales), TycoonTheme.PALETTE["text"])
	_biz_row(&"chart_up", "Profit Today", "$%s" % TycoonHud._fmt(sales - expenses),
		TycoonTheme.PALETTE["good"] if sales - expenses >= 0.0 else TycoonTheme.PALETTE["bad"])
	_biz_row(&"people", "Guests / Tables", "%d  ·  %d/%d" % [guests, rest.tables_occupied, rest.table_count], TycoonTheme.PALETTE["text"])
	_biz_row(&"scooter", "Deliveries", "%d active · %d cancelled" % [
		rest.active_deliveries, int(rest.today.get("cancelled", 0))], TycoonTheme.PALETTE["text"])
	_spark.set_values(rest.sales_history)


func _biz_row(icon_name: StringName, label_text: String, value_text: String, value_color: Color) -> void:
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 5)
	name_row.add_child(_assets.icon_rect(icon_name, 15))
	var name_label: Label = Label.new()
	name_label.text = label_text
	name_label.add_theme_font_size_override("font_size", 13)
	name_row.add_child(name_label)
	_biz_grid.add_child(name_row)
	var value_label: Label = Label.new()
	value_label.text = value_text
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.add_theme_font_size_override("font_size", 13)
	value_label.add_theme_color_override("font_color", value_color)
	_biz_grid.add_child(value_label)


func _render_operations(rest: RestaurantState) -> void:
	_set_overview_visible(false)
	_content.visible = true
	var snapshot: Dictionary = RestaurantManager.operations_snapshot(rest.building_id)
	if snapshot.is_empty():
		return
	var bottleneck: Dictionary = snapshot["bottleneck"]
	var severity: String = String(bottleneck.get("severity", "good"))
	_content_panel.add_theme_stylebox_override("panel", TycoonTheme.status_box(severity))
	var severity_icon: String = "✓"
	if severity == "warning":
		severity_icon = "!"
	elif severity == "critical":
		severity_icon = "⚠"
	elif severity == "info":
		severity_icon = "i"
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[font_size=16][b]%s %s[/b][/font_size]" % [severity_icon, bottleneck.get("title", "Operations")])
	lines.append("[color=#6b421c]%s[/color]" % bottleneck.get("evidence", ""))
	lines.append("")
	lines.append("[b]DINING ROOM[/b]  Tables %d/%d  ·  Waiting %d" % [
		snapshot["tables_occupied"], snapshot["table_count"], snapshot["dine_queue"].size()])
	if int(snapshot["oldest_queue_wait"]) > 0:
		lines.append("Oldest table wait: [b]%d min[/b]" % snapshot["oldest_queue_wait"])
	lines.append("")
	lines.append("[b]KITCHEN[/b]  Cooking %d/%d  ·  Backlog %d" % [
		snapshot["cooking"].size(), snapshot["cook_slots"], snapshot["cook_backlog"]])
	if snapshot["cooking"].is_empty():
		lines.append("No dishes cooking right now.")
	else:
		for row: Dictionary in snapshot["cooking"].slice(0, 4):
			lines.append("• %s — %s · %.0f min" % [row["dish"], row["cook_name"], row["minutes_left"]])
	lines.append("")
	lines.append("[b]DELIVERIES[/b]  Active %d/%d  ·  Ready %d" % [
		snapshot["active_deliveries"], snapshot["delivery_cap"], snapshot["ready_deliveries"]])
	for driver: Dictionary in snapshot["drivers"].slice(0, 3):
		var shift_text: String = "off shift" if not driver["on_shift"] else String(driver["status"])
		lines.append("• %s — %s" % [driver["name"], shift_text])
	lines.append("")
	var inbound: Array = snapshot["inbound_citizens"]
	lines.append("[b]ON THE WAY[/b]  %d citizens" % inbound.size())
	for intent: Dictionary in inbound.slice(0, 3):
		lines.append("• %s wants %s — %s" % [
			intent["name"], String(intent["dish_id"]).replace("_", " "), intent["goal"]])
	_content.text = "\n".join(lines)
	_bottleneck_screen = bottleneck.get("screen", &"")
	var action_text: String = String(bottleneck.get("action", ""))
	_bottleneck_action.visible = not action_text.is_empty() and not _bottleneck_screen.is_empty()
	_bottleneck_action.text = "→ " + action_text


func _district_name(code: String) -> String:
	var names: Dictionary = {
		"D": "Downtown", "C": "Commercial", "I": "Industrial",
		"R": "Rich Suburb", "N": "Suburb", "P": "Old Town", "K": "Park", "G": "Park",
	}
	return String(names.get(code, code))


func _rebuild_selector() -> void:
	_selector.clear()
	for rest: RestaurantState in RestaurantManager.owned:
		_selector.add_item(rest.restaurant_name)
		_selector.set_item_metadata(_selector.item_count - 1, rest.building_id)
	_selector.visible = _selector.item_count > 1
	if selected_building_id < 0 and _selector.item_count > 0:
		selected_building_id = _selector.get_item_metadata(0)
	_sync_selector()
	refresh()


func _sync_selector() -> void:
	for index: int in _selector.item_count:
		if int(_selector.get_item_metadata(index)) == selected_building_id:
			_selector.select(index)
			return


func _on_selector_changed(index: int) -> void:
	selected_building_id = _selector.get_item_metadata(index)
	refresh()


func _on_entity_selected(info: Dictionary, _entity: Node) -> void:
	if String(info.get("kind", "")) != "building":
		return
	var building_id: int = int(info.get("id", -1))
	if not RestaurantManager.by_building.has(building_id):
		return
	selected_building_id = building_id
	_show_operations = true
	_sync_selector()
	refresh()


func _on_bottleneck_action() -> void:
	if not _bottleneck_screen.is_empty():
		action_pressed.emit(_bottleneck_screen, selected_building_id)


func _on_purchased(_rest: RestaurantState) -> void:
	_rebuild_selector()


func _on_updated(building_id: int) -> void:
	if building_id == selected_building_id:
		refresh()


func _on_intent_changed(_citizen_id: int, restaurant_id: int, _active: bool) -> void:
	if restaurant_id == selected_building_id and _show_operations:
		refresh()
