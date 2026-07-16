extends TycoonScreen
## D11 · Security & Incidents — per-restaurant defense and incident log. Tabs:
## Coverage / Guards / Incidents / Recovery / Police & Insurance. Warm wood
## chrome (unlike the dark underworld screen). Click-only, so the per-minute
## refresh is safe; the active tab and branch persist.

const INK: Color = Color("#3a2010")
const MUTED: Color = Color("#92704d")
const RED: Color = Color("#ea4a2f")
const RED_EDGE: Color = Color("#97230f")
const GREEN: Color = Color("#6fb63a")
const GOLD_EDGE: Color = Color("#b5810a")
const TABS: Array[Array] = [
	[&"coverage", "Coverage"],
	[&"guards", "Guards"],
	[&"incidents", "Incidents"],
	[&"recovery", "Recovery"],
	[&"police", "Police & Insurance"],
]

var _active_tab: StringName = &"coverage"
var _body: VBoxContainer


func screen_title() -> String:
	return "Security & Incidents"


func screen_icon() -> StringName:
	return &"shield"


func _build() -> void:
	custom_minimum_size = Vector2(900, 620)
	_build_branch_picker()
	_body = add_scroll_list()


func refresh() -> void:
	if _body == null:
		return
	for child: Node in _body.get_children():
		child.queue_free()
	var crime: Node = _crime()
	if crime == null or not crime.call("enabled"):
		_body.add_child(_hint("Security systems are inactive — the underworld is disabled in this game."))
		return
	var rest: RestaurantState = restaurant()
	if rest == null:
		_body.add_child(_hint("Select a branch to review its security."))
		return
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_body.add_child(tabs)
	for tab: Array in TABS:
		var chip: Button = BellaUi.chip(String(tab[1]), StringName(tab[0]) == _active_tab)
		chip.pressed.connect(func() -> void:
			_active_tab = StringName(tab[0])
			refresh())
		tabs.add_child(chip)
	var sec: SecurityState = crime.call("security_for", rest.building_id)
	match _active_tab:
		&"coverage":
			_render_coverage(crime, sec)
		&"guards":
			_render_guards(crime, rest, sec)
		&"incidents":
			_render_incidents(crime, sec)
		&"recovery":
			_render_recovery(crime, sec)
		&"police":
			_render_police(crime, sec)


# --- Coverage --------------------------------------------------------------

func _render_coverage(crime: Node, sec: SecurityState) -> void:
	var score: float = crime.call("security_score_for", sec.building_id)
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	_body.add_child(split)
	var card: PanelContainer = _tile()
	card.custom_minimum_size = Vector2(240, 0)
	split.add_child(card)
	var col: VBoxContainer = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(col)
	col.add_child(_eyebrow("Security Score"))
	var big: Label = Label.new()
	big.text = "%d%%" % int(score * 100.0)
	big.add_theme_font_size_override("font_size", 48)
	big.add_theme_color_override("font_color", GOLD_EDGE)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(big)
	var alert_pill: PanelContainer = _alert_pill(sec.alert_level)
	alert_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(alert_pill)
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)
	right.add_child(_eyebrow("Coverage"))
	var guard_effect: float = crime.call("guard_effect", sec.building_id)
	var svc: Object = crime.get("security_math")
	if svc != null:
		for row: Dictionary in svc.call("coverage_breakdown", sec, guard_effect):
			right.add_child(_bar_row(String(row.get("label", "")), float(row.get("value", 0.0)), GREEN))
		var vulns: Array = svc.call("vulnerabilities", sec, guard_effect)
		if not vulns.is_empty():
			var names: Array[String] = []
			for v: Variant in vulns:
				names.append(String(v).replace("_", " ").capitalize())
			right.add_child(_callout("Weak points: %s" % ", ".join(names)))
	right.add_child(_eyebrow("Alert Posture"))
	var alert_row: HBoxContainer = HBoxContainer.new()
	alert_row.add_theme_constant_override("separation", 6)
	right.add_child(alert_row)
	for level: StringName in [&"normal", &"elevated", &"lockdown"]:
		var chip: Button = BellaUi.chip(String(level).capitalize(), sec.alert_level == level)
		chip.pressed.connect(func() -> void:
			_toast(crime.call("set_alert_cmd", _company_id(), sec.building_id, level))
			refresh())
		alert_row.add_child(chip)


# --- Guards ----------------------------------------------------------------

