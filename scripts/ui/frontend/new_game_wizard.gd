extends Control
## New Game Wizard (design A3): Mode → Company → City → Rivals → Review.
## Two-column layout with a persistent "YOUR SETUP" rail; step 4 is the
## competitor picker where each rival card carries its personality trait and
## difficulty. Choices are committed to GameSetup on Start.

const STEP_TITLES: Array[String] = ["Mode", "Company", "City", "Rivals", "Review"]

const INK: Color = Color("#3A2010")
const INK_SOFT: Color = Color("#6E4326")
const INK_MUTED: Color = Color("#9A7245")
const CREAM: Color = Color("#FFF4DC")
const PAPER: Color = Color("#FBEFC9")
const PAPER_SUNK: Color = Color("#F6E4B0")
const WOOD: Color = Color("#A8692A")
const WOOD_EDGE: Color = Color("#6E3D18")
const WOOD_MID: Color = Color("#8A5222")
const RED: Color = Color("#EA4A2F")
const RED_EDGE: Color = Color("#C7331C")
const GREEN: Color = Color("#6FB63A")
const GREEN_EDGE: Color = Color("#4E8F27")
const GOLD: Color = Color("#F5C518")
const GOLD_EDGE: Color = Color("#B5810A")

const PLAYER_COLORS: Array[String] = [
	"#EA4A2F", "#F99A1C", "#F5C518", "#6FB63A",
	"#3AA6D6", "#2380AE", "#8A5222", "#B05CC7",
]

var _step: int = 0
var _mode: StringName = &"free_play"
var _company_name: String = ""
var _company_color: Color = Color("#EA4A2F")
var _selected_rivals: Array[StringName] = []
var _seed_text: String = ""
var _difficulty: StringName = &"medium"

var _stepper: HBoxContainer
var _content: VBoxContainer
var _rail_body: VBoxContainer
var _back_btn: Button
var _next_btn: Button
var _profile_ids: Array[StringName] = []


func _ready() -> void:
	CompanyManager.load_profiles()
	_profile_ids = []
	for id: StringName in CompanyManager.profiles:
		_profile_ids.append(id)
	_profile_ids.sort()
	_build_shell()
	_refresh()


# --- Shell -------------------------------------------------------------------


