class_name EventsPanel
extends PanelContainer
## UPCOMING EVENTS — the next scheduled economy beats (festival, rent review,
## inspection) from EconomyManager.upcoming_events(). Refreshes on day change.

const KIND_ICONS: Dictionary = {
	"festival": &"megaphone", "rent": &"rent", "inspection": &"magnifier",
	"competition": &"trophy",
}

var _rows: VBoxContainer
var _assets: GDScript = load("res://scripts/ui/ui_assets.gd")


func _ready() -> void:
	add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
	custom_minimum_size = Vector2(252.0, 0.0)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	box.add_child(header)
	var clock_icon: TextureRect = _assets.icon_rect(&"clock", 18)
	header.add_child(clock_icon)
	var title: Label = Label.new()
	title.text = "UPCOMING EVENTS"
	title.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_BODY)
	title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	header.add_child(title)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	box.add_child(_rows)

	GameClock.day_changed.connect(func(_day: int) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	for child: Node in _rows.get_children():
		child.queue_free()
	for event: Dictionary in EconomyManager.upcoming_events(2):
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var icon_name: StringName = KIND_ICONS.get(String(event["kind"]), &"bell")
		row.add_child(_assets.icon_rect(icon_name, 15))
		var title: Label = Label.new()
		title.text = String(event["title"])
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var when: Label = Label.new()
		when.text = String(event["when"])
		when.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		row.add_child(when)
		_rows.add_child(row)
