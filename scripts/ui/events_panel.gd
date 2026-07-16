class_name EventsPanel
extends PanelContainer
## UPCOMING EVENTS combines authored scenario beats with the economy calendar.
## Scenario entries lead so campaign promises remain visible and predictable.

const MAX_VISIBLE_EVENTS: int = 4
const KIND_ICONS: Dictionary = {
	"festival": &"megaphone",
	"rent": &"rent",
	"inspection": &"magnifier",
	"competition": &"trophy",
	"prompt_side_mission": &"star",
	"set_rival_aggression": &"trophy",
	"message": &"bell",
	"scenario": &"star",
}

var _rows: VBoxContainer
var _assets: GDScript = load("res://scripts/ui/ui_assets.gd")
var _bound_manager: ScenarioManager


func _ready() -> void:
	add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
	custom_minimum_size = Vector2(270.0, 0.0)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	add_child(box)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	box.add_child(header)
	header.add_child(_assets.icon_rect(&"clock", 18))
	var title: Label = Label.new()
	title.text = "UPCOMING EVENTS"
	title.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_BODY)
	title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	header.add_child(title)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	box.add_child(_rows)

	GameClock.day_changed.connect(_on_day_changed)
	if not GameSetup.services_ready.is_connected(_bind_scenario_manager):
		GameSetup.services_ready.connect(_bind_scenario_manager)
	if not GameSetup.session_initialized.is_connected(_on_session_initialized):
		GameSetup.session_initialized.connect(_on_session_initialized)
	_bind_scenario_manager()
	_refresh()


func _bind_scenario_manager() -> void:
	var manager: ScenarioManager = GameSetup.scenario_manager
	if not is_instance_valid(manager) or manager == _bound_manager:
		return
	_bound_manager = manager
	if not manager.runtime_changed.is_connected(_refresh):
		manager.runtime_changed.connect(_refresh)
	if not manager.scenario_initialized.is_connected(_on_scenario_initialized):
		manager.scenario_initialized.connect(_on_scenario_initialized)


func _on_day_changed(_day: int) -> void:
	_refresh()


func _on_session_initialized(_config: GameSessionConfig) -> void:
	_bind_scenario_manager()
	_refresh()


func _on_scenario_initialized(_definition: ScenarioDef) -> void:
	_refresh()


func _refresh() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		child.queue_free()
	var events: Array[Dictionary] = []
	if is_instance_valid(_bound_manager) and _bound_manager.state != null:
		for event: Dictionary in _bound_manager.upcoming_events(MAX_VISIBLE_EVENTS):
			var scenario_event: Dictionary = event.duplicate(true)
			scenario_event["source"] = "scenario"
			events.append(scenario_event)
	for event: Dictionary in EconomyManager.upcoming_events(MAX_VISIBLE_EVENTS):
		if events.size() >= MAX_VISIBLE_EVENTS:
			break
		if _contains_event(events, String(event.get("id", "")), String(event.get("title", ""))):
			continue
		var economy_event: Dictionary = event.duplicate(true)
		economy_event["source"] = "economy"
		events.append(economy_event)
	if events.is_empty():
		var empty: Label = Label.new()
		empty.text = "No scheduled events"
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		_rows.add_child(empty)
		return
	for event: Dictionary in events:
		_rows.add_child(_event_row(event))


func _event_row(event: Dictionary) -> Control:
	var source: String = String(event.get("source", "economy"))
	var row_panel: PanelContainer = PanelContainer.new()
	row_panel.add_theme_stylebox_override("panel", TycoonTheme.status_box("warning" if source == "scenario" else "info"))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row_panel.add_child(row)
	var kind: String = String(event.get("kind", "scenario"))
	var icon_name: StringName = KIND_ICONS.get(kind, &"bell")
	row.add_child(_assets.icon_rect(icon_name, 16))
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 1)
	row.add_child(copy)
	var title: Label = Label.new()
	title.text = String(event.get("title", "City event"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 13)
	copy.add_child(title)
	var source_label: Label = Label.new()
	source_label.text = "MISSION EVENT" if source == "scenario" else "CITY CALENDAR"
	source_label.add_theme_font_size_override("font_size", 10)
	source_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["accent_red"] if source == "scenario" else TycoonTheme.PALETTE["text_soft"])
	copy.add_child(source_label)
	var when: Label = Label.new()
	when.text = String(event.get("when", "Soon"))
	when.add_theme_font_size_override("font_size", 12)
	when.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	row.add_child(when)
	return row_panel


static func _contains_event(events: Array[Dictionary], event_id: String,
		title: String) -> bool:
	for event: Dictionary in events:
		if not event_id.is_empty() and String(event.get("id", "")) == event_id:
			return true
		if not title.is_empty() and String(event.get("title", "")) == title:
			return true
	return false