func _render_guards(crime: Node, rest: RestaurantState, _sec: SecurityState) -> void:
	var capacity: int = int(crime.call("crew_capacity", _company_id()))  # unused; guard cap below
	var guard_cap: int = CapabilityRegistry.capacity(_company_id(), &"security.guard_capacity")
	var guards: Array[StaffMember] = []
	for member: StaffMember in rest.staff:
		var def: StaffTypeDef = RestaurantManager.staff_type(member.type_id)
		if def != null and def.operational_tags.has(&"security"):
			guards.append(member)
	_body.add_child(_eyebrow("Guards · %d / %d" % [guards.size(), guard_cap]))
	if guard_cap <= 0:
		_body.add_child(_callout(CapabilityRegistry.explain(_company_id(), &"security.guard_capacity")))
	for guard: StaffMember in guards:
		_body.add_child(_guard_card(guard))
	_body.add_child(_eyebrow("Hire a Guard"))
	if guards.size() >= guard_cap:
		_body.add_child(_hint("Guard capacity is full. Build the Security department for more."))
	else:
		var pool: Array[JobCandidate] = RestaurantManager.candidates_for(&"guard")
		if pool.is_empty():
			_body.add_child(_hint("No guards on the market right now — check back tomorrow."))
		for candidate: JobCandidate in pool:
			_body.add_child(_guard_candidate_card(rest, candidate))
	var _unused: int = capacity


# --- Incidents -------------------------------------------------------------

func _render_incidents(crime: Node, sec: SecurityState) -> void:
	_body.add_child(_eyebrow("Incident Log"))
	if sec.incidents.is_empty():
		_body.add_child(_hint("No incidents recorded. A quiet block is a good block."))
		return
	for row: Dictionary in sec.incidents:
		_body.add_child(_incident_card(crime, sec, row))


# --- Recovery --------------------------------------------------------------

func _render_recovery(crime: Node, sec: SecurityState) -> void:
	_body.add_child(_eyebrow("Active Effects"))
	var day: int = GameClock.day
	var any: bool = false
	for row: Dictionary in sec.active_effects:
		if day > int(row.get("until_day", 0)):
			continue
		any = true
		var card: PanelContainer = _tile()
		var col: VBoxContainer = VBoxContainer.new()
		card.add_child(col)
		col.add_child(_label("%s −%d%%" % [
			String(row.get("kind", "")).replace("_", " ").capitalize(),
			int(float(row.get("magnitude", 0.0)) * 100.0)], 14, INK, true))
		col.add_child(_label("Clears day %d" % int(row.get("until_day", 0)), 12, MUTED))
		_body.add_child(card)
	if not any:
		_body.add_child(_hint("No lingering damage. Repair incidents from the Incidents tab."))
	_body.add_child(_eyebrow("Active Repairs"))
	var pending: int = 0
	for row: Dictionary in sec.active_incidents():
		pending += 1
		_body.add_child(_incident_card(crime, sec, row))
	if pending == 0:
		_body.add_child(_hint("Nothing to repair right now."))


# --- Police & Insurance ----------------------------------------------------

func _render_police(crime: Node, sec: SecurityState) -> void:
	var heat_state: CompanyHeatState = crime.call("heat_for", _company_id())
	_body.add_child(_eyebrow("Company Heat"))
	_body.add_child(_bar_row("Police heat", clampf(heat_state.heat / 100.0, 0.0, 1.0), RED))
	if heat_state.fines_total > 0.0:
		_body.add_child(_label("Fines paid to date: $%d" % int(heat_state.fines_total), 12, MUTED))
	_body.add_child(_eyebrow("Insurance"))
	var levels: Array[String] = ["None", "Basic", "Full"]
	var insurance_row: HBoxContainer = HBoxContainer.new()
	insurance_row.add_theme_constant_override("separation", 6)
	_body.add_child(insurance_row)
	for level: int in range(3):
		var chip: Button = BellaUi.chip(levels[level], sec.insurance_level == level)
		chip.pressed.connect(func() -> void:
			_toast(crime.call("set_insurance_cmd", _company_id(), sec.building_id, level))
			refresh())
		insurance_row.add_child(chip)
	_body.add_child(_eyebrow("Equipment"))
	var up: Button = Button.new()
	up.text = "Upgrade security (L%d → L%d)" % [sec.equipment_level, mini(sec.equipment_level + 1, 3)]
	up.disabled = sec.equipment_level >= 3
	TycoonTheme.apply_orange(up)
	up.pressed.connect(func() -> void:
		_toast(crime.call("upgrade_security_cmd", _company_id(), sec.building_id))
		refresh())
	_body.add_child(up)
	var sweep: Button = Button.new()
	sweep.text = "Counterintel sweep"
	sweep.pressed.connect(func() -> void:
		var result: CommandResult = crime.call("counterintel_sweep_cmd", _company_id())
		if result != null and result.ok:
			EconomyManager.post_message("good", "Sweep done — %d plot(s) uncovered." % int(result.payload.get("found", 0)))
		else:
			_toast(result)
		refresh())
	_body.add_child(sweep)
	_body.add_child(_eyebrow("Demands Against You"))
	var demands: Array[Dictionary] = heat_state.open_extortion()
	if demands.is_empty():
		_body.add_child(_hint("No outstanding demands."))
	for row: Dictionary in demands:
		_body.add_child(_incoming_demand_card(crime, row))


