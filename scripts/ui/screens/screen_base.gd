class_name TycoonScreen
extends PanelContainer
## Base class for modal management screens (Menu, Staff, Finances, ...).
## Subclasses build their content in _build() and refresh state in refresh().

signal closed

var building_id: int = -1

var _content: VBoxContainer


func setup(target_building_id: int) -> void:
	building_id = target_building_id
	custom_minimum_size = Vector2(560, 420)
	add_theme_stylebox_override("panel", TycoonTheme.wood_frame_lg_box())
	var paper: PanelContainer = PanelContainer.new()
	paper.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	add_child(paper)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	paper.add_child(_content)
	var assets: GDScript = load("res://scripts/ui/ui_assets.gd")
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	if assets.icon(screen_icon()) != null:
		header.add_child(assets.icon_rect(screen_icon(), 26))
	var title: Label = Label.new()
	title.text = screen_title()
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn: Button = Button.new()
	close_btn.text = "✕"
	if assets.icon(&"close") != null:
		close_btn.text = ""
		assets.icon_button(close_btn, &"close", 18)
	close_btn.tooltip_text = "Close"
	close_btn.pressed.connect(func() -> void: closed.emit())
	header.add_child(close_btn)
	_content.add_child(header)
	_build()
	refresh()


func restaurant() -> RestaurantState:
	return RestaurantManager.by_building.get(building_id)


## Override: static title shown in the header.
func screen_title() -> String:
	return "Screen"


## Override: header icon name from the UiAssets registry.
func screen_icon() -> StringName:
	return &"pizza"


## Override: build the (static) widget tree under _content.
func _build() -> void:
	pass


## Override: re-read manager state into the widgets.
func refresh() -> void:
	pass


# --- Shared widget helpers ---


func add_section(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color("#8a5a2b"))
	_content.add_child(label)


func add_scroll_list() -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	_content.add_child(scroll)
	return list


func make_row() -> PanelContainer:
	var row: PanelContainer = PanelContainer.new()
	row.add_theme_stylebox_override("panel", TycoonTheme.inner_box())
	return row
