class_name TycoonHud
extends Control
## Root of the tycoon management UI: top bar (company badge, cash, profit,
## date, quarter, speed), right restaurant panel, bottom bar (bank, reputation,
## messages/news, today's summary, navigation tabs), and the modal sub-screen
## manager. Built entirely in code on the texture-skinned TycoonTheme.

const MAX_MESSAGES: int = 30

var restaurant_panel: RestaurantPanel
var screens: SubScreenManager
var inspector: InspectorPanel
var insight_overlay: WorldInsightOverlay

var _assets: GDScript = load("res://scripts/ui/ui_assets.gd")
var _cash_label: Label
var _profit_label: Label
var _profit_icon: TextureRect
var _date_label: Label
var _quarter_label: Label
var _level_label: Label
var _clock_label: Label
var _bank_cash_label: Label
var _bank_loan_label: Label
var _rep_row: HBoxContainer
var _summary_grid: GridContainer
var _deliveries_box: HBoxContainer
var _company_label: Label
var _messages: RichTextLabel
var _feed_entries: Array[Dictionary] = []
var _feed_mode: String = "messages"
var _feed_tabs: Dictionary = {}
var _speed_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = TycoonTheme.build()

	insight_overlay = WorldInsightOverlay.new()
	add_child(insight_overlay)
	move_child(insight_overlay, 0)

	_build_top_bar()
	_build_right_panel()
	_build_bottom_bar()
	_build_right_status()

	var left_panels: VBoxContainer = VBoxContainer.new()
	left_panels.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_panels.offset_left = 14.0
	left_panels.offset_top = 76.0
	left_panels.add_theme_constant_override("separation", 8)
	add_child(left_panels)
	left_panels.add_child(ObjectivesPanel.new())
	var events_script: GDScript = load("res://scripts/ui/events_panel.gd")
	left_panels.add_child(events_script.new())
	var insights_button: Button = Button.new()
	insights_button.text = "CITY INSIGHTS"
	_assets.icon_button(insights_button, &"magnifier", 18)
	insights_button.toggle_mode = true
	insights_button.tooltip_text = "Show who is heading to your restaurants and what selected citizens are thinking"
	insights_button.toggled.connect(insight_overlay.set_insights_enabled)
	left_panels.add_child(insights_button)
	inspector = InspectorPanel.new()
	inspector.manage_requested.connect(func(building_id: int) -> void:
		restaurant_panel.selected_building_id = building_id
		restaurant_panel.refresh())
	left_panels.add_child(inspector)

	screens = SubScreenManager.new()
	add_child(screens)

	GameClock.minute_ticked.connect(_on_minute)
	GameClock.speed_changed.connect(_on_speed_changed)
	EconomyManager.cash_changed.connect(_on_cash_changed)
	EconomyManager.reputation_changed.connect(func(_r: float) -> void: _refresh_static())
	EconomyManager.message_posted.connect(_on_message)
	EconomyManager.bankrupt.connect(_on_bankrupt)
	DeliveryManager.active_count_changed.connect(_on_deliveries_changed)
	_refresh_static.call_deferred()


# --- Layout builders ---------------------------------------------------------


