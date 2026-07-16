class_name FrontendTitleScreen
extends Control
## Poster-like title screen for the Bella Vista frontend. The brand owns the
## left half while continuation and primary navigation sit on one calm action
## plane to the right.

const LOGO_PATH: String = "res://assets/ui/logo_badge.png"

const INK: Color = Color("#3A2010")
const INK_SOFT: Color = Color("#6E4326")
const CREAM: Color = Color("#FFF4DC")
const PAPER: Color = Color("#FBEFC9")
const PAPER_EDGE: Color = Color("#DDBF78")
const WOOD: Color = Color("#8A5222")
const WOOD_EDGE: Color = Color("#43260F")
const RED: Color = Color("#EA4A2F")
const GOLD: Color = Color("#F5C518")

var _hero: Control = null
var _actions: Control = null


func _ready() -> void:
	if not is_instance_valid(GameSetup):
		return
	_build()
	call_deferred("_play_entrance")


func _build() -> void:
	var outer: MarginContainer = MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 58)
	outer.add_theme_constant_override("margin_right", 58)
	outer.add_theme_constant_override("margin_top", 34)
	outer.add_theme_constant_override("margin_bottom", 34)
	add_child(outer)
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", 20)
	outer.add_child(page)
	page.add_child(_build_top_bar())

	var spread: HBoxContainer = HBoxContainer.new()
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spread.add_theme_constant_override("separation", 62)
	page.add_child(spread)
	_hero = _build_hero()
	_hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spread.add_child(_hero)
	_actions = _build_actions()
	spread.add_child(_actions)

	var footer: HBoxContainer = HBoxContainer.new()
	page.add_child(footer)
	var footer_copy: Label = Label.new()
	footer_copy.text = "A pizza empire story"
	footer_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_copy.add_theme_font_size_override("font_size", 11)
	footer_copy.add_theme_color_override("font_color", Color("#C99550"))
	footer.add_child(footer_copy)
	var version: Label = Label.new()
	version.text = "PROFILE PROGRESSION  ·  LOCAL SAVE"
	version.add_theme_font_size_override("font_size", 10)
	version.add_theme_color_override("font_color", Color("#A8753C"))
	footer.add_child(version)


func _build_top_bar() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var mark: Label = Label.new()
	mark.text = "BELLA VISTA"
	mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mark.add_theme_font_size_override("font_size", 13)
	mark.add_theme_color_override("font_color", GOLD)
	row.add_child(mark)
	var profile: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color("#6E3D18")
	box.set_corner_radius_all(999)
	box.set_border_width_all(2)
	box.border_color = Color("#A8692A")
	box.content_margin_left = 13.0
	box.content_margin_right = 13.0
	box.content_margin_top = 7.0
	box.content_margin_bottom = 7.0
	profile.add_theme_stylebox_override("panel", box)
	row.add_child(profile)
	var profile_row: HBoxContainer = HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 8)
	profile.add_child(profile_row)
	var dot: Label = Label.new()
	dot.text = "●"
	dot.add_theme_color_override("font_color", Color("#6FB63A"))
	profile_row.add_child(dot)
	var profile_label: Label = Label.new()
	profile_label.text = "%s  ·  %s" % [_profile_name(), _profile_progress()]
	profile_label.add_theme_font_size_override("font_size", 12)
	profile_label.add_theme_color_override("font_color", CREAM)
	profile_row.add_child(profile_label)
	return row


func _build_hero() -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	var lead: Control = Control.new()
	lead.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(lead)
	if ResourceLoader.exists(LOGO_PATH):
		var logo: TextureRect = TextureRect.new()
		logo.texture = load(LOGO_PATH)
		logo.custom_minimum_size = Vector2(184, 184)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(logo)
	var eyebrow: Label = Label.new()
	eyebrow.text = "THE ORIGINAL PIZZA TYCOON"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", GOLD)
	column.add_child(eyebrow)
	var title: Label = Label.new()
	title.text = "Bella Vista\nPizza Co."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", CREAM)
	title.add_theme_color_override("font_shadow_color", Color(0.08, 0.03, 0.01, 0.72))
	title.add_theme_constant_override("shadow_offset_y", 5)
	column.add_child(title)
	var rule: ColorRect = ColorRect.new()
	rule.color = Color("#D59A42")
	rule.custom_minimum_size = Vector2(120, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(rule)
	var subtitle: Label = Label.new()
	subtitle.text = "Build a neighborhood favorite into a city legend."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color("#E6B667"))
	column.add_child(subtitle)
	var trail: Control = Control.new()
	trail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(trail)
	return column


