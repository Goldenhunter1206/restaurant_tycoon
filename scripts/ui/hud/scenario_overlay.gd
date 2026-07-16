class_name ScenarioOverlay
extends Control
## Topmost campaign UI layer for pause, side-mission, tutorial, and frozen
## scenario-result presentation. The layer pauses simulation speed, not the
## SceneTree, so menu buttons and lightweight reveal motion remain responsive.

const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"
const FRONTEND_SCENE_PATH: String = "res://scenes/Frontend.tscn"

var _assets: GDScript = load("res://scripts/ui/ui_assets.gd")
var _scrim: ColorRect
var _modal_host: CenterContainer
var _tutorial_host: MarginContainer
var _active_modal: Control
var _tutorial_card: Control
var _modal_kind: StringName = &""
var _paused_speed: int = 1
var _side_mission_id: StringName = &""
var _tutorial_objective_id: StringName = &""
var _last_result: ScenarioResultSnapshot
var _progression_changes: Dictionary = {}
var _bound_manager: ScenarioManager
var _bound_campaign_manager: CampaignManager


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200
	_build_layer()
	_bind_services()
	if not GameSetup.services_ready.is_connected(_bind_services):
		GameSetup.services_ready.connect(_bind_services)


func _unhandled_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_ESCAPE:
		return
	if _modal_kind == &"results":
		return
	if _modal_kind == &"pause":
		_close_pause()
	elif _modal_kind == &"side_mission":
		_decline_side_mission()
	else:
		open_pause()
	get_viewport().set_input_as_handled()


func open_pause() -> void:
	if _modal_kind == &"results" or _modal_kind == &"side_mission":
		return
	_paused_speed = GameClock.speed if GameClock.speed > 0 else maxi(_paused_speed, 1)
	GameClock.set_speed(0)
	_show_modal(_build_pause_card(), &"pause")


func _build_layer() -> void:
	_scrim = ColorRect.new()
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.color = Color(0.10, 0.045, 0.015, 0.84)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.hide()
	add_child(_scrim)

	_modal_host = CenterContainer.new()
	_modal_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_host.hide()
	add_child(_modal_host)

	_tutorial_host = MarginContainer.new()
	_tutorial_host.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_tutorial_host.offset_left = 286.0
	_tutorial_host.offset_right = -418.0
	_tutorial_host.offset_top = -206.0
	_tutorial_host.offset_bottom = -102.0
	_tutorial_host.add_theme_constant_override("margin_left", 10)
	_tutorial_host.add_theme_constant_override("margin_right", 10)
	_tutorial_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_host.hide()
	add_child(_tutorial_host)


func _bind_services() -> void:
	var manager: ScenarioManager = GameSetup.scenario_manager
	if manager != null and manager != _bound_manager:
		_bound_manager = manager
		if not manager.side_mission_offered.is_connected(_on_side_mission_offered):
			manager.side_mission_offered.connect(_on_side_mission_offered)
		if not manager.tutorial_prompted.is_connected(_on_tutorial_prompted):
			manager.tutorial_prompted.connect(_on_tutorial_prompted)
		if not manager.scenario_completed.is_connected(_on_scenario_completed):
			manager.scenario_completed.connect(_on_scenario_completed)
		if not manager.scenario_failed.is_connected(_on_scenario_failed):
			manager.scenario_failed.connect(_on_scenario_failed)
	var progression: CampaignManager = GameSetup.campaign_manager
	if progression != null and progression != _bound_campaign_manager:
		_bound_campaign_manager = progression
		if not progression.progression_committed.is_connected(_on_progression_committed):
			progression.progression_committed.connect(_on_progression_committed)


func _build_pause_card() -> Control:
	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(420.0, 0.0)
	frame.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_lg_box())
	var paper: PanelContainer = PanelContainer.new()
	paper.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	frame.add_child(paper)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	paper.add_child(box)
	box.add_child(_title_label("GAME PAUSED", 28))
	var breadcrumb: Label = _body_label(GameSetup.breadcrumb(), 15)
	breadcrumb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	breadcrumb.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	box.add_child(breadcrumb)
	box.add_child(HSeparator.new())
	box.add_child(_action_button("RESUME", _close_pause, true))
	box.add_child(_action_button("SAVE GAME", _save_from_pause))
	box.add_child(_action_button("RESTART SCENARIO", _restart_session))
	box.add_child(_action_button("MAIN MENU", _go_to_menu))
	return frame