func _build_shell() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Header: close, title, stepper.
	var header: PanelContainer = PanelContainer.new()
	var header_box: StyleBoxFlat = StyleBoxFlat.new()
	header_box.bg_color = WOOD
	header_box.border_width_bottom = 4
	header_box.border_color = WOOD_EDGE
	header_box.content_margin_left = 20.0
	header_box.content_margin_right = 20.0
	header_box.content_margin_top = 12.0
	header_box.content_margin_bottom = 12.0
	header.add_theme_stylebox_override("panel", header_box)
	column.add_child(header)
	var header_row: HBoxContainer = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 16)
	header.add_child(header_row)
	var close_btn: Button = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(44, 44)
	close_btn.pressed.connect(func() -> void: get_parent().show_title())
	header_row.add_child(close_btn)
	var title: Label = Label.new()
	title.text = "New Game"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", CREAM)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	title.add_theme_constant_override("shadow_offset_y", 2)
	header_row.add_child(title)
	var lead: Control = Control.new()
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(lead)
	_stepper = HBoxContainer.new()
	_stepper.add_theme_constant_override("separation", 6)
	header_row.add_child(_stepper)
	var trail: Control = Control.new()
	trail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(trail)

	# Body: content column + setup rail.
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	column.add_child(body)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var content_margin: MarginContainer = MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 24)
	content_margin.add_theme_constant_override("margin_right", 24)
	content_margin.add_theme_constant_override("margin_top", 20)
	content_margin.add_theme_constant_override("margin_bottom", 20)
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content_margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_child(_content)

	var rail: PanelContainer = PanelContainer.new()
	var rail_box: StyleBoxFlat = StyleBoxFlat.new()
	rail_box.bg_color = WOOD
	rail_box.border_width_left = 4
	rail_box.border_color = WOOD_EDGE
	rail_box.content_margin_left = 18.0
	rail_box.content_margin_right = 18.0
	rail_box.content_margin_top = 18.0
	rail_box.content_margin_bottom = 18.0
	rail.add_theme_stylebox_override("panel", rail_box)
	rail.custom_minimum_size = Vector2(340, 0)
	body.add_child(rail)
	var rail_column: VBoxContainer = VBoxContainer.new()
	rail_column.add_theme_constant_override("separation", 10)
	rail.add_child(rail_column)
	var eyebrow: Label = Label.new()
	eyebrow.text = "YOUR SETUP"
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", CREAM)
	rail_column.add_child(eyebrow)
	var rail_panel: PanelContainer = PanelContainer.new()
	rail_panel.add_theme_stylebox_override("panel", _paper_box(14))
	rail_column.add_child(rail_panel)
	_rail_body = VBoxContainer.new()
	_rail_body.add_theme_constant_override("separation", 6)
	rail_panel.add_child(_rail_body)

	# Footer: Back / Next.
	var footer: PanelContainer = PanelContainer.new()
	var footer_box: StyleBoxFlat = StyleBoxFlat.new()
	footer_box.bg_color = WOOD
	footer_box.border_width_top = 4
	footer_box.border_color = WOOD_EDGE
	footer_box.content_margin_left = 24.0
	footer_box.content_margin_right = 24.0
	footer_box.content_margin_top = 12.0
	footer_box.content_margin_bottom = 12.0
	footer.add_theme_stylebox_override("panel", footer_box)
	column.add_child(footer)
	var footer_row: HBoxContainer = HBoxContainer.new()
	footer.add_child(footer_row)
	_back_btn = Button.new()
	_back_btn.text = "Back"
	_back_btn.custom_minimum_size = Vector2(140, 48)
	_back_btn.add_theme_font_size_override("font_size", 17)
	_back_btn.pressed.connect(_on_back)
	footer_row.add_child(_back_btn)
	var footer_gap: Control = Control.new()
	footer_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(footer_gap)
	_next_btn = Button.new()
	_next_btn.custom_minimum_size = Vector2(200, 48)
	_next_btn.add_theme_font_size_override("font_size", 17)
	TycoonTheme.apply_orange(_next_btn)
	_next_btn.add_theme_color_override("font_color", Color.WHITE)
	_next_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	_next_btn.pressed.connect(_on_next)
	footer_row.add_child(_next_btn)


func _refresh() -> void:
	_rebuild_stepper()
	_rebuild_content()
	_rebuild_rail()
	_back_btn.visible = _step > 0
	_next_btn.text = "Start Game" if _step == STEP_TITLES.size() - 1 else "Next: %s" % STEP_TITLES[_step + 1]


func _on_back() -> void:
	if _step > 0:
		_step -= 1
		_refresh()


func _on_next() -> void:
	if _step < STEP_TITLES.size() - 1:
		_step += 1
		_refresh()
		return
	_start_game()


func _start_game() -> void:
	GameSetup.mode = _mode
	GameSetup.player_name = _company_name.strip_edges()
	GameSetup.player_color = _company_color
	GameSetup.city_id = &"riverside"
	GameSetup.selected_rivals = _selected_rivals.duplicate()
	GameSetup.difficulty = _difficulty
	var seed_input: String = _seed_text.strip_edges()
	if seed_input.is_empty():
		GameSetup.world_seed = 0
	elif seed_input.is_valid_int():
		GameSetup.world_seed = int(seed_input)
	else:
		GameSetup.world_seed = hash(seed_input)
	var root: Control = get_parent()
	if SaveSystem.save_state() == &"ok":
		TycoonConfirmDialog.ask(self, "Start a new game?",
			"Your existing save stays until you save the new game over it.",
			func() -> void: root.start_new_game(), "Start")
		return
	root.start_new_game()