# --- Cards -----------------------------------------------------------------

func _incident_card(crime: Node, sec: SecurityState, row: Dictionary) -> PanelContainer:
	var active: bool = bool(row.get("active", false))
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.92, 0.29, 0.18, 0.10) if active else BellaUi.PAPER
	style.border_color = RED if active else BellaUi.PAPER_EDGE
	style.set_border_width_all(3 if active else 2)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(13.0)
	card.add_theme_stylebox_override("panel", style)
	if not active:
		card.modulate = Color(1, 1, 1, 0.8)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(UiAssets.icon_rect(&"hammer", 26))
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(_label(String(row.get("title", "Incident")), 15, INK, true))
	titles.add_child(_label("Day %d · %s" % [int(row.get("day", 0)), restaurant().district], 11, MUTED))
	head.add_child(_status_pill(active))
	# Effect / Loss / Attacker cells.
	var cells: HBoxContainer = HBoxContainer.new()
	cells.add_theme_constant_override("separation", 8)
	col.add_child(cells)
	cells.add_child(_cell("Effect", String(row.get("effect_summary", "—")), INK))
	cells.add_child(_cell("Loss", "−$%d" % int(row.get("loss", 0.0)), RED))
	cells.add_child(_cell("Attacker", _attacker_text(row), Color("#6e3d18")))
	if active:
		var actions: HBoxContainer = HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		col.add_child(actions)
		if not bool(row.get("police_called", false)):
			var police: Button = Button.new()
			police.text = "Call police"
			BellaUi.red_button(police)
			police.pressed.connect(func() -> void:
				_toast(crime.call("call_police_cmd", _company_id(), sec.building_id, int(row.get("uid", -1))))
				refresh())
			actions.add_child(police)
		if float(row.get("repair_cost", 0.0)) > 0.0:
			var repair: Button = Button.new()
			repair.text = "Begin repair · $%d" % int(row.get("repair_cost", 0.0))
			TycoonTheme.apply_orange(repair)
			repair.pressed.connect(func() -> void:
				_toast(crime.call("repair_incident_cmd", _company_id(), sec.building_id, int(row.get("uid", -1))))
				refresh())
			actions.add_child(repair)
	return card


func _incoming_demand_card(crime: Node, row: Dictionary) -> PanelContainer:
	var card: PanelContainer = _tile()
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	var kind: String = String(row.get("kind", "extortion")).capitalize()
	col.add_child(_label("%s demand · $%d" % [kind, int(row.get("amount", 0.0))], 15, INK, true))
	col.add_child(_label("Pay by day %d, or they escalate." % int(row.get("deadline_day", 0)), 12, MUTED))
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	col.add_child(actions)
	var uid: int = int(row.get("uid", -1))
	var pay: Button = Button.new()
	pay.text = "Pay $%d" % int(row.get("amount", 0.0))
	TycoonTheme.apply_orange(pay)
	pay.pressed.connect(func() -> void:
		_toast(crime.call("pay_extortion_cmd", _company_id(), uid))
		refresh())
	actions.add_child(pay)
	var refuse: Button = Button.new()
	refuse.text = "Refuse"
	BellaUi.red_button(refuse)
	refuse.pressed.connect(func() -> void:
		_toast(crime.call("refuse_extortion_cmd", _company_id(), uid))
		refresh())
	actions.add_child(refuse)
	var report: Button = Button.new()
	report.text = "Report"
	report.pressed.connect(func() -> void:
		_toast(crime.call("report_extortion_cmd", _company_id(), uid))
		refresh())
	actions.add_child(report)
	return card


func _guard_card(guard: StaffMember) -> PanelContainer:
	var card: PanelContainer = _tile()
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	row.add_child(UiAssets.icon_rect(&"people", 26))
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_label(guard.display_name, 14, INK, true))
	var status: String = "Injured" if guard.is_injured(GameClock.day) else "On duty"
	col.add_child(_label("$%d/day · %s" % [int(guard.hourly_wage), status], 12, MUTED))
	return card


