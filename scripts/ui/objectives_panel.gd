class_name ObjectivesPanel
extends PanelContainer
## Left-side live objective tracker. ScenarioManager owns campaign/challenge/
## tutorial objectives; tuning.json remains a fallback for legacy free-play.

var _assets: GDScript = load("res://scripts/ui/ui_assets.gd")
var _done: Dictionary = {}
var _rush_label: Label
var _hours_label: Label
var _goals_box: VBoxContainer
var _title: Label
var _bound_manager: ScenarioManager


func _ready() -> void:
	custom_minimum_size = Vector2(270.0, 0.0)
	add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	add_child(box)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	box.add_child(header)
	header.add_child(_assets.icon_rect(&"star", 18))
	_title = Label.new()
	_title.text = "OBJECTIVES"
	_title.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_BODY)
	_title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	header.add_child(_title)

	_goals_box = VBoxContainer.new()
	_goals_box.add_theme_constant_override("separation", 7)
	box.add_child(_goals_box)

	box.add_child(HSeparator.new())
	_rush_label = _footer_row(box, &"dining")
	_hours_label = _footer_row(box, &"clock")
	GameClock.minute_ticked.connect(_on_minute)
	if not GameSetup.services_ready.is_connected(_bind_scenario_manager):
		GameSetup.services_ready.connect(_bind_scenario_manager)
	if not GameSetup.session_initialized.is_connected(_on_session_initialized):
		GameSetup.session_initialized.connect(_on_session_initialized)
	_bind_scenario_manager()
	_refresh.call_deferred()


func _footer_row(parent: Control, icon_name: StringName) -> Label:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	row.add_child(_assets.icon_rect(icon_name, 15))
	var label: Label = Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	return label


func _bind_scenario_manager() -> void:
	var manager: ScenarioManager = GameSetup.scenario_manager
	if not is_instance_valid(manager) or manager == _bound_manager:
		return
	_bound_manager = manager
	if not manager.scenario_initialized.is_connected(_on_scenario_initialized):
		manager.scenario_initialized.connect(_on_scenario_initialized)
	if not manager.objective_updated.is_connected(_on_objective_updated):
		manager.objective_updated.connect(_on_objective_updated)
	if not manager.objective_resolved.is_connected(_on_objective_updated):
		manager.objective_resolved.connect(_on_objective_updated)
	if not manager.runtime_changed.is_connected(_refresh):
		manager.runtime_changed.connect(_refresh)


func _on_session_initialized(_config: GameSessionConfig) -> void:
	_bind_scenario_manager()
	_refresh()


func _on_scenario_initialized(_definition: ScenarioDef) -> void:
	_refresh()


func _on_objective_updated(_objective_id: StringName, _state: ObjectiveState) -> void:
	_refresh()


func _on_minute(_day: int, _hour: int, _minute: int) -> void:
	_refresh()


func _refresh() -> void:
	if _goals_box == null:
		return
	for child: Node in _goals_box.get_children():
		child.queue_free()
	if _bound_manager != null and _bound_manager.state != null:
		_render_scenario_objectives(_bound_manager.objective_rows())
		_refresh_scenario_footer()
	else:
		_render_legacy_objectives()
		_refresh_legacy_footer()


func _render_scenario_objectives(rows: Array[Dictionary]) -> void:
	_title.text = "MISSION OBJECTIVES"
	if rows.is_empty():
		var empty: Label = Label.new()
		empty.text = "This run has no scored objectives. Build at your own pace."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		_goals_box.add_child(empty)
		return
	for objective: Dictionary in rows:
		_goals_box.add_child(_scenario_objective_row(objective))


