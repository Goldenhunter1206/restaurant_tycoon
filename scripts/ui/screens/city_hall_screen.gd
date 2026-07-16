extends TycoonScreen
## F1 · City Hall (feature 13). Company-scoped civic hub: permits, official
## reputation, inspections with a live checklist, donations/lobbying, city
## development proposals, and fines/appeals. Warm wood chrome per the Bella
## Vista handoff; tabs match the F1 mockup exactly. Click-only-safe: the HUD
## calls refresh() every game minute and the body is rebuilt from state.

const TABS: Array[Array] = [
	[&"overview", "Overview"],
	[&"permits", "Permits"],
	[&"inspections", "Inspections"],
	[&"mayor", "Mayor & Influence"],
	[&"development", "Development"],
	[&"fines", "Fines & Legal"],
]

var _active_tab: StringName = &"overview"
var _body: VBoxContainer
var _standing_slot: Control = null
var _focus_building: int = -1
var _selected_official: StringName = &"mayor"
var _donation_amount: float = 1000.0


func screen_title() -> String:
	return "City Hall"


func screen_icon() -> StringName:
	return &"city_hall"


func _build() -> void:
	custom_minimum_size = Vector2(980, 660)
	_focus_building = building_id
	var gov: Node = _gov()
	if gov != null and building_id >= 0 and bool(gov.call("inspection_focus", building_id)):
		_active_tab = &"inspections"
	_insert_standing_pill()
	_body = add_scroll_list()


func refresh() -> void:
	if _body == null:
		return
	for child: Node in _body.get_children():
		child.queue_free()
	var gov: Node = _gov()
	if gov == null or not bool(gov.call("enabled")):
		var off: Label = _hint("The civic layer is disabled in this game.")
		_body.add_child(off)
		return
	_refresh_standing(gov)
	_body.add_child(_chip_row())
	match _active_tab:
		&"permits":
			_render_permits(gov)
		&"inspections":
			_render_inspections(gov)
		&"mayor":
			_render_mayor(gov)
		&"development":
			_render_development(gov)
		&"fines":
			_render_fines(gov)
		_:
			_render_overview(gov)


# --- Tabs ----------------------------------------------------------------------


func _render_overview(gov: Node) -> void:
	var civic: Resource = gov.call("civic_for", _company_id())
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	grid.add_child(_tile("OFFICIAL REPUTATION", "%d%%" % int(round(float(civic.get("official_reputation")) * 100.0))))
	grid.add_child(_tile("POLICE REPUTATION", "%d%%" % int(round(float(civic.get("police_reputation")) * 100.0))))
	grid.add_child(_tile("MAYOR RELATIONSHIP", _relationship_text(float(civic.get("mayor_relationship")))))
	grid.add_child(_tile("INFLUENCE", "%d" % int(civic.get("influence"))))
	var open_violations: Array = civic.call("open_violations")
	var unpaid: Array = civic.call("unpaid_fines")
	var summary: GridContainer = GridContainer.new()
	summary.columns = 2
	summary.add_theme_constant_override("h_separation", 8)
	_body.add_child(summary)
	summary.add_child(_tile("OPEN VIOLATIONS", str(open_violations.size()),
		open_violations.size() > 0))
	summary.add_child(_tile("UNPAID FINES", str(unpaid.size()), unpaid.size() > 0))
	_section("City officials")
	for officer: Resource in gov.get("officials"):
		_body.add_child(_official_row(officer, civic))
	_section("Civic calendar")
	var upcoming: Array = gov.call("upcoming_civic", 6)
	if upcoming.is_empty():
		_body.add_child(_hint("Nothing on the docket."))
	for entry: Dictionary in upcoming:
		_body.add_child(BellaUi.feed_row(_kind_icon(String(entry.get("kind", ""))),
			String(entry.get("title", "")), String(entry.get("when", "")),
			"Day %d" % int(entry.get("day", 0)), &"info"))