func _on_side_mission_offered(objective_id: StringName, definition: ObjectiveDef) -> void:
	if definition == null or _modal_kind == &"results":
		return
	_side_mission_id = objective_id
	_paused_speed = GameClock.speed if GameClock.speed > 0 else maxi(_paused_speed, 1)
	GameClock.set_speed(0)
	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(560.0, 0.0)
	frame.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_lg_box())
	var paper: PanelContainer = PanelContainer.new()
	paper.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	frame.add_child(paper)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	paper.add_child(box)
	box.add_child(_eyebrow_label("SIDE MISSION OFFER"))
	var title: Label = _title_label(definition.text, 24)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var details: Label = _body_label(_objective_offer_details(definition), 15)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	box.add_child(details)
	var reward_text: String = _reward_text(definition.reward)
	if not reward_text.is_empty():
		var reward_panel: PanelContainer = PanelContainer.new()
		reward_panel.add_theme_stylebox_override("panel", TycoonTheme.status_box("info"))
		var reward_label: Label = _body_label("REWARD  •  %s" % reward_text, 15)
		reward_panel.add_child(reward_label)
		box.add_child(reward_panel)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	var decline: Button = _action_button("DECLINE", _decline_side_mission)
	decline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(decline)
	var accept: Button = _action_button("ACCEPT MISSION", _accept_side_mission, true)
	accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(accept)
	_show_modal(frame, &"side_mission")


func _on_tutorial_prompted(objective_id: StringName, allow_skip: bool,
		allow_reset: bool) -> void:
	if _modal_kind == &"results":
		return
	_tutorial_objective_id = objective_id
	_clear_tutorial_card()
	var frame: PanelContainer = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	var paper: PanelContainer = PanelContainer.new()
	paper.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	frame.add_child(paper)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	paper.add_child(row)
	row.add_child(_assets.icon_rect(&"star", 32))
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	copy.add_child(_eyebrow_label("GUIDED STEP"))
	var instruction: Label = _body_label(_objective_text(objective_id), 16)
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(instruction)
	if allow_skip:
		row.add_child(_compact_button("SKIP", _skip_tutorial_step))
	if allow_reset:
		row.add_child(_compact_button("RESET", _reset_tutorial))
	_tutorial_card = frame
	_tutorial_host.add_child(frame)
	_tutorial_host.show()
	_animate_in(frame, Vector2(0.96, 0.96))


func _on_scenario_completed(result: ScenarioResultSnapshot) -> void:
	_show_results(result)


func _on_scenario_failed(result: ScenarioResultSnapshot) -> void:
	_show_results(result)


func _on_progression_committed(result_id: StringName, changes: Dictionary) -> void:
	if _last_result == null or _last_result.result_id == result_id:
		_progression_changes = changes.duplicate(true)


func _show_results(result: ScenarioResultSnapshot) -> void:
	if result == null:
		return
	_last_result = result
	GameClock.set_speed(0)
	_clear_tutorial_card()
	var success: bool = result.outcome == &"success"
	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(1000.0, 620.0)
	frame.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_lg_box())
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	frame.add_child(outer)
	var hero: HBoxContainer = HBoxContainer.new()
	hero.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_theme_constant_override("separation", 14)
	outer.add_child(hero)
	hero.add_child(_assets.icon_rect(&"trophy" if success else &"alert", 64))
	var hero_copy: VBoxContainer = VBoxContainer.new()
	hero.add_child(hero_copy)
	hero_copy.add_child(_eyebrow_label("SCENARIO COMPLETE" if success else "SCENARIO ENDED"))
	var heading: Label = _title_label("A PIZZA EMPIRE RISES!" if success else "BACK TO THE DRAWING BOARD", 30)
	heading.add_theme_color_override("font_color", TycoonTheme.PALETTE["accent_gold"] if success else Color("#ffb09d"))
	hero_copy.add_child(heading)
	var crumb: Label = _body_label(GameSetup.breadcrumb(), 15)
	crumb.add_theme_color_override("font_color", Color("#fff0cc"))
	hero_copy.add_child(crumb)

	var columns: HBoxContainer = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	outer.add_child(columns)
	columns.add_child(_build_result_objectives(result))
	columns.add_child(_build_result_awards(result, success))
	_show_modal(frame, &"results")


