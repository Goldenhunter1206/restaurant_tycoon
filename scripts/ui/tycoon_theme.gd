class_name TycoonTheme
extends RefCounted
## Builds the warm wooden-cartoon Theme for the tycoon HUD in code.
## Production skin: StyleBoxTexture builders backed by assets/ui/*.png with
## StyleBoxFlat fallbacks when a texture is missing. Colors live in PALETTE,
## texture nine-patch specs in TEX_SPECS — tune margins in one place.

const PALETTE: Dictionary = {
	"panel": Color("#f3e2bc"),
	"panel_dark": Color("#e8d3a8"),
	"panel_light": Color("#faf0d8"),
	"wood": Color("#b97f42"),
	"wood_dark": Color("#8a5a2b"),
	"wood_deep": Color("#6b421c"),
	"text": Color("#4a3318"),
	"text_soft": Color("#7a6142"),
	"accent_red": Color("#d8452e"),
	"accent_green": Color("#3f9b45"),
	"accent_gold": Color("#e8a825"),
	"star": Color("#f2b01e"),
	"bad": Color("#c0392b"),
	"good": Color("#2e7d32"),
	"cream": Color("#faf3e0"),
}

const FONT_PATH: String = "res://assets/fonts/display.ttf"
const FONT_SIZE_SMALL: int = 12
const FONT_SIZE_BODY: int = 15
const FONT_SIZE_TITLE: int = 18
const FONT_SIZE_BIG: int = 22

## name -> [path, texture margins (l,t,r,b), content margins (l,t,r,b)]
const TEX_SPECS: Dictionary = {
	"panel_lg": ["res://assets/ui/panel_frame_lg.png", [80, 80, 80, 80], [26, 24, 26, 24]],
	"panel_sm": ["res://assets/ui/panel_frame_sm.png", [20, 20, 20, 20], [16, 14, 16, 14]],
	"paper": ["res://assets/ui/paper_inner.png", [24, 24, 24, 24], [10, 8, 10, 8]],
	"chip": ["res://assets/ui/chip_slot.png", [30, 16, 30, 16], [14, 5, 14, 5]],
	"nav_tab": ["res://assets/ui/nav_tab.png", [24, 24, 24, 24], [12, 6, 12, 6]],
	"nav_tab_active": ["res://assets/ui/nav_tab_active.png", [24, 24, 24, 24], [12, 6, 12, 6]],
	"btn_wood": ["res://assets/ui/btn_wood.png", [15, 15, 15, 15], [10, 4, 10, 4]],
	"btn_wood_hover": ["res://assets/ui/btn_wood_hover.png", [15, 15, 15, 15], [10, 4, 10, 4]],
	"btn_wood_pressed": ["res://assets/ui/btn_wood_pressed.png", [15, 15, 15, 15], [10, 4, 10, 4]],
	"btn_orange": ["res://assets/ui/btn_orange.png", [13, 13, 13, 13], [8, 4, 8, 4]],
	"btn_orange_hover": ["res://assets/ui/btn_orange_hover.png", [13, 13, 13, 13], [8, 4, 8, 4]],
	"btn_orange_pressed": ["res://assets/ui/btn_orange_pressed.png", [13, 13, 13, 13], [8, 4, 8, 4]],
	"action_tile": ["res://assets/ui/action_tile.png", [20, 20, 20, 20], [6, 6, 6, 6]],
	"minimap_frame": ["res://assets/ui/minimap_frame.png", [46, 46, 46, 46], [8, 8, 8, 8]],
	"tooltip": ["res://assets/ui/tooltip_box.png", [13, 13, 13, 13], [10, 6, 10, 6]],
	"feed_row": ["res://assets/ui/feed_row.png", [22, 18, 22, 18], [10, 4, 10, 4]],
}