func _build_top_bar() -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 12.0
	bar.offset_right = -410.0
	bar.offset_top = 10.0
	bar.offset_bottom = 68.0
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)

	var logo: TextureRect = TextureRect.new()
	var logo_tex: Texture2D = load("res://assets/ui/logo_badge.png") if ResourceLoader.exists("res://assets/ui/logo_badge.png") else load("res://assets/ui/pizza_delivery_badge.png")
	logo.texture = logo_tex
	logo.custom_minimum_size = Vector2(54, 54)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(logo)

	var company_chip: HBoxContainer = _chip(bar)
	_company_label = _chip_label(company_chip, "…", 20)
	var level_icon: TextureRect = _assets.icon_rect(&"star", 18)
	company_chip.add_child(level_icon)
	_level_label = _chip_label(company_chip, "1", 15)
	_level_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["accent_gold"])

	var cash_chip: HBoxContainer = _chip(bar)
	cash_chip.add_child(_assets.icon_rect(&"banknotes", 20))
	_cash_label = _chip_label(cash_chip, "$0", 17)

	var profit_chip: HBoxContainer = _chip(bar)
	_profit_icon = _assets.icon_rect(&"chart_up", 20)
	profit_chip.add_child(_profit_icon)
	_profit_label = _chip_label(profit_chip, "+$0", 16)

	var date_chip: HBoxContainer = _chip(bar)
	date_chip.add_child(_assets.icon_rect(&"calendar", 20))
	_date_label = _chip_label(date_chip, "Jan 1, Year 1", 15)

	var quarter_chip: HBoxContainer = _chip(bar)
	_quarter_label = _chip_label(quarter_chip, "Q1", 17)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var speed_box: HBoxContainer = HBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 5)
	for entry: Array in [
		["⏸", 0, &"pause", "Pause"], ["▶", 1, &"play", "Normal speed"],
		["⏩", 4, &"fast", "Fast (4x)"], ["⏭", 16, &"fastest", "Ultra (16x)"],
	]:
		var btn: Button = Button.new()
		if _assets.icon(entry[2]) != null:
			_assets.icon_button(btn, entry[2], 22)
		else:
			btn.text = entry[0]
		btn.tooltip_text = entry[3]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(46, 42)
		TycoonTheme.apply_orange(btn)
		btn.pressed.connect(func() -> void: GameClock.set_speed(entry[1]))
		speed_box.add_child(btn)
		_speed_buttons[entry[1]] = btn
	bar.add_child(speed_box)
	_on_speed_changed(GameClock.speed)


func _build_right_panel() -> void:
	restaurant_panel = RestaurantPanel.new()
	restaurant_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	restaurant_panel.offset_left = -398.0
	restaurant_panel.offset_right = -10.0
	restaurant_panel.offset_top = 10.0
	restaurant_panel.offset_bottom = -190.0
	restaurant_panel.action_pressed.connect(_on_action)
	add_child(restaurant_panel)


