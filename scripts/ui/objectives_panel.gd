class_name ObjectivesPanel
extends PanelContainer
## Left-side objectives list, defined in tuning.json ("objectives").
## Each objective renders as text + a slim progress bar + "current / target".
## Adding a new objective type = one extra case in _progress_for().

var _assets: GDScript = load("res://scripts/ui/ui_assets.gd")
## goal_id -> {label, bar, value}
var _rows: Dictionary = {}
var _done: Dictionary = {}
var _rush_label: Label
var _hours_label: Label
var _goals_box: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(252, 0)
	add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	box.add_child(header)
	header.add_child(_assets.icon_rect(&"star", 18))
	var title: Label = Label.new()
	title.text = "OBJECTIVES"
	title.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_BODY)
	title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	header.add_child(title)

	# Objective rows are built lazily in _refresh(): tuning.json may not be
	# loaded yet when the HUD constructs this panel at boot.
	_goals_box = VBoxContainer.new()
	_goals_box.add_theme_constant_override("separation", 4)
	box.add_child(_goals_box)

	box.add_child(HSeparator.new())
	_rush_label = _footer_row(box, &"dining")
	_hours_label = _footer_row(box, &"clock")
	GameClock.minute_ticked.connect(_on_minute)
	_refresh.call_deferred()


func _footer_row(parent: Control, icon_name: StringName) -> Label:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	row.add_child(_assets.icon_rect(icon_name, 15))
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", 13)
	row.add_child(label)
	return label


func _on_minute(_day: int, _hour: int, _minute: int) -> void:
	_refresh()


func _ensure_rows() -> void:
	if not _rows.is_empty():
		return
	for goal: Dictionary in EconomyManager.tuning_value("objectives", []):
		var label: Label = Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 13)
		_goals_box.add_child(label)
		var bar_row: HBoxContainer = HBoxContainer.new()
		bar_row.add_theme_constant_override("separation", 8)
		_goals_box.add_child(bar_row)
		var bar: ProgressBar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(150, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar_row.add_child(bar)
		var value: Label = Label.new()
		value.add_theme_font_size_override("font_size", 12)
		value.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		bar_row.add_child(value)
		_rows[String(goal["id"])] = {"label": label, "bar": bar, "value": value}


func _refresh() -> void:
	_ensure_rows()
	for goal: Dictionary in EconomyManager.tuning_value("objectives", []):
		var goal_id: String = String(goal["id"])
		var row: Dictionary = _rows.get(goal_id, {})
		if row.is_empty():
			continue
		var target: float = float(goal.get("target", 1.0))
		var current: float = _progress_for(String(goal.get("type", "")))
		var done: bool = current >= target
		var label: Label = row["label"]
		label.text = String(goal.get("text", goal_id))
		label.add_theme_color_override(
			"font_color", Color("#2e7d32") if done else TycoonTheme.PALETTE["text"])
		var bar: ProgressBar = row["bar"]
		bar.max_value = target
		bar.value = minf(current, target)
		var value: Label = row["value"]
		value.text = "%s / %s" % [_fmt(current, goal), _fmt(target, goal)]
		if done and not _done.get(goal_id, false):
			_done[goal_id] = true
			EconomyManager.post_message("good", "Objective complete: %s!" % goal.get("text", ""))
	var hour: float = GameClock.game_hours
	var rush_hour: int = 12 if hour < 12.0 or hour >= 20.0 else 18
	var hours_until: float = fposmod(float(rush_hour) - hour, 24.0)
	_rush_label.text = "Next meal rush in %.1f h" % hours_until
	var rest: RestaurantState = RestaurantManager.owned[0] if not RestaurantManager.owned.is_empty() else null
	_hours_label.text = "Hours %02d:00–%02d:00" % [int(rest.open_hour), int(rest.close_hour)] if rest != null else "Open your first restaurant"


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
		"stars":
			var best: float = 0.0
			for rest: RestaurantState in RestaurantManager.owned:
				best = maxf(best, rest.star_rating)
			return best
		"awards":
			var awards: Node = get_tree().root.get_node_or_null(^"AwardsManager")
			return float(awards.trophies_for(CompanyManager.player.id)) if awards != null else 0.0
	return 0.0


func _fmt(value: float, goal: Dictionary) -> String:
	if String(goal.get("type", "")) == "cash":
		return "$%.0f" % value
	if String(goal.get("type", "")) == "reputation" or String(goal.get("type", "")) == "stars":
		return "%.1f" % value
	return "%d" % int(value)