func _render_permits(gov: Node) -> void:
	var civic: Resource = gov.call("civic_for", _company_id())
	var day: int = GameClock.day
	_section("Company permits")
	for def: Resource in gov.call("permit_defs"):
		var row: Dictionary = civic.call("permit_row", def.get("id"))
		var status: String = String(row.get("status", "")) if not row.is_empty() else "not held"
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override("panel", BellaUi.tile_box())
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(line)
		_body.add_child(card)
		var icon: TextureRect = UiAssets.icon_rect(def.get("icon"), 26)
		if icon != null:
			line.add_child(icon)
		var texts: VBoxContainer = VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_theme_constant_override("separation", 0)
		line.add_child(texts)
		texts.add_child(_strong(String(def.get("display_name"))))
		var blurb: Label = _hint(String(def.get("blurb")))
		texts.add_child(blurb)
		match status:
			"active":
				var expires: int = int(row.get("expires_day", 0))
				var tone: StringName = &"warning" if expires - day <= 3 else &"positive"
				line.add_child(BellaUi.standing_pill("Until Day %d" % expires, &"check", tone))
			"lapsed", "suspended":
				line.add_child(BellaUi.standing_pill(status.capitalize(), &"close", &"negative"))
			_:
				line.add_child(BellaUi.standing_pill("Not held", &"permit", &"warning"))
		var renew: Button = Button.new()
		renew.text = "%s · $%.0f" % ["Renew" if status == "active" else "Acquire", float(def.get("cost"))]
		TycoonTheme.apply_orange(renew)
		var permit_id: StringName = def.get("id")
		renew.pressed.connect(func() -> void:
			var result: RefCounted = gov.call("renew_permit_cmd", _company_id(), permit_id)
			if result != null and not result.ok:
				EconomyManager.post_message("alert", result.message)
			refresh())
		line.add_child(renew)


