extends TycoonScreen
## Company finances in three tabs: Overview (profit trend + day summaries),
## Categories (income/expense drill-down, today vs last 7 days) and
## Restaurants (per-location P&L). Loan controls stay pinned below the tabs.

const GOOD: Color = Color("#2e7d32")
const BAD: Color = Color("#c0392b")
const MUTED: Color = Color("#8a7150")

const CATEGORY_NAMES: Dictionary = {
	&"dine_in_sales": "Dine-in sales",
	&"delivery_sales": "Delivery sales",
	&"loan": "Loan taken",
	&"ingredients": "Ingredients",
	&"wages": "Wages",
	&"rent": "Rent",
	&"menu_upkeep": "Menu upkeep",
	&"kitchen_stations": "Kitchen stations",
	&"signing_fee": "Lease signing",
	&"property_purchase": "Property buyout",
	&"loan_repayment": "Loan repayment",
	&"loan_interest": "Loan interest",
}

var _tabs: TabContainer
## chip key -> value Label (cash / income / expenses / profit).
var _chips: Dictionary = {}
var _profit_spark: Sparkline
var _overview_list: VBoxContainer
var _category_list: VBoxContainer
var _restaurant_list: VBoxContainer
var _loan_label: Label


func screen_title() -> String:
	return "Finances"


func screen_icon() -> StringName:
	return &"coin"


func _build() -> void:
	custom_minimum_size = Vector2(760, 560)
	var chip_row: HBoxContainer = HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	_content.add_child(chip_row)
	_chips["cash"] = _make_chip(chip_row, "Cash")
	_chips["income"] = _make_chip(chip_row, "Income today")
	_chips["expenses"] = _make_chip(chip_row, "Expenses today")
	_chips["profit"] = _make_chip(chip_row, "Profit today")

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The default TabContainer panel is dark and fights the paper skin.
	_tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_content.add_child(_tabs)

	var overview: VBoxContainer = VBoxContainer.new()
	overview.name = "Overview"
	overview.add_theme_constant_override("separation", 6)
	_tabs.add_child(overview)
	var spark_title: Label = Label.new()
	spark_title.text = "Daily profit — last 14 days"
	spark_title.add_theme_font_size_override("font_size", 13)
	spark_title.add_theme_color_override("font_color", MUTED)
	overview.add_child(spark_title)
	_profit_spark = Sparkline.new()
	_profit_spark.custom_minimum_size = Vector2(0, 64)
	_profit_spark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.add_child(_profit_spark)
	_overview_list = _make_scroll(overview)

	var categories: VBoxContainer = VBoxContainer.new()
	categories.name = "Categories"
	categories.add_theme_constant_override("separation", 6)
	_tabs.add_child(categories)
	_category_list = _make_scroll(categories)

	var restaurants: VBoxContainer = VBoxContainer.new()
	restaurants.name = "Restaurants"
	restaurants.add_theme_constant_override("separation", 6)
	_tabs.add_child(restaurants)
	_restaurant_list = _make_scroll(restaurants)

	var loan_bar: HBoxContainer = HBoxContainer.new()
	loan_bar.add_theme_constant_override("separation", 8)
	_content.add_child(loan_bar)
	_loan_label = Label.new()
	_loan_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loan_bar.add_child(_loan_label)
	var borrow: Button = Button.new()
	borrow.text = "Borrow"
	borrow.pressed.connect(func() -> void:
		EconomyManager.take_loan(float(EconomyManager.tuning_value("loan.increment", 5000.0)))
		refresh())
	loan_bar.add_child(borrow)
	var repay: Button = Button.new()
	repay.text = "Repay"
	repay.pressed.connect(func() -> void:
		EconomyManager.repay_loan(float(EconomyManager.tuning_value("loan.increment", 5000.0)))
		refresh())
	loan_bar.add_child(repay)
	# Connect only after every tab is built: adding the first tab already fires
	# tab_changed, which would hit refresh() before the widgets exist.
	_tabs.tab_changed.connect(func(_tab: int) -> void: refresh())