func _guard_candidate_card(rest: RestaurantState, candidate: JobCandidate) -> PanelContainer:
	var card: PanelContainer = _tile()
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_label(candidate.display_name, 14, INK, true))
	col.add_child(_label("$%d/hr" % int(candidate.hourly_wage), 12, MUTED))
	var hire: Button = Button.new()
	hire.text = "Hire"
	TycoonTheme.apply_orange(hire)
	hire.pressed.connect(func() -> void:
		var result: CommandResult = RestaurantManager.hire(_company_id(), rest.building_id, candidate.uid, 9.0, 12.0)
		_toast(result)
		refresh())
	row.add_child(hire)
	return card


# --- Small builders --------------------------------------------------------

func _build_branch_picker() -> void:
	var owned: Array = RestaurantManager.owned
	if owned.size() <= 1:
		if building_id < 0 and not owned.is_empty():
			building_id = owned[0].building_id
		return
	var picker: OptionButton = OptionButton.new()
	for rest: RestaurantState in owned:
		picker.add_item(rest.restaurant_name, rest.building_id)
	if building_id < 0:
		building_id = owned[0].building_id
	picker.selected = maxi(0, picker.get_item_index(building_id))
	picker.item_selected.connect(func(index: int) -> void:
		building_id = picker.get_item_id(index)
		refresh())
	_content.add_child(picker)
	_content.move_child(picker, 1)


func _tile() -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.tile_box())
	return card


func _cell(title: String, value: String, value_color: Color) -> PanelContainer:
	var cell: PanelContainer = PanelContainer.new()
	cell.add_theme_stylebox_override("panel", BellaUi.sunk_box(11))
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	cell.add_child(col)
	col.add_child(_label(title.to_upper(), 10, MUTED, true))
	var value_label: Label = _label(value, 13, value_color, true)
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(value_label)
	return cell


func _bar_row(label_text: String, value: float, color: Color) -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(_label(label_text, 12, MUTED))
	var track: ProgressBar = ProgressBar.new()
	track.min_value = 0.0
	track.max_value = 1.0
	track.value = clampf(value, 0.0, 1.0)
	track.show_percentage = false
	track.custom_minimum_size = Vector2(0, 12)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	track.add_theme_stylebox_override("fill", fill)
	col.add_child(track)
	return col


func _status_pill(active: bool) -> PanelContainer:
	if active:
		return BellaUi.pill("ACTIVE", Color.WHITE, RED, RED_EDGE)
	return BellaUi.pill("CLOSED", Color.WHITE, GREEN, Color("#356615"))


func _alert_pill(level: StringName) -> PanelContainer:
	match level:
		&"elevated":
			return BellaUi.pill("ALERT: ELEVATED", Color("#F79286"), Color(0.92, 0.29, 0.18, 0.15), RED)
		&"lockdown":
			return BellaUi.pill("LOCKDOWN", Color.WHITE, RED, RED_EDGE)
		_:
			return BellaUi.pill("ALERT: NORMAL", Color("#4a7a2a"), Color(0.44, 0.71, 0.23, 0.15), GREEN)


func _attacker_text(row: Dictionary) -> String:
	var suspect: String = String(row.get("suspected_company", ""))
	var confidence: float = float(row.get("confidence", 0.0))
	if suspect.is_empty():
		if confidence > 0.2:
			return "Unknown (low confidence)"
		return "Unknown"
	return "%s (%d%%)" % [_company_name(suspect), int(confidence * 100.0)]


func _callout(text: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.77, 0.09, 0.14)
	style.border_color = Color("#f5c518")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(10.0)
	panel.add_theme_stylebox_override("panel", style)
	var label: Label = _label(text, 12, Color("#6e3d18"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	return panel


func _eyebrow(text: String) -> Label:
	return _label(text.to_upper(), 12, Color("#8a5a2b"), true)


func _hint(text: String) -> Label:
	var l: Label = _label(text, 13, TycoonTheme.PALETTE["text_soft"])
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _label(text: String, size: int, color: Color, _bold: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _toast(result: CommandResult) -> void:
	if result != null and not result.ok:
		EconomyManager.post_message("alert", result.message)


func _company_name(company_id: String) -> String:
	var company: CompanyState = CompanyManager.company(StringName(company_id))
	return company.display_name if company != null else company_id


func _company_id() -> StringName:
	return CompanyManager.player.id if CompanyManager.player != null else &"player"


func _crime() -> Node:
	return get_tree().root.get_node_or_null("CrimeManager")