func _render_inspections(gov: Node) -> void:
	_body.add_child(_branch_picker())
	if _focus_building < 0:
		_body.add_child(_hint("Buy a restaurant to see its inspection record."))
		return
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(split)
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	split.add_child(left)
	# Upcoming inspection card.
	var pending: Resource = gov.call("pending_inspection_for", _focus_building)
	if pending != null:
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override("panel", BellaUi.tile_box())
		left.add_child(card)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		row.add_child(UiAssets.icon_rect(&"calendar", 30))
		var texts: VBoxContainer = VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_theme_constant_override("separation", 0)
		row.add_child(texts)
		texts.add_child(_strong("%s inspection — %s" % [
			_kind_label(pending.get("kind")), _branch_label(_focus_building)]))
		texts.add_child(_hint("Scheduled Day %d · %s" % [int(pending.get("scheduled_day")),
			_official_name(gov, pending.get("official_id"))]))
		var days_left: int = maxi(int(pending.get("scheduled_day")) - GameClock.day, 0)
		row.add_child(BellaUi.standing_pill(
			"Today" if days_left == 0 else "In %d day%s" % [days_left, "" if days_left == 1 else "s"],
			&"hourglass", &"warning"))
	else:
		left.add_child(_hint("No inspection scheduled at this branch."))
	# Live checklist — what an inspector would find right now.
	_section_in(left, "Checklist (live)")
	var findings: Array = gov.call("checklist_preview", _focus_building, &"food_safety")
	for finding: Dictionary in findings:
		left.add_child(BellaUi.checklist_row(String(finding.get("label", "")),
			&"pass" if bool(finding.get("passed", true)) else &"fail",
			String(finding.get("detail", ""))))
	# Open violations with their exact correctives.
	var civic: Resource = gov.call("civic_for", _company_id())
	var open_rows: Array = []
	for violation: Dictionary in civic.call("open_violations"):
		if int(violation.get("building_id", -1)) == _focus_building:
			open_rows.append(violation)
	if not open_rows.is_empty():
		_section_in(left, "Open violations")
	for violation: Dictionary in open_rows:
		var uid: int = int(violation.get("uid", -1))
		left.add_child(BellaUi.checklist_row(String(violation.get("label", "")), &"fail",
			"%s — fix before Day %d or: fine. %s" % [String(violation.get("corrective", "")),
				int(violation.get("deadline_day", 0)), String(violation.get("needed", ""))],
			"Fix now", func() -> void:
				var result: RefCounted = gov.call("fix_violation_cmd", _company_id(), uid)
				if result != null and not result.ok:
					EconomyManager.post_message("alert", result.message)
				refresh()))
	# History.
	var history: Array = gov.call("inspections_for", _focus_building)
	var done: Array = []
	for insp: Resource in history:
		if bool(insp.get("visit_done")):
			done.append(insp)
	if not done.is_empty():
		_section_in(left, "Inspection history")
	for i: int in range(done.size() - 1, maxi(done.size() - 6, 0) - 1, -1):
		var insp: Resource = done[i]
		var grade: StringName = insp.get("grade")
		var tone: StringName = &"positive" if grade == &"clean" \
			else (&"warning" if grade == &"warning" else &"negative")
		left.add_child(BellaUi.feed_row(&"magnifier",
			"%s inspection — %s" % [_kind_label(insp.get("kind")), String(grade).capitalize()],
			"Day %d · score %d" % [int(insp.get("scheduled_day")), int(insp.get("score"))],
			"", tone))
	# Right rail: the stakes + re-inspection request.
	var rail: VBoxContainer = VBoxContainer.new()
	rail.custom_minimum_size = Vector2(280, 0)
	rail.add_theme_constant_override("separation", 8)
	split.add_child(rail)
	var warn: PanelContainer = PanelContainer.new()
	warn.add_theme_stylebox_override("panel", TycoonTheme.status_box(&"warning"))
	rail.add_child(warn)
	var warn_col: VBoxContainer = VBoxContainer.new()
	warn_col.add_theme_constant_override("separation", 4)
	warn.add_child(warn_col)
	warn_col.add_child(_strong("If you fail"))
	var stakes: Label = _hint("Failed checks become violations with a %d-day deadline. Ignoring them escalates to a fine of $%.0f+; severe failures can close the branch for %d days." % [
		int(EconomyManager.tuning_value("government.inspection.remediation_days", 5)),
		float(EconomyManager.tuning_value("government.fines.base", 2000.0)),
		int(EconomyManager.tuning_value("government.fines.closure_days", 3))])
	stakes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn_col.add_child(stakes)
	var reinspect: Button = Button.new()
	reinspect.text = "Request re-inspection · $%.0f" % float(
		EconomyManager.tuning_value("government.inspection.reinspection_fee", 150.0))
	TycoonTheme.apply_orange(reinspect)
	reinspect.disabled = pending != null
	reinspect.pressed.connect(func() -> void:
		var result: RefCounted = gov.call("request_reinspection_cmd", _company_id(), _focus_building)
		if result != null and not result.ok:
			EconomyManager.post_message("alert", result.message)
		refresh())
	rail.add_child(reinspect)
	var eta_label: Label = _hint("Police response here: ~%d min" % int(gov.call("police_eta", _focus_building)))
	rail.add_child(eta_label)


