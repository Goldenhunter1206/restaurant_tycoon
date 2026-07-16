extends TycoonScreen
## F2 · The Back Room — company-scoped underworld workspace. Dark chrome over
## the standard TycoonScreen frame. Tabs: Crew / Available Actions / Target
## Intel / Active Ops / Extortion. The right rail reviews the selected
## operation (cost, success %, attribution meter, "if caught") and launches it
## behind a hold-to-confirm. Click-only, so the per-minute refresh is safe.

signal request_screen(screen_id: StringName)

const GOLD: Color = Color("#E6B667")
const GOLD_BRIGHT: Color = Color("#F5C518")
const CREAM: Color = Color("#F3E4C4")
const RED: Color = Color("#EA4A2F")
const RED_SOFT: Color = Color("#F79286")
const GREEN: Color = Color("#8FD16A")
const PANEL_BG: Color = Color("#3A2617")
const PANEL_EDGE: Color = Color("#1C0F06")
const INK_DARK: Color = Color("#2A1A0D")
const MUTED: Color = Color("#B08A5E")
const TABS: Array[Array] = [
	[&"crew", "Crew"],
	[&"actions", "Available Actions"],
	[&"intel", "Target Intel"],
	[&"ops", "Active Ops"],
	[&"extortion", "Extortion"],
]

var _active_tab: StringName = &"actions"
var _selected_action: StringName = &""
var _selected_building: int = -1
var _body: VBoxContainer
var _heat_pill: PanelContainer


func screen_title() -> String:
	return "The Back Room"


func screen_icon() -> StringName:
	return &"mask"


func set_screen_id(_id: StringName) -> void:
	pass


func _build() -> void:
	custom_minimum_size = Vector2(940, 640)
	# Dark chrome over the base wood/paper frame.
	var dark_frame: StyleBoxFlat = StyleBoxFlat.new()
	dark_frame.bg_color = INK_DARK
	dark_frame.border_color = PANEL_EDGE
	dark_frame.set_border_width_all(4)
	dark_frame.set_corner_radius_all(16)
	dark_frame.set_content_margin_all(12.0)
	add_theme_stylebox_override("panel", dark_frame)
	var paper: PanelContainer = _content.get_parent() as PanelContainer
	if paper != null:
		var inner: StyleBoxFlat = StyleBoxFlat.new()
		inner.bg_color = Color("#221509")
		inner.set_corner_radius_all(12)
		inner.set_content_margin_all(12.0)
		paper.add_theme_stylebox_override("panel", inner)
	_restyle_header()
	_body = add_scroll_list()


func _restyle_header() -> void:
	var header: HBoxContainer = _content.get_child(0) as HBoxContainer
	if header == null:
		return
	for child: Node in header.get_children():
		if child is Label:
			(child as Label).add_theme_color_override("font_color", GOLD)
	_heat_pill = BellaUi.pill("Heat: 0%", RED_SOFT, Color(0.59, 0.14, 0.06, 0.35), RED)
	header.add_child(_heat_pill)
	header.move_child(_heat_pill, header.get_child_count() - 2)


func refresh() -> void:
	if _body == null:
		return
	for child: Node in _body.get_children():
		child.queue_free()
	var crime: Node = _crime()
	if crime == null or not crime.call("enabled"):
		_locked_notice()
		return
	_update_heat_pill(crime)
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_body.add_child(tabs)
	for tab: Array in TABS:
		tabs.add_child(_dark_chip(String(tab[1]), StringName(tab[0]) == _active_tab, StringName(tab[0])))
	if crime.call("action_tier", _company_id()) <= 0:
		_needs_department(crime)
		return
	match _active_tab:
		&"crew":
			_render_crew(crime)
		&"actions":
			_render_actions(crime)
		&"intel":
			_render_intel(crime)
		&"ops":
			_render_ops(crime)
		&"extortion":
			_render_extortion(crime)


# --- Tabs ------------------------------------------------------------------

func _render_crew(crime: Node) -> void:
	var company_id: StringName = _company_id()
	var crew: Array = crime.call("crew_of", company_id)
	var capacity: int = int(crime.call("crew_capacity", company_id))
	_body.add_child(_eyebrow("Crew · %d / %d" % [crew.size(), capacity]))
	if crew.is_empty():
		_body.add_child(_dark_hint("No crew yet. Recruit from the market below."))
	for agent: CriminalAgentState in crew:
		_body.add_child(_crew_card(agent))
	_body.add_child(_eyebrow("Recruit"))
	if crew.size() >= capacity:
		_body.add_child(_dark_hint(CapabilityRegistry.explain(company_id, &"crime.crew_capacity")))
	var market: Array = crime.call("market_candidates", company_id)
	for candidate: Dictionary in market:
		_body.add_child(_recruit_card(crime, candidate, crew.size() < capacity))


