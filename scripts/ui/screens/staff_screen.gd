class_name StaffWorkspaceScreen
extends TycoonScreen
## Persistent workforce workspace. Employee condition, market, schedules,
## training, transfers, promotions, and contracts all share authoritative state.

const INK: Color = Color("#3a2010")
const INK_SOFT: Color = Color("#6e3d18")
const MUTED: Color = Color("#92704d")
const RED: Color = Color("#ea4a2f")
const ORANGE: Color = Color("#f99a1c")
const GOLD: Color = Color("#f5c518")
const GREEN: Color = Color("#6fb63a")
const BREAKPOINT_PHONE: float = 720.0
const ROLE_COLORS: Dictionary = {
	&"cook": Color("#c7331c"),
	&"waiter": Color("#4e8f27"),
	&"driver": Color("#2b6cb0"),
	&"manager": Color("#b77a12"),
	&"runner": Color("#d46a1f"),
	&"cleaner": Color("#4f8f85"),
}
const TABS: Array[Dictionary] = [
	{"id": &"roster", "label": "Roster"},
	{"id": &"schedule", "label": "Schedule"},
	{"id": &"market", "label": "Job Market"},
	{"id": &"detail", "label": "Employee Detail"},
	{"id": &"training", "label": "Training"},
	{"id": &"moves", "label": "Transfers / Promotion"},
	{"id": &"policies", "label": "Policies"},
]

var _active_tab: StringName = &"roster"
var _selected_staff_uid: int = -1
var _market_filter_role: StringName = &""
var _tab_buttons: Dictionary = {}
var _branch_picker: OptionButton
var _workspace: VBoxContainer
var _workspace_scroll: ScrollContainer
var _status: Label
var _timelines: Dictionary = {}
var _command_serial: int = 0
var _refresh_queued: bool = false
var _is_phone: bool = false


func screen_title() -> String:
	return "Staff"


func screen_icon() -> StringName:
	return &"people"


func _build() -> void:
	custom_minimum_size = Vector2(360, 520)
	var base_header := _content.get_child(0) as HBoxContainer
	if base_header != null and base_header.get_child_count() > 0:
		var close_button := base_header.get_child(base_header.get_child_count() - 1) as Button
		if close_button != null:
			close_button.custom_minimum_size = Vector2(44, 44)
	_build_branch_picker()
	_build_tabs()
	_workspace_scroll = ScrollContainer.new()
	_workspace_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_workspace = VBoxContainer.new()
	_workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace.add_theme_constant_override("separation", 12)
	_workspace_scroll.add_child(_workspace)
	_content.add_child(_workspace_scroll)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", INK_SOFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status)
	_connect_services()
	_apply_responsive_layout()
	resized.connect(_apply_responsive_layout)


func refresh() -> void:
	_refresh_queued = false
	for timeline: ShiftTimeline in _timelines.values():
		if is_instance_valid(timeline) and timeline.is_dragging():
			return
	_ensure_branch()
	_populate_branch_picker()
	_clear(_workspace)
	_timelines.clear()
	_refresh_tabs()
	var rest := restaurant()
	if rest == null:
		_workspace.add_child(_empty_card("No Branch Selected",
			"Choose one of your restaurants to manage its workforce."))
		return
	match _active_tab:
		&"schedule":
			_render_schedule(rest)
		&"market":
			_render_market(rest)
		&"detail":
			_render_employee_detail(rest)
		&"training":
			_render_training(rest)
		&"moves":
			_render_moves(rest)
		&"policies":
			_render_policies(rest)
		_:
			_render_roster(rest)


func _build_branch_picker() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := _label("Branch", 14, MUTED)
	row.add_child(label)
	_branch_picker = OptionButton.new()
	_branch_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_branch_picker.custom_minimum_size = Vector2(190, 44)
	_branch_picker.item_selected.connect(_on_branch_picked)
	row.add_child(_branch_picker)
	_content.add_child(row)


func _build_tabs() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 52
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	scroll.add_child(row)
	_content.add_child(scroll)
	for tab: Dictionary in TABS:
		var button := Button.new()
		button.text = String(tab["label"])
		button.custom_minimum_size = Vector2(122, 44)
		button.pressed.connect(_select_tab.bind(StringName(tab["id"])))
		row.add_child(button)
		_tab_buttons[StringName(tab["id"])] = button