# --- Stepper -----------------------------------------------------------------


func _rebuild_stepper() -> void:
	for child: Node in _stepper.get_children():
		child.queue_free()
	for i: int in STEP_TITLES.size():
		if i > 0:
			var connector: ColorRect = ColorRect.new()
			connector.custom_minimum_size = Vector2(26, 3)
			connector.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			connector.color = GREEN_EDGE if i <= _step else WOOD_EDGE
			_stepper.add_child(connector)
		var circle: PanelContainer = PanelContainer.new()
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.set_corner_radius_all(999)
		box.set_border_width_all(2)
		if i < _step:
			box.bg_color = GREEN
			box.border_color = GREEN_EDGE
		elif i == _step:
			box.bg_color = RED
			box.border_color = RED_EDGE
		else:
			box.bg_color = WOOD
			box.border_color = WOOD_EDGE
		circle.add_theme_stylebox_override("panel", box)
		circle.custom_minimum_size = Vector2(24, 24)
		var number: Label = Label.new()
		number.text = "✓" if i < _step else str(i + 1)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.add_theme_font_size_override("font_size", 12)
		number.add_theme_color_override("font_color", Color.WHITE if i <= _step else CREAM)
		circle.add_child(number)
		_stepper.add_child(circle)
		var step_label: Label = Label.new()
		step_label.text = STEP_TITLES[i]
		step_label.add_theme_font_size_override("font_size", 12)
		step_label.add_theme_color_override("font_color", Color.WHITE if i == _step else Color("#E6B667"))
		_stepper.add_child(step_label)


# --- Step content ------------------------------------------------------------


func _rebuild_content() -> void:
	for child: Node in _content.get_children():
		child.queue_free()
	match _step:
		0: _build_mode_step()
		1: _build_company_step()
		2: _build_city_step()
		3: _build_rivals_step()
		4: _build_review_step()


func _build_mode_step() -> void:
	_heading("Choose a mode", "How do you want to run your empire?")
	var grid: GridContainer = _card_grid()
	grid.add_child(_card(Color("#F99A1C"), "Free Play",
		"Run your pizza empire with no time limit.", [],
		_mode == &"free_play", false,
		func() -> void:
			_mode = &"free_play"
			_refresh()))
	grid.add_child(_card(Color("#9A7245"), "Scenarios", "Coming soon.", [], false, true, Callable()))
	grid.add_child(_card(Color("#9A7245"), "Sandbox", "Coming soon.", [], false, true, Callable()))


func _build_company_step() -> void:
	_heading("Your company", "Name it and pick your brand color — it marks your restaurants on the map.")
	var name_label: Label = _field_label("Company name")
	_content.add_child(name_label)
	var name_edit: LineEdit = LineEdit.new()
	name_edit.text = _company_name
	name_edit.placeholder_text = String(EconomyManager.tuning_value("company.name", "Bella Vista Pizza Co."))
	name_edit.custom_minimum_size = Vector2(340, 44)
	name_edit.add_theme_font_size_override("font_size", 17)
	name_edit.text_changed.connect(func(value: String) -> void:
		_company_name = value
		_rebuild_rail())
	_content.add_child(name_edit)
	_content.add_child(_field_label("Brand color"))
	var swatch_row: HBoxContainer = HBoxContainer.new()
	swatch_row.add_theme_constant_override("separation", 10)
	_content.add_child(swatch_row)
	for hex: String in PLAYER_COLORS:
		var color: Color = Color(hex)
		var swatch: Button = Button.new()
		swatch.custom_minimum_size = Vector2(44, 44)
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = color
		box.set_corner_radius_all(12)
		var selected: bool = color.is_equal_approx(_company_color)
		box.set_border_width_all(4 if selected else 2)
		box.border_color = INK if selected else WOOD_EDGE
		swatch.add_theme_stylebox_override("normal", box)
		swatch.add_theme_stylebox_override("hover", box)
		swatch.add_theme_stylebox_override("pressed", box)
		swatch.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		swatch.pressed.connect(func() -> void:
			_company_color = color
			_refresh())
		swatch_row.add_child(swatch)


