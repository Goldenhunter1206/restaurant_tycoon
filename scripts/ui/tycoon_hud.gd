class_name TycoonHud
extends Control
## Root of the tycoon management UI: top bar (company, cash, profit, date,
## speed), right restaurant panel, bottom bar (bank, reputation, messages,
## today's summary, navigation), and the modal sub-screen manager.
## Built entirely in code on the procedural TycoonTheme.

const MAX_MESSAGES: int = 30

var restaurant_panel: RestaurantPanel
var screens: SubScreenManager
var inspector: InspectorPanel

var _cash_label: Label
var _profit_label: Label
var _date_label: Label
var _clock_label: Label
var _bank_label: Label
var _reputation_label: Label
var _summary_label: Label
var _deliveries_label: Label
var _company_label: Label
var _messages: RichTextLabel
var _speed_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = TycoonTheme.build()

	_build_top_bar()
	_build_right_panel()
	_build_bottom_bar()

	var left_panels: VBoxContainer = VBoxContainer.new()
	left_panels.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_panels.offset_left = 12.0
	left_panels.offset_top = 64.0
	left_panels.add_theme_constant_override("separation", 8)
	add_child(left_panels)
	left_panels.add_child(ObjectivesPanel.new())
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
	bar.offset_right = -332.0
	bar.offset_top = 8.0
	bar.offset_bottom = 56.0
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)

	_company_label = _chip(bar, "🍕 …", 20)
	_cash_label = _chip(bar, "💵 $0")
	_profit_label = _chip(bar, "📈 +$0")
	_date_label = _chip(bar, "📅 Day 1, Q1")

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var speed_panel: PanelContainer = PanelContainer.new()
	var speed_box: HBoxContainer = HBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 4)
	speed_panel.add_child(speed_box)
	for entry: Array in [["⏸", 0], ["▶", 1], ["⏩", 4], ["⏭", 16]]:
		var btn: Button = Button.new()
		btn.text = entry[0]
		btn.toggle_mode = true
		btn.pressed.connect(func() -> void: GameClock.set_speed(entry[1]))
		speed_box.add_child(btn)
		_speed_buttons[entry[1]] = btn
	bar.add_child(speed_panel)
	_on_speed_changed(GameClock.speed)

	var save_btn: Button = Button.new()
	save_btn.text = "💾"
	save_btn.tooltip_text = "Save game"
	save_btn.pressed.connect(func() -> void: SaveSystem.save_game())
	bar.add_child(save_btn)


func _build_right_panel() -> void:
	restaurant_panel = RestaurantPanel.new()
	restaurant_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	restaurant_panel.offset_left = -320.0
	restaurant_panel.offset_right = -8.0
	restaurant_panel.offset_top = 8.0
	restaurant_panel.offset_bottom = -172.0
	restaurant_panel.action_pressed.connect(_on_action)
	add_child(restaurant_panel)


func _build_bottom_bar() -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -164.0
	bar.offset_left = 12.0
	bar.offset_right = -12.0
	bar.offset_bottom = -8.0
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)

	# Bank + reputation column.
	var money_panel: PanelContainer = PanelContainer.new()
	var money_box: VBoxContainer = VBoxContainer.new()
	money_panel.add_child(money_box)
	_bank_label = Label.new()
	money_box.add_child(_bank_label)
	_reputation_label = Label.new()
	_reputation_label.add_theme_color_override("font_color", Color("#f2b01e"))
	money_box.add_child(_reputation_label)
	_deliveries_label = Label.new()
	money_box.add_child(_deliveries_label)
	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 19)
	money_box.add_child(_clock_label)
	bar.add_child(money_panel)

	# Messages feed.
	var feed_panel: PanelContainer = PanelContainer.new()
	feed_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var feed_box: VBoxContainer = VBoxContainer.new()
	feed_panel.add_child(feed_box)
	var feed_title: Label = Label.new()
	feed_title.text = "📨 Messages"
	feed_box.add_child(feed_title)
	_messages = RichTextLabel.new()
	_messages.bbcode_enabled = true
	_messages.scroll_following = true
	_messages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed_box.add_child(_messages)
	bar.add_child(feed_panel)

	# Today's summary.
	var summary_panel: PanelContainer = PanelContainer.new()
	summary_panel.custom_minimum_size.x = 190
	var summary_box: VBoxContainer = VBoxContainer.new()
	summary_panel.add_child(summary_box)
	var summary_title: Label = Label.new()
	summary_title.text = "TODAY'S SUMMARY"
	summary_box.add_child(summary_title)
	_summary_label = Label.new()
	summary_box.add_child(_summary_label)
	bar.add_child(summary_panel)

	# Navigation buttons.
	var nav_panel: PanelContainer = PanelContainer.new()
	var nav_grid: GridContainer = GridContainer.new()
	nav_grid.columns = 2
	nav_grid.add_theme_constant_override("h_separation", 6)
	nav_grid.add_theme_constant_override("v_separation", 6)
	nav_panel.add_child(nav_grid)
	for entry: Array in [
		["🏛 Restaurants", &"build"], ["👥 Staff", &"staff"],
		["🍕 Recipes", &"recipes"], ["💵 Finances", &"finances"],
		["🛵 Deliveries", &"deliveries"], ["🏆 Rankings", &"rankings"],
	]:
		var btn: Button = Button.new()
		btn.text = entry[0]
		btn.pressed.connect(func() -> void: _on_action(entry[1], _selected_building()))
		nav_grid.add_child(btn)
	bar.add_child(nav_panel)


