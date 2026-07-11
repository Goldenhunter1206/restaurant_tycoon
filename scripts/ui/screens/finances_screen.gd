extends TycoonScreen
## Company finances: today's ledger by category, recent day summaries,
## loan controls.

var _ledger_list: VBoxContainer
var _history_list: VBoxContainer
var _loan_label: Label


func screen_title() -> String:
	return "Finances"


func screen_icon() -> StringName:
	return &"coin"


func _build() -> void:
	add_section("Today's ledger")
	_ledger_list = add_scroll_list()
	add_section("Recent days")
	_history_list = add_scroll_list()
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


func refresh() -> void:
	for child: Node in _ledger_list.get_children():
		child.queue_free()
	var categories: Array = EconomyManager.ledger_today.keys()
	categories.sort()
	if categories.is_empty():
		var empty: Label = Label.new()
		empty.text = "No transactions yet today."
		_ledger_list.add_child(empty)
	for category: StringName in categories:
		var amount: float = EconomyManager.ledger_today[category]
		var line: Label = Label.new()
		line.text = "%s    %s$%.2f" % [
			String(category).capitalize(), "+" if amount >= 0.0 else "−", absf(amount)]
		line.add_theme_color_override(
			"font_color", Color("#2e7d32") if amount >= 0.0 else Color("#c0392b"))
		_ledger_list.add_child(line)
	var total: Label = Label.new()
	total.text = "Profit today: $%.2f" % EconomyManager.profit_today()
	total.add_theme_font_size_override("font_size", 17)
	_ledger_list.add_child(total)

	for child: Node in _history_list.get_children():
		child.queue_free()
	var history: Array[Dictionary] = EconomyManager.history
	for i: int in range(history.size() - 1, maxi(-1, history.size() - 8), -1):
		var day: Dictionary = history[i]
		var line: Label = Label.new()
		line.text = "Day %d — income $%.0f, expenses $%.0f, profit $%.0f" % [
			int(day["day"]), float(day["income"]), absf(float(day["expenses"])),
			float(day["profit"])]
		_history_list.add_child(line)
	_loan_label.text = "🏦 Loan: $%.0f (max $%.0f, %.1f%%/day interest)" % [
		EconomyManager.loan,
		float(EconomyManager.tuning_value("loan.max", 50000.0)),
		float(EconomyManager.tuning_value("loan.daily_interest", 0.002)) * 100.0,
	]