func _build_bottom_bar() -> void:
	var info_frame: PanelContainer = PanelContainer.new()
	info_frame.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	info_frame.offset_top = -226.0
	info_frame.offset_left = 0.0
	info_frame.offset_right = -402.0
	info_frame.offset_bottom = -94.0
	info_frame.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
	add_child(info_frame)
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	info_frame.add_child(bar)

	# Money + reputation cluster.
	var money_panel: PanelContainer = PanelContainer.new()
	money_panel.custom_minimum_size.x = 250.0
	money_panel.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	var money_box: VBoxContainer = VBoxContainer.new()
	money_box.add_theme_constant_override("separation", 2)
	money_panel.add_child(money_box)
	var cash_row: HBoxContainer = HBoxContainer.new()
	cash_row.add_theme_constant_override("separation", 8)
	money_box.add_child(cash_row)
	cash_row.add_child(_assets.icon_rect(&"money_bag", 30))
	_bank_cash_label = Label.new()
	_bank_cash_label.add_theme_font_size_override("font_size", 20)
	cash_row.add_child(_bank_cash_label)
	_bank_loan_label = Label.new()
	_bank_loan_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	money_box.add_child(_bank_loan_label)
	var rep_title_row: HBoxContainer = HBoxContainer.new()
	rep_title_row.add_theme_constant_override("separation", 6)
	money_box.add_child(rep_title_row)
	rep_title_row.add_child(_assets.icon_rect(&"trophy", 17))
	var reputation_title: Label = Label.new()
	reputation_title.text = "REPUTATION"
	reputation_title.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL + 1)
	reputation_title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	rep_title_row.add_child(reputation_title)
	_rep_row = HBoxContainer.new()
	_rep_row.add_theme_constant_override("separation", 6)
	money_box.add_child(_rep_row)
	bar.add_child(money_panel)

	# Messages / news feed.
	var feed_panel: PanelContainer = PanelContainer.new()
	feed_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_panel.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	var feed_box: VBoxContainer = VBoxContainer.new()
	feed_box.add_theme_constant_override("separation", 2)
	feed_panel.add_child(feed_box)
	var tab_row: HBoxContainer = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	feed_box.add_child(tab_row)
	for mode: Array in [["messages", "MESSAGES"], ["news", "NEWS"]]:
		var tab: Button = Button.new()
		tab.text = mode[1]
		tab.toggle_mode = true
		tab.add_theme_font_size_override("font_size", 13)
		tab.pressed.connect(func() -> void: _set_feed_mode(mode[0]))
		tab_row.add_child(tab)
		_feed_tabs[mode[0]] = tab
	_messages = RichTextLabel.new()
	_messages.bbcode_enabled = true
	_messages.scroll_following = true
	_messages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed_box.add_child(_messages)
	bar.add_child(feed_panel)
	_update_feed_tabs()

	# Today's summary.
	var summary_panel: PanelContainer = PanelContainer.new()
	summary_panel.custom_minimum_size.x = 240.0
	summary_panel.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	var summary_box: VBoxContainer = VBoxContainer.new()
	summary_box.add_theme_constant_override("separation", 3)
	summary_panel.add_child(summary_box)
	var summary_title: Label = Label.new()
	summary_title.text = "TODAY'S SUMMARY"
	summary_title.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL + 1)
	summary_title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	summary_box.add_child(summary_title)
	_summary_grid = GridContainer.new()
	_summary_grid.columns = 2
	_summary_grid.add_theme_constant_override("h_separation", 24)
	_summary_grid.add_theme_constant_override("v_separation", 2)
	summary_box.add_child(_summary_grid)
	bar.add_child(summary_panel)

	# Navigation tabs.
	var nav_frame: PanelContainer = PanelContainer.new()
	nav_frame.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	nav_frame.offset_top = -88.0
	nav_frame.offset_left = 0.0
	nav_frame.offset_right = -402.0
	nav_frame.offset_bottom = 0.0
	nav_frame.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
	add_child(nav_frame)
	var nav: HBoxContainer = HBoxContainer.new()
	nav.add_theme_constant_override("separation", 7)
	nav_frame.add_child(nav)

	var menu_btn: Button = Button.new()
	menu_btn.text = "☰"
	_assets.icon_button(menu_btn, &"menu", 22)
	if menu_btn.icon != null:
		menu_btn.text = ""
	menu_btn.tooltip_text = "Save game"
	menu_btn.custom_minimum_size = Vector2(56, 58)
	menu_btn.pressed.connect(func() -> void: SaveSystem.save_game())
	nav.add_child(menu_btn)

	for entry: Array in [
		["CITY MAP", &"__city_map", &"city_map", true],
		["RESTAURANTS", &"build", &"store", false],
		["STAFF", &"staff", &"people", false],
		["RECIPES", &"recipes", &"pizza", false],
		["FINANCES", &"finances", &"coin", false],
		["RANKINGS", &"rankings", &"trophy", false],
	]:
		var btn: Button = Button.new()
		btn.text = entry[0]
		_assets.icon_button(btn, entry[2], 22)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size.y = 58.0
		btn.add_theme_font_size_override("font_size", 14)
		var active: bool = entry[3]
		btn.add_theme_stylebox_override("normal", TycoonTheme.nav_tab_box(active))
		btn.add_theme_stylebox_override("hover", TycoonTheme.nav_tab_box(true) if not active else TycoonTheme.nav_tab_box(true))
		btn.add_theme_stylebox_override("pressed", TycoonTheme.nav_tab_box(true))
		if active:
			btn.add_theme_color_override("font_color", Color("#fff6e0"))
		var screen_id: StringName = entry[1]
		btn.pressed.connect(func() -> void:
			if screen_id == &"__city_map":
				screens.close_active()
			else:
				_on_action(screen_id, _selected_building()))
		var anim: GDScript = load("res://scripts/ui/ui_anim.gd")
		anim.hover_pop(btn, 1.04)
		nav.add_child(btn)


