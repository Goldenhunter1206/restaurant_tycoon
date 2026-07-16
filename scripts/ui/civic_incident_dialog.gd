class_name CivicIncidentDialog
extends Control
## Government enforcement modal (feature 13). When the police raid the
## PLAYER's company over criminal heat, the game pauses and this scrimmed
## dialog states what happened, what it cost, and where to deal with it.
## Mirrors PoliceIncidentDialog (F3 design); restores game speed on close.

const RED: Color = Color("#ea4a2f")
const RED_EDGE: Color = Color("#97230f")
const INK: Color = Color("#3a2010")
const MUTED: Color = Color("#92704d")

var _gov: Node
var _payload: Dictionary = {}
var _open_city_hall: Callable = Callable()
var _prev_speed: int = 1


## Pauses the game and pops the dialog over `parent`. `payload` is the
## GovernmentManager.police_incident Dictionary; `open_city_hall` jumps to the
## City Hall screen (Fines & Legal) when provided.
static func present(parent: Node, gov: Node, payload: Dictionary,
		open_city_hall: Callable = Callable()) -> void:
	var dialog: CivicIncidentDialog = CivicIncidentDialog.new()
	dialog._gov = gov
	dialog._payload = payload
	dialog._open_city_hall = open_city_hall
	parent.add_child(dialog)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prev_speed = GameClock.speed
	GameClock.set_speed(0)
	var scrim: ColorRect = ColorRect.new()
	scrim.color = Color(0.16, 0.08, 0.03, 0.62)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(_build_panel())


func _build_panel() -> PanelContainer:
	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(560, 0)
	frame.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_lg_box())
	var paper: PanelContainer = PanelContainer.new()
	paper.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	frame.add_child(paper)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	paper.add_child(col)
	# Red title bar with GAME PAUSED chip.
	var bar: PanelContainer = PanelContainer.new()
	var bar_style: StyleBoxFlat = StyleBoxFlat.new()
	bar_style.bg_color = RED
	bar_style.border_color = RED_EDGE
	bar_style.border_width_bottom = 3
	bar_style.set_corner_radius_all(12)
	bar_style.set_content_margin_all(12.0)
	bar.add_theme_stylebox_override("panel", bar_style)
	col.add_child(bar)
	var bar_row: HBoxContainer = HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 10)
	bar.add_child(bar_row)
	bar_row.add_child(UiAssets.icon_rect(&"handcuffs", 28))
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(titles)
	titles.add_child(_label("Police raid — your company", 18, Color.WHITE, true))
	titles.add_child(_label("Investigators moved on your operations", 12, Color("#ffe0da")))
	bar_row.add_child(BellaUi.pill("GAME PAUSED", RED, Color.WHITE, Color.WHITE))
	# 2x2 stat grid.
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	var fine: float = float(_payload.get("fine", 0.0))
	var standing: Dictionary = {}
	if _gov != null and _gov.has_method("standing_label"):
		standing = _gov.call("standing_label", _payload.get("company_id", &"player"))
	grid.add_child(_stat_cell("Fine issued", "$%.0f" % fine, true))
	grid.add_child(_stat_cell("Operations", "Frozen pending review", true))
	grid.add_child(_stat_cell("Crew", "Arrests made", true))
	grid.add_child(_stat_cell("Official standing", String(standing.get("text", "Standing: Poor")).replace("Standing: ", "")))
	var hint: Label = _label("Evidence was seized. Heat cooled — but the fine is on your legal record.", 13, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)
	# Actions.
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 9)
	col.add_child(actions)
	if _open_city_hall.is_valid():
		var hall_btn: Button = Button.new()
		hall_btn.text = "Open City Hall"
		TycoonTheme.apply_orange(hall_btn)
		hall_btn.pressed.connect(func() -> void:
			var open_call: Callable = _open_city_hall
			_close()
			open_call.call())
		actions.add_child(hall_btn)
	var ok_btn: Button = Button.new()
	ok_btn.text = "Acknowledge"
	ok_btn.pressed.connect(_close)
	actions.add_child(ok_btn)
	return frame


func _stat_cell(title: String, value: String, danger: bool = false) -> PanelContainer:
	var cell: PanelContainer = PanelContainer.new()
	cell.add_theme_stylebox_override("panel", BellaUi.sunk_box(12))
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	cell.add_child(col)
	col.add_child(_label(title.to_upper(), 10, MUTED, true))
	col.add_child(_label(value, 15, RED if danger else INK, true))
	return cell


func _label(text: String, size: int, color: Color, _bold: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _close() -> void:
	GameClock.set_speed(_prev_speed)
	queue_free()
