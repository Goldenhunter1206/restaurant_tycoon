class_name NewGameWizard
extends Control
## Campaign-aware New Game Wizard: Mode → Company → City → Setup → Review.
## The right rail is intentionally persistent, so every choice reads as one
## deterministic session configuration rather than a collection of screens.

const STEP_TITLES: Array[String] = ["Mode", "Company", "City", "Setup", "Review"]

const INK: Color = Color("#3A2010")
const INK_SOFT: Color = Color("#6E4326")
const INK_MUTED: Color = Color("#9A7245")
const CREAM: Color = Color("#FFF4DC")
const PAPER: Color = Color("#FBEFC9")
const PAPER_SUNK: Color = Color("#F1DFAD")
const PAPER_EDGE: Color = Color("#DDBF78")
const WOOD: Color = Color("#A8692A")
const WOOD_EDGE: Color = Color("#6E3D18")
const WOOD_MID: Color = Color("#8A5222")
const RED: Color = Color("#EA4A2F")
const RED_EDGE: Color = Color("#C7331C")
const GREEN: Color = Color("#6FB63A")
const GREEN_EDGE: Color = Color("#4E8F27")
const GOLD: Color = Color("#F5C518")
const GOLD_EDGE: Color = Color("#B5810A")
const BLUE: Color = Color("#3AA6D6")

const CAMPAIGN_ID: StringName = &"bella_vista_rise"
const CITY_IDS: Array[StringName] = [&"riverside", &"harbor_quarter", &"bella_heights"]
const PLAYER_COLORS: Array[String] = [
	"#EA4A2F", "#F99A1C", "#F5C518", "#6FB63A",
	"#3AA6D6", "#2380AE", "#8A5222", "#B05CC7",
]

var _step: int = 0
var _mode: StringName = &"campaign"
var _campaign_id: StringName = CAMPAIGN_ID
var _scenario_id: StringName = &""
var _city_id: StringName = &"riverside"
var _company_name: String = ""
var _company_color: Color = Color("#EA4A2F")
var _selected_rivals: Array[StringName] = []
var _seed_text: String = ""
var _difficulty: StringName = &"normal"
var _victory_preset: StringName = &"endless"
var _incoming_config: GameSessionConfig = null
var _fallback_catalog: Variant = null

var _stepper: HBoxContainer = null
var _content: VBoxContainer = null
var _rail_body: VBoxContainer = null
var _back_button: Button = null
var _next_button: Button = null
var _profile_ids: Array[StringName] = []
var _status_label: Label = null


func setup(config: GameSessionConfig) -> void:
	_incoming_config = config


func _ready() -> void:
	if not is_instance_valid(GameSetup) or not is_instance_valid(CompanyManager):
		return
	CompanyManager.load_profiles()
	_profile_ids.clear()
	for id: StringName in CompanyManager.profiles:
		_profile_ids.append(id)
	_profile_ids.sort()
	if _incoming_config != null:
		_apply_config(_incoming_config)
	else:
		_choose_initial_campaign_scenario()
	_build_shell()
	_refresh()


func _apply_config(config: GameSessionConfig) -> void:
	_mode = config.mode
	_campaign_id = config.campaign_id
	_scenario_id = config.scenario_id
	_city_id = config.city_id
	_difficulty = config.difficulty
	_seed_text = str(config.seed)
	_company_name = String(config.company_identity.get("name", ""))
	var color_text: String = String(config.company_identity.get("color", ""))
	if not color_text.is_empty():
		_company_color = Color(color_text)
	_selected_rivals.clear()
	for rival: Dictionary in config.rivals:
		var rival_id: StringName = StringName(String(rival.get("id", "")))
		if rival_id != &"":
			_selected_rivals.append(rival_id)
	_victory_preset = _preset_from_rules(config.victory_rules)


# --- Shell -----------------------------------------------------------------


func _build_shell() -> void:
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", 0)
	add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(_build_header())

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	page.add_child(body)
	var workspace: PanelContainer = PanelContainer.new()
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var workspace_box: StyleBoxFlat = StyleBoxFlat.new()
	workspace_box.bg_color = Color("#F3DEAA")
	workspace_box.border_width_right = 2
	workspace_box.border_color = PAPER_EDGE
	workspace.add_theme_stylebox_override("panel", workspace_box)
	body.add_child(workspace)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	workspace.add_child(scroll)
	var content_margin: MarginContainer = MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 26)
	content_margin.add_theme_constant_override("margin_right", 26)
	content_margin.add_theme_constant_override("margin_top", 22)
	content_margin.add_theme_constant_override("margin_bottom", 22)
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content_margin)
	_content = VBoxContainer.new()
	_content.custom_minimum_size = Vector2(700, 0)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	content_margin.add_child(_content)
	body.add_child(_build_rail())
	page.add_child(_build_footer())


func _build_header() -> PanelContainer:
	var header: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = WOOD
	box.border_width_bottom = 4
	box.border_color = WOOD_EDGE
	box.content_margin_left = 20.0
	box.content_margin_right = 20.0
	box.content_margin_top = 11.0
	box.content_margin_bottom = 11.0
	header.add_theme_stylebox_override("panel", box)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	header.add_child(row)
	var close_button: Button = Button.new()
	close_button.text = "✕"
	close_button.custom_minimum_size = Vector2(48, 48)
	close_button.tooltip_text = "Return to title"
	close_button.pressed.connect(func() -> void: get_parent().show_title())
	row.add_child(close_button)
	var title: Label = Label.new()
	title.text = "New Game"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", CREAM)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	title.add_theme_constant_override("shadow_offset_y", 2)
	row.add_child(title)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_stepper = HBoxContainer.new()
	_stepper.add_theme_constant_override("separation", 6)
	row.add_child(_stepper)
	return header