func _build_result_objectives(result: ScenarioResultSnapshot) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_section_label("OBJECTIVES"))
	var objective_names: Dictionary = _objective_name_map()
	var shown: int = 0
	for objective_id: StringName in result.completed_objectives:
		box.add_child(_result_line(true, String(objective_names.get(objective_id, String(objective_id).capitalize()))))
		shown += 1
	for objective_id: StringName in result.failed_objectives:
		box.add_child(_result_line(false, String(objective_names.get(objective_id, String(objective_id).capitalize()))))
		shown += 1
	for objective_id: StringName in result.expired_objectives:
		box.add_child(_result_line(false, "%s  •  EXPIRED" % String(objective_names.get(objective_id, String(objective_id).capitalize()))))
		shown += 1
	if shown == 0:
		box.add_child(_body_label("No scored objectives in this sandbox run.", 14))
	box.add_child(HSeparator.new())
	box.add_child(_section_label("SCORE BREAKDOWN"))
	if result.score_breakdown.is_empty():
		box.add_child(_score_line("Scenario score", result.score))
	else:
		for key: Variant in result.score_breakdown:
			box.add_child(_score_line(String(key).replace("_", " ").capitalize(), float(result.score_breakdown[key])))
	return panel


func _build_result_awards(result: ScenarioResultSnapshot, success: bool) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = 390.0
	panel.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var score: Label = _title_label("%s PTS" % _format_number(result.score), 30)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(score)
	var medal_text: String = String(result.medal).to_upper()
	if medal_text.is_empty():
		medal_text = "COMPLETED" if success else "TRY AGAIN"
	var medal: Label = _body_label(medal_text, 18)
	medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	medal.add_theme_color_override("font_color", _medal_color(result.medal, success))
	box.add_child(medal)
	box.add_child(HSeparator.new())
	box.add_child(_section_label("AWARDS & UNLOCKS"))
	var rewards: Array[String] = _result_reward_lines(result)
	if rewards.is_empty():
		rewards.append("Profile progress saved" if success else "Replay to improve your result")
	for reward: String in rewards:
		var line: Label = _body_label("★  %s" % reward, 14)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(line)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	if not success and not result.failure_reason.is_empty():
		var reason: Label = _body_label(result.failure_reason, 14)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.add_theme_color_override("font_color", TycoonTheme.PALETTE["bad"])
		box.add_child(reason)
	if success and result.mode == &"free_play":
		box.add_child(_action_button("KEEP PLAYING", _continue_pressed, true))
	elif success and _next_scenario_id() != &"":
		box.add_child(_action_button("NEXT CHAPTER", _continue_pressed, true))
	box.add_child(_action_button("REPLAY SCENARIO", _restart_session, not success))
	box.add_child(_action_button("MAIN MENU", _go_to_menu))
	return panel


func _show_modal(content: Control, kind: StringName) -> void:
	_clear_active_modal()
	_modal_kind = kind
	_active_modal = content
	_modal_host.add_child(content)
	_scrim.show()
	_modal_host.show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_animate_in(content, Vector2(0.96, 0.96))


func _clear_active_modal() -> void:
	if is_instance_valid(_active_modal):
		_active_modal.queue_free()
	_active_modal = null
	_modal_kind = &""


func _dismiss_modal() -> void:
	_clear_active_modal()
	_scrim.hide()
	_modal_host.hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _close_pause() -> void:
	if _modal_kind != &"pause":
		return
	_dismiss_modal()
	GameClock.set_speed(maxi(_paused_speed, 1))


