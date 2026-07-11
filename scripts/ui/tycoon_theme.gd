class_name TycoonTheme
extends RefCounted
## Builds the warm wooden-cartoon Theme for the tycoon HUD in code.
## Swap-in art later: replace the StyleBoxFlat builders with StyleBoxTexture
## without touching any UI logic. All colors live in the PALETTE dict.

const PALETTE: Dictionary = {
	"panel": Color("#f3e2bc"),
	"panel_dark": Color("#e8d3a8"),
	"panel_light": Color("#faf0d8"),
	"wood": Color("#b97f42"),
	"wood_dark": Color("#8a5a2b"),
	"wood_deep": Color("#6b421c"),
	"text": Color("#4a3318"),
	"accent_red": Color("#d8452e"),
	"accent_green": Color("#3f9b45"),
	"accent_gold": Color("#e8a825"),
	"star": Color("#f2b01e"),
	"bad": Color("#c0392b"),
	"good": Color("#2e7d32"),
}


static func build() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font = _default_font()
	theme.default_font_size = 15
	var text_color: Color = Color("#4a3318")
	theme.set_color("font_color", "Label", text_color)
	theme.set_color("font_color", "Button", Color("#fff6e0"))
	theme.set_color("font_color", "CheckButton", text_color)
	theme.set_color("font_color", "RichTextLabel", text_color)
	theme.set_constant("outline_size", "Label", 0)
	theme.set_font_size("font_size", "Label", 15)
	theme.set_font_size("font_size", "Button", 15)

	theme.set_stylebox("panel", "PanelContainer", panel_box())
	theme.set_stylebox("panel", "Panel", panel_box())

	theme.set_stylebox("normal", "Button", button_box(Color("#b97f42")))
	theme.set_stylebox("hover", "Button", button_box(Color("#c98f4f")))
	theme.set_stylebox("pressed", "Button", button_box(Color("#8a5a2b")))
	theme.set_stylebox("disabled", "Button", button_box(Color("#a99274")))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	var line_box: StyleBoxFlat = StyleBoxFlat.new()
	line_box.bg_color = Color("#faf0d8")
	line_box.set_corner_radius_all(6)
	line_box.set_border_width_all(2)
	line_box.border_color = Color("#b97f42")
	line_box.content_margin_left = 8.0
	line_box.content_margin_right = 8.0
	line_box.content_margin_top = 4.0
	line_box.content_margin_bottom = 4.0
	theme.set_stylebox("normal", "LineEdit", line_box)
	theme.set_color("font_color", "LineEdit", text_color)

	theme.set_stylebox("panel", "PopupPanel", panel_box())
	theme.set_stylebox("scroll", "HScrollBar", _slim_scroll())
	theme.set_stylebox("scroll", "VScrollBar", _slim_scroll())
	return theme


static func _default_font() -> Font:
	## Rounded system font with a color-emoji fallback so icon glyphs render.
	var base: SystemFont = SystemFont.new()
	base.font_names = PackedStringArray([
		"Arial Rounded MT Bold", "Avenir Next", "Helvetica Neue", "Arial",
	])
	var emoji: SystemFont = SystemFont.new()
	emoji.font_names = PackedStringArray(["Apple Color Emoji", "Noto Color Emoji"])
	base.fallbacks = [emoji]
	return base


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


static func _slim_scroll() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color("#e8d3a8")
	box.set_corner_radius_all(4)
	return box


static func stars_text(rating: float) -> String:
	## "★★★★☆ 3.8" style string for labels.
	var full: int = int(roundf(clampf(rating, 0.0, 5.0)))
	return "★".repeat(full) + "☆".repeat(5 - full)