func _build_rail() -> PanelContainer:
	var rail: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = WOOD
	box.border_width_left = 4
	box.border_color = WOOD_EDGE
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 18.0
	box.content_margin_bottom = 18.0
	rail.add_theme_stylebox_override("panel", box)
	rail.custom_minimum_size = Vector2(340, 0)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	rail.add_child(column)
	var eyebrow: Label = Label.new()
	eyebrow.text = "YOUR SETUP"
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", CREAM)
	column.add_child(eyebrow)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _paper_box(15))
	column.add_child(panel)
	_rail_body = VBoxContainer.new()
	_rail_body.add_theme_constant_override("separation", 7)
	panel.add_child(_rail_body)
	var rail_spacer: Control = Control.new()
	rail_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(rail_spacer)
	var profile: Label = Label.new()
	profile.text = "%s\nUnlocks and medals save to this profile." % _profile_name()
	profile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profile.add_theme_font_size_override("font_size", 11)
	profile.add_theme_color_override("font_color", Color("#E6B667"))
	column.add_child(profile)
	return rail


func _build_footer() -> PanelContainer:
	var footer: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = WOOD
	box.border_width_top = 4
	box.border_color = WOOD_EDGE
	box.content_margin_left = 24.0
	box.content_margin_right = 24.0
	box.content_margin_top = 11.0
	box.content_margin_bottom = 11.0
	footer.add_theme_stylebox_override("panel", box)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	footer.add_child(row)
	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.custom_minimum_size = Vector2(140, 48)
	_back_button.add_theme_font_size_override("font_size", 16)
	_back_button.pressed.connect(_on_back)
	row.add_child(_back_button)
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color("#F2C982"))
	row.add_child(_status_label)
	_next_button = Button.new()
	_next_button.custom_minimum_size = Vector2(214, 48)
	_next_button.add_theme_font_size_override("font_size", 16)
	TycoonTheme.apply_orange(_next_button)
	_next_button.add_theme_color_override("font_color", Color.WHITE)
	_next_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_next_button.pressed.connect(_on_next)
	row.add_child(_next_button)
	return footer


func _refresh() -> void:
	_rebuild_stepper()
	_rebuild_content()
	_rebuild_rail()
	_back_button.visible = _step > 0
	_next_button.disabled = not _can_advance()
	_next_button.text = "Read briefing  →" if _step == STEP_TITLES.size() - 1 else "Next: %s  →" % STEP_TITLES[_step + 1]
	_status_label.text = _advance_hint()
	call_deferred("_animate_content")


func _on_back() -> void:
	if _step <= 0:
		return
	_step -= 1
	_refresh()


func _on_next() -> void:
	if not _can_advance():
		return
	if _step < STEP_TITLES.size() - 1:
		_step += 1
		_refresh()
		return
	_prepare_briefing()


# --- Stepper ---------------------------------------------------------------


func _rebuild_stepper() -> void:
	_clear(_stepper)
	for index: int in STEP_TITLES.size():
		if index > 0:
			var connector: ColorRect = ColorRect.new()
			connector.custom_minimum_size = Vector2(24, 3)
			connector.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			connector.color = GREEN_EDGE if index <= _step else WOOD_EDGE
			_stepper.add_child(connector)
		var circle: PanelContainer = PanelContainer.new()
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.set_corner_radius_all(999)
		box.set_border_width_all(2)
		if index < _step:
			box.bg_color = GREEN
			box.border_color = GREEN_EDGE
		elif index == _step:
			box.bg_color = RED
			box.border_color = RED_EDGE
		else:
			box.bg_color = WOOD_MID
			box.border_color = WOOD_EDGE
		circle.add_theme_stylebox_override("panel", box)
		circle.custom_minimum_size = Vector2(24, 24)
		var number: Label = Label.new()
		number.text = "✓" if index < _step else str(index + 1)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.add_theme_font_size_override("font_size", 12)
		number.add_theme_color_override("font_color", Color.WHITE if index <= _step else CREAM)
		circle.add_child(number)
		_stepper.add_child(circle)
		var label: Label = Label.new()
		label.text = STEP_TITLES[index]
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color.WHITE if index == _step else Color("#E6B667"))
		_stepper.add_child(label)


# --- Steps -----------------------------------------------------------------


func _rebuild_content() -> void:
	_clear(_content)
	match _step:
		0: _build_mode_step()
		1: _build_company_step()
		2: _build_city_step()
		3: _build_setup_step()
		4: _build_review_step()