static func build() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font = _default_font()
	theme.default_font_size = FONT_SIZE_BODY
	var text_color: Color = PALETTE["text"]
	theme.set_color("font_color", "Label", text_color)
	theme.set_color("font_color", "Button", text_color)
	theme.set_color("font_hover_color", "Button", text_color)
	theme.set_color("font_pressed_color", "Button", Color("#fff6e0"))
	theme.set_color("font_color", "CheckButton", text_color)
	theme.set_color("font_color", "RichTextLabel", text_color)
	theme.set_color("default_color", "RichTextLabel", text_color)
	theme.set_constant("outline_size", "Label", 0)
	theme.set_font_size("font_size", "Label", FONT_SIZE_BODY)
	theme.set_font_size("font_size", "Button", FONT_SIZE_BODY)

	theme.set_stylebox("panel", "PanelContainer", panel_box())
	theme.set_stylebox("panel", "Panel", panel_box())

	theme.set_stylebox("normal", "Button", button_box_tex("normal"))
	theme.set_stylebox("hover", "Button", button_box_tex("hover"))
	theme.set_stylebox("pressed", "Button", button_box_tex("pressed"))
	theme.set_stylebox("disabled", "Button", button_box_tex("disabled"))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	var line_box: StyleBoxFlat = StyleBoxFlat.new()
	line_box.bg_color = PALETTE["panel_light"]
	line_box.set_corner_radius_all(6)
	line_box.set_border_width_all(2)
	line_box.border_color = PALETTE["wood"]
	line_box.content_margin_left = 8.0
	line_box.content_margin_right = 8.0
	line_box.content_margin_top = 4.0
	line_box.content_margin_bottom = 4.0
	theme.set_stylebox("normal", "LineEdit", line_box)
	theme.set_color("font_color", "LineEdit", text_color)

	theme.set_stylebox("panel", "PopupPanel", panel_box())
	theme.set_stylebox("panel", "TooltipPanel", tooltip_box_tex())
	theme.set_color("font_color", "TooltipLabel", Color("#fff2d9"))
	theme.set_font_size("font_size", "TooltipLabel", FONT_SIZE_SMALL + 1)
	theme.set_stylebox("scroll", "HScrollBar", _slim_scroll())
	theme.set_stylebox("scroll", "VScrollBar", _slim_scroll())

	var pb_bg: StyleBoxFlat = StyleBoxFlat.new()
	pb_bg.bg_color = PALETTE["panel_dark"].darkened(0.08)
	pb_bg.set_corner_radius_all(5)
	pb_bg.set_border_width_all(1)
	pb_bg.border_color = PALETTE["wood_dark"]
	var pb_fill: StyleBoxFlat = StyleBoxFlat.new()
	pb_fill.bg_color = PALETTE["accent_green"]
	pb_fill.set_corner_radius_all(5)
	theme.set_stylebox("background", "ProgressBar", pb_bg)
	theme.set_stylebox("fill", "ProgressBar", pb_fill)
	theme.set_color("font_color", "ProgressBar", text_color)
	theme.set_font_size("font_size", "ProgressBar", FONT_SIZE_SMALL)
	return theme


static func _default_font() -> Font:
	## Bundled rounded display font; system + emoji fallbacks keep any
	## not-yet-converted glyph icons rendering until the emoji purge.
	var bundled: FontFile = load(FONT_PATH) as FontFile
	var emoji: SystemFont = SystemFont.new()
	emoji.font_names = PackedStringArray(["Apple Color Emoji", "Noto Color Emoji"])
	if bundled != null:
		bundled.fallbacks = [emoji]
		return bundled
	var base: SystemFont = SystemFont.new()
	base.font_names = PackedStringArray([
		"Avenir Next", "Helvetica Neue", "Arial",
	])
	base.fallbacks = [emoji]
	return base


static func tex_box(spec_name: String, fallback: StyleBox = null) -> StyleBox:
	## Nine-patch StyleBoxTexture from TEX_SPECS; flat fallback if missing.
	if not TEX_SPECS.has(spec_name):
		return fallback if fallback != null else panel_box()
	var spec: Array = TEX_SPECS[spec_name]
	if not ResourceLoader.exists(spec[0]):
		return fallback if fallback != null else panel_box()
	var texture: Texture2D = load(spec[0])
	if texture == null:
		return fallback if fallback != null else panel_box()
	var box: StyleBoxTexture = StyleBoxTexture.new()
	box.texture = texture
	var margins: Array = spec[1]
	box.set_texture_margin(SIDE_LEFT, float(margins[0]))
	box.set_texture_margin(SIDE_TOP, float(margins[1]))
	box.set_texture_margin(SIDE_RIGHT, float(margins[2]))
	box.set_texture_margin(SIDE_BOTTOM, float(margins[3]))
	var content: Array = spec[2]
	box.content_margin_left = float(content[0])
	box.content_margin_top = float(content[1])
	box.content_margin_right = float(content[2])
	box.content_margin_bottom = float(content[3])
	return box


static func panel_box(bg: Color = Color("#f3e2bc")) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(10)
	box.set_border_width_all(3)
	box.border_color = Color("#8a5a2b")
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
	box.shadow_size = 4
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


static func inner_box(bg: Color = Color("#faf0d8")) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(8)
	box.set_border_width_all(2)
	box.border_color = Color("#b97f42")
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	return box


static func paper_box() -> StyleBox:
	return tex_box("paper", inner_box())


static func chip_box() -> StyleBox:
	return tex_box("chip", inner_box())


static func feed_row_box() -> StyleBox:
	return tex_box("feed_row", inner_box(PALETTE["cream"]))


static func action_tile_box() -> StyleBox:
	return tex_box("action_tile", button_box(PALETTE["panel_light"]))


static func nav_tab_box(active: bool) -> StyleBox:
	if active:
		return tex_box("nav_tab_active", button_box(PALETTE["accent_red"]))
	return tex_box("nav_tab", button_box(PALETTE["panel_light"]))


