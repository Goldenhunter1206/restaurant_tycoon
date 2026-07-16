class_name ScenarioIntroScreen
extends Control
## Mission briefing shown after a session config is committed and before the
## simulation scene launches. Keeps the wizard choices inspectable and gives
## objectives, opponents, and restrictions a single calm reading surface.

const INK: Color = Color("#3A2010")
const INK_SOFT: Color = Color("#6E4326")
const CREAM: Color = Color("#FFF4DC")
const PAPER: Color = Color("#FBEFC9")
const PAPER_EDGE: Color = Color("#DDBF78")
const WOOD: Color = Color("#8A5222")
const WOOD_EDGE: Color = Color("#43260F")
const RED: Color = Color("#EA4A2F")
const GOLD: Color = Color("#F5C518")
const GREEN: Color = Color("#6FB63A")

const MAP_ICON_PATH: String = "res://assets/ui/icons/city_map.png"

var _config: GameSessionConfig = null
var _briefing_panel: Control = null
var _mission_stamp: Control = null


func setup(config: GameSessionConfig) -> void:
	_config = config


func _ready() -> void:
	if not is_instance_valid(GameSetup):
		return
	if is_instance_valid(CompanyManager):
		CompanyManager.load_profiles()
	if _config == null:
		var candidate: Variant = GameSetup.get("session_config")
		if candidate is GameSessionConfig:
			_config = candidate as GameSessionConfig
	_build()
	call_deferred("_play_entrance")


func _build() -> void:
	var outer: MarginContainer = MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 48)
	outer.add_theme_constant_override("margin_right", 48)
	outer.add_theme_constant_override("margin_top", 28)
	outer.add_theme_constant_override("margin_bottom", 32)
	add_child(outer)
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	outer.add_child(page)

	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	page.add_child(top)
	var back_button: Button = Button.new()
	back_button.text = "‹  Edit setup"
	back_button.custom_minimum_size = Vector2(148, 48)
	back_button.pressed.connect(_on_back)
	top.add_child(back_button)
	var eyebrow: Label = Label.new()
	eyebrow.text = _breadcrumb()
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eyebrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", Color("#E6B667"))
	top.add_child(eyebrow)
	var seed_pill: PanelContainer = _pill("SEED  %d" % _seed(), Color("#6E3D18"), CREAM)
	top.add_child(seed_pill)

	var center: CenterContainer = CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(center)
	var spread: HBoxContainer = HBoxContainer.new()
	spread.custom_minimum_size = Vector2(1040, 0)
	spread.add_theme_constant_override("separation", 24)
	center.add_child(spread)

	_mission_stamp = _build_stamp()
	spread.add_child(_mission_stamp)
	_briefing_panel = _build_briefing()
	spread.add_child(_briefing_panel)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	page.add_child(footer)
	var note: Label = Label.new()
	note.text = "Your setup is locked when the city opens. Progress saves separately from profile unlocks."
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color("#E6B667"))
	footer.add_child(note)
	var start_button: Button = Button.new()
	start_button.text = "Open the doors  →"
	start_button.custom_minimum_size = Vector2(238, 52)
	start_button.add_theme_font_size_override("font_size", 18)
	TycoonTheme.apply_orange(start_button)
	start_button.add_theme_color_override("font_color", Color.WHITE)
	start_button.add_theme_color_override("font_hover_color", Color.WHITE)
	start_button.pressed.connect(func() -> void: get_parent().start_new_game())
	footer.add_child(start_button)