func _connect_services() -> void:
	var service := _staff_service()
	if service != null:
		for signal_name: StringName in [
			&"workforce_changed", &"candidate_market_changed",
			&"training_changed", &"resignation_warning",
		]:
			if service.has_signal(signal_name):
				var callback := Callable(self, "_queue_refresh")
				if not service.is_connected(signal_name, callback):
					service.connect(signal_name, callback)
	var market_callback := Callable(self, "_queue_refresh")
	if not RestaurantManager.job_market_changed.is_connected(market_callback):
		RestaurantManager.job_market_changed.connect(market_callback)


func _queue_refresh(_first: Variant = null, _second: Variant = null) -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	refresh.call_deferred()


func _apply_responsive_layout() -> void:
	if not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var phone: bool = viewport_size.x < BREAKPOINT_PHONE
	var target_size: Vector2 = Vector2(
		maxf(340.0, viewport_size.x - 24.0),
		minf(780.0, maxf(600.0, viewport_size.y - 32.0))) if phone else Vector2(
			minf(1080.0, maxf(780.0, viewport_size.x - 48.0)),
			minf(920.0, maxf(680.0, viewport_size.y - 48.0)))
	if phone == _is_phone and custom_minimum_size.is_equal_approx(target_size):
		return
	_is_phone = phone
	custom_minimum_size = target_size
	_force_layout_sort()


func _force_layout_sort() -> void:
	notification(Container.NOTIFICATION_SORT_CHILDREN)
	var paper := get_child(0) as Container
	if paper != null:
		paper.notification(Container.NOTIFICATION_SORT_CHILDREN)
	_content.notification(Container.NOTIFICATION_SORT_CHILDREN)
	_workspace_scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)


func _ensure_branch() -> void:
	if CompanyManager.player == null:
		building_id = -1
		return
	for rest: RestaurantState in CompanyManager.player.restaurants:
		if rest.building_id == building_id:
			return
	building_id = -1 if CompanyManager.player.restaurants.is_empty() else (
		CompanyManager.player.restaurants[0] as RestaurantState).building_id


func _populate_branch_picker() -> void:
	_branch_picker.clear()
	if CompanyManager.player == null:
		return
	var selected_index := 0
	for rest: RestaurantState in CompanyManager.player.restaurants:
		var index := _branch_picker.item_count
		_branch_picker.add_item(rest.restaurant_name)
		_branch_picker.set_item_metadata(index, rest.building_id)
		if rest.building_id == building_id:
			selected_index = index
	if _branch_picker.item_count > 0:
		_branch_picker.select(selected_index)


func _refresh_tabs() -> void:
	var service := _staff_service()
	var enrollment_count := 0
	if service != null:
		for enrollment: TrainingEnrollment in service.get("training_enrollments") as Array:
			if enrollment.company_id == CompanyManager.player.id and enrollment.status in [&"queued", &"active"]:
				enrollment_count += 1
	for tab: Dictionary in TABS:
		var id := StringName(tab["id"])
		var text_value := String(tab["label"])
		if id == &"training" and enrollment_count > 0:
			text_value += "  %d" % enrollment_count
		var button: Button = _tab_buttons[id]
		button.text = text_value
		BellaUi.style_chip(button, id == _active_tab)


func _render_roster(rest: RestaurantState) -> void:
	_workspace.add_child(_section_heading("Roster",
		"Condition changes at shift and day boundaries. Effects stay bounded for every role."))
	var summary := _add_card(_workspace, GOLD)
	var total_pay := 0.0
	var on_shift := 0
	var absent := 0
	for member: StaffMember in rest.staff:
		total_pay += member.daily_pay()
		on_shift += int(member.on_shift(GameClock.game_hours))
		absent += int(member.is_absent(GameClock.day))
	summary.add_child(_metric_row("Team", "%d people" % rest.staff.size(),
		"%d on shift  ·  %d absent" % [on_shift, absent]))
	summary.add_child(_metric_row("Scheduled payroll", "$%.0f/day" % total_pay,
		"Only scheduled hours are paid."))
	if rest.staff.is_empty():
		_workspace.add_child(_empty_card("Nobody Hired",
			"Open Job Market to compare candidates shared with rival companies."))
		return
	for member: StaffMember in rest.staff:
		var accent: Color = ROLE_COLORS.get(member.type_id, GOLD)
		var card := _add_card(_workspace, accent)
		var heading := HBoxContainer.new()
		var title := _label(member.staff_name, 19, INK)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(title)
		heading.add_child(_pill(_role_name(member.type_id), accent))
		card.add_child(heading)
		var state := "Absent" if member.is_absent(GameClock.day) else (
			"On shift" if member.on_shift(GameClock.game_hours) else "Off shift")
		if member.resignation_warning_day >= 0:
			state = "Resignation warning"
		card.add_child(_message("%s  ·  %s  ·  $%.2f/h" % [
			state, String(member.contract_type).capitalize(), member.hourly_wage], INK_SOFT))
		card.add_child(_condition_bars(member))
		card.add_child(_message(_competency_summary(member), MUTED))
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		var detail := _button("View Detail", false, true)
		detail.pressed.connect(_open_detail.bind(member.uid))
		actions.add_child(detail)
		var fire := _button("End Employment", true)
		fire.pressed.connect(_fire_member.bind(member))
		actions.add_child(fire)
		card.add_child(actions)


