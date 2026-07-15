extends TycoonScreen
## Delivery + dine-in channel settings: toggles, max concurrent delivery
## orders, opening hours.

var _dine_toggle: CheckButton
var _delivery_toggle: CheckButton
var _cap: SpinBox
var _open_hour: SpinBox
var _close_hour: SpinBox
var _status: Label


func screen_title() -> String:
	return "Service & Deliveries"


func screen_icon() -> StringName:
	return &"scooter"


func _build() -> void:
	add_section("Sales channels")
	_dine_toggle = CheckButton.new()
	_dine_toggle.text = "🍽 Dine-in service (needs waiters + cooks)"
	_dine_toggle.toggled.connect(func(_on: bool) -> void: _apply())
	_content.add_child(_dine_toggle)
	_delivery_toggle = CheckButton.new()
	_delivery_toggle.text = "🛵 Online delivery orders (needs drivers + cooks)"
	_delivery_toggle.toggled.connect(func(_on: bool) -> void: _apply())
	_content.add_child(_delivery_toggle)

	var cap_bar: HBoxContainer = HBoxContainer.new()
	var cap_label: Label = Label.new()
	cap_label.text = "Max simultaneous delivery orders:"
	cap_bar.add_child(cap_label)
	_cap = SpinBox.new()
	_cap.min_value = 0
	_cap.max_value = 30
	_cap.value_changed.connect(func(_value: float) -> void: _apply())
	cap_bar.add_child(_cap)
	_content.add_child(cap_bar)

	add_section("Opening hours")
	var hours_bar: HBoxContainer = HBoxContainer.new()
	hours_bar.add_theme_constant_override("separation", 8)
	var open_label: Label = Label.new()
	open_label.text = "Open from"
	hours_bar.add_child(open_label)
	_open_hour = SpinBox.new()
	_open_hour.min_value = 0
	_open_hour.max_value = 23
	_open_hour.suffix = ":00"
	_open_hour.value_changed.connect(func(_value: float) -> void: _apply())
	hours_bar.add_child(_open_hour)
	var to_label: Label = Label.new()
	to_label.text = "until"
	hours_bar.add_child(to_label)
	_close_hour = SpinBox.new()
	_close_hour.min_value = 0
	_close_hour.max_value = 23
	_close_hour.suffix = ":00"
	_close_hour.value_changed.connect(func(_value: float) -> void: _apply())
	hours_bar.add_child(_close_hour)
	_content.add_child(hours_bar)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status)


func refresh() -> void:
	var rest: RestaurantState = restaurant()
	if rest == null:
		return
	_dine_toggle.set_pressed_no_signal(rest.dine_in_enabled)
	_delivery_toggle.set_pressed_no_signal(rest.delivery_enabled)
	_cap.set_value_no_signal(rest.delivery_cap)
	_open_hour.set_value_no_signal(rest.open_hour)
	_close_hour.set_value_no_signal(rest.close_hour)
	var hourf: float = GameClock.game_hours
	_status.text = "Right now: %d cooks, %d waiters, %d drivers on shift. %d/%d tables busy, %d active deliveries." % [
		rest.staff_on_shift(&"cook", hourf),
		rest.staff_on_shift(&"waiter", hourf),
		rest.staff_on_shift(&"driver", hourf),
		rest.tables_occupied, rest.table_count,
		rest.active_deliveries,
	]


func _apply() -> void:
	var router := get_node_or_null("/root/BranchCommandRouter")
	if router == null or CompanyManager.player == null:
		_status.text = "The branch command router is unavailable."
		return
	var actor := {"kind": &"player", "id": "delivery_workspace", "company_id": CompanyManager.player.id}
	var stamp := "%d:%d" % [GameClock.total_minutes(), building_id]
	var results: Array[CommandResult] = []
	results.append(router.call("execute", &"restaurant.set_channels", {
		"building_id": building_id,
		"dine_in": _dine_toggle.button_pressed,
		"delivery": _delivery_toggle.button_pressed,
	}, actor, "ui:channels:%s" % stamp) as CommandResult)
	results.append(router.call("execute", &"delivery.set_cap", {
		"building_id": building_id,
		"cap": int(_cap.value),
	}, actor, "ui:delivery_cap:%s" % stamp) as CommandResult)
	results.append(router.call("execute", &"restaurant.set_hours", {
		"building_id": building_id,
		"open_hour": _open_hour.value,
		"close_hour": _close_hour.value,
	}, actor, "ui:hours:%s" % stamp) as CommandResult)
	for result: CommandResult in results:
		if result == null or not result.ok:
			_status.text = result.message if result != null else "A delivery command was unavailable."
			return
	_status.text = "Branch service settings updated."
	refresh()