func _build_city_step() -> void:
	_heading("Choose a city", "Each city changes demand, rents, and rivals.")
	var grid: GridContainer = _card_grid()
	grid.add_child(_card(Color("#3AA6D6"), "Riverside",
		"A balanced river town — families, offices and a lively downtown.",
		["Your pick of rivals", "Med rent"], true, false, Callable()))
	grid.add_child(_card(Color("#9A7245"), "Portside", "Coming soon.", [], false, true, Callable()))
	grid.add_child(_card(Color("#9A7245"), "Neon Heights", "Coming soon.", [], false, true, Callable()))
	grid.add_child(_card(Color("#9A7245"), "Sunnydale", "Coming soon.", [], false, true, Callable()))


func _build_rivals_step() -> void:
	_heading("Choose your competition",
		"Every rival runs a real company under the same rules as you. Pick who shares your city — more (and harder) rivals means a tougher game.")
	var grid: GridContainer = _card_grid()
	for id: StringName in _profile_ids:
		var prof: CompetitorProfile = CompanyManager.profiles[id]
		var pills: Array[String] = _trait_pills(prof)
		var selected: bool = _selected_rivals.has(id)
		grid.add_child(_rival_card(prof, pills, selected))
	var options_label: Label = _field_label("World options")
	_content.add_child(options_label)
	var seed_row: HBoxContainer = HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	_content.add_child(seed_row)
	var seed_edit: LineEdit = LineEdit.new()
	seed_edit.text = _seed_text
	seed_edit.placeholder_text = "Seed (blank = random)"
	seed_edit.custom_minimum_size = Vector2(220, 40)
	seed_edit.text_changed.connect(func(value: String) -> void:
		_seed_text = value
		_rebuild_rail())
	seed_row.add_child(seed_edit)
	var random_btn: Button = Button.new()
	random_btn.text = "Randomize"
	random_btn.custom_minimum_size = Vector2(0, 40)
	random_btn.pressed.connect(func() -> void:
		_seed_text = str(randi() % 1000000)
		_refresh())
	seed_row.add_child(random_btn)
	var difficulty_row: HBoxContainer = HBoxContainer.new()
	difficulty_row.add_theme_constant_override("separation", 8)
	_content.add_child(_field_label("Rival sharpness (reaction speed + forecast quality)"))
	_content.add_child(difficulty_row)
	for level: StringName in [&"easy", &"medium", &"hard"]:
		var chip: Button = BellaUi.chip(String(level).capitalize(), _difficulty == level)
		chip.pressed.connect(func() -> void:
			_difficulty = level
			_refresh())
		difficulty_row.add_child(chip)


func _build_review_step() -> void:
	_heading("Ready to open?", "Review your setup — you can't change rivals mid-game.")
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _paper_box(16))
	_content.add_child(panel)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)
	rows.add_child(_summary_row("Mode", "Free Play"))
	rows.add_child(_summary_swatch_row("Company", _display_company_name(), _company_color))
	rows.add_child(_summary_row("City", "Riverside"))
	if _selected_rivals.is_empty():
		rows.add_child(_summary_row("Rivals", "None — the city is yours"))
	else:
		for id: StringName in _selected_rivals:
			var prof: CompetitorProfile = CompanyManager.profiles.get(id)
			if prof != null:
				rows.add_child(_summary_swatch_row("Rival", prof.display_name, prof.brand_color))
	rows.add_child(_summary_row("Rival sharpness", String(_difficulty).capitalize()))
	rows.add_child(_summary_row("Seed", _seed_text if not _seed_text.strip_edges().is_empty() else "Random"))
	rows.add_child(_summary_row("Starting cash", "$%.0f" % float(EconomyManager.tuning_value("company.starting_cash", 20000.0))))
	if SaveSystem.save_state() != &"none":
		var warning: Label = Label.new()
		warning.text = "Heads up: saving the new game will overwrite the existing save file."
		warning.add_theme_font_size_override("font_size", 13)
		warning.add_theme_color_override("font_color", Color("#C7331C"))
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(warning)