func _build_mode_step() -> void:
	_heading("Choose how the story starts", "Campaign progress, challenge records, and tutorial completion belong to your active profile.")
	var grid: GridContainer = _card_grid()
	var campaign: Dictionary = _campaign(CAMPAIGN_ID)
	var campaign_locked: bool = not _is_campaign_unlocked(CAMPAIGN_ID)
	grid.add_child(_selection_card(Color("#EA4A2F"), String(campaign.get("title", "Campaign")),
		String(campaign.get("tagline", "Grow Bella Vista through a connected three-city story.")),
		["3 chapters", _campaign_progress_label()], _mode == &"campaign", campaign_locked,
		"LOCKED" if campaign_locked else "STORY",
		func() -> void: _select_mode(&"campaign")))

	var tutorial: Dictionary = _scenario_by_mode(&"tutorial")
	var tutorial_id: StringName = StringName(String(tutorial.get("id", "")))
	var tutorial_locked: bool = tutorial_id == &"" or not _is_scenario_unlocked(tutorial_id)
	grid.add_child(_selection_card(GREEN, String(tutorial.get("title", "Tutorial")),
		"A guided first shift that watches what you do without taking control.",
		["15–20 min", "Skippable steps"], _mode == &"tutorial", tutorial_locked,
		_record_status(tutorial_id, "GUIDED"), func() -> void: _select_mode(&"tutorial")))

	var free_play: Dictionary = _scenario_by_mode(&"free_play")
	var free_play_id: StringName = StringName(String(free_play.get("id", "")))
	var free_locked: bool = free_play_id == &"" or not _is_scenario_unlocked(free_play_id)
	grid.add_child(_selection_card(Color("#F99A1C"), "Free Play",
		"Choose a city, rivals, seed, and victory rule. Build at your own pace.",
		["Custom setup", "Reproducible seed"], _mode == &"free_play", free_locked,
		"OPEN ENDED" if not free_locked else "LOCKED", func() -> void: _select_mode(&"free_play")))

	var challenge_id: StringName = _first_available_mode_scenario(&"challenge")
	var challenge_locked: bool = challenge_id == &""
	grid.add_child(_selection_card(BLUE, "Challenges",
		"Focused scenarios with fixed constraints, score medals, and compact time limits.",
		["3 challenges", "Best scores"], _mode == &"challenge", challenge_locked,
		"LOCKED" if challenge_locked else "SCORE ATTACK", func() -> void: _select_mode(&"challenge")))


func _build_company_step() -> void:
	_heading("Name the company", "Your brand travels between campaign chapters and marks every restaurant on the map.")
	_content.add_child(_field_label("Company name"))
	var name_edit: LineEdit = LineEdit.new()
	name_edit.text = _company_name
	name_edit.placeholder_text = String(EconomyManager.tuning_value("company.name", "Bella Vista Pizza Co."))
	name_edit.custom_minimum_size = Vector2(420, 46)
	name_edit.add_theme_font_size_override("font_size", 17)
	name_edit.text_changed.connect(func(value: String) -> void:
		_company_name = value
		_rebuild_rail())
	_content.add_child(name_edit)
	_content.add_child(_field_label("Brand color"))
	var swatches: HBoxContainer = HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 10)
	_content.add_child(swatches)
	for hex: String in PLAYER_COLORS:
		var color: Color = Color(hex)
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(46, 46)
		button.tooltip_text = hex
		var normal: StyleBoxFlat = StyleBoxFlat.new()
		normal.bg_color = color
		normal.set_corner_radius_all(12)
		normal.set_border_width_all(4 if color.is_equal_approx(_company_color) else 2)
		normal.border_color = INK if color.is_equal_approx(_company_color) else WOOD_EDGE
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", normal)
		button.add_theme_stylebox_override("pressed", normal)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.pressed.connect(func() -> void:
			_company_color = color
			_refresh())
		swatches.add_child(button)
	var note: Label = Label.new()
	note.text = "Profile unlocks stay separate from this company's session save."
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", INK_MUTED)
	_content.add_child(note)


func _build_city_step() -> void:
	var fixed_city: bool = _mode != &"free_play"
	_heading("Choose a city" if not fixed_city else "Mission city",
		"Each city changes demand, rent pressure, and available systems." if not fixed_city else "Story and challenge scenarios have a fixed city. Locked cities reveal exactly what opens them.")
	var grid: GridContainer = _card_grid()
	for id: StringName in CITY_IDS:
		var city: Dictionary = _city(id)
		if city.is_empty():
			continue
		var profile_locked: bool = not _is_city_unlocked(id)
		var mission_locked: bool = fixed_city and id != _city_id
		var locked: bool = profile_locked or mission_locked
		var traits: Array[String] = _city_trait_labels(city)
		var status: String = "MISSION CITY" if id == _city_id and fixed_city else "SELECTED" if id == _city_id else "LOCKED" if profile_locked else "SET BY MISSION" if mission_locked else "AVAILABLE"
		var description: String = String(city.get("description", city.get("tagline", "")))
		if profile_locked:
			description = _unlock_description(city)
		grid.add_child(_selection_card(_city_color(id), String(city.get("name", String(id).capitalize())),
			description, traits, id == _city_id, locked, status,
			func() -> void: _select_city(id), 174))


func _build_setup_step() -> void:
	match _mode:
		&"campaign": _build_campaign_setup()
		&"challenge": _build_challenge_setup()
		&"tutorial": _build_tutorial_setup()
		_: _build_free_play_setup()


func _build_campaign_setup() -> void:
	_heading("Choose a chapter", "Completed chapters stay replayable. New chapters unlock in sequence and remember your best score.")
	var grid: GridContainer = _card_grid()
	var campaign: Dictionary = _campaign(_campaign_id)
	for chapter_value: Variant in campaign.get("chapters", []):
		if chapter_value is not Dictionary:
			continue
		var chapter: Dictionary = chapter_value
		var scenario_ids: Array = chapter.get("scenario_ids", [])
		if scenario_ids.is_empty():
			continue
		var id: StringName = StringName(String(scenario_ids[0]))
		var scenario: Dictionary = _scenario(id)
		var scenario_city_id: StringName = StringName(String(scenario.get("city_id", chapter.get("city_id", "riverside"))))
		var scenario_city: Dictionary = _city(scenario_city_id)
		var intro: Dictionary = scenario.get("intro", {}) if scenario.get("intro", {}) is Dictionary else {}
		var locked: bool = not _is_scenario_unlocked(id)
		var pills: Array[String] = [String(scenario_city.get("name", chapter.get("city_id", "City")))]
		var days: int = int(scenario.get("time_limit_days", 0))
		if days > 0:
			pills.append("%d days" % days)
		grid.add_child(_selection_card(_city_color(StringName(String(chapter.get("city_id", "riverside")))),
			"Chapter %d · %s" % [int(chapter.get("order", 0)), String(chapter.get("title", scenario.get("title", "Chapter")))],
			String(chapter.get("description", intro.get("briefing", ""))), pills,
			id == _scenario_id, locked, _record_status(id, "AVAILABLE"), func() -> void: _select_scenario(id), 178))


