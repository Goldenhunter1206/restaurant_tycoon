class_name BellaUi
extends RefCounted
## Small style helpers matching the Bella Vista hi-fi handoff: pill chips,
## sunk wells, dark wood insets, the green success button and the warm radial
## canvas backdrop. Complements TycoonTheme (which owns the 9-patch skin).

const PAPER_LIT: Color = Color("#FEF8E4")
const PAPER: Color = Color("#FBEFC9")
const PAPER_SUNK: Color = Color("#F6E4B0")
const PAPER_EDGE: Color = Color("#EAD59B")
const WOOD_MID: Color = Color("#C6883A")
const WOOD_EDGE: Color = Color("#8A5222")
const WOOD_DEEP: Color = Color("#6E3D18")
const RED_ACTIVE: Color = Color("#EA4A2F")
const RED_EDGE: Color = Color("#97230F")
const GOLD: Color = Color("#F5C518")
const GOLD_EDGE: Color = Color("#B5810A")
const GREEN: Color = Color("#6FB63A")
const GREEN_EDGE: Color = Color("#356615")
const INK: Color = Color("#3A2010")
const INK_SOFT: Color = Color("#6E4326")


## Rounded pill chip stylebox: red when active, sunk paper when not.
static func chip_style(active: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(999)
	style.content_margin_left = 11.0
	style.content_margin_right = 11.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	if active:
		style.bg_color = RED_ACTIVE
		style.border_color = RED_EDGE
	else:
		style.bg_color = PAPER_SUNK
		style.border_color = PAPER_EDGE
	style.set_border_width_all(2)
	return style


## Toggle-look pill chip button.
static func chip(text: String, active: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 12)
	style_chip(button, active)
	return button


static func style_chip(button: Button, active: bool) -> void:
	var style: StyleBoxFlat = chip_style(active)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color.WHITE if active else INK_SOFT)
	button.add_theme_color_override("font_hover_color", Color.WHITE if active else INK)
	button.add_theme_color_override("font_pressed_color", Color.WHITE if active else INK)


## Static informational pill (e.g. "6 layers · 214mm tall", "UNSAVED DRAFT").
static func pill(text: String, fg: Color, bg: Color, border: Color) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(999)
	style.content_margin_left = 11.0
	style.content_margin_right = 11.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", style)
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", fg)
	panel.add_child(label)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


## Inset paper well (stat tiles, list backgrounds).
static func sunk_box(radius: int = 13) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PAPER_SUNK
	style.border_color = PAPER_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.29, 0.16, 0.06, 0.18)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 1)
	style.set_content_margin_all(6.0)
	return style


## Dark translucent inset used on the wood header (recipe name field).
static func dark_inset() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.16)
	style.border_color = WOOD_DEEP
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


## Paper card for browser tiles / recipe cards.
static func tile_box(border: Color = PAPER_EDGE, border_width: int = 2) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(13)
	style.shadow_color = Color(0.29, 0.16, 0.06, 0.22)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	style.set_content_margin_all(9.0)
	return style


## Chunky green success button (handoff "Save recipe").
static func green_button(button: Button) -> void:
	var states: Dictionary = {
		"normal": GREEN,
		"hover": GREEN.lightened(0.08),
		"pressed": GREEN.darkened(0.12),
		"disabled": GREEN.lerp(Color("#9a9a8a"), 0.55),
	}
	for state: String in states:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = states[state]
		style.border_color = GREEN_EDGE
		style.set_border_width_all(2)
		style.border_width_bottom = 5
		style.set_corner_radius_all(12)
		style.set_content_margin_all(8.0)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("#EAF5DC"))
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))


## Warm radial backdrop behind the assembly canvases.
static func radial_backdrop() -> TextureRect:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color("#F6E4B0"), Color("#E5C784"), Color("#D6B26A")])
	gradient.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.42)
	texture.fill_to = Vector2(0.5, 1.05)
	texture.width = 256
	texture.height = 256
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Sunk card-header row ("Ingredients · 6 items" with an icon).
static func card_header(icon_name: StringName, title: String, trailing: String) -> Dictionary:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PAPER_SUNK
	style.border_color = PAPER_EDGE
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	panel.add_theme_stylebox_override("panel", style)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var icon: TextureRect = UiAssets.icon_rect(icon_name, 20)
	if icon != null:
		row.add_child(icon)
	var title_label: Label = Label.new()
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.add_theme_color_override("font_color", INK)
	row.add_child(title_label)
	var trailing_label: Label = Label.new()
	trailing_label.text = trailing
	trailing_label.add_theme_font_size_override("font_size", 12)
	trailing_label.add_theme_color_override("font_color", WOOD_EDGE)
	row.add_child(trailing_label)
	return {"panel": panel, "title": title_label, "trailing": trailing_label}


## Restyle a TabContainer to the handoff pill-tab look (red active tab).
static func style_tabs(tabs: TabContainer) -> void:
	tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var selected: StyleBoxFlat = StyleBoxFlat.new()
	selected.bg_color = RED_ACTIVE
	selected.border_color = RED_EDGE
	selected.set_border_width_all(2)
	selected.set_corner_radius_all(11)
	selected.set_content_margin_all(7.0)
	selected.content_margin_left = 14.0
	selected.content_margin_right = 14.0
	tabs.add_theme_stylebox_override("tab_selected", selected)
	var unselected: StyleBoxFlat = StyleBoxFlat.new()
	unselected.bg_color = PAPER_SUNK
	unselected.border_color = PAPER_SUNK
	unselected.set_border_width_all(2)
	unselected.set_corner_radius_all(11)
	unselected.set_content_margin_all(7.0)
	unselected.content_margin_left = 14.0
	unselected.content_margin_right = 14.0
	tabs.add_theme_stylebox_override("tab_unselected", unselected)
	var hovered: StyleBoxFlat = unselected.duplicate()
	hovered.bg_color = PAPER_EDGE
	tabs.add_theme_stylebox_override("tab_hovered", hovered)
	tabs.add_theme_color_override("font_selected_color", Color.WHITE)
	tabs.add_theme_color_override("font_unselected_color", INK_SOFT)
	tabs.add_theme_color_override("font_hovered_color", INK)
	tabs.add_theme_constant_override("tab_separation", 5)