func refresh() -> void:
	if _profit_spark == null or _loan_label == null:
		return
	_set_chip("cash", EconomyManager.cash, EconomyManager.cash >= 0.0)
	_set_chip("income", EconomyManager.income_today(), true)
	_set_chip("expenses", EconomyManager.expenses_today(), false)
	var profit: float = EconomyManager.profit_today()
	_set_chip("profit", profit, profit >= 0.0)
	match _tabs.current_tab:
		0:
			_refresh_overview()
		1:
			_refresh_categories()
		2:
			_refresh_restaurants()
	_loan_label.text = "🏦 Loan: $%.0f (max $%.0f, %.1f%%/day interest)" % [
		EconomyManager.loan,
		float(EconomyManager.tuning_value("loan.max", 50000.0)),
		float(EconomyManager.tuning_value("loan.daily_interest", 0.002)) * 100.0,
	]


# --- Overview -------------------------------------------------------------------


func _refresh_overview() -> void:
	_profit_spark.set_values(EconomyManager.series("profit", 14))
	for child: Node in _overview_list.get_children():
		child.queue_free()
	var history: Array[Dictionary] = EconomyManager.history
	if history.is_empty():
		var empty: Label = Label.new()
		empty.text = "No finished days yet — the first summary lands at midnight."
		_overview_list.add_child(empty)
	for i: int in range(history.size() - 1, maxi(-1, history.size() - 15), -1):
		var day: Dictionary = history[i]
		var row: PanelContainer = make_row()
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		row.add_child(box)
		var day_label: Label = Label.new()
		day_label.text = "Day %d" % int(day["day"])
		day_label.custom_minimum_size = Vector2(70, 0)
		box.add_child(day_label)
		var detail: Label = Label.new()
		detail.text = "income $%.0f · expenses $%.0f" % [float(day["income"]), absf(float(day["expenses"]))]
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.add_theme_color_override("font_color", MUTED)
		box.add_child(detail)
		var profit_label: Label = Label.new()
		var day_profit: float = float(day["profit"])
		profit_label.text = "%s$%.0f" % ["+" if day_profit >= 0.0 else "−", absf(day_profit)]
		profit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		profit_label.custom_minimum_size = Vector2(90, 0)
		profit_label.add_theme_color_override("font_color", GOOD if day_profit >= 0.0 else BAD)
		box.add_child(profit_label)
		_overview_list.add_child(row)


# --- Categories -----------------------------------------------------------------


func _refresh_categories() -> void:
	for child: Node in _category_list.get_children():
		child.queue_free()
	var today: Dictionary = EconomyManager.category_totals(1)
	var week: Dictionary = EconomyManager.category_totals(7)
	if week.is_empty():
		var empty: Label = Label.new()
		empty.text = "No transactions recorded yet."
		_category_list.add_child(empty)
		return
	var keys: Array = week.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool:
		return absf(float(week[a])) > absf(float(week[b])))
	_category_list.add_child(_columns_row("", "Today", "Last 7 days", MUTED, 13))
	for income_pass: bool in [true, false]:
		var section: Label = Label.new()
		section.text = "Income" if income_pass else "Expenses"
		section.add_theme_font_size_override("font_size", 15)
		section.add_theme_color_override("font_color", Color("#8a5a2b"))
		_category_list.add_child(section)
		var today_sum: float = 0.0
		var week_sum: float = 0.0
		var any: bool = false
		for key: StringName in keys:
			var week_amount: float = float(week[key])
			var reference: float = week_amount if not is_zero_approx(week_amount) else float(today.get(key, 0.0))
			if (reference >= 0.0) != income_pass:
				continue
			any = true
			var today_amount: float = float(today.get(key, 0.0))
			today_sum += today_amount
			week_sum += week_amount
			var display: String = CATEGORY_NAMES.get(key, String(key).capitalize())
			var row: PanelContainer = make_row()
			row.add_child(_columns_content(display, today_amount, week_amount))
			_category_list.add_child(row)
		if not any:
			var none: Label = Label.new()
			none.text = "    Nothing in this period."
			none.add_theme_font_size_override("font_size", 12)
			none.add_theme_color_override("font_color", MUTED)
			_category_list.add_child(none)
		else:
			var subtotal: HBoxContainer = _columns_content("Subtotal", today_sum, week_sum)
			subtotal.get_child(0).add_theme_color_override("font_color", MUTED)
			_category_list.add_child(subtotal)