func _scenario_objective_row(objective: Dictionary) -> Control:
	var state: StringName = StringName(String(objective.get("state", "active")))
	var completed: bool = state == &"completed"
	var failed: bool = state in [&"failed", &"expired"]
	var card: PanelContainer = PanelContainer.new()
	var severity: String = "info"
	if completed:
		severity = "success"
	elif failed:
		severity = "critical"
	card.add_theme_stylebox_override("panel", TycoonTheme.status_box(severity))
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)

	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 5)
	box.add_child(heading)
	var mark: Label = Label.new()
	mark.text = "✓" if completed else ("×" if failed else "◆")
	mark.add_theme_color_override("font_color", TycoonTheme.PALETTE["good"] if completed else (TycoonTheme.PALETTE["bad"] if failed else TycoonTheme.PALETTE["accent_red"]))
	heading.add_child(mark)
	var label: Label = Label.new()
	label.text = String(objective.get("text", objective.get("id", "Objective")))
	if bool(objective.get("optional", false)):
		label.text = "SIDE  •  %s" % label.text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", TycoonTheme.PALETTE["good"] if completed else (TycoonTheme.PALETTE["bad"] if failed else TycoonTheme.PALETTE["text"]))
	heading.add_child(label)
	var state_label: Label = Label.new()
	state_label.text = _state_text(state, bool(objective.get("accepted", false)))
	state_label.add_theme_font_size_override("font_size", 11)
	state_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	heading.add_child(state_label)

	var progress_row: HBoxContainer = HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 8)
	box.add_child(progress_row)
	var current: float = float(objective.get("current", 0.0))
	var target: float = float(objective.get("target", 1.0))
	var bar: ProgressBar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(142.0, 9.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = maxf(absf(target), 1.0)
	bar.value = _progress_value(current, target, StringName(String(objective.get("operator", ">="))))
	progress_row.add_child(bar)
	var value: Label = Label.new()
	value.text = "%s / %s" % [String(objective.get("current_text", "%.0f" % current)), String(objective.get("target_text", "%.0f" % target))]
	value.add_theme_font_size_override("font_size", 12)
	value.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	progress_row.add_child(value)
	var deadline_text: String = _deadline_text(objective.get("deadline", {}))
	if not deadline_text.is_empty():
		var deadline: Label = Label.new()
		deadline.text = deadline_text
		deadline.add_theme_font_size_override("font_size", 11)
		deadline.add_theme_color_override("font_color", TycoonTheme.PALETTE["accent_red"])
		box.add_child(deadline)
	return card


func _refresh_scenario_footer() -> void:
	var definition: ScenarioDef = _bound_manager.definition
	var state: ScenarioState = _bound_manager.state
	var mode_name: String = String(GameSetup.session_config.mode).replace("_", " ").capitalize() if GameSetup.session_config != null else "Scenario"
	_rush_label.text = "%s  •  %s" % [mode_name, definition.title if definition != null else "Active"]
	if definition != null and definition.time_limit_days > 0.0 and state != null:
		var remaining: float = maxf(0.0, definition.time_limit_days - state.elapsed_time_days)
		_hours_label.text = "%.1f days remaining" % remaining
	else:
		_hours_label.text = "No time limit"


func _render_legacy_objectives() -> void:
	_title.text = "OBJECTIVES"
	for goal: Dictionary in EconomyManager.tuning_value("objectives", []):
		var target: float = float(goal.get("target", 1.0))
		var current: float = _legacy_progress_for(String(goal.get("type", "")))
		var done: bool = current >= target
		var block: VBoxContainer = VBoxContainer.new()
		_goals_box.add_child(block)
		var label: Label = Label.new()
		label.text = String(goal.get("text", goal.get("id", "Objective")))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", TycoonTheme.PALETTE["good"] if done else TycoonTheme.PALETTE["text"])
		block.add_child(label)
		var row: HBoxContainer = HBoxContainer.new()
		block.add_child(row)
		var bar: ProgressBar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(150.0, 10.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.show_percentage = false
		bar.max_value = maxf(target, 1.0)
		bar.value = minf(current, target)
		row.add_child(bar)
		var value: Label = Label.new()
		value.text = "%s / %s" % [_legacy_format(current, goal), _legacy_format(target, goal)]
		value.add_theme_font_size_override("font_size", 12)
		row.add_child(value)
		var goal_id: String = String(goal.get("id", ""))
		if done and not _done.get(goal_id, false):
			_done[goal_id] = true
			EconomyManager.post_message("good", "Objective complete: %s!" % goal.get("text", ""))


func _refresh_legacy_footer() -> void:
	var hour: float = GameClock.game_hours
	var rush_hour: int = 12 if hour < 12.0 or hour >= 20.0 else 18
	var hours_until: float = fposmod(float(rush_hour) - hour, 24.0)
	_rush_label.text = "Next meal rush in %.1f h" % hours_until
	var restaurant: RestaurantState = RestaurantManager.owned[0] if not RestaurantManager.owned.is_empty() else null
	_hours_label.text = "Hours %02d:00–%02d:00" % [int(restaurant.open_hour), int(restaurant.close_hour)] if restaurant != null else "Open your first restaurant"


func _legacy_progress_for(goal_type: String) -> float:
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
			for restaurant: RestaurantState in RestaurantManager.owned:
				best = maxf(best, restaurant.star_rating)
			return best
		"awards":
			var awards: Node = get_tree().root.get_node_or_null(^"AwardsManager")
			return float(awards.call("trophies_for", CompanyManager.player.id)) if awards != null else 0.0
	return 0.0


func _legacy_format(value: float, goal: Dictionary) -> String:
	var goal_type: String = String(goal.get("type", ""))
	if goal_type == "cash":
		return "$%.0f" % value
	if goal_type in ["reputation", "stars"]:
		return "%.1f" % value
	return "%d" % int(value)


static func _progress_value(current: float, target: float, operator: StringName) -> float:
	var maximum: float = maxf(absf(target), 1.0)
	if operator in [&"<=", &"<", &"lte"]:
		return clampf(maximum - maxf(current - target, 0.0), 0.0, maximum)
	return clampf(current, 0.0, maximum)


static func _deadline_text(deadline: Dictionary) -> String:
	if deadline.is_empty():
		return ""
	var metric: String = String(deadline.get("metric", "day"))
	var target: String = String(deadline.get("target", deadline.get("day", "")))
	if target.is_empty():
		return ""
	return "Deadline  •  Day %s" % target if metric == "day" else "Deadline  •  %s %s" % [metric.replace("_", " ").capitalize(), target]


static func _state_text(state: StringName, accepted: bool) -> String:
	match state:
		&"completed":
			return "DONE"
		&"failed":
			return "FAILED"
		&"expired":
			return "EXPIRED"
		&"revealed":
			return "OFFER" if not accepted else "ACTIVE"
	return "ACTIVE"