# --- Cards & widgets ---------------------------------------------------------


func _rival_card(prof: CompetitorProfile, pills: Array[String], selected: bool) -> PanelContainer:
	var id: StringName = prof.id
	return _card(prof.brand_color, prof.display_name, prof.tagline, pills, selected, false,
		func() -> void:
			if _selected_rivals.has(id):
				_selected_rivals.erase(id)
			else:
				_selected_rivals.append(id)
			_refresh(),
		prof.difficulty)


func _card(banner_color: Color, title: String, sub: String, pills: Array[String],
		selected: bool, locked: bool, on_click: Callable, difficulty: StringName = &"") -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PAPER if not locked else PAPER_SUNK
	box.set_corner_radius_all(18)
	if selected:
		box.set_border_width_all(4)
		box.border_color = RED_EDGE
		box.shadow_color = Color(0.92, 0.29, 0.18, 0.3)
		box.shadow_size = 6
	else:
		box.set_border_width_all(3)
		box.border_color = WOOD_MID if not locked else INK_MUTED
	card.add_theme_stylebox_override("panel", box)
	card.custom_minimum_size = Vector2(0, 150)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var banner: PanelContainer = PanelContainer.new()
	var banner_box: StyleBoxFlat = StyleBoxFlat.new()
	banner_box.bg_color = banner_color if not locked else Color("#8f7551")
	banner_box.corner_radius_top_left = 15
	banner_box.corner_radius_top_right = 15
	banner_box.content_margin_left = 12.0
	banner_box.content_margin_top = 8.0
	banner_box.content_margin_bottom = 8.0
	banner.add_theme_stylebox_override("panel", banner_box)
	banner.custom_minimum_size = Vector2(0, 44)
	column.add_child(banner)
	if selected:
		var badge: Label = Label.new()
		badge.text = "Selected ✓"
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		banner.add_child(badge)
	var body: MarginContainer = MarginContainer.new()
	body.add_theme_constant_override("margin_left", 14)
	body.add_theme_constant_override("margin_right", 14)
	body.add_theme_constant_override("margin_top", 8)
	body.add_theme_constant_override("margin_bottom", 10)
	column.add_child(body)
	var info: VBoxContainer = VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	body.add_child(info)
	var name_label: Label = Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", INK if not locked else INK_MUTED)
	info.add_child(name_label)
	var sub_label: Label = Label.new()
	sub_label.text = sub
	sub_label.add_theme_font_size_override("font_size", 12)
	sub_label.add_theme_color_override("font_color", INK_SOFT if not locked else INK_MUTED)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(sub_label)
	if not pills.is_empty() or difficulty != &"":
		var pill_row: HBoxContainer = HBoxContainer.new()
		pill_row.add_theme_constant_override("separation", 6)
		info.add_child(pill_row)
		if difficulty != &"":
			pill_row.add_child(_difficulty_pill(difficulty))
		for text: String in pills:
			pill_row.add_child(BellaUi.pill(text, INK_SOFT, PAPER_SUNK, Color("#EAD59B")))
	if not locked and on_click.is_valid():
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(func(event: InputEvent) -> void:
			var click: InputEventMouseButton = event as InputEventMouseButton
			if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				on_click.call())
	return card


func _difficulty_pill(level: StringName) -> PanelContainer:
	match level:
		&"easy":
			return BellaUi.pill("Easy", Color.WHITE, GREEN, GREEN_EDGE)
		&"hard":
			return BellaUi.pill("Hard", INK, Color("#F26852"), Color("#97230F"))
	return BellaUi.pill("Medium", INK, GOLD, GOLD_EDGE)