func _build_challenge_setup() -> void:
	_heading("Choose a challenge", "Every challenge fixes its city, rivals, systems, and deadline. Your profile keeps the best score and medal.")
	var grid: GridContainer = _card_grid()
	for scenario: Dictionary in _scenarios_for_mode(&"challenge"):
		var id: StringName = StringName(String(scenario.get("id", "")))
		var locked: bool = not _is_scenario_unlocked(id)
		var city: Dictionary = _city(StringName(String(scenario.get("city_id", ""))))
		var intro: Dictionary = scenario.get("intro", {}) if scenario.get("intro", {}) is Dictionary else {}
		var pills: Array[String] = [String(city.get("name", "City")), "%d days" % int(scenario.get("time_limit_days", 0))]
		grid.add_child(_selection_card(BLUE, String(scenario.get("title", "Challenge")),
			String(intro.get("briefing", "A focused score challenge.")), pills,
			id == _scenario_id, locked, _record_status(id, "AVAILABLE"), func() -> void: _select_scenario(id), 184))


func _build_tutorial_setup() -> void:
	_heading("Your first shift", "The tutorial observes normal play. Skip individual steps or reset the walkthrough whenever you want.")
	var scenario: Dictionary = _scenario(_scenario_id)
	var intro: Dictionary = scenario.get("intro", {}) if scenario.get("intro", {}) is Dictionary else {}
	var grid: GridContainer = _card_grid()
	grid.add_child(_selection_card(GREEN, String(scenario.get("title", "Your First Shift")),
		String(intro.get("briefing", "Learn the rhythm of a restaurant.")),
		["Camera", "Open a location", "Run a shift", "Read the report"], true, false,
		_record_status(_scenario_id, "READY"), Callable(), 190))
	_content.add_child(_setup_note("Guidance never takes over the camera or company controls. Tutorial state is stored on your profile."))


func _build_free_play_setup() -> void:
	_heading("Set the house rules", "Choose rivals, a reproducible seed, and whether this city has a finish line.")
	_content.add_child(_field_label("Competition"))
	var grid: GridContainer = _card_grid()
	for id: StringName in _profile_ids:
		var profile: CompetitorProfile = CompanyManager.profiles[id]
		var selected: bool = _selected_rivals.has(id)
		grid.add_child(_selection_card(profile.brand_color, profile.display_name, profile.tagline,
			_trait_pills(profile), selected, false, "SELECTED" if selected else String(profile.difficulty).to_upper(),
			func() -> void: _toggle_rival(id), 162))

	_content.add_child(_field_label("World seed"))
	var seed_row: HBoxContainer = HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	_content.add_child(seed_row)
	var seed_edit: LineEdit = LineEdit.new()
	seed_edit.text = _seed_text
	seed_edit.placeholder_text = "Blank uses the scenario's stable seed"
	seed_edit.custom_minimum_size = Vector2(300, 42)
	seed_edit.text_changed.connect(func(value: String) -> void:
		_seed_text = value
		_rebuild_rail())
	seed_row.add_child(seed_edit)
	var shuffle_button: Button = Button.new()
	shuffle_button.text = "Shuffle seed"
	shuffle_button.custom_minimum_size = Vector2(130, 42)
	shuffle_button.pressed.connect(func() -> void:
		_seed_text = str(randi_range(1, 999999999))
		_refresh())
	seed_row.add_child(shuffle_button)

	_content.add_child(_field_label("Rival sharpness"))
	var difficulty_row: HBoxContainer = HBoxContainer.new()
	difficulty_row.add_theme_constant_override("separation", 8)
	_content.add_child(difficulty_row)
	for level: StringName in [&"easy", &"normal", &"hard"]:
		var chip: Button = BellaUi.chip(String(level).capitalize(), _difficulty == level)
		chip.pressed.connect(func() -> void:
			_difficulty = level
			_refresh())
		difficulty_row.add_child(chip)

	_content.add_child(_field_label("Victory rule"))
	var victory_row: HBoxContainer = HBoxContainer.new()
	victory_row.add_theme_constant_override("separation", 8)
	_content.add_child(victory_row)
	for preset: StringName in [&"endless", &"cash", &"reputation"]:
		var chip: Button = BellaUi.chip(_victory_label(preset), _victory_preset == preset)
		chip.pressed.connect(func() -> void:
			_victory_preset = preset
			_refresh())
		victory_row.add_child(chip)


