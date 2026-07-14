extends Control
## Title screen (design A1): logo badge, game title, New Game / Load /
## Settings. Load reflects the save state — pre-v4 saves surface as
## "incompatible" and route to the Load screen for deletion.

const LOGO_PATH: String = "res://assets/ui/logo_badge.png"

var _ink: Color = Color("#3A2010")
var _ink_soft: Color = Color("#6E4326")


func _ready() -> void:
	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(column)

	if ResourceLoader.exists(LOGO_PATH):
		var logo: TextureRect = TextureRect.new()
		logo.texture = load(LOGO_PATH)
		logo.custom_minimum_size = Vector2(150, 150)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(logo)

	var title: Label = Label.new()
	title.text = "Bella Vista Pizza Co."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", _ink)
	title.add_theme_color_override("font_shadow_color", Color(0.23, 0.13, 0.06, 0.28))
	title.add_theme_constant_override("shadow_offset_y", 3)
	column.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "Build the tastiest empire in town."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", _ink_soft)
	column.add_child(subtitle)

	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	column.add_child(gap)

	var save_state: StringName = SaveSystem.save_state()

	var new_btn: Button = _menu_button("New Game", true)
	new_btn.pressed.connect(func() -> void: _root().show_wizard())
	column.add_child(new_btn)

	var load_btn: Button = _menu_button("Load Game", false)
	load_btn.disabled = save_state == &"none"
	load_btn.pressed.connect(func() -> void: _root().show_load())
	column.add_child(load_btn)

	if save_state == &"incompatible":
		var note: Label = Label.new()
		note.text = "Existing save is from an older version."
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", Color("#C7331C"))
		column.add_child(note)

	var settings_btn: Button = _menu_button("Settings", false)
	settings_btn.disabled = true
	settings_btn.tooltip_text = "Coming soon"
	column.add_child(settings_btn)


func _menu_button(text: String, primary: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300, 52)
	button.add_theme_font_size_override("font_size", 20)
	if primary:
		TycoonTheme.apply_orange(button)
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_shadow_color", Color(0.23, 0.13, 0.06, 0.45))
		button.add_theme_constant_override("shadow_offset_y", 2)
	return button


func _root() -> Control:
	return get_parent()
