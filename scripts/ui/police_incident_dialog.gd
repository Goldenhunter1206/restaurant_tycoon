class_name PoliceIncidentDialog
extends Control
## F3 · Active-incident modal. When a hostile operation is detected live at a
## player branch, the game pauses and this scrimmed dialog shows the situation
## (nearest unit, response ETA, guards present, evidence) and the player's
## immediate options. Restores the previous game speed on close.

const RED: Color = Color("#ea4a2f")
const RED_EDGE: Color = Color("#97230f")
const INK: Color = Color("#3a2010")
const MUTED: Color = Color("#92704d")

var _crime: Node
var _op_uid: int = -1
var _building_id: int = -1
var _prev_speed: int = 1


## Pauses the game and pops the dialog over `parent`. `op` is a
## CrimeOperationState; `crime` is the CrimeManager node.
static func present(parent: Node, crime: Node, op: Object) -> void:
	var dialog: PoliceIncidentDialog = PoliceIncidentDialog.new()
	dialog._crime = crime
	dialog._op_uid = int(op.get("uid"))
	dialog._building_id = int(op.get("target_building"))
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
	bar_row.add_child(UiAssets.icon_rect(&"bell", 28))
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(titles)
	var op: Object = _crime.call("operation_by_uid", _op_uid)
	var def: Object = _crime.call("action", op.get("action_id")) if op != null else null
	var title: String = "Active incident"
	if def != null:
		title = "Active incident — %s" % def.get("display_name")
	titles.add_child(_label(title, 18, Color.WHITE, true))
	titles.add_child(_label("%s · now" % _branch_name(), 12, Color("#ffe0da")))
	bar_row.add_child(BellaUi.pill("GAME PAUSED", RED, Color.WHITE, Color.WHITE))
	# 2x2 stat grid.
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	var eta: float = _crime.call("police_eta", _building_id)
	var guards: bool = float(_crime.call("guard_effect", _building_id)) > 0.01
	var evidence: float = float(op.get("evidence")) if op != null else 0.0
	grid.add_child(_stat_cell("Nearest unit", "Precinct · available"))
	grid.add_child(_stat_cell("Response ETA", "~%d min" % int(eta)))
	grid.add_child(_stat_cell("Guards present", "Yes" if guards else "None", not guards))
	grid.add_child(_stat_cell("Evidence", "CCTV" if evidence > 0.3 else "Thin", false))
	# Actions.
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 9)
	col.add_child(actions)
	var call_btn: Button = Button.new()
	call_btn.text = "Call police"
	BellaUi.red_button(call_btn)
	call_btn.pressed.connect(func() -> void:
		var incident_uid: int = int(op.get("incident_uid")) if op != null else -1
		_crime.call("call_police_cmd", _company_id(), _building_id, incident_uid)
		_close())
	actions.add_child(call_btn)
	var alert_btn: Button = Button.new()
	alert_btn.text = "Raise alert"
	TycoonTheme.apply_orange(alert_btn)
	alert_btn.pressed.connect(func() -> void:
		_crime.call("set_alert_cmd", _company_id(), _building_id, &"elevated")
		_close())
	actions.add_child(alert_btn)
	var close_btn: Button = Button.new()
	close_btn.text = "Evacuate & close"
	close_btn.pressed.connect(_close)
	actions.add_child(close_btn)
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


func _branch_name() -> String:
	var rest: RestaurantState = RestaurantManager.by_building.get(_building_id)
	return rest.restaurant_name if rest != null else "your branch"


func _company_id() -> StringName:
	return CompanyManager.player.id if CompanyManager.player != null else &"player"


func _close() -> void:
	GameClock.set_speed(_prev_speed)
	queue_free()