func _build_review_step() -> void:
	_heading("Ready for the briefing?", "This exact configuration and seed are stored with the session, so the setup is reproducible.")
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _paper_box(18))
	_content.add_child(panel)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)
	rows.add_child(_summary_row("Mode", _mode_label()))
	rows.add_child(_summary_row("Mission", _scenario_title()))
	rows.add_child(_summary_swatch_row("Company", _display_company_name(), _company_color))
	rows.add_child(_summary_row("City", _city_name()))
	rows.add_child(_summary_row("Difficulty", String(_difficulty).capitalize()))
	rows.add_child(_summary_row("Rivals", _rival_summary()))
	rows.add_child(_summary_row("Seed", str(_resolved_seed())))
	rows.add_child(_summary_row("Starting cash", _starting_cash_label()))
	rows.add_child(_summary_row("Victory", _victory_summary()))
	var scenario: Dictionary = _scenario(_scenario_id)
	var rules: Dictionary = scenario.get("restrictions", {}) if scenario.get("restrictions", {}) is Dictionary else {}
	var disabled: Array = rules.get("disabled_systems", [])
	if not disabled.is_empty():
		_content.add_child(_setup_note("Scenario restrictions: %s" % ", ".join(_string_array(disabled))))
	if SaveSystem.save_state() != &"none":
		var warning: Label = Label.new()
		warning.text = "Your current session save remains until you save this new game over it. Profile progress is unaffected."
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warning.add_theme_font_size_override("font_size", 12)
		warning.add_theme_color_override("font_color", RED_EDGE)
		_content.add_child(warning)


# --- Selection -------------------------------------------------------------


func _select_mode(mode_id: StringName) -> void:
	_mode = mode_id
	_campaign_id = CAMPAIGN_ID if mode_id == &"campaign" else &""
	match mode_id:
		&"campaign": _choose_initial_campaign_scenario()
		&"challenge": _select_scenario(_first_available_mode_scenario(&"challenge"), false)
		&"tutorial": _select_scenario(_first_available_mode_scenario(&"tutorial"), false)
		_: _select_scenario(_first_available_mode_scenario(&"free_play"), false)
	_refresh()


func _select_city(id: StringName) -> void:
	if _mode != &"free_play" or not _is_city_unlocked(id):
		return
	_city_id = id
	_refresh()


func _select_scenario(id: StringName, refresh: bool = true) -> void:
	if id == &"" or not _is_scenario_unlocked(id):
		return
	_scenario_id = id
	var scenario: Dictionary = _scenario(id)
	_city_id = StringName(String(scenario.get("city_id", "riverside")))
	_selected_rivals = _scenario_rival_ids(scenario)
	if refresh:
		_refresh()


func _toggle_rival(id: StringName) -> void:
	if _selected_rivals.has(id):
		_selected_rivals.erase(id)
	else:
		_selected_rivals.append(id)
	_selected_rivals.sort()
	_refresh()


func _choose_initial_campaign_scenario() -> void:
	var campaign: Dictionary = _campaign(CAMPAIGN_ID)
	var first_locked: StringName = &""
	for chapter_value: Variant in campaign.get("chapters", []):
		if chapter_value is not Dictionary:
			continue
		var ids: Array = (chapter_value as Dictionary).get("scenario_ids", [])
		for value: Variant in ids:
			var id: StringName = StringName(String(value))
			if first_locked == &"":
				first_locked = id
			if _is_scenario_unlocked(id) and not _has_completed(id):
				_select_scenario(id, false)
				return
			if _is_scenario_unlocked(id):
				first_locked = id
	if first_locked != &"":
		_select_scenario(first_locked, false)


# --- Config and launch -----------------------------------------------------


func _prepare_briefing() -> void:
	var config: GameSessionConfig = _make_config()
	var proceed: Callable = func() -> void: _commit_and_show_briefing(config)
	if SaveSystem.save_state() == &"ok":
		TycoonConfirmDialog.ask(self, "Start a new game?",
			"Your existing session stays until you save the new game over it. Profile unlocks are always kept.",
			proceed, "Continue")
		return
	proceed.call()


func _commit_and_show_briefing(config: GameSessionConfig) -> void:
	if not GameSetup.has_method("configure_session"):
		_status_label.text = "Session services are still starting. Try again in a moment."
		return
	var accepted: Variant = GameSetup.call("configure_session", config)
	if accepted is bool and not bool(accepted):
		_status_label.text = "That setup could not be validated. Review the selected mission."
		return
	get_parent().show_intro(config)


func _make_config() -> GameSessionConfig:
	var config: GameSessionConfig = GameSessionConfig.new()
	config.mode = _mode
	config.seed = _resolved_seed()
	config.city_id = _city_id
	config.scenario_id = _scenario_id
	config.campaign_id = _campaign_id
	config.difficulty = _difficulty
	config.difficulty_overrides = _difficulty_overrides()
	config.company_identity = {
		"name": _display_company_name(),
		"color": "#%s" % _company_color.to_html(false),
	}
	config.starting_resources = _starting_resources()
	config.rivals = _rivals_for_config()
	config.enabled_systems = _enabled_systems()
	config.victory_rules = _victory_rules()
	return config


func _resolved_seed() -> int:
	var value: String = _seed_text.strip_edges()
	if value.is_valid_int():
		var numeric: int = abs(int(value))
		return numeric if numeric > 0 else 1
	if not value.is_empty():
		return _positive_hash(value)
	var scenario: Dictionary = _scenario(_scenario_id)
	var starting: Dictionary = scenario.get("starting_state", {}) if scenario.get("starting_state", {}) is Dictionary else {}
	var stable_key: String = String(starting.get("seed", "%s|%s|%s" % [_mode, _scenario_id, _city_id]))
	return _positive_hash(stable_key)


func _positive_hash(value: String) -> int:
	return posmod(hash(value), 2147483646) + 1


func _difficulty_overrides() -> Dictionary:
	match _difficulty:
		&"easy": return {"rival_reaction_scale": 1.25, "rival_forecast_scale": 0.8}
		&"hard": return {"rival_reaction_scale": 0.75, "rival_forecast_scale": 1.2}
	return {"rival_reaction_scale": 1.0, "rival_forecast_scale": 1.0}