func _render_actions(crime: Node) -> void:
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(split)
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	split.add_child(left)
	left.add_child(_target_picker(crime))
	var available: Array = crime.call("actions_for", _company_id())
	for entry: Dictionary in available:
		left.add_child(_action_card(entry))
	split.add_child(_review_rail(crime))


func _render_intel(crime: Node) -> void:
	var company_id: StringName = _company_id()
	_body.add_child(_eyebrow("Target Intelligence"))
	var seen: Dictionary = {}
	for target: Dictionary in crime.call("target_buildings", company_id):
		var company: StringName = target["company"]
		if seen.has(company):
			continue
		seen[company] = true
		for row: Dictionary in crime.call("target_intel_report", company_id, company):
			_body.add_child(_intel_card(row, String(target.get("company_name", ""))))


func _render_ops(crime: Node) -> void:
	var ops: Array = crime.call("ops_of", _company_id())
	var live: Array[Dictionary] = []
	for op: CrimeOperationState in ops:
		if op.is_live():
			live.append({"op": op})
	_body.add_child(_eyebrow("Active Operations · %d" % live.size()))
	if live.is_empty():
		_body.add_child(_dark_hint("No operations running. Plan one from Available Actions."))
	for op: CrimeOperationState in ops:
		if op.is_live():
			_body.add_child(_op_card(crime, op))


func _render_extortion(crime: Node) -> void:
	var company_id: StringName = _company_id()
	_body.add_child(_eyebrow("Your Demands"))
	var demands: Array = crime.call("outgoing_extortion", company_id)
	if demands.is_empty():
		_body.add_child(_dark_hint("No active demands. Run a Protection Racket to collect."))
	for row: Dictionary in demands:
		_body.add_child(_demand_card(row))


# --- Cards -----------------------------------------------------------------

func _crew_card(agent: CriminalAgentState) -> PanelContainer:
	var card: PanelContainer = _dark_card(PANEL_BG)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	row.add_child(UiAssets.icon_rect(&"people", 28))
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_label(agent.display_name, 15, CREAM, true))
	col.add_child(_label("%s · skill %d%%" % [String(agent.role).capitalize(), int(agent.skill * 100.0)], 12, MUTED))
	var status: String = agent.status_label(GameClock.day)
	var status_color: Color = GREEN if status == "Idle" else RED_SOFT
	row.add_child(_label(status, 12, status_color, true))
	return card


func _recruit_card(crime: Node, candidate: Dictionary, can_hire: bool) -> PanelContainer:
	var card: PanelContainer = _dark_card(PANEL_BG)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_label(String(candidate.get("name", "")), 14, CREAM, true))
	col.add_child(_label("%s · skill %d%% · $%d/day" % [
		String(candidate.get("role", "")).capitalize(),
		int(float(candidate.get("skill", 0.0)) * 100.0),
		int(candidate.get("wage", 0.0))], 12, MUTED))
	var hire: Button = Button.new()
	hire.text = "Hire · $%d" % int(candidate.get("hire_fee", 0.0))
	hire.disabled = not can_hire
	TycoonTheme.apply_orange(hire)
	hire.pressed.connect(func() -> void:
		var result: CommandResult = crime.call("hire_agent_cmd", _company_id(), candidate)
		_toast(result)
		refresh())
	row.add_child(hire)
	return card


func _action_card(entry: Dictionary) -> PanelContainer:
	var def: CrimeActionDef = entry["def"]
	var ok: bool = bool(entry.get("ok", false))
	var selected: bool = def.id == _selected_action
	var card: PanelContainer = _dark_card(PANEL_BG, RED if selected else PANEL_EDGE, 3 if selected else 2)
	card.modulate = Color(1, 1, 1, 1.0 if ok else 0.55)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	row.add_child(UiAssets.icon_rect(def.icon, 30))
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_label(def.display_name, 15, CREAM, true))
	var sub: String = def.blurb if ok else String(entry.get("reason", ""))
	col.add_child(_label(sub, 11, MUTED))
	row.add_child(_label("$%d" % int(def.cost), 13, GOLD_BRIGHT, true))
	var pick: Button = _ghost_button()
	pick.pressed.connect(func() -> void:
		_selected_action = def.id
		refresh())
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_selected_action = def.id
			refresh())
	return card