func _build_actions() -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(420, 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	var top_gap: Control = Control.new()
	top_gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(top_gap)

	var save_state: StringName = SaveSystem.save_state()
	if save_state != &"none":
		column.add_child(_build_continue_card(save_state))

	var new_button: Button = _menu_button("New Game", true)
	new_button.pressed.connect(func() -> void: _root().show_wizard())
	column.add_child(new_button)
	var load_button: Button = _menu_button("Load Game", false)
	load_button.disabled = save_state == &"none"
	load_button.tooltip_text = "No session save found" if load_button.disabled else "Review the current session save"
	load_button.pressed.connect(func() -> void: _root().show_load())
	column.add_child(load_button)
	var settings_button: Button = _menu_button("Settings", false)
	settings_button.pressed.connect(func() -> void:
		_show_notice("Settings", "Audio, display, and accessibility controls are available from the in-game pause menu."))
	column.add_child(settings_button)

	var utility_row: HBoxContainer = HBoxContainer.new()
	utility_row.add_theme_constant_override("separation", 8)
	column.add_child(utility_row)
	var credits_button: Button = _utility_button("Credits")
	credits_button.pressed.connect(func() -> void:
		_show_notice("Credits", "Bella Vista Pizza Co.\nBuilt with care, hot ovens, and an unreasonable amount of mozzarella."))
	utility_row.add_child(credits_button)
	var quit_button: Button = _utility_button("Quit")
	quit_button.pressed.connect(func() -> void:
		TycoonConfirmDialog.ask(self, "Leave Bella Vista?", "Your local progress is safe.", func() -> void: get_tree().quit(), "Quit"))
	utility_row.add_child(quit_button)
	var bottom_gap: Control = Control.new()
	bottom_gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(bottom_gap)
	return column


func _build_continue_card(save_state: StringName) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(420, 132)
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PAPER
	box.set_corner_radius_all(18)
	box.set_border_width_all(4)
	box.border_color = PAPER_EDGE
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 14.0
	box.content_margin_bottom = 14.0
	box.shadow_color = Color(0.08, 0.03, 0.01, 0.4)
	box.shadow_size = 10
	box.shadow_offset = Vector2(0, 5)
	card.add_theme_stylebox_override("panel", box)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 3)
	row.add_child(copy)
	var label: Label = Label.new()
	label.text = "CONTINUE"
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", RED)
	copy.add_child(label)
	var title: Label = Label.new()
	title.text = "Resume your latest company" if save_state == &"ok" else "Older session found"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", INK)
	copy.add_child(title)
	var detail: Label = Label.new()
	detail.text = "Pick up exactly where the city paused." if save_state == &"ok" else "Review or remove this incompatible save."
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", INK_SOFT)
	copy.add_child(detail)
	var continue_button: Button = Button.new()
	continue_button.text = "▶"
	continue_button.custom_minimum_size = Vector2(58, 58)
	continue_button.add_theme_font_size_override("font_size", 20)
	continue_button.tooltip_text = "Continue"
	continue_button.pressed.connect(func() -> void:
		if save_state == &"ok":
			_root().load_saved_game()
		else:
			_root().show_load())
	row.add_child(continue_button)
	return card


func _menu_button(text: String, primary: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(420, 50)
	button.add_theme_font_size_override("font_size", 18)
	if primary:
		TycoonTheme.apply_orange(button)
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_shadow_color", Color(0.23, 0.13, 0.06, 0.45))
		button.add_theme_constant_override("shadow_offset_y", 2)
	return button


func _utility_button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.flat = true
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("#E6B667"))
	button.add_theme_color_override("font_hover_color", CREAM)
	return button


func _show_notice(title_text: String, body_text: String) -> void:
	var scrim: ColorRect = ColorRect.new()
	scrim.color = Color(0.08, 0.03, 0.01, 0.72)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	scrim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 220)
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PAPER
	box.set_corner_radius_all(20)
	box.set_border_width_all(5)
	box.border_color = WOOD_EDGE
	box.content_margin_left = 26.0
	box.content_margin_right = 26.0
	box.content_margin_top = 24.0
	box.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var title: Label = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", INK)
	column.add_child(title)
	var body: Label = Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", INK_SOFT)
	column.add_child(body)
	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(0, 42)
	close_button.pressed.connect(func() -> void: scrim.queue_free())
	column.add_child(close_button)


func _play_entrance() -> void:
	if _hero == null or _actions == null:
		return
	_hero.modulate.a = 0.0
	_actions.modulate.a = 0.0
	_hero.position.y += 14.0
	_actions.position.x += 30.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_hero, "modulate:a", 1.0, 0.32)
	tween.tween_property(_hero, "position:y", _hero.position.y - 14.0, 0.38)
	tween.tween_property(_actions, "modulate:a", 1.0, 0.28).set_delay(0.08)
	tween.tween_property(_actions, "position:x", _actions.position.x - 30.0, 0.36).set_delay(0.08)


func _profile_name() -> String:
	var profile: Variant = _profile()
	if profile == null:
		return "Local Profile"
	var profile_id: String = String(profile.get("profile_id"))
	return profile_id.replace("_", " ").capitalize() if not profile_id.is_empty() else "Local Profile"


func _profile_progress() -> String:
	var profile: Variant = _profile()
	if profile == null:
		return "Ready"
	var completed: Variant = profile.get("completed_scenarios")
	if completed is Array:
		return "%d missions complete" % completed.size()
	return "Ready"


func _profile() -> Variant:
	var manager: Variant = GameSetup.get("campaign_manager")
	return manager.get("profile") if manager != null else null


func _root() -> Control:
	return get_parent()