func _build_right_status() -> void:
	var frame: PanelContainer = PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	frame.offset_left = -398.0
	frame.offset_right = -10.0
	frame.offset_top = -180.0
	frame.offset_bottom = -10.0
	frame.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
	add_child(frame)
	var inner: PanelContainer = PanelContainer.new()
	inner.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	frame.add_child(inner)
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	inner.add_child(box)
	var active_title: Label = Label.new()
	active_title.text = "ACTIVE DELIVERIES"
	active_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	active_title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	box.add_child(active_title)
	_deliveries_box = HBoxContainer.new()
	_deliveries_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_deliveries_box.add_theme_constant_override("separation", 12)
	box.add_child(_deliveries_box)
	var clock_row: HBoxContainer = HBoxContainer.new()
	clock_row.alignment = BoxContainer.ALIGNMENT_CENTER
	clock_row.add_theme_constant_override("separation", 8)
	box.add_child(clock_row)
	clock_row.add_child(_assets.icon_rect(&"clock", 24))
	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 23)
	clock_row.add_child(_clock_label)


func _chip(parent: Control) -> HBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", TycoonTheme.chip_box())
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	parent.add_child(panel)
	return row


func _chip_label(chip_row: HBoxContainer, text: String, font_size: int = 15) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	chip_row.add_child(label)
	return label


# --- Signal handlers ----------------------------------------------------------


func _on_action(screen_id: StringName, building_id: int) -> void:
	if screen_id == &"interior":
		_open_interior(building_id)
		return
	screens.open(screen_id, building_id)


func _open_interior(building_id: int) -> void:
	if not RestaurantManager.by_building.has(building_id):
		return
	var parent: Node = get_parent()
	if parent.get_node_or_null("InteriorViewer") != null:
		return
	screens.close()
	var viewer_script: GDScript = load("res://scripts/ui/interior_viewer.gd")
	var viewer: Control = viewer_script.new()
	viewer.name = "InteriorViewer"
	viewer.hud = self
	parent.add_child(viewer)
	viewer.setup(building_id)


func _selected_building() -> int:
	return restaurant_panel.selected_building_id


func _on_minute(_day: int, _hour: int, _minute: int) -> void:
	_refresh_static()
	if screens.is_open():
		screens.refresh_active()


func _on_cash_changed(cash: float) -> void:
	_cash_label.text = "$%s" % _fmt(cash)
	if _bank_cash_label != null:
		_bank_cash_label.text = "$%s" % _fmt(cash)


func _on_speed_changed(speed: int) -> void:
	for value: int in _speed_buttons:
		(_speed_buttons[value] as Button).set_pressed_no_signal(value == speed)


func _set_feed_mode(mode: String) -> void:
	_feed_mode = mode
	_update_feed_tabs()
	_render_feed()


func _update_feed_tabs() -> void:
	for mode: String in _feed_tabs:
		var tab: Button = _feed_tabs[mode]
		tab.set_pressed_no_signal(mode == _feed_mode)
		var active_box: StyleBox = TycoonTheme.nav_tab_box(mode == _feed_mode)
		tab.add_theme_stylebox_override("normal", active_box)
		if mode == _feed_mode:
			tab.add_theme_color_override("font_color", Color("#fff6e0"))
		else:
			tab.remove_theme_color_override("font_color")


func _on_message(kind: String, text: String) -> void:
	_feed_entries.append({
		"kind": kind, "text": text,
		"day": GameClock.day, "time": GameClock.time_string(),
	})
	if _feed_entries.size() > MAX_MESSAGES:
		_feed_entries.pop_front()
	_render_feed()


func _render_feed() -> void:
	_messages.clear()
	for entry: Dictionary in _feed_entries:
		var kind: String = String(entry["kind"])
		if _feed_mode == "news" and kind == "alert":
			continue
		var color: String = "#4a3318"
		var dot_color: String = "#3f83a5"
		match kind:
			"good":
				color = "#2e7d32"
				dot_color = "#3f9b45"
			"alert":
				color = "#c0392b"
				dot_color = "#d8452e"
		_messages.append_text("[color=%s]●[/color] [color=%s]Day %d %s: %s[/color]\n" % [
			dot_color, color, int(entry["day"]), String(entry["time"]), String(entry["text"])])