func _render_mayor(gov: Node) -> void:
	var civic: Resource = gov.call("civic_for", _company_id())
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(split)
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	split.add_child(left)
	_section_in(left, "Officials")
	for officer: Resource in gov.get("officials"):
		var row: PanelContainer = _official_row(officer, civic)
		var id: StringName = officer.get("def_id")
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed:
				_selected_official = id
				refresh())
		left.add_child(row)
	# Right rail: review + commit (donation / envelope).
	var rail: VBoxContainer = VBoxContainer.new()
	rail.custom_minimum_size = Vector2(300, 0)
	rail.add_theme_constant_override("separation", 8)
	split.add_child(rail)
	var officer: Resource = gov.call("official_by_id", _selected_official)
	if officer == null:
		rail.add_child(_hint("Select an official."))
		return
	rail.add_child(_strong("Approach %s" % String(officer.get("display_name"))))
	rail.add_child(_hint(_integrity_text(float(officer.get("integrity")))))
	var amount_row: HBoxContainer = HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 6)
	rail.add_child(amount_row)
	for amount: float in [500.0, 1000.0, 2500.0, 5000.0]:
		var chip: Button = BellaUi.chip("$%.0f" % amount, is_equal_approx(_donation_amount, amount))
		chip.pressed.connect(func() -> void:
			_donation_amount = amount
			refresh())
		amount_row.add_child(chip)
	var donate: Button = Button.new()
	donate.text = "Donate · $%.0f" % _donation_amount
	TycoonTheme.apply_orange(donate)
	donate.pressed.connect(func() -> void:
		var amount: float = _donation_amount
		load("res://scripts/ui/confirm_dialog.gd").ask(self, "Donate $%.0f?" % amount,
			"A declared donation. Bounded goodwill with %s — and it fades." % String(officer.get("display_name")),
			func() -> void:
				var result: RefCounted = gov.call("donate_cmd", _company_id(), _selected_official, amount, &"declared")
				if result != null and not result.ok:
					EconomyManager.post_message("alert", result.message)
				refresh(),
			"Donate"))
	rail.add_child(donate)
	if bool(gov.call("corruption_enabled")):
		var bribe: Button = load("res://scripts/ui/hold_to_confirm_button.gd").new()
		bribe.text = "Slip an envelope · $%.0f (hold)" % _donation_amount
		bribe.connect("confirmed", func() -> void:
			var result: RefCounted = gov.call("bribe_cmd", _company_id(), _selected_official, _donation_amount)
			if result != null and not result.ok:
				EconomyManager.post_message("alert", result.message)
			refresh())
		rail.add_child(bribe)
		var risk: Label = _hint("Illicit. May be refused; may leave evidence. Exposure means a fine and a corruption probe.")
		risk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rail.add_child(risk)
	else:
		rail.add_child(_hint("Corruption is disabled in this scenario — donations only."))
	rail.add_child(HSeparator.new())
	rail.add_child(_tile("YOUR INFLUENCE", "%d" % int(civic.get("influence"))))
	rail.add_child(_tile("MAYOR RELATIONSHIP", _relationship_text(float(civic.get("mayor_relationship")))))
	var decay_hint: Label = _hint("Influence decays daily and donations flatten — standing must be maintained, not bought once.")
	decay_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rail.add_child(decay_hint)


func _render_development(gov: Node) -> void:
	_section("Proposals before the council")
	var proposals: Array = gov.call("open_proposals")
	if proposals.is_empty():
		_body.add_child(_hint("No open proposals. City Hall floats new projects every few weeks."))
	for project: Resource in proposals:
		_body.add_child(_project_card(gov, project, true))
	_section("Decided & built")
	var shown: int = 0
	var all_projects: Array = gov.get("projects")
	for i: int in range(all_projects.size() - 1, -1, -1):
		var project: Resource = all_projects[i]
		if project.get("status") == &"proposed" or shown >= 5:
			continue
		_body.add_child(_project_card(gov, project, false))
		shown += 1
	if shown == 0:
		_body.add_child(_hint("Nothing decided yet."))