func _intel_card(row: Dictionary, company_name: String) -> PanelContainer:
	var card: PanelContainer = _dark_card(PANEL_BG)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	col.add_child(_label("%s · %s" % [String(row.get("name", "")), company_name], 14, CREAM, true))
	if not bool(row.get("known", false)):
		col.add_child(_label("No current intel — case the joint first.", 12, MUTED))
		return card
	col.add_child(_label("Security %d%% · %s · equip L%d" % [
		int(float(row.get("security_score", 0.0)) * 100.0),
		"guards" if bool(row.get("guards", false)) else "no guards",
		int(row.get("equipment_level", 0))], 12, MUTED))
	var vulns: Array = row.get("vulnerabilities", [])
	if not vulns.is_empty():
		var names: Array[String] = []
		for v: Variant in vulns:
			names.append(String(v).replace("_", " "))
		col.add_child(_label("Weak points: %s" % ", ".join(names), 11, GREEN))
	return card


func _op_card(crime: Node, op: CrimeOperationState) -> PanelContainer:
	var card: PanelContainer = _dark_card(PANEL_BG)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	card.add_child(col)
	var def: CrimeActionDef = crime.call("action", op.action_id)
	var title: String = def.display_name if def != null else String(op.action_id)
	col.add_child(_label("%s → %s" % [title, _branch_label(op.target_building)], 14, CREAM, true))
	col.add_child(_label("Phase: %s" % String(op.phase).capitalize(), 12, GOLD))
	var track: ProgressBar = ProgressBar.new()
	track.min_value = 0.0
	track.max_value = 1.0
	track.value = op.progress_at(GameClock.total_minutes())
	track.show_percentage = false
	track.custom_minimum_size = Vector2(0, 10)
	col.add_child(track)
	if op.can_cancel():
		var cancel: Button = _ghost_button("Call it off")
		cancel.pressed.connect(func() -> void:
			_toast(crime.call("cancel_operation_cmd", _company_id(), op.uid))
			refresh())
		col.add_child(cancel)
	return card


func _demand_card(row: Dictionary) -> PanelContainer:
	var card: PanelContainer = _dark_card(PANEL_BG)
	var col: VBoxContainer = VBoxContainer.new()
	card.add_child(col)
	var status: String = String(row.get("status", "open"))
	col.add_child(_label("$%d from %s" % [int(row.get("amount", 0.0)), String(row.get("target_company", ""))], 14, GOLD_BRIGHT, true))
	col.add_child(_label("%s · due day %d" % [status.capitalize(), int(row.get("deadline_day", 0))], 12, MUTED))
	return card


# --- Review rail -----------------------------------------------------------

func _review_rail(crime: Node) -> PanelContainer:
	var rail: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color("#2E1D0F")
	box.border_color = PANEL_EDGE
	box.set_border_width_all(3)
	box.set_corner_radius_all(16)
	box.set_content_margin_all(14.0)
	rail.add_theme_stylebox_override("panel", box)
	rail.custom_minimum_size = Vector2(300, 0)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	rail.add_child(col)
	col.add_child(_label("Review Operation", 15, GOLD, true))
	if _selected_action == &"" or _selected_building < 0:
		col.add_child(_label("Pick a target and an action to plan a job.", 12, MUTED))
		return rail
	var preview: Dictionary = crime.call("preview_operation", _company_id(), _selected_action, _selected_building)
	var def: CrimeActionDef = crime.call("action", _selected_action)
	col.add_child(_stat_line("Target", _branch_label(_selected_building)))
	col.add_child(_stat_line("Cost", "$%d" % int(preview.get("cost", 0.0)), GOLD_BRIGHT))
	col.add_child(_stat_line("Travel", "~%d min" % int(preview.get("travel_minutes", 0))))
	if bool(preview.get("uncertain", false)):
		col.add_child(_stat_line("Success", "unknown", MUTED))
	else:
		col.add_child(_stat_line("Success", "%d%%" % int(float(preview.get("success_chance", 0.0)) * 100.0), GREEN))
	col.add_child(_risk_meter("Attribution risk", float(preview.get("evidence_risk", 0.0))))
	var defenses: Array = preview.get("known_defenses", [])
	if not defenses.is_empty():
		var lines: Array[String] = []
		for d: Variant in defenses:
			lines.append(String(d))
		col.add_child(_label("Known defenses: %s" % ", ".join(lines), 11, MUTED))
	var warn: PanelContainer = _dark_card(Color(0.59, 0.14, 0.06, 0.25), RED, 2)
	warn.add_child(_label(String(preview.get("collateral", "")) if def != null else "", 11, RED_SOFT))
	col.add_child(warn)
	col.add_child(_spacer())
	if bool(preview.get("ok", false)):
		var confirm: HoldToConfirmButton = HoldToConfirmButton.new()
		confirm.text = "Hold to Launch"
		confirm.confirmed.connect(func() -> void:
			var result: CommandResult = crime.call("launch_operation_cmd", _company_id(), _selected_action, _selected_building)
			_toast(result)
			if result != null and result.ok:
				_selected_action = &""
				_active_tab = &"ops"
			refresh())
		col.add_child(confirm)
	else:
		col.add_child(_label(String(preview.get("reason", "Not available.")), 12, RED_SOFT))
	return rail