func _render_schedule(rest: RestaurantState) -> void:
	_workspace.add_child(_section_heading("Schedule",
		"Drag shifts in 30-minute steps. Availability, overtime, absence, and training conflicts are validated before mutation."))
	var summary := _add_card(_workspace, GOLD)
	summary.add_child(_metric_row("Opening hours", "%s–%s" % [
		_hour(rest.open_hour), _hour(rest.close_hour)], _coverage_summary(rest)))
	var balance := _button("Build Coverage Schedule", false, true)
	balance.pressed.connect(_balance_schedule.bind(rest))
	summary.add_child(balance)
	if rest.staff.is_empty():
		_workspace.add_child(_empty_card("No Schedule Yet", "Hire people before building shift coverage."))
		return
	for member: StaffMember in rest.staff:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", BellaUi.tile_box())
		_workspace.add_child(panel)
		var margin := MarginContainer.new()
		for side: String in ["left", "top", "right", "bottom"]:
			margin.add_theme_constant_override("margin_%s" % side, 10)
		panel.add_child(margin)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		margin.add_child(row)
		var name_box := VBoxContainer.new()
		name_box.custom_minimum_size.x = 166
		name_box.add_child(_label(member.staff_name, 15, INK))
		name_box.add_child(_message("%s  ·  %s" % [
			_role_name(member.type_id),
			"absent" if member.is_absent(GameClock.day) else "available"], MUTED))
		row.add_child(name_box)
		var timeline := ShiftTimeline.new()
		timeline.setup(member, rest.open_hour, rest.close_hour,
			ROLE_COLORS.get(member.type_id, GOLD))
		timeline.shift_changed.connect(_change_shift.bind(member))
		row.add_child(timeline)
		var pay := _label("$%.0f\n%s" % [
			member.daily_pay(), _shift_text(member)], 14, INK_SOFT)
		pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pay.custom_minimum_size.x = 110
		row.add_child(pay)
		_timelines[member.uid] = timeline


func _render_market(rest: RestaurantState) -> void:
	_workspace.add_child(_section_heading("Job Market",
		"Candidates are shared, time-limited, and available to player and rivals through the same hiring command."))
	var filter_card := _add_card(_workspace)
	var row := HBoxContainer.new()
	row.add_child(_label("Role filter", 14, MUTED))
	var filter := OptionButton.new()
	filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter.custom_minimum_size.y = 44
	filter.add_item("All roles")
	filter.set_item_metadata(0, &"")
	var selected := 0
	for type_id: StringName in RestaurantManager.staff_types:
		var definition: StaffTypeDef = RestaurantManager.staff_type(type_id)
		var index := filter.item_count
		filter.add_item(definition.display_name)
		filter.set_item_metadata(index, type_id)
		if type_id == _market_filter_role:
			selected = index
	filter.select(selected)
	filter.item_selected.connect(func(index: int) -> void:
		_market_filter_role = StringName(filter.get_item_metadata(index))
		refresh())
	row.add_child(filter)
	filter_card.add_child(row)
	var filters := {}
	if _market_filter_role != &"":
		filters["role_id"] = _market_filter_role
	var service := _staff_service()
	var candidates: Array = service.call("candidates", CompanyManager.player.id, filters) if service != null else []
	if candidates.is_empty():
		_workspace.add_child(_empty_card("No Candidates Available",
			"The market refreshes daily. Relax the role filter or check again tomorrow."))
		return
	for candidate: JobCandidate in candidates:
		var accent: Color = ROLE_COLORS.get(candidate.type_id, GOLD)
		var card := _add_card(_workspace, accent)
		var heading := HBoxContainer.new()
		var title := _label(candidate.candidate_name, 19, INK)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(title)
		heading.add_child(_pill(_role_name(candidate.type_id), accent))
		card.add_child(heading)
		card.add_child(_message("Asking $%.2f/h  ·  %.0f desired hours  ·  expires day %d" % [
			candidate.hourly_wage, candidate.desired_weekly_hours, candidate.expires_day], INK_SOFT))
		card.add_child(_metric_row("Experience", "%.0f" % candidate.experience,
			_candidate_competencies(candidate)))
		card.add_child(_message("Traits: %s  ·  contracts: %s" % [
			_names(candidate.traits), _names(candidate.contract_preferences)], MUTED))
		if candidate.competing_offers.size() > 0:
			card.add_child(_message("%d competing offer%s" % [
				candidate.competing_offers.size(),
				"" if candidate.competing_offers.size() == 1 else "s"], ORANGE))
		var hire := _button("Make Offer  ·  $%.2f/h" % candidate.hourly_wage, false, true)
		hire.pressed.connect(_hire_candidate.bind(rest, candidate))
		card.add_child(hire)