static func minimap_frame_box() -> StyleBox:
	var box: StyleBox = tex_box("minimap_frame", panel_box(Color("#c98848")))
	if box is StyleBoxTexture:
		(box as StyleBoxTexture).draw_center = false
	return box


static func tooltip_box_tex() -> StyleBox:
	var fallback: StyleBoxFlat = StyleBoxFlat.new()
	fallback.bg_color = Color("#5a3a1a")
	fallback.set_corner_radius_all(7)
	fallback.set_border_width_all(2)
	fallback.border_color = PALETTE["accent_gold"]
	fallback.content_margin_left = 10.0
	fallback.content_margin_right = 10.0
	fallback.content_margin_top = 6.0
	fallback.content_margin_bottom = 6.0
	return tex_box("tooltip", fallback)


static func button_box(bg: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(9)
	box.set_border_width_all(2)
	box.border_color = Color("#6b421c")
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.2)
	box.shadow_size = 2
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	return box


static func button_box_tex(state: String) -> StyleBox:
	match state:
		"hover":
			return tex_box("btn_wood_hover", button_box(Color("#f3e2bc")))
		"pressed":
			return tex_box("btn_wood_pressed", button_box(Color("#d8452e")))
		"disabled":
			var box: StyleBox = tex_box("btn_wood", button_box(Color("#a99274")))
			if box is StyleBoxTexture:
				(box as StyleBoxTexture).modulate_color = Color(0.72, 0.68, 0.62)
			return box
	return tex_box("btn_wood", button_box(Color("#faf0d8")))


static func orange_button_box(state: String) -> StyleBox:
	match state:
		"hover":
			return tex_box("btn_orange_hover", button_box(PALETTE["accent_gold"].lightened(0.15)))
		"pressed":
			return tex_box("btn_orange_pressed", button_box(PALETTE["accent_red"]))
	return tex_box("btn_orange", button_box(PALETTE["accent_gold"]))


static func apply_orange(button: Button) -> void:
	## Styles a single button with the chunky orange candy look.
	button.add_theme_stylebox_override("normal", orange_button_box("normal"))
	button.add_theme_stylebox_override("hover", orange_button_box("hover"))
	button.add_theme_stylebox_override("pressed", orange_button_box("pressed"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


static func wood_frame_box() -> StyleBox:
	var texture: Texture2D = load("res://assets/ui/wood_panel_frame.png")
	if texture == null:
		return panel_box(Color("#c98848"))
	var box: StyleBoxTexture = StyleBoxTexture.new()
	box.texture = texture
	box.set_texture_margin(SIDE_LEFT, 185.0)
	box.set_texture_margin(SIDE_TOP, 185.0)
	box.set_texture_margin(SIDE_RIGHT, 185.0)
	box.set_texture_margin(SIDE_BOTTOM, 185.0)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 16.0
	box.content_margin_bottom = 16.0
	return box


static func wood_frame_lg_box() -> StyleBox:
	return tex_box("panel_lg", wood_frame_box())


static func wood_frame_sm_box() -> StyleBox:
	return tex_box("panel_sm", panel_box())


static func status_box(severity: String) -> StyleBoxFlat:
	var bg: Color = Color("#e7f4d5")
	var border: Color = Color("#4f9b42")
	match severity:
		"critical":
			bg = Color("#ffe0d6")
			border = Color("#c9432d")
		"warning":
			bg = Color("#fff0bf")
			border = Color("#d88a1d")
		"info":
			bg = Color("#dceef6")
			border = Color("#3f83a5")
	var box: StyleBoxFlat = inner_box(bg)
	box.border_color = border
	box.set_border_width_all(3)
	return box


static func _slim_scroll() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color("#e8d3a8")
	box.set_corner_radius_all(4)
	return box


static func star_row(rating: float, size: int = 16) -> HBoxContainer:
	## Row of 5 star sprites (full/half/empty); falls back to glyph label.
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	var full_tex: Texture2D = _star_tex("full")
	if full_tex == null:
		var label: Label = Label.new()
		label.text = stars_text(rating)
		label.add_theme_color_override("font_color", PALETTE["star"])
		row.add_child(label)
		return row
	var clamped: float = clampf(rating, 0.0, 5.0)
	for i: int in range(5):
		var kind: String = "empty"
		if clamped >= float(i) + 0.75:
			kind = "full"
		elif clamped >= float(i) + 0.25:
			kind = "half"
		var rect: TextureRect = TextureRect.new()
		rect.texture = _star_tex(kind)
		rect.custom_minimum_size = Vector2(size, size)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(rect)
	return row


static func _star_tex(kind: String) -> Texture2D:
	var path: String = "res://assets/ui/star_%s.png" % kind
	if not ResourceLoader.exists(path):
		return null
	return load(path)


static func stars_text(rating: float) -> String:
	## "★★★★☆" style string for BBCode call sites (pre-sprite fallback).
	var full: int = int(roundf(clampf(rating, 0.0, 5.0)))
	return "★".repeat(full) + "☆".repeat(5 - full)