func _starting_resources() -> Dictionary:
	var scenario: Dictionary = _scenario(_scenario_id)
	var resources: Dictionary = {}
	if scenario.get("starting_state", {}) is Dictionary:
		resources = (scenario.get("starting_state", {}) as Dictionary).duplicate(true)
	resources["city_id"] = String(_city_id)
	return resources


func _rivals_for_config() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var scenario: Dictionary = _scenario(_scenario_id)
	var source_by_id: Dictionary = {}
	for value: Variant in scenario.get("rivals", []):
		if value is Dictionary:
			var rival: Dictionary = value
			source_by_id[StringName(String(rival.get("id", "")))] = rival
	var ids: Array[StringName] = _selected_rivals if _mode == &"free_play" else _scenario_rival_ids(scenario)
	for id: StringName in ids:
		var entry: Dictionary = (source_by_id.get(id, {}) as Dictionary).duplicate(true)
		entry["id"] = String(id)
		entry["difficulty"] = String(_difficulty) if _mode == &"free_play" else String(entry.get("difficulty", _difficulty))
		entry["starting_restaurant_count"] = int(entry.get("starting_restaurant_count", 1))
		entry["starting_cash"] = float(entry.get("starting_cash", 18000.0))
		result.append(entry)
	return result


func _enabled_systems() -> Array[StringName]:
	var result: Array[StringName] = []
	var scenario: Dictionary = _scenario(_scenario_id)
	var restrictions: Dictionary = scenario.get("restrictions", {}) if scenario.get("restrictions", {}) is Dictionary else {}
	for value: Variant in restrictions.get("enabled_systems", []):
		var id: StringName = StringName(String(value))
		if not result.has(id):
			result.append(id)
	if _mode == &"free_play":
		var flags: Dictionary = _city(_city_id).get("system_flags", {})
		for key: Variant in flags:
			var id: StringName = StringName(String(key))
			if bool(flags[key]) and not result.has(id):
				result.append(id)
	return result


func _victory_rules() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _mode == &"free_play":
		match _victory_preset:
			&"cash":
				result.append({"id": "free_play_cash", "kind": "required", "text": "Grow the treasury to $50,000", "metric": "cash", "operator": ">=", "target": 50000.0, "initial_state": "active"})
			&"reputation":
				result.append({"id": "free_play_reputation", "kind": "required", "text": "Reach 4.5 reputation", "metric": "reputation", "operator": ">=", "target": 4.5, "initial_state": "active"})
		return result
	for value: Variant in _scenario(_scenario_id).get("objectives", []):
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result


# --- Catalog and progression ----------------------------------------------


func _catalog() -> Variant:
	var catalog: Variant = GameSetup.get("catalog")
	if catalog != null:
		return catalog
	if _fallback_catalog == null:
		_fallback_catalog = load("res://scripts/campaign/scenario_catalog.gd").new()
		_fallback_catalog.call("load_all")
	return _fallback_catalog


func _city(id: StringName) -> Dictionary:
	var catalog: Variant = _catalog()
	return catalog.call("city", id) as Dictionary if catalog != null and catalog.has_method("city") else {}


func _scenario(id: StringName) -> Dictionary:
	var catalog: Variant = _catalog()
	return catalog.call("scenario", id) as Dictionary if catalog != null and catalog.has_method("scenario") else {}


func _campaign(id: StringName) -> Dictionary:
	var catalog: Variant = _catalog()
	return catalog.call("campaign", id) as Dictionary if catalog != null and catalog.has_method("campaign") else {}


func _scenarios_for_mode(mode_id: StringName) -> Array[Dictionary]:
	var catalog: Variant = _catalog()
	if catalog != null and catalog.has_method("scenarios_for_mode"):
		return catalog.call("scenarios_for_mode", mode_id) as Array[Dictionary]
	return []


func _scenario_by_mode(mode_id: StringName) -> Dictionary:
	var scenarios: Array[Dictionary] = _scenarios_for_mode(mode_id)
	return scenarios[0] if not scenarios.is_empty() else {}


func _first_available_mode_scenario(mode_id: StringName) -> StringName:
	for scenario: Dictionary in _scenarios_for_mode(mode_id):
		var id: StringName = StringName(String(scenario.get("id", "")))
		if _is_scenario_unlocked(id):
			return id
	return &""


func _campaign_manager() -> Variant:
	return GameSetup.get("campaign_manager")


func _is_campaign_unlocked(id: StringName) -> bool:
	var manager: Variant = _campaign_manager()
	return bool(manager.call("is_campaign_unlocked", id)) if manager != null and manager.has_method("is_campaign_unlocked") else true


func _is_scenario_unlocked(id: StringName) -> bool:
	if id == &"":
		return false
	var manager: Variant = _campaign_manager()
	return bool(manager.call("is_scenario_unlocked", id)) if manager != null and manager.has_method("is_scenario_unlocked") else true


func _is_city_unlocked(id: StringName) -> bool:
	var manager: Variant = _campaign_manager()
	return bool(manager.call("is_city_unlocked", id)) if manager != null and manager.has_method("is_city_unlocked") else true


func _has_completed(id: StringName) -> bool:
	var profile: Variant = _profile()
	return bool(profile.call("has_completed_scenario", id)) if profile != null and profile.has_method("has_completed_scenario") else false


func _best_score(id: StringName) -> int:
	var manager: Variant = _campaign_manager()
	return int(manager.call("best_score", id)) if manager != null and manager.has_method("best_score") else 0


func _medal(id: StringName) -> String:
	var manager: Variant = _campaign_manager()
	return String(manager.call("medal", id)) if manager != null and manager.has_method("medal") else ""