func _target_picker(crime: Node) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label("Target", 13, GOLD))
	var picker: OptionButton = OptionButton.new()
	var targets: Array = crime.call("target_buildings", _company_id())
	for target: Dictionary in targets:
		picker.add_item("%s — %s" % [String(target["name"]), String(target["company_name"])], int(target["building_id"]))
	if _selected_building < 0 and not targets.is_empty():
		_selected_building = int(targets[0]["building_id"])
	if _selected_building >= 0:
		picker.selected = maxi(0, picker.get_item_index(_selected_building))
	picker.item_selected.connect(func(index: int) -> void:
		_selected_building = picker.get_item_id(index)
		refresh())
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	return row


# --- Locked / empty states -------------------------------------------------

func _locked_notice() -> void:
	_body.add_child(_eyebrow("The Back Room is Closed"))
	_body.add_child(_dark_hint("The underworld is disabled in this game."))


func _needs_department(crime: Node) -> void:
	_body.add_child(_eyebrow("No Back Room Yet"))
	_body.add_child(_dark_hint(CapabilityRegistry.explain(_company_id(), &"crime.crew_capacity")))
	var open_hq: Button = _ghost_button("Open Headquarters")
	open_hq.pressed.connect(func() -> void: request_screen.emit(&"headquarters"))
	_body.add_child(open_hq)
	var _unused: Node = crime


# --- Small builders --------------------------------------------------------

func _update_heat_pill(crime: Node) -> void:
	if _heat_pill == null:
		return
	var heat_state: CompanyHeatState = crime.call("heat_for", _company_id())
	var label: Label = _heat_pill.get_child(0) as Label
	if label != null:
		label.text = "Heat: %d%%" % int(heat_state.heat)


func _dark_chip(text: String, active: bool, tab_id: StringName) -> Button:
	var chip: Button = Button.new()
	chip.text = text
	chip.focus_mode = Control.FOCUS_NONE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = RED if active else Color("#3A2617")
	style.border_color = Color("#97230F") if active else PANEL_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(11)
	style.content_margin_left = 13.0
	style.content_margin_right = 13.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	for s: String in ["normal", "hover", "pressed"]:
		chip.add_theme_stylebox_override(s, style)
	chip.add_theme_color_override("font_color", Color.WHITE if active else CREAM)
	chip.pressed.connect(func() -> void:
		_active_tab = tab_id
		refresh())
	return chip


func _dark_card(bg: Color, border: Color = PANEL_EDGE, border_width: int = 2) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(12.0)
	card.add_theme_stylebox_override("panel", style)
	return card


func _stat_line(label_text: String, value: String, value_color: Color = CREAM) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var l: Label = _label(label_text, 12, MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(_label(value, 13, value_color, true))
	return row


func _risk_meter(label_text: String, value: float) -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.add_child(_stat_line(label_text, "%d%%" % int(clampf(value, 0.0, 1.0) * 100.0), RED_SOFT))
	var track: ProgressBar = ProgressBar.new()
	track.min_value = 0.0
	track.max_value = 1.0
	track.value = clampf(value, 0.0, 1.0)
	track.show_percentage = false
	track.custom_minimum_size = Vector2(0, 10)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = RED
	fill.set_corner_radius_all(6)
	track.add_theme_stylebox_override("fill", fill)
	col.add_child(track)
	return col


func _eyebrow(text: String) -> Label:
	return _label(text.to_upper(), 12, GOLD, true)


func _dark_hint(text: String) -> Label:
	var l: Label = _label(text, 12, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _label(text: String, size: int, color: Color, bold: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_constant_override("outline_size", 0)
	return l


func _ghost_button(text: String = "Select") -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("#4A2F18")
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(7.0)
	for s: String in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(s, style)
	button.add_theme_color_override("font_color", GOLD)
	return button


func _spacer() -> Control:
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer


func _branch_label(building_id: int) -> String:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	return rest.restaurant_name if rest != null else "target"


func _toast(result: CommandResult) -> void:
	if result == null:
		return
	if not result.ok:
		EconomyManager.post_message("alert", result.message)


func _company_id() -> StringName:
	return CompanyManager.player.id if CompanyManager.player != null else &"player"


func _crime() -> Node:
	return get_tree().root.get_node_or_null("CrimeManager")
