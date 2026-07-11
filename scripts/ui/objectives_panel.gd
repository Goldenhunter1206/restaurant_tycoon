class_name ObjectivesPanel
extends PanelContainer
## Left-side objectives list, defined in tuning.json ("objectives").
## Adding a new objective type = one extra case in _progress_for().

var _rows: Dictionary = {}
var _done: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(250, 0)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var title: Label = Label.new()
	title.text = "⭐ OBJECTIVES"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#8a5a2b"))
	box.add_child(title)
	for goal: Dictionary in EconomyManager.tuning_value("objectives", []):
		var row: Label = Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(row)
		_rows[String(goal["id"])] = row
	GameClock.minute_ticked.connect(_on_minute)
	_refresh.call_deferred()


func _on_minute(_day: int, _hour: int, _minute: int) -> void:
	_refresh()


func _refresh() -> void:
	for goal: Dictionary in EconomyManager.tuning_value("objectives", []):
		var goal_id: String = String(goal["id"])
		var row: Label = _rows.get(goal_id)
		if row == null:
			continue
		var target: float = float(goal.get("target", 1.0))
		var current: float = _progress_for(String(goal.get("type", "")))
		var done: bool = current >= target
		row.text = "%s %s  (%s / %s)" % [
			"✅" if done else "◻", String(goal.get("text", goal_id)),
			_fmt(current, goal), _fmt(target, goal)]
		row.add_theme_color_override(
			"font_color", Color("#2e7d32") if done else Color("#4a3318"))
		if done and not _done.get(goal_id, false):
			_done[goal_id] = true
			EconomyManager.post_message("good", "Objective complete: %s!" % goal.get("text", ""))


func _progress_for(goal_type: String) -> float:
	match goal_type:
		"cash":
			return EconomyManager.cash
		"restaurants":
			return float(RestaurantManager.owned.size())
		"reputation":
			return EconomyManager.reputation
		"deliveries":
			return float(DeliveryManager.total_delivered)
	return 0.0


func _fmt(value: float, goal: Dictionary) -> String:
	if String(goal.get("type", "")) == "cash":
		return "$%.0f" % value
	if String(goal.get("type", "")) == "reputation":
		return "%.1f" % value
	return "%d" % int(value)