func _profile() -> Variant:
	var manager: Variant = _campaign_manager()
	return manager.get("profile") if manager != null else null


# --- Cards and shared widgets ---------------------------------------------


func _selection_card(banner_color: Color, title_text: String, body_text: String,
		pills: Array[String], selected: bool, locked: bool, status: String,
		on_click: Callable, height: float = 158.0) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, height)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PAPER_SUNK if locked else PAPER
	box.set_corner_radius_all(18)
	box.set_border_width_all(4 if selected else 3)
	box.border_color = RED_EDGE if selected else INK_MUTED if locked else WOOD_MID
	if selected:
		box.shadow_color = Color(0.92, 0.29, 0.18, 0.3)
		box.shadow_size = 7
	card.add_theme_stylebox_override("panel", box)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var banner: PanelContainer = PanelContainer.new()
	var banner_box: StyleBoxFlat = StyleBoxFlat.new()
	banner_box.bg_color = Color("#8F7551") if locked else banner_color
	banner_box.corner_radius_top_left = 15
	banner_box.corner_radius_top_right = 15
	banner_box.content_margin_left = 12.0
	banner_box.content_margin_right = 12.0
	banner_box.content_margin_top = 8.0
	banner_box.content_margin_bottom = 8.0
	banner.add_theme_stylebox_override("panel", banner_box)
	column.add_child(banner)
	var status_label: Label = Label.new()
	status_label.text = "LOCKED  ·  %s" % status if locked and status != "LOCKED" else status
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", Color.WHITE)
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	banner.add_child(status_label)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 11)
	column.add_child(margin)
	var info: VBoxContainer = VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	margin.add_child(info)
	var title: Label = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", INK_MUTED if locked else INK)
	info.add_child(title)
	var body: Label = Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 12)
	body.add_theme_color_override("font_color", INK_MUTED if locked else INK_SOFT)
	info.add_child(body)
	if not pills.is_empty():
		var pill_row: HBoxContainer = HBoxContainer.new()
		pill_row.add_theme_constant_override("separation", 5)
		info.add_child(pill_row)
		for text: String in pills:
			pill_row.add_child(BellaUi.pill(text, INK_SOFT, PAPER_SUNK, Color("#EAD59B")))
	if not locked and on_click.is_valid():
		var hit_target: Button = Button.new()
		hit_target.text = ""
		hit_target.tooltip_text = title_text
		hit_target.focus_mode = Control.FOCUS_ALL
		hit_target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit_target.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		hit_target.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
		var hover: StyleBoxFlat = StyleBoxFlat.new()
		hover.bg_color = Color(1, 1, 1, 0.06)
		hover.set_corner_radius_all(15)
		hit_target.add_theme_stylebox_override("hover", hover)
		var pressed: StyleBoxFlat = hover.duplicate()
		pressed.bg_color = Color(0.25, 0.12, 0.04, 0.09)
		hit_target.add_theme_stylebox_override("pressed", pressed)
		var focus: StyleBoxFlat = StyleBoxFlat.new()
		focus.bg_color = Color(1, 1, 1, 0.02)
		focus.set_corner_radius_all(15)
		focus.set_border_width_all(3)
		focus.border_color = GOLD
		hit_target.add_theme_stylebox_override("focus", focus)
		hit_target.pressed.connect(on_click)
		card.add_child(hit_target)
	return card


func _rebuild_rail() -> void:
	if _rail_body == null:
		return
	_clear(_rail_body)
	_rail_body.add_child(_summary_row("Mode", _mode_label()))
	_rail_body.add_child(_summary_row("Mission", _scenario_title()))
	_rail_body.add_child(_summary_swatch_row("Company", _display_company_name(), _company_color))
	_rail_body.add_child(_summary_row("City", _city_name()))
	_rail_body.add_child(_summary_row("Rivals", str(_selected_rivals.size())))
	_rail_body.add_child(_summary_row("Difficulty", String(_difficulty).capitalize()))
	_rail_body.add_child(_rule())
	_rail_body.add_child(_summary_row("Starting cash", _starting_cash_label(), GOLD_EDGE))
	_rail_body.add_child(_summary_row("Seed", str(_resolved_seed())))
	_rail_body.add_child(_summary_row("Victory", _victory_summary()))


func _heading(title_text: String, subtitle_text: String) -> void:
	var heading: Label = Label.new()
	heading.text = title_text
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", INK)
	_content.add_child(heading)
	var subtitle: Label = Label.new()
	subtitle.text = subtitle_text
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", INK_SOFT)
	_content.add_child(subtitle)


func _field_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", INK_SOFT)
	return label


func _card_grid() -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)
	return grid


func _summary_row(label_text: String, value_text: String, value_color: Color = INK) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label: Label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", INK_SOFT)
	row.add_child(label)
	var value: Label = Label.new()
	value.text = value_text
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.custom_minimum_size.x = 112
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 13)
	value.add_theme_color_override("font_color", value_color)
	row.add_child(value)
	return row


func _summary_swatch_row(label_text: String, value_text: String, color: Color) -> HBoxContainer:
	var row: HBoxContainer = _summary_row(label_text, value_text)
	var swatch: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(6)
	box.set_border_width_all(2)
	box.border_color = WOOD_EDGE
	swatch.add_theme_stylebox_override("panel", box)
	swatch.custom_minimum_size = Vector2(20, 20)
	row.add_child(swatch)
	row.move_child(swatch, 1)
	return row