func _save_from_pause() -> void:
	SaveSystem.save_game()
	EconomyManager.post_message("good", "Game saved.")


func _accept_side_mission() -> void:
	if _bound_manager != null:
		_bound_manager.accept_side_mission(_side_mission_id)
	_dismiss_modal()
	GameClock.set_speed(maxi(_paused_speed, 1))


func _decline_side_mission() -> void:
	if _bound_manager != null:
		_bound_manager.decline_side_mission(_side_mission_id)
	_dismiss_modal()
	GameClock.set_speed(maxi(_paused_speed, 1))


func _skip_tutorial_step() -> void:
	if _bound_manager != null:
		_bound_manager.skip_tutorial_step(_tutorial_objective_id)
	_clear_tutorial_card()


func _reset_tutorial() -> void:
	if _bound_manager != null:
		_bound_manager.reset_tutorial()
	_clear_tutorial_card()


func _clear_tutorial_card() -> void:
	if is_instance_valid(_tutorial_card):
		_tutorial_card.queue_free()
	_tutorial_card = null
	_tutorial_host.hide()


func _restart_session() -> void:
	if GameSetup.has_method("restart_current_scenario"):
		GameSetup.call("restart_current_scenario")
		return
	if GameSetup.session_config == null:
		return
	var config_script: Script = load("res://scripts/data/game_session_config.gd") as Script
	var fresh_config: GameSessionConfig = config_script.call(
		"from_dict", GameSetup.session_config.to_dict()
	) as GameSessionConfig
	CompanyManager.loaded_save = null
	GameSetup.configure_session(fresh_config)
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _continue_pressed() -> void:
	if _last_result == null:
		return
	if _last_result.mode == &"free_play":
		if GameSetup.has_method("continue_after_result"):
			GameSetup.call("continue_after_result")
		elif _bound_manager != null:
			_bound_manager.continue_in_free_play()
		_dismiss_modal()
		return
	var next_id: StringName = _next_scenario_id()
	if next_id == &"":
		_go_to_menu()
		return
	if GameSetup.has_method("advance_to_next_scenario"):
		GameSetup.call("advance_to_next_scenario")
		return
	var next_config: GameSessionConfig = GameSetup.create_config(_last_result.mode, next_id)
	var previous: GameSessionConfig = GameSetup.session_config
	if previous != null:
		next_config.company_identity = previous.company_identity.duplicate(true)
		next_config.difficulty = previous.difficulty
		next_config.difficulty_overrides = previous.difficulty_overrides.duplicate(true)
	CompanyManager.loaded_save = null
	GameSetup.configure_session(next_config)
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _go_to_menu() -> void:
	if GameSetup.has_method("return_to_frontend"):
		GameSetup.call("return_to_frontend")
		return
	CompanyManager.loaded_save = null
	GameSetup.reset()
	get_tree().change_scene_to_file(FRONTEND_SCENE_PATH)


func _next_scenario_id() -> StringName:
	if _last_result == null or _last_result.campaign_id == &"" or GameSetup.catalog == null:
		return &""
	return GameSetup.catalog.next_scenario_id(
		_last_result.campaign_id, _last_result.scenario_id
	)


func _objective_text(objective_id: StringName) -> String:
	if _bound_manager == null:
		return String(objective_id).replace("_", " ").capitalize()
	for row: Dictionary in _bound_manager.objective_rows():
		if StringName(String(row.get("id", ""))) == objective_id:
			return String(row.get("text", objective_id))
	return String(objective_id).replace("_", " ").capitalize()


func _objective_name_map() -> Dictionary:
	var names: Dictionary = {}
	if _bound_manager == null:
		return names
	for row: Dictionary in _bound_manager.objective_rows():
		var objective_id: StringName = StringName(String(row.get("id", "")))
		names[objective_id] = String(row.get("text", objective_id))
	return names