func _build_stamp() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(270, 500)
	panel.add_theme_stylebox_override("panel", _wood_box())
	var column: VBoxContainer = VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var top_gap: Control = Control.new()
	top_gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(top_gap)
	if ResourceLoader.exists(MAP_ICON_PATH):
		var icon: TextureRect = TextureRect.new()
		icon.texture = load(MAP_ICON_PATH)
		icon.custom_minimum_size = Vector2(118, 118)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(icon)
	var mission: Label = Label.new()
	mission.text = _mode_label().to_upper()
	mission.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission.add_theme_font_size_override("font_size", 13)
	mission.add_theme_color_override("font_color", GOLD)
	column.add_child(mission)
	var city_name: Label = Label.new()
	city_name.text = _city_name()
	city_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	city_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	city_name.add_theme_font_size_override("font_size", 28)
	city_name.add_theme_color_override("font_color", CREAM)
	column.add_child(city_name)
	var line: ColorRect = ColorRect.new()
	line.color = Color("#D59A42")
	line.custom_minimum_size = Vector2(150, 2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(line)
	var company: Label = Label.new()
	company.text = _company_name()
	company.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	company.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	company.add_theme_font_size_override("font_size", 15)
	company.add_theme_color_override("font_color", Color("#E6B667"))
	column.add_child(company)
	var lower_gap: Control = Control.new()
	lower_gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(lower_gap)
	var difficulty: Label = Label.new()
	difficulty.text = "%s · %s" % [_difficulty_label(), _duration_label()]
	difficulty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	difficulty.add_theme_font_size_override("font_size", 12)
	difficulty.add_theme_color_override("font_color", CREAM)
	column.add_child(difficulty)
	return panel


func _build_briefing() -> PanelContainer:
	var scenario: Dictionary = _scenario()
	var intro: Dictionary = scenario.get("intro", {}) if scenario.get("intro", {}) is Dictionary else {}
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(740, 500)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _paper_box())
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var chapter: Label = Label.new()
	chapter.text = _briefing_eyebrow()
	chapter.add_theme_font_size_override("font_size", 12)
	chapter.add_theme_color_override("font_color", RED)
	column.add_child(chapter)
	var headline: Label = Label.new()
	headline.text = String(intro.get("headline", scenario.get("title", "Ready to open?")))
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.add_theme_font_size_override("font_size", 30)
	headline.add_theme_color_override("font_color", INK)
	column.add_child(headline)
	var briefing: Label = Label.new()
	briefing.text = String(intro.get("briefing", "Build a company the city will remember."))
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing.add_theme_font_size_override("font_size", 15)
	briefing.add_theme_color_override("font_color", INK_SOFT)
	column.add_child(briefing)
	column.add_child(_rule())

	var objective_heading: Label = Label.new()
	objective_heading.text = "OPENING OBJECTIVES"
	objective_heading.add_theme_font_size_override("font_size", 12)
	objective_heading.add_theme_color_override("font_color", INK_SOFT)
	column.add_child(objective_heading)
	var objectives: Array = scenario.get("objectives", [])
	if objectives.is_empty():
		column.add_child(_objective_row("Build freely. Set your own pace and measure of success.", false))
	else:
		var shown: int = 0
		for value: Variant in objectives:
			if value is not Dictionary:
				continue
			var objective: Dictionary = value
			var hidden: bool = bool(objective.get("hidden", false))
			if hidden:
				continue
			column.add_child(_objective_row(String(objective.get("text", "Objective")), false))
			shown += 1
			if shown >= 3:
				break
		if shown < objectives.size():
			column.add_child(_objective_row("More objectives reveal as the story advances.", true))

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var detail_row: HBoxContainer = HBoxContainer.new()
	detail_row.add_theme_constant_override("separation", 8)
	column.add_child(detail_row)
	for rival_name: String in _rival_names():
		detail_row.add_child(_pill("RIVAL  %s" % rival_name.to_upper(), Color("#E7D7A7"), INK_SOFT))
	if _rival_names().is_empty():
		detail_row.add_child(_pill("NO RIVALS", Color("#DDE8C1"), Color("#4E7A2D")))
	if int(scenario.get("time_limit_days", 0)) > 0:
		detail_row.add_child(_pill("%d DAYS" % int(scenario.get("time_limit_days", 0)), Color("#F2D99C"), INK))
	return panel


func _objective_row(text: String, muted: bool) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	var marker: Label = Label.new()
	marker.text = "◇" if muted else "◆"
	marker.add_theme_color_override("font_color", Color("#B5810A") if muted else GREEN)
	row.add_child(marker)
	var label: Label = Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", INK_SOFT if muted else INK)
	row.add_child(label)
	return row


func _on_back() -> void:
	get_parent().show_wizard(_config)


func _play_entrance() -> void:
	if _briefing_panel == null or _mission_stamp == null:
		return
	_mission_stamp.modulate.a = 0.0
	_briefing_panel.modulate.a = 0.0
	_mission_stamp.position.x -= 20.0
	_briefing_panel.position.x += 24.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_mission_stamp, "modulate:a", 1.0, 0.22)
	tween.tween_property(_mission_stamp, "position:x", _mission_stamp.position.x + 20.0, 0.3)
	tween.tween_property(_briefing_panel, "modulate:a", 1.0, 0.28).set_delay(0.06)
	tween.tween_property(_briefing_panel, "position:x", _briefing_panel.position.x - 24.0, 0.34).set_delay(0.06)