func _on_deliveries_changed(_count: int) -> void:
	_render_deliveries()


func _render_deliveries() -> void:
	for child: Node in _deliveries_box.get_children():
		child.queue_free()
	var breakdown: Dictionary = DeliveryManager.active_breakdown()
	var shown: Array[Array] = [
		[&"scooter", &"scooter"], [&"car", &"truck"], [&"walker", &"walker"],
	]
	for pair: Array in shown:
		var count: int = int(breakdown.get(pair[0], 0))
		var cell: HBoxContainer = HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.add_child(_assets.icon_rect(pair[1], 24))
		var count_label: Label = Label.new()
		count_label.text = str(count)
		count_label.add_theme_font_size_override("font_size", 18)
		if count == 0:
			count_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		cell.add_child(count_label)
		_deliveries_box.add_child(cell)


func _on_bankrupt() -> void:
	GameClock.set_speed(0)
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Bankrupt!"
	dialog.dialog_text = "The bank has called in its loans. %s is bankrupt." % EconomyManager.company_name
	add_child(dialog)
	dialog.popup_centered()


func _refresh_static() -> void:
	_company_label.text = EconomyManager.company_name
	_level_label.text = str(maxi(1, RestaurantManager.owned.size()))
	_on_cash_changed(EconomyManager.cash)
	var profit: float = EconomyManager.profit_today()
	_profit_label.text = "%s$%s" % ["+" if profit >= 0.0 else "−", _fmt(absf(profit))]
	_profit_label.add_theme_color_override(
		"font_color", TycoonTheme.PALETTE["good"] if profit >= 0.0 else TycoonTheme.PALETTE["bad"])
	if _profit_icon != null:
		_profit_icon.modulate = Color.WHITE if profit >= 0.0 else Color(1.0, 0.55, 0.5)
	_date_label.text = GameClock.date_string()
	_quarter_label.text = "Q%d" % GameClock.quarter()
	_clock_label.text = GameClock.time_string_ampm()
	_bank_loan_label.text = "Bank Loan   $%s" % _fmt(EconomyManager.loan)
	_render_reputation()
	_render_summary(profit)
	if _deliveries_box.get_child_count() == 0:
		_render_deliveries()
	restaurant_panel.refresh()


func _render_reputation() -> void:
	for child: Node in _rep_row.get_children():
		child.queue_free()
	var stars: HBoxContainer = TycoonTheme.star_row(EconomyManager.reputation, 17)
	_rep_row.add_child(stars)
	var value: Label = Label.new()
	value.text = "%.1f / 5.0" % EconomyManager.reputation
	value.add_theme_color_override("font_color", Color("#e49a16"))
	_rep_row.add_child(value)


func _render_summary(profit: float) -> void:
	for child: Node in _summary_grid.get_children():
		child.queue_free()
	var rows: Array[Array] = [
		["Sales", EconomyManager.income_today(), TycoonTheme.PALETTE["text"]],
		["Expenses", EconomyManager.expenses_today(), TycoonTheme.PALETTE["bad"]],
		["Profit", profit, TycoonTheme.PALETTE["good"] if profit >= 0.0 else TycoonTheme.PALETTE["bad"]],
	]
	for row: Array in rows:
		var name_label: Label = Label.new()
		name_label.text = row[0]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_summary_grid.add_child(name_label)
		var amount: float = row[1]
		var value_label: Label = Label.new()
		var sign_str: String = "−" if amount < 0.0 else ""
		value_label.text = "%s$%s" % [sign_str, _fmt(absf(amount))]
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_color_override("font_color", row[2])
		_summary_grid.add_child(value_label)


static func _fmt(value: float) -> String:
	## 254718 -> "254,718"
	var raw: String = "%.0f" % absf(value)
	var out: String = ""
	var count: int = 0
	for i: int in range(raw.length() - 1, -1, -1):
		out = raw[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