func _render_fines(gov: Node) -> void:
	var civic: Resource = gov.call("civic_for", _company_id())
	_section("Fines")
	var fines: Array = civic.get("fines")
	if fines.is_empty():
		_body.add_child(_hint("A clean slate — no fines on record."))
	for i: int in range(fines.size() - 1, -1, -1):
		var fine: Dictionary = fines[i]
		var uid: int = int(fine.get("uid", -1))
		var status: String = String(fine.get("status", ""))
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override("panel", BellaUi.tile_box())
		card.add_child(line)
		_body.add_child(card)
		var texts: VBoxContainer = VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_theme_constant_override("separation", 0)
		line.add_child(texts)
		texts.add_child(_strong("%s — $%.0f" % [String(fine.get("reason", "Fine")), float(fine.get("amount", 0.0))]))
		texts.add_child(_hint("Issued Day %d%s" % [int(fine.get("day", 0)),
			" · pay or appeal by Day %d" % int(fine.get("appeal_deadline_day", 0)) if status == "unpaid" else ""]))
		match status:
			"unpaid":
				line.add_child(BellaUi.standing_pill("Unpaid", &"gavel", &"negative"))
				var pay: Button = Button.new()
				pay.text = "Pay"
				TycoonTheme.apply_orange(pay)
				pay.pressed.connect(func() -> void:
					load("res://scripts/ui/confirm_dialog.gd").ask(self,
						"Pay $%.0f?" % float(fine.get("amount", 0.0)),
						"Settles the fine and closes the case.",
						func() -> void:
							gov.call("pay_fine_cmd", _company_id(), uid)
							refresh(),
						"Pay"))
				line.add_child(pay)
				if not bool(fine.get("appealed_once", false)) and GameClock.day <= int(fine.get("appeal_deadline_day", 0)):
					var appeal: Button = Button.new()
					appeal.text = "Appeal · $%.0f" % float(EconomyManager.tuning_value("government.fines.appeal_fee", 250.0))
					appeal.pressed.connect(func() -> void:
						var result: RefCounted = gov.call("appeal_fine_cmd", _company_id(), uid)
						if result != null and not result.ok:
							EconomyManager.post_message("alert", result.message)
						refresh())
					line.add_child(appeal)
			"appealed":
				line.add_child(BellaUi.standing_pill("Under appeal", &"hourglass", &"warning"))
			"overturned":
				line.add_child(BellaUi.standing_pill("Overturned", &"check", &"positive"))
			_:
				line.add_child(BellaUi.standing_pill("Paid", &"check", &"info"))
	_section("Closures")
	var closures: Array = civic.get("closures")
	if closures.is_empty():
		_body.add_child(_hint("No branches under civic closure."))
	for closure: Dictionary in closures:
		_body.add_child(BellaUi.feed_row(&"close", _branch_label(int(closure.get("building_id", -1))),
			"Closed until Day %d (%s)" % [int(closure.get("until_day", 0)), String(closure.get("reason", ""))],
			"", &"negative"))
	_section("Public record")
	var donations: Array = civic.get("donations")
	var listed: int = 0
	for i: int in range(donations.size() - 1, -1, -1):
		if listed >= 6:
			break
		var donation: Dictionary = donations[i]
		var kind: String = String(donation.get("kind", "declared"))
		var exposed: bool = bool(donation.get("exposed", false))
		if kind == "bribe" and not exposed:
			continue  # Undiscovered envelopes are not on the public record.
		listed += 1
		_body.add_child(BellaUi.feed_row(&"bank",
			"%s · $%.0f" % ["EXPOSED bribe" if exposed else kind.capitalize(), float(donation.get("amount", 0.0))],
			"Day %d · %s" % [int(donation.get("day", 0)), String(donation.get("official_id", ""))],
			"", &"negative" if exposed else &"info"))
	if listed == 0:
		_body.add_child(_hint("No donations on record."))


# --- Widgets ---------------------------------------------------------------------


func _chip_row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for tab: Array in TABS:
		var chip: Button = BellaUi.chip(tab[1], _active_tab == tab[0])
		var tab_id: StringName = tab[0]
		chip.pressed.connect(func() -> void:
			_active_tab = tab_id
			refresh())
		row.add_child(chip)
	return row