func _scenario() -> Dictionary:
	var catalog: Variant = GameSetup.get("catalog")
	if catalog != null and catalog.has_method("scenario"):
		return catalog.call("scenario", _scenario_id()) as Dictionary
	return {}


func _city() -> Dictionary:
	var catalog: Variant = GameSetup.get("catalog")
	if catalog != null and catalog.has_method("city"):
		return catalog.call("city", _city_id()) as Dictionary
	return {}


func _campaign() -> Dictionary:
	if _config == null or _config.campaign_id == &"":
		return {}
	var catalog: Variant = GameSetup.get("catalog")
	if catalog != null and catalog.has_method("campaign"):
		return catalog.call("campaign", _config.campaign_id) as Dictionary
	return {}


func _scenario_id() -> StringName:
	return _config.scenario_id if _config != null else &""


func _city_id() -> StringName:
	return _config.city_id if _config != null else &"riverside"


func _seed() -> int:
	return _config.seed if _config != null else 0


func _city_name() -> String:
	return String(_city().get("name", String(_city_id()).capitalize()))


func _company_name() -> String:
	if _config == null:
		return "Bella Vista Pizza Co."
	return String(_config.company_identity.get("name", "Bella Vista Pizza Co."))


func _mode_label() -> String:
	return String(_config.mode).replace("_", " ").capitalize() if _config != null else "New game"


func _difficulty_label() -> String:
	return String(_config.difficulty).capitalize() if _config != null else "Normal"


func _duration_label() -> String:
	var scenario: Dictionary = _scenario()
	var days: int = int(scenario.get("time_limit_days", 0))
	return "%d day limit" % days if days > 0 else "Open ended"


func _breadcrumb() -> String:
	return "%s  /  %s  /  MISSION BRIEFING" % [_mode_label().to_upper(), _city_name().to_upper()]


func _briefing_eyebrow() -> String:
	var campaign: Dictionary = _campaign()
	var scenario: Dictionary = _scenario()
	if not campaign.is_empty():
		return "%s  ·  %s" % [String(campaign.get("title", "Campaign")).to_upper(), String(scenario.get("title", "Chapter")).to_upper()]
	return String(scenario.get("title", _mode_label())).to_upper()


func _rival_names() -> Array[String]:
	var result: Array[String] = []
	if _config == null:
		return result
	for rival: Dictionary in _config.rivals:
		var id: StringName = StringName(String(rival.get("id", "")))
		if id == &"":
			continue
		var profile: Variant = CompanyManager.profiles.get(id)
		if profile != null:
			result.append(String(profile.get("display_name")))
		else:
			result.append(String(id).replace("_", " ").capitalize())
	return result


func _rule() -> ColorRect:
	var rule: ColorRect = ColorRect.new()
	rule.color = Color(0.36, 0.22, 0.11, 0.18)
	rule.custom_minimum_size = Vector2(0, 1)
	return rule


func _pill(text: String, background: Color, foreground: Color) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = background
	box.set_corner_radius_all(999)
	box.content_margin_left = 11.0
	box.content_margin_right = 11.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", box)
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", foreground)
	panel.add_child(label)
	return panel


func _paper_box() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PAPER
	box.set_corner_radius_all(22)
	box.set_border_width_all(4)
	box.border_color = PAPER_EDGE
	box.content_margin_left = 28.0
	box.content_margin_right = 28.0
	box.content_margin_top = 26.0
	box.content_margin_bottom = 24.0
	box.shadow_color = Color(0.1, 0.05, 0.02, 0.32)
	box.shadow_size = 16
	box.shadow_offset = Vector2(0, 8)
	return box


func _wood_box() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = WOOD
	box.set_corner_radius_all(22)
	box.set_border_width_all(5)
	box.border_color = WOOD_EDGE
	box.content_margin_left = 24.0
	box.content_margin_right = 24.0
	box.content_margin_top = 24.0
	box.content_margin_bottom = 22.0
	box.shadow_color = Color(0.08, 0.03, 0.01, 0.5)
	box.shadow_size = 16
	box.shadow_offset = Vector2(0, 8)
	return box