func _columns_row(name_text: String, col1: String, col2: String, color: Color, font_size: int) -> HBoxContainer:
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var name_label: Label = Label.new()
	name_label.text = name_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var a: Label = Label.new()
	a.text = col1
	a.custom_minimum_size = Vector2(110, 0)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var b: Label = Label.new()
	b.text = col2
	b.custom_minimum_size = Vector2(110, 0)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for label: Label in [name_label, a, b]:
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", color)
		box.add_child(label)
	return box


func _columns_content(name_text: String, today_amount: float, week_amount: float) -> HBoxContainer:
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var name_label: Label = Label.new()
	name_label.text = name_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(name_label)
	for amount: float in [today_amount, week_amount]:
		var value: Label = Label.new()
		value.text = "%s$%.0f" % ["+" if amount > 0.0 else ("−" if amount < 0.0 else ""), absf(amount)]
		value.custom_minimum_size = Vector2(110, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_color_override("font_color",
			GOOD if amount > 0.0 else (BAD if amount < 0.0 else MUTED))
		box.add_child(value)
	return box


# --- Restaurants ----------------------------------------------------------------


func _refresh_restaurants() -> void:
	for child: Node in _restaurant_list.get_children():
		child.queue_free()
	var rents: Dictionary = EconomyManager.tuning_value("rent.daily_by_district", {})
	for rest: RestaurantState in RestaurantManager.owned:
		var row: PanelContainer = make_row()
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		row.add_child(box)

		var name_box: VBoxContainer = VBoxContainer.new()
		name_box.custom_minimum_size = Vector2(190, 0)
		name_box.add_theme_constant_override("separation", 0)
		var name_label: Label = Label.new()
		name_label.text = rest.restaurant_name
		name_box.add_child(name_label)
		var tenure: Label = Label.new()
		if rest.owned_outright:
			tenure.text = "Owned — no rent"
			tenure.add_theme_color_override("font_color", GOOD)
		else:
			tenure.text = "Rented — $%.0f/day" % float(rents.get(rest.district, 120.0))
			tenure.add_theme_color_override("font_color", MUTED)
		tenure.add_theme_font_size_override("font_size", 11)
		name_box.add_child(tenure)
		box.add_child(name_box)

		var today_box: VBoxContainer = VBoxContainer.new()
		today_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		today_box.add_theme_constant_override("separation", 0)
		var sales: float = float(rest.today.get("sales", 0.0))
		var expenses: float = float(rest.today.get("expenses", 0.0))
		var detail: Label = Label.new()
		detail.text = "Today: sales $%.0f · expenses $%.0f" % [sales, expenses]
		detail.add_theme_font_size_override("font_size", 12)
		detail.add_theme_color_override("font_color", MUTED)
		today_box.add_child(detail)
		var profit_label: Label = Label.new()
		var profit: float = sales - expenses
		profit_label.text = "Profit %s$%.0f" % ["+" if profit >= 0.0 else "−", absf(profit)]
		profit_label.add_theme_color_override("font_color", GOOD if profit >= 0.0 else BAD)
		today_box.add_child(profit_label)
		box.add_child(today_box)

		var spark: Sparkline = Sparkline.new()
		spark.custom_minimum_size = Vector2(150, 46)
		var profits: Array = []
		var days: int = mini(rest.sales_history.size(), rest.expense_history.size())
		for i: int in days:
			profits.append(rest.sales_history[i] - rest.expense_history[i])
		spark.set_values(profits)
		spark.tooltip_text = "Daily profit, last %d days" % days
		box.add_child(spark)
		_restaurant_list.add_child(row)


# --- Helpers --------------------------------------------------------------------


func _make_scroll(parent: Control) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	parent.add_child(scroll)
	return list


func _make_chip(parent: Control, title: String) -> Label:
	var chip: PanelContainer = PanelContainer.new()
	chip.add_theme_stylebox_override("panel", TycoonTheme.chip_box())
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	chip.add_child(box)
	var title_label: Label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.add_theme_color_override("font_color", MUTED)
	box.add_child(title_label)
	var value: Label = Label.new()
	value.add_theme_font_size_override("font_size", 17)
	box.add_child(value)
	parent.add_child(chip)
	return value


func _set_chip(key: String, amount: float, positive: bool) -> void:
	var label: Label = _chips.get(key)
	if label == null:
		return
	label.text = "$%.0f" % absf(amount)
	label.add_theme_color_override("font_color", GOOD if positive else BAD)