func _branch_picker() -> Control:
	var player: CompanyState = CompanyManager.player
	var restaurants: Array[RestaurantState] = player.restaurants if player != null else []
	if restaurants.size() <= 1:
		if restaurants.size() == 1:
			_focus_building = restaurants[0].building_id
		var label: Label = _hint(_branch_label(_focus_building) if _focus_building >= 0 else "")
		return label
	if _focus_building < 0:
		_focus_building = restaurants[0].building_id
	var picker: OptionButton = OptionButton.new()
	picker.fit_to_longest_item = false
	for i: int in range(restaurants.size()):
		picker.add_item(restaurants[i].restaurant_name, restaurants[i].building_id)
		if restaurants[i].building_id == _focus_building:
			picker.select(i)
	picker.item_selected.connect(func(index: int) -> void:
		_focus_building = picker.get_item_id(index)
		refresh())
	return picker


func _official_row(officer: Resource, _civic: Resource) -> PanelContainer:
	var selected: bool = officer.get("def_id") == _selected_official and _active_tab == &"mayor"
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		BellaUi.tile_box(BellaUi.GOLD_EDGE if selected else BellaUi.PAPER_EDGE, 3 if selected else 2))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var icon: TextureRect = UiAssets.icon_rect(_role_icon(officer.get("role")), 26)
	if icon != null:
		row.add_child(icon)
	var texts: VBoxContainer = VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	texts.add_child(_strong(String(officer.get("display_name"))))
	texts.add_child(_hint("%s · %s" % [_role_label(officer.get("role")),
		_integrity_text(float(officer.get("integrity")))]))
	var relationship: float = officer.call("relationship_for", _company_id())
	row.add_child(BellaUi.standing_pill(_relationship_text(relationship), &"people",
		&"positive" if relationship > 0.15 else (&"negative" if relationship < -0.15 else &"info")))
	return card


func _project_card(gov: Node, project: Resource, open_for_support: bool) -> PanelContainer:
	var def: Resource = gov.call("project_def", project.get("def_id"))
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.tile_box())
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var icon: TextureRect = UiAssets.icon_rect(def.get("icon") if def != null else &"city_hall", 26)
	if icon != null:
		row.add_child(icon)
	var texts: VBoxContainer = VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	texts.add_child(_strong("%s — district %s" % [
		String(def.get("display_name")) if def != null else "Project", String(project.get("district"))]))
	if def != null:
		texts.add_child(_hint(String(def.get("blurb"))))
		texts.add_child(_hint("Expected: %+d%% local demand once built." % int(round(float(def.get("demand_delta")) * 100.0))))
	var status: StringName = project.get("status")
	match status:
		&"proposed":
			row.add_child(BellaUi.standing_pill("Decision Day %d" % int(project.get("decision_day")), &"hourglass", &"info"))
		&"approved":
			row.add_child(BellaUi.standing_pill("Under construction", &"hammer", &"warning"))
		&"built":
			row.add_child(BellaUi.standing_pill("Built", &"check", &"positive"))
		_:
			row.add_child(BellaUi.standing_pill("Rejected", &"close", &"negative"))
	var support_total: float = project.call("support_total")
	var support: Dictionary = project.get("support")
	if support_total > 0.0 or open_for_support:
		var backers: Array[String] = []
		for key: String in support:
			backers.append("%s $%.0f" % [_company_label(key), float(support[key])])
		col.add_child(_hint("Support: %s" % (" · ".join(backers) if not backers.is_empty() else "none yet")))
	var rationale: String = String(project.get("rationale"))
	if not rationale.is_empty():
		col.add_child(_hint(rationale))
	if open_for_support:
		var actions: HBoxContainer = HBoxContainer.new()
		actions.add_theme_constant_override("separation", 6)
		col.add_child(actions)
		var uid: int = int(project.get("uid"))
		for pledge: float in [250.0, 1000.0]:
			var back: Button = Button.new()
			back.text = "Back · $%.0f" % pledge
			TycoonTheme.apply_orange(back)
			back.pressed.connect(func() -> void:
				var result: RefCounted = gov.call("lobby_development_cmd", _company_id(), uid, pledge)
				if result != null and not result.ok:
					EconomyManager.post_message("alert", result.message)
				refresh())
			actions.add_child(back)
	return card