func _render_employee_detail(rest: RestaurantState) -> void:
	_workspace.add_child(_section_heading("Employee Detail",
		"Condition, skills, attendance, contract, training, and manager relationships stay with the employee."))
	var member := _selected_member(rest)
	if member == null:
		_workspace.add_child(_empty_card("Select an Employee",
			"Choose View Detail from the Roster to inspect a persistent employee record."))
		return
	var card := _add_card(_workspace, ROLE_COLORS.get(member.type_id, GOLD))
	var heading := HBoxContainer.new()
	var title := _label(member.staff_name, 22, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(_pill(_role_name(member.type_id), ROLE_COLORS.get(member.type_id, GOLD)))
	card.add_child(heading)
	card.add_child(_message("%s  ·  hired day %d  ·  branch %s" % [
		String(member.contract_type).capitalize(), member.contract_start_day,
		rest.restaurant_name], INK_SOFT))
	card.add_child(_condition_bars(member))
	card.add_child(_metric_row("Experience", "%.0f" % member.experience,
		"Operational effect %.0f%%  ·  attendance entries %d" % [
			member.operational_effect(_primary_competency(member)) * 100.0, member.attendance_history.size()]))
	card.add_child(_message("Competencies: %s" % _all_competencies(member), MUTED))
	card.add_child(_message("Traits: %s" % _names(member.traits), MUTED))
	card.add_child(_message("Availability: %s  ·  overtime %s up to %.1fh" % [
		_availability_summary(member),
		"allowed" if member.overtime_allowed else "not allowed",
		member.maximum_overtime_hours], MUTED))
	if member.resignation_warning_day >= 0:
		card.add_child(_message("Resignation warning active. Risk %.0f%%." % [
			member.resignation_risk * 100.0], RED))
	var history := _add_card(_workspace)
	history.add_child(_label("History", 18, INK))
	history.add_child(_message("Training completions: %d  ·  employment events: %d" % [
		member.training_history.size(), member.employment_history.size()], INK_SOFT))
	history.add_child(_message("Manager relationships: %s" % _dictionary_text(
		member.manager_relationships), MUTED))


func _render_training(rest: RestaurantState) -> void:
	var service := _staff_service()
	_workspace.add_child(_section_heading("Training",
		"Headquarters capacity gates the queue. Costs are charged once and completion is applied exactly once."))
	if service == null:
		_workspace.add_child(_empty_card("Training Unavailable", "The workforce service is still starting."))
		return
	var capacity := int(service.call("training_capacity", CompanyManager.player.id))
	var active := 0
	var enrollments: Array = service.get("training_enrollments") as Array
	for enrollment: TrainingEnrollment in enrollments:
		if enrollment.company_id == CompanyManager.player.id and enrollment.status == &"active":
			active += 1
	var summary := _add_card(_workspace, GOLD)
	summary.add_child(_metric_row("Headquarters capacity", "%d slots" % capacity,
		"%d active  ·  queued enrollments start when capacity opens" % active))
	for enrollment: TrainingEnrollment in enrollments:
		if enrollment.company_id != CompanyManager.player.id or enrollment.status not in [&"queued", &"active"]:
			continue
		var program: TrainingProgramDef = service.get("training_programs").get(enrollment.program_id)
		var member := service.call("staff_member", CompanyManager.player.id, enrollment.staff_uid) as StaffMember
		var card := _add_card(_workspace, ORANGE if enrollment.status == &"queued" else GREEN)
		card.add_child(_label("%s  ·  %s" % [
			member.staff_name if member != null else "Former employee",
			program.display_name if program != null else String(enrollment.program_id)], 18, INK))
		card.add_child(_message("%s  ·  %s" % [
			String(enrollment.status).capitalize(),
			"waiting for capacity" if enrollment.status == &"queued"
			else "%d hours remaining" % maxi(0, enrollment.completes_window - _window())], INK_SOFT))
	var programs: Dictionary = service.get("training_programs")
	if programs.is_empty():
		_workspace.add_child(_empty_card("No Programs Configured",
			"Training definitions can be added without changing the workspace."))
		return
	for program_id: StringName in programs:
		var program: TrainingProgramDef = programs[program_id]
		var card := _add_card(_workspace)
		card.add_child(_label(program.display_name, 19, INK))
		card.add_child(_message(program.description, INK_SOFT))
		card.add_child(_message("$%.0f  ·  %d hours  ·  %s +%.0f%%  ·  work penalty %.0f%%" % [
			program.cost, program.duration_hours,
			String(program.competency_id).capitalize(), program.competency_gain * 100.0,
			program.work_penalty * 100.0], MUTED))
		var choice := OptionButton.new()
		choice.custom_minimum_size.y = 44
		for member: StaffMember in rest.staff:
			if program.supports_role(member.type_id):
				var index := choice.item_count
				choice.add_item(member.staff_name)
				choice.set_item_metadata(index, member.uid)
		card.add_child(choice)
		var enroll := _button("Enroll", false, true)
		enroll.disabled = choice.item_count == 0
		enroll.pressed.connect(_enroll_training.bind(rest, program, choice))
		card.add_child(enroll)


func _render_moves(rest: RestaurantState) -> void:
	_workspace.add_child(_section_heading("Transfers & Promotion",
		"Transfers preserve the employee record. Promotions require role eligibility and experience."))
	if rest.staff.is_empty():
		_workspace.add_child(_empty_card("No Employees", "Hire staff before arranging moves."))
		return
	for member: StaffMember in rest.staff:
		var card := _add_card(_workspace, ROLE_COLORS.get(member.type_id, GOLD))
		card.add_child(_label("%s  ·  %s" % [member.staff_name, _role_name(member.type_id)], 18, INK))
		var destination := OptionButton.new()
		destination.custom_minimum_size.y = 44
		for other: RestaurantState in CompanyManager.player.restaurants:
			if other.building_id == rest.building_id:
				continue
			var index := destination.item_count
			destination.add_item("Transfer to %s" % other.restaurant_name)
			destination.set_item_metadata(index, other.building_id)
		var transfer := _button("Transfer", false)
		transfer.disabled = destination.item_count == 0
		transfer.pressed.connect(_transfer_member.bind(rest, member, destination))
		card.add_child(_field("Destination", destination))
		card.add_child(transfer)
		var roles := _promotion_roles(member)
		var promotion := OptionButton.new()
		promotion.custom_minimum_size.y = 44
		for role: StaffTypeDef in roles:
			var index := promotion.item_count
			promotion.add_item("%s  ·  $%.2f/h" % [role.display_name, role.base_hourly_wage])
			promotion.set_item_metadata(index, role.id)
		var promote := _button("Promote", false, true)
		promote.disabled = promotion.item_count == 0
		promote.pressed.connect(_promote_member.bind(rest, member, promotion))
		card.add_child(_field("Promotion", promotion))
		card.add_child(promote)
		if roles.is_empty():
			card.add_child(_message("No eligible promotion at %.0f experience." % member.experience, MUTED))


func _render_policies(rest: RestaurantState) -> void:
	var service := _staff_service()
	_workspace.add_child(_section_heading("Workforce Policies",
		"Reusable schedules, availability, overtime, wage fairness, and warnings remain explicit."))
	var coverage := _add_card(_workspace, GOLD)
	coverage.add_child(_metric_row("Forecasted coverage", _coverage_grade(rest), _coverage_summary(rest)))
	var save_template := _button("Save Current Schedule Template", false, true)
	save_template.pressed.connect(_save_schedule_template.bind(rest))
	coverage.add_child(save_template)
	var templates: Dictionary = service.get("schedule_templates") if service != null else {}
	var prefix := "%s:" % CompanyManager.player.id
	for key: String in templates:
		if not key.begins_with(prefix):
			continue
		var template: Dictionary = templates[key]
		var card := _add_card(_workspace)
		card.add_child(_label(String(template.get("display_name", key.trim_prefix(prefix))), 18, INK))
		card.add_child(_message("%d assignments  ·  reusable across branches" % (
			template.get("assignments", []) as Array).size(), MUTED))
		var apply := _button("Apply to This Branch", false)
		apply.pressed.connect(_apply_schedule_template.bind(rest, key.trim_prefix(prefix)))
		card.add_child(apply)
	if templates.is_empty():
		_workspace.add_child(_message("No saved schedule templates yet.", MUTED))
	for member: StaffMember in rest.staff:
		var card := _add_card(_workspace, RED if member.resignation_warning_day >= 0 else Color.TRANSPARENT)
		card.add_child(_label(member.staff_name, 17, INK))
		card.add_child(_message("Guaranteed %.0fh/week  ·  $%.2f/h  ·  wage fairness %s" % [
			member.guaranteed_weekly_hours, member.hourly_wage,
			"at risk" if member.satisfaction < 0.4 else "stable"], INK_SOFT))
		card.add_child(_message("Availability %s  ·  overtime %s" % [
			_availability_summary(member),
			"allowed" if member.overtime_allowed else "blocked"], MUTED))
		var toggle := _button("Block Overtime" if member.overtime_allowed else "Allow Overtime", false)
		toggle.pressed.connect(_toggle_overtime.bind(rest, member))
		card.add_child(toggle)
	var absence_log: Array = service.get("absence_log") as Array if service != null else []
	if not absence_log.is_empty():
		var log_card := _add_card(_workspace)
		log_card.add_child(_label("Recent Absence Records", 18, INK))
		for index: int in range(maxi(0, absence_log.size() - 5), absence_log.size()):
			log_card.add_child(_message(_dictionary_text(absence_log[index]), MUTED))


func _change_shift(start: float, hours: float, member: StaffMember) -> void:
	_execute(&"staff.set_schedule", {
		"building_id": building_id,
		"staff_uid": member.uid,
		"start": start,
		"hours": hours,
		"weekday": -1,
	}, "schedule:%d" % member.uid)


func _balance_schedule(rest: RestaurantState) -> void:
	var assignments: Array[Dictionary] = []
	for index: int in range(rest.staff.size()):
		var member := rest.staff[index] as StaffMember
		var start := fmod(rest.open_hour + float(index % 3), 24.0)
		assignments.append({
			"staff_uid": member.uid,
			"start": start,
			"hours": clampf(member.shift_hours, 4.0, 8.0),
			"weekday": -1,
		})
	_execute(&"staff.bulk_schedule", {
		"building_id": rest.building_id,
		"assignments": assignments,
	}, "coverage")


func _hire_candidate(rest: RestaurantState, candidate: JobCandidate) -> void:
	_execute(&"staff.hire", {
		"building_id": rest.building_id,
		"candidate_uid": candidate.uid,
		"offer": {
			"hourly_wage": candidate.hourly_wage,
			"contract_type": candidate.contract_preferences[0] if not candidate.contract_preferences.is_empty() else &"permanent",
			"weekly_hours": candidate.desired_weekly_hours,
			"shift_start": rest.open_hour,
			"shift_hours": minf(8.0, candidate.desired_weekly_hours / 5.0),
		},
	}, "hire:%d" % candidate.uid)


func _fire_member(member: StaffMember) -> void:
	_execute(&"staff.fire", {
		"building_id": building_id,
		"staff_uid": member.uid,
	}, "fire:%d" % member.uid)


func _enroll_training(rest: RestaurantState, program: TrainingProgramDef,
		choice: OptionButton) -> void:
	if choice.selected < 0:
		return
	_execute(&"staff.train", {
		"building_id": rest.building_id,
		"staff_uid": int(choice.get_item_metadata(choice.selected)),
		"program_id": program.id,
	}, "training:%s:%d" % [program.id, int(choice.get_item_metadata(choice.selected))])


func _transfer_member(rest: RestaurantState, member: StaffMember,
		destination: OptionButton) -> void:
	if destination.selected < 0:
		return
	_execute(&"staff.transfer", {
		"building_id": rest.building_id,
		"staff_uid": member.uid,
		"to_building_id": int(destination.get_item_metadata(destination.selected)),
	}, "transfer:%d" % member.uid)


func _promote_member(rest: RestaurantState, member: StaffMember,
		promotion: OptionButton) -> void:
	if promotion.selected < 0:
		return
	var role_id: StringName = StringName(promotion.get_item_metadata(promotion.selected))
	var definition: StaffTypeDef = RestaurantManager.staff_type(role_id)
	_execute(&"staff.promote", {
		"building_id": rest.building_id,
		"staff_uid": member.uid,
		"new_role_id": role_id,
		"hourly_wage": maxf(member.hourly_wage, definition.base_hourly_wage),
	}, "promote:%d:%s" % [member.uid, role_id])


func _save_schedule_template(rest: RestaurantState) -> void:
	var assignments: Array[Dictionary] = []
	for member: StaffMember in rest.staff:
		assignments.append({
			"staff_uid": member.uid,
			"role_id": member.type_id,
			"start": member.shift_start,
			"hours": member.shift_hours,
			"weekday": -1,
		})
	_execute(&"staff.save_schedule_template", {
		"building_id": rest.building_id,
		"template_id": "standard",
		"display_name": "Standard Week",
		"assignments": assignments,
	}, "save_template")


func _apply_schedule_template(rest: RestaurantState, template_id: String) -> void:
	_execute(&"staff.apply_schedule_template", {
		"building_id": rest.building_id,
		"template_id": template_id,
	}, "apply_template:%s" % template_id)


func _toggle_overtime(rest: RestaurantState, member: StaffMember) -> void:
	_execute(&"staff.set_contract", {
		"building_id": rest.building_id,
		"staff_uid": member.uid,
		"contract_type": member.contract_type,
		"hourly_wage": member.hourly_wage,
		"overtime_allowed": not member.overtime_allowed,
		"maximum_overtime_hours": member.maximum_overtime_hours,
	}, "overtime:%d" % member.uid)


func _execute(command_id: StringName, arguments: Dictionary, suffix: String) -> void:
	var router := _router()
	if router == null or CompanyManager.player == null:
		_status.text = "The command router is unavailable."
		return
	_command_serial += 1
	var key := "ui:%s:%s:%d:%d:%d" % [
		command_id, suffix, GameClock.total_minutes(), building_id, _command_serial]
	var result := router.call("execute", command_id, arguments, {
		"kind": &"player",
		"id": "staff_workspace",
		"company_id": CompanyManager.player.id,
	}, key) as CommandResult
	if result == null:
		_status.text = "That workforce action is unavailable."
	elif result.ok:
		_status.text = result.explanation if not result.explanation.is_empty() else (
			result.message if not result.message.is_empty() else "Workforce updated.")
	else:
		_status.text = result.message
	_queue_refresh()


func _open_detail(uid: int) -> void:
	_selected_staff_uid = uid
	_active_tab = &"detail"
	refresh()


func _selected_member(rest: RestaurantState) -> StaffMember:
	for member: StaffMember in rest.staff:
		if member.uid == _selected_staff_uid:
			return member
	return null


func _promotion_roles(member: StaffMember) -> Array[StaffTypeDef]:
	var result: Array[StaffTypeDef] = []
	for type_id: StringName in RestaurantManager.staff_types:
		var definition := RestaurantManager.staff_type(type_id)
		if definition.promotion_from_roles.has(member.type_id) and (
				member.experience >= definition.minimum_experience_for_promotion):
			result.append(definition)
	return result


func _select_tab(tab_id: StringName) -> void:
	_active_tab = tab_id
	refresh()
	_workspace_scroll.scroll_vertical = 0


func _on_branch_picked(index: int) -> void:
	if index >= 0:
		building_id = int(_branch_picker.get_item_metadata(index))
		_selected_staff_uid = -1
		refresh()


func _router() -> Node:
	return get_node_or_null("/root/BranchCommandRouter")


func _staff_service() -> Node:
	return get_node_or_null("/root/StaffManager")


func _window() -> int:
	return int(GameClock.total_minutes() / 60)


func _coverage_grade(rest: RestaurantState) -> String:
	var roles := {}
	for member: StaffMember in rest.staff:
		if member.is_absent(GameClock.day):
			continue
		roles[member.type_id] = int(roles.get(member.type_id, 0)) + 1
	var core := int(roles.get(&"cook", 0)) + int(roles.get(&"waiter", 0))
	if core >= 4:
		return "Strong"
	if core >= 2:
		return "Workable"
	return "At risk"


func _coverage_summary(rest: RestaurantState) -> String:
	var counts := {}
	for member: StaffMember in rest.staff:
		if not member.is_absent(GameClock.day):
			counts[member.type_id] = int(counts.get(member.type_id, 0)) + 1
	var parts: Array[String] = []
	for role_id: StringName in [&"cook", &"waiter", &"driver", &"runner", &"cleaner", &"manager"]:
		if int(counts.get(role_id, 0)) > 0:
			parts.append("%d %s" % [int(counts[role_id]), _role_name(role_id).to_lower()])
	return "No available coverage" if parts.is_empty() else ", ".join(parts)


func _condition_bars(member: StaffMember) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	for entry: Array in [
		["Energy", member.energy, GREEN],
		["Motivation", member.motivation, GOLD],
		["Satisfaction", member.satisfaction, ORANGE],
		["Stress", member.stress, RED],
	]:
		var box := VBoxContainer.new()
		box.add_child(_label(String(entry[0]), 12, MUTED))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(150, 20)
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = float(entry[1]) * 100.0
		bar.show_percentage = true
		box.add_child(bar)
		grid.add_child(box)
	return grid


func _primary_competency(member: StaffMember) -> StringName:
	for key: Variant in member.competencies:
		return StringName(key)
	var definition := RestaurantManager.staff_type(member.type_id)
	if definition != null and not definition.competency_keys.is_empty():
		return definition.competency_keys[0]
	return &"service"


func _competency_summary(member: StaffMember) -> String:
	var parts: Array[String] = []
	for key: Variant in member.competencies:
		parts.append("%s %.0f%%" % [String(key).capitalize(), float(member.competencies[key]) * 100.0])
		if parts.size() >= 3:
			break
	return "Skills pending assessment" if parts.is_empty() else "Skills: %s" % ", ".join(parts)


func _all_competencies(member: StaffMember) -> String:
	var parts: Array[String] = []
	for key: Variant in member.competencies:
		parts.append("%s %.0f%%" % [String(key).capitalize(), float(member.competencies[key]) * 100.0])
	return "Pending assessment" if parts.is_empty() else ", ".join(parts)


func _candidate_competencies(candidate: JobCandidate) -> String:
	var parts: Array[String] = []
	for key: Variant in candidate.competencies:
		parts.append("%s %.0f%%" % [String(key).capitalize(), float(candidate.competencies[key]) * 100.0])
		if parts.size() >= 3:
			break
	return "Skills pending assessment" if parts.is_empty() else ", ".join(parts)


func _availability_summary(member: StaffMember) -> String:
	if member.availability_by_weekday.is_empty():
		return "all week"
	return "%d configured days" % member.availability_by_weekday.size()


func _shift_text(member: StaffMember) -> String:
	return "%s–%s" % [_hour(member.shift_start), _hour(fmod(member.shift_start + member.shift_hours, 24.0))]


func _hour(value: float) -> String:
	var whole := int(floor(value)) % 24
	var minutes := int(round((value - floor(value)) * 60.0)) % 60
	return "%02d:%02d" % [whole, minutes]


func _role_name(role_id: StringName) -> String:
	var definition := RestaurantManager.staff_type(role_id)
	return definition.display_name if definition != null else String(role_id).capitalize()


func _names(values: Array) -> String:
	if values.is_empty():
		return "None"
	var result: Array[String] = []
	for value: Variant in values:
		result.append(String(value).replace("_", " ").capitalize())
	return ", ".join(result)


func _dictionary_text(values: Dictionary) -> String:
	if values.is_empty():
		return "No records"
	var parts: Array[String] = []
	for key: Variant in values:
		parts.append("%s %s" % [String(key).replace("_", " "), str(values[key])])
	return ", ".join(parts)


func _section_heading(title_text: String, explanation: String) -> Control:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	stack.add_child(_label(title_text, 21, INK))
	stack.add_child(_message(explanation, MUTED))
	return stack


func _add_card(parent: Container, accent: Color = Color.TRANSPARENT) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",
		BellaUi.tile_box(accent if accent.a > 0.0 else BellaUi.PAPER_EDGE,
			3 if accent.a > 0.0 else 2))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	return stack


func _empty_card(title_text: String, explanation: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BellaUi.tile_box())
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	stack.add_child(_label(title_text, 19, INK))
	stack.add_child(_message(explanation, MUTED))
	margin.add_child(stack)
	return panel


func _field(label_text: String, control: Control) -> Control:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	stack.add_child(_label(label_text, 13, MUTED))
	stack.add_child(control)
	return stack


func _metric_row(label_text: String, value_text: String, detail: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(_label(label_text, 13, MUTED))
	stack.add_child(_message(detail, INK_SOFT))
	row.add_child(stack)
	var value := _label(value_text, 17, INK)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size.x = 120
	row.add_child(value)
	return row


func _pill(text_value: String, color: Color) -> PanelContainer:
	return BellaUi.pill(text_value, INK, color.lightened(0.45), color.darkened(0.18))


func _button(text_value: String, danger: bool = false, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 44
	if primary:
		BellaUi.green_button(button)
	elif danger:
		TycoonTheme.apply_orange(button)
	return button


func _label(text_value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _message(text_value: String, color: Color) -> Label:
	var label := _label(text_value, 14, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