func _objective_offer_details(definition: ObjectiveDef) -> String:
	var details: Array[String] = []
	if definition.target > 0.0:
		details.append("Target: %s %.0f" % [String(definition.operator), definition.target])
	if not definition.deadline.is_empty():
		var day_value: Variant = definition.deadline.get("target", definition.deadline.get("day", ""))
		if not String(day_value).is_empty():
			details.append("Deadline: Day %s" % String(day_value))
	return "  •  ".join(details) if not details.is_empty() else "An optional opportunity has appeared in the city."


func _result_reward_lines(result: ScenarioResultSnapshot) -> Array[String]:
	var lines: Array[String] = []
	for reward: Dictionary in result.rewards:
		var text: String = _reward_text(reward)
		if not text.is_empty() and not lines.has(text):
			lines.append(text)
	for key: String in ["unlocked_cities", "unlocked_scenarios", "unlocked_content"]:
		for value: Variant in _progression_changes.get(key, []):
			var label: String = String(value).replace("_", " ").replace(":", ": ").capitalize()
			if not label.is_empty() and not lines.has(label):
				lines.append(label)
	return lines


func _reward_text(reward: Dictionary) -> String:
	var pieces: Array[String] = []
	var reward_type: String = String(reward.get("type", ""))
	var reward_id: String = String(reward.get("id", ""))
	if not reward_type.is_empty() and not reward_id.is_empty():
		pieces.append("%s: %s" % [reward_type.replace("_", " ").capitalize(), reward_id.replace("_", " ").capitalize()])
	var cash: float = float(reward.get("cash", reward.get("amount", 0.0) if reward_type == "profile_cash" else 0.0))
	if not is_zero_approx(cash):
		pieces.append("$%s" % _format_number(cash))
	var reputation: float = float(reward.get("reputation", 0.0))
	if not is_zero_approx(reputation):
		pieces.append("%+.1f reputation" % reputation)
	return "  •  ".join(pieces)


func _result_line(completed: bool, text: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var mark: Label = _body_label("✓" if completed else "×", 18)
	mark.add_theme_color_override("font_color", TycoonTheme.PALETTE["good"] if completed else TycoonTheme.PALETTE["bad"])
	row.add_child(mark)
	var copy: Label = _body_label(text, 14)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(copy)
	return row


func _score_line(label_text: String, score: float) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = _body_label(label_text, 14)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value: Label = _body_label(_format_number(score), 14)
	value.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	row.add_child(value)
	return row


func _action_button(text_value: String, callback: Callable, primary: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 44.0
	button.add_theme_font_size_override("font_size", 15)
	if primary:
		TycoonTheme.apply_orange(button)
	button.pressed.connect(callback)
	return button


func _compact_button(text_value: String, callback: Callable) -> Button:
	var button: Button = _action_button(text_value, callback)
	button.custom_minimum_size = Vector2(76.0, 38.0)
	return button


func _title_label(text_value: String, size: int) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	return label


func _section_label(text_value: String) -> Label:
	var label: Label = _body_label(text_value, 15)
	label.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	return label


func _eyebrow_label(text_value: String) -> Label:
	var label: Label = _body_label(text_value, 13)
	label.add_theme_color_override("font_color", TycoonTheme.PALETTE["accent_red"])
	return label


func _body_label(text_value: String, size: int) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	return label


func _animate_in(control: Control, start_scale: Vector2) -> void:
	control.pivot_offset = control.size * 0.5
	control.scale = start_scale
	control.modulate.a = 0.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.18)
	tween.tween_property(control, "modulate:a", 1.0, 0.12)


func _medal_color(medal: StringName, success: bool) -> Color:
	match medal:
		&"gold":
			return Color("#d99000")
		&"silver":
			return Color("#78838e")
		&"bronze":
			return Color("#a95d2c")
	return TycoonTheme.PALETTE["good"] if success else TycoonTheme.PALETTE["bad"]


static func _format_number(value: float) -> String:
	var raw: String = "%.0f" % absf(value)
	var out: String = ""
	var count: int = 0
	for index: int in range(raw.length() - 1, -1, -1):
		out = raw[index] + out
		count += 1
		if count % 3 == 0 and index > 0:
			out = "," + out
	return ("−" if value < 0.0 else "") + out