# --- Small helpers ----------------------------------------------------------------


func _insert_standing_pill() -> void:
	# Header row is the first child of _content (built by TycoonScreen.setup).
	var header: HBoxContainer = _content.get_child(0) as HBoxContainer
	if header == null:
		return
	_standing_slot = Control.new()
	header.add_child(_standing_slot)
	header.move_child(_standing_slot, header.get_child_count() - 2)


func _refresh_standing(gov: Node) -> void:
	if _standing_slot == null:
		return
	for child: Node in _standing_slot.get_children():
		child.queue_free()
	var standing: Dictionary = gov.call("standing_label", _company_id())
	_standing_slot.add_child(BellaUi.standing_pill(
		String(standing.get("text", "")), &"bank", standing.get("tone", &"info")))


func _tile(title: String, value: String, danger: bool = false) -> PanelContainer:
	var cell: PanelContainer = PanelContainer.new()
	cell.add_theme_stylebox_override("panel", BellaUi.sunk_box(12))
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	cell.add_child(col)
	var eyebrow: Label = Label.new()
	eyebrow.text = title
	eyebrow.add_theme_font_size_override("font_size", 10)
	eyebrow.add_theme_color_override("font_color", BellaUi.INK_SOFT)
	col.add_child(eyebrow)
	var value_label: Label = Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 16)
	value_label.add_theme_color_override("font_color",
		BellaUi.RED_EDGE if danger else BellaUi.INK)
	col.add_child(value_label)
	return cell


func _section(text: String) -> void:
	_section_in(_body, text)


func _section_in(parent: Control, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("#8a5a2b"))
	parent.add_child(label)


func _strong(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", BellaUi.INK)
	return label


func _hint(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", BellaUi.INK_SOFT)
	return label


func _gov() -> Node:
	return get_tree().root.get_node_or_null("GovernmentManager")


func _company_id() -> StringName:
	return CompanyManager.player.id if CompanyManager.player != null else &"player"


func _company_label(company_key: String) -> String:
	var company: CompanyState = CompanyManager.company(StringName(company_key))
	return company.display_name if company != null else company_key


func _branch_label(target_building: int) -> String:
	var rest: RestaurantState = RestaurantManager.by_building.get(target_building)
	return rest.restaurant_name if rest != null else "Branch %d" % target_building


func _official_name(gov: Node, official_id: StringName) -> String:
	var officer: Resource = gov.call("official_by_id", official_id)
	return String(officer.get("display_name")) if officer != null else "an inspector"


func _relationship_text(value: float) -> String:
	if value >= 0.4:
		return "Ally"
	if value >= 0.15:
		return "Warm"
	if value <= -0.4:
		return "Hostile"
	if value <= -0.15:
		return "Cold"
	return "Neutral"


func _integrity_text(value: float) -> String:
	if value >= 0.75:
		return "By the book"
	if value >= 0.5:
		return "Professional"
	if value >= 0.3:
		return "Flexible"
	return "For sale"


func _kind_label(kind: StringName) -> String:
	match kind:
		&"labor":
			return "Labor"
		&"tax":
			return "Tax"
	return "Health"


func _kind_icon(kind: String) -> StringName:
	match kind:
		"civic_inspection":
			return &"magnifier"
		"fine":
			return &"gavel"
		"development":
			return &"city_hall"
		"election":
			return &"ballot"
	return &"receipt"


func _role_icon(role: StringName) -> StringName:
	match role:
		&"mayor":
			return &"ballot"
		&"police_commander":
			return &"bell"
		&"tax_official":
			return &"receipt"
		&"labor_inspector":
			return &"people"
	return &"magnifier"


func _role_label(role: StringName) -> String:
	match role:
		&"mayor":
			return "Mayor"
		&"police_commander":
			return "Police Commander"
		&"tax_official":
			return "Tax Assessor"
		&"labor_inspector":
			return "Labor Inspector"
	return "Food Inspector"