func _trait_pills(prof: CompetitorProfile) -> Array[String]:
	var pills: Array[String] = [_archetype(prof)]
	if prof.aggression >= 0.7:
		pills.append("Aggressive")
	elif prof.aggression <= 0.35:
		pills.append("Defensive")
	if prof.expansion_appetite >= 0.7:
		pills.append("Expands fast")
	if prof.price_bias <= 0.3:
		pills.append("Price war")
	elif prof.price_bias >= 0.7:
		pills.append("Premium")
	if prof.quality_bias >= 0.8:
		pills.append("Quality-first")
	pills.append(_marketing_hint(prof))
	return pills


## One prominent personality label per rival, first pill on the card.
func _archetype(prof: CompetitorProfile) -> String:
	if prof.marketing_style >= 0.6:
		return "MARKETER"
	if prof.aggression >= 0.7:
		return "AGGRESSIVE"
	if prof.aggression <= 0.35:
		return "DEFENSIVE"
	if prof.price_bias >= 0.7:
		return "PREMIUM"
	if prof.price_bias <= 0.3:
		return "BUDGET"
	return "BALANCED"


## How loudly this rival advertises — sets expectations for the ad war.
func _marketing_hint(prof: CompetitorProfile) -> String:
	if prof.marketing_style >= 0.6:
		return "Heavy advertiser"
	if prof.marketing_style >= 0.35:
		return "Occasional ads"
	return "Rarely advertises"


# --- Rail & shared widgets ---------------------------------------------------


func _rebuild_rail() -> void:
	for child: Node in _rail_body.get_children():
		child.queue_free()
	_rail_body.add_child(_summary_row("Mode", "Free Play"))
	_rail_body.add_child(_summary_swatch_row("Company", _display_company_name(), _company_color))
	_rail_body.add_child(_summary_row("City", "Riverside"))
	_rail_body.add_child(_summary_row("Rivals", str(_selected_rivals.size())))
	_rail_body.add_child(_summary_row("Sharpness", String(_difficulty).capitalize()))
	var divider: ColorRect = ColorRect.new()
	divider.color = Color(0.29, 0.16, 0.09, 0.22)
	divider.custom_minimum_size = Vector2(0, 1)
	_rail_body.add_child(divider)
	var cash_row: HBoxContainer = HBoxContainer.new()
	var cash_label: Label = Label.new()
	cash_label.text = "Starting cash"
	cash_label.add_theme_font_size_override("font_size", 13)
	cash_label.add_theme_color_override("font_color", INK_SOFT)
	cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cash_row.add_child(cash_label)
	var cash_value: Label = Label.new()
	cash_value.text = "$%.0f" % float(EconomyManager.tuning_value("company.starting_cash", 20000.0))
	cash_value.add_theme_font_size_override("font_size", 15)
	cash_value.add_theme_color_override("font_color", Color("#B5810A"))
	cash_row.add_child(cash_value)
	_rail_body.add_child(cash_row)


func _display_company_name() -> String:
	var trimmed: String = _company_name.strip_edges()
	if trimmed.is_empty():
		return String(EconomyManager.tuning_value("company.name", "Bella Vista Pizza Co."))
	return trimmed


func _heading(title: String, sub: String) -> void:
	var heading: Label = Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", INK)
	_content.add_child(heading)
	var sub_label: Label = Label.new()
	sub_label.text = sub
	sub_label.add_theme_font_size_override("font_size", 14)
	sub_label.add_theme_color_override("font_color", INK_SOFT)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(sub_label)


func _field_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
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


func _summary_row(label_text: String, value_text: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", INK_SOFT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value: Label = Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", INK)
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


func _paper_box(radius: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PAPER
	box.set_corner_radius_all(radius)
	box.set_border_width_all(3)
	box.border_color = Color("#EAD59B")
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 12.0
	box.content_margin_bottom = 12.0
	return box