func _chip(parent: Control, text: String, font_size: int = 15) -> Label:
	var panel: PanelContainer = PanelContainer.new()
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	panel.add_child(label)
	parent.add_child(panel)
	return label


# --- Signal handlers ----------------------------------------------------------


func _on_action(screen_id: StringName, building_id: int) -> void:
	screens.open(screen_id, building_id)


func _selected_building() -> int:
	return restaurant_panel.selected_building_id


func _on_minute(_day: int, _hour: int, _minute: int) -> void:
	_refresh_static()
	if screens.is_open():
		screens.refresh_active()


func _on_cash_changed(cash: float) -> void:
	_cash_label.text = "💵 $%s" % _fmt(cash)


func _on_speed_changed(speed: int) -> void:
	for value: int in _speed_buttons:
		(_speed_buttons[value] as Button).set_pressed_no_signal(value == speed)


func _on_message(kind: String, text: String) -> void:
	var color: String = "#4a3318"
	match kind:
		"good":
			color = "#2e7d32"
		"alert":
			color = "#c0392b"
	_messages.append_text("[color=%s]• Day %d %s: %s[/color]\n" % [
		color, GameClock.day, GameClock.time_string(), text])
	if _messages.get_paragraph_count() > MAX_MESSAGES:
		_messages.remove_paragraph(0)


func _on_deliveries_changed(count: int) -> void:
	_deliveries_label.text = "🛵 Active deliveries: %d" % count


func _on_bankrupt() -> void:
	GameClock.set_speed(0)
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Bankrupt!"
	dialog.dialog_text = "The bank has called in its loans. %s is bankrupt." % EconomyManager.company_name
	add_child(dialog)
	dialog.popup_centered()


func _refresh_static() -> void:
	_company_label.text = "🍕 %s" % EconomyManager.company_name
	_on_cash_changed(EconomyManager.cash)
	var profit: float = EconomyManager.profit_today()
	_profit_label.text = "%s %s$%s" % [
		"📈" if profit >= 0.0 else "📉",
		"+" if profit >= 0.0 else "−", _fmt(absf(profit))]
	var quarter: int = ((GameClock.day - 1) / 90) % 4 + 1
	_date_label.text = "📅 Day %d · Q%d" % [GameClock.day, quarter]
	_clock_label.text = "🕐 %s" % GameClock.time_string()
	_bank_label.text = "🏦 Loan: $%s" % _fmt(EconomyManager.loan)
	_reputation_label.text = "%s %.1f / 5.0" % [
		TycoonTheme.stars_text(EconomyManager.reputation), EconomyManager.reputation]
	_summary_label.text = "Sales      $%s\nExpenses   −$%s\nProfit     $%s" % [
		_fmt(EconomyManager.income_today()),
		_fmt(absf(EconomyManager.expenses_today())),
		_fmt(profit)]
	if _deliveries_label.text.is_empty():
		_on_deliveries_changed(0)
	restaurant_panel.refresh()


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