func _setup_note(text: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color("#E8D49B")
	box.set_corner_radius_all(12)
	box.content_margin_left = 13.0
	box.content_margin_right = 13.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", box)
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", INK_SOFT)
	panel.add_child(label)
	return panel


func _paper_box(radius: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PAPER
	box.set_corner_radius_all(radius)
	box.set_border_width_all(3)
	box.border_color = PAPER_EDGE
	box.content_margin_left = 15.0
	box.content_margin_right = 15.0
	box.content_margin_top = 13.0
	box.content_margin_bottom = 13.0
	return box


func _rule() -> ColorRect:
	var rule: ColorRect = ColorRect.new()
	rule.color = Color(0.29, 0.16, 0.09, 0.22)
	rule.custom_minimum_size = Vector2(0, 1)
	return rule


# --- Display helpers -------------------------------------------------------


func _mode_label() -> String:
	return String(_mode).replace("_", " ").capitalize()


func _scenario_title() -> String:
	return String(_scenario(_scenario_id).get("title", "Select a mission"))


func _city_name() -> String:
	return String(_city(_city_id).get("name", String(_city_id).replace("_", " ").capitalize()))


func _display_company_name() -> String:
	var value: String = _company_name.strip_edges()
	return value if not value.is_empty() else String(EconomyManager.tuning_value("company.name", "Bella Vista Pizza Co."))


func _profile_name() -> String:
	var profile: Variant = _profile()
	if profile == null:
		return "Local Profile"
	var id: String = String(profile.get("profile_id"))
	return id.replace("_", " ").capitalize() if not id.is_empty() else "Local Profile"


func _record_status(id: StringName, fallback: String) -> String:
	if id == &"":
		return "LOCKED"
	var medal: String = _medal(id)
	var score: int = _best_score(id)
	if not medal.is_empty():
		return "%s · %d" % [medal.to_upper(), score]
	if score > 0:
		return "BEST · %d" % score
	if _has_completed(id):
		return "COMPLETE"
	return fallback


func _campaign_progress_label() -> String:
	var completed: int = 0
	var total: int = 0
	for chapter_value: Variant in _campaign(CAMPAIGN_ID).get("chapters", []):
		if chapter_value is not Dictionary:
			continue
		for value: Variant in (chapter_value as Dictionary).get("scenario_ids", []):
			total += 1
			if _has_completed(StringName(String(value))):
				completed += 1
	return "%d/%d complete" % [completed, total]


func _starting_cash_label() -> String:
	return "$%.0f" % float(_starting_resources().get("cash", EconomyManager.tuning_value("company.starting_cash", 20000.0)))


func _rival_summary() -> String:
	if _selected_rivals.is_empty():
		return "None"
	var names: Array[String] = []
	for id: StringName in _selected_rivals:
		var profile: Variant = CompanyManager.profiles.get(id)
		names.append(String(profile.get("display_name")) if profile != null else String(id).capitalize())
	return ", ".join(names)


func _victory_summary() -> String:
	if _mode != &"free_play":
		var scenario: Dictionary = _scenario(_scenario_id)
		var days: int = int(scenario.get("time_limit_days", 0))
		return "%d day scenario" % days if days > 0 else "Scenario objectives"
	return _victory_label(_victory_preset)


func _victory_label(preset: StringName) -> String:
	match preset:
		&"cash": return "$50k treasury"
		&"reputation": return "4.5 reputation"
	return "Endless"


func _preset_from_rules(rules: Array[Dictionary]) -> StringName:
	if rules.is_empty():
		return &"endless"
	var metric: StringName = StringName(String(rules[0].get("metric", "")))
	return &"reputation" if metric == &"reputation" else &"cash"


func _scenario_rival_ids(scenario: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in scenario.get("rivals", []):
		if value is Dictionary:
			var id: StringName = StringName(String((value as Dictionary).get("id", "")))
			if id != &"":
				result.append(id)
	return result


func _city_trait_labels(city: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in city.get("strategic_traits", []):
		if value is Dictionary:
			result.append(String((value as Dictionary).get("label", "Trait")))
		if result.size() >= 3:
			break
	return result


func _unlock_description(city: Dictionary) -> String:
	var requirement: Dictionary = city.get("unlock_requirement", {}) if city.get("unlock_requirement", {}) is Dictionary else {}
	return String(requirement.get("description", "Complete more campaign chapters to unlock this city."))


func _city_color(id: StringName) -> Color:
	match id:
		&"harbor_quarter": return BLUE
		&"bella_heights": return Color("#B05CC7")
	return GREEN


func _trait_pills(profile: CompetitorProfile) -> Array[String]:
	var result: Array[String] = []
	if profile.aggression >= 0.7:
		result.append("Aggressive")
	elif profile.aggression <= 0.35:
		result.append("Defensive")
	else:
		result.append("Balanced")
	if profile.expansion_appetite >= 0.7:
		result.append("Expands fast")
	if profile.price_bias <= 0.3:
		result.append("Price war")
	elif profile.price_bias >= 0.7:
		result.append("Premium")
	return result


func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(String(value).replace("_", " ").capitalize())
	return result


func _can_advance() -> bool:
	if _scenario_id == &"" or _city_id == &"":
		return false
	if not _is_scenario_unlocked(_scenario_id):
		return false
	return true


func _advance_hint() -> String:
	if _scenario_id == &"":
		return "Choose an available mode to continue."
	if not _is_scenario_unlocked(_scenario_id):
		return "This mission is locked on the active profile."
	return "%s · %s" % [_mode_label(), _scenario_title()]


func _animate_content() -> void:
	if _content == null:
		return
	_content.modulate.a = 0.0
	_content.position.y += 10.0
	var target_y: float = _content.position.y - 10.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_content, "modulate:a", 1.0, 0.16)
	tween.tween_property(_content, "position:y", target_y, 0.2)


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
