class_name ManagersScreen
extends TycoonScreen
## Six-tab branch management workspace. Managers act through policy and the
## shared command router; this screen only presents evidence and player intent.

signal request_screen(screen_id: StringName)

const INK: Color = Color("#3a2010")
const INK_SOFT: Color = Color("#6e3d18")
const MUTED: Color = Color("#92704d")
const RED: Color = Color("#ea4a2f")
const ORANGE: Color = Color("#f99a1c")
const GOLD: Color = Color("#f5c518")
const GREEN: Color = Color("#6fb63a")
const PAPER: Color = Color("#fbefc9")
const BREAKPOINT_PHONE: float = 720.0
const RAIL_WIDTH: float = 240.0
const CATEGORIES: Array[StringName] = [
	&"inventory", &"maintenance", &"staffing", &"schedules", &"delivery",
	&"hours", &"menu", &"marketing", &"layout", &"training", &"emergency",
]
const TABS: Array[Dictionary] = [
	{"id": &"assignments", "label": "Assignments"},
	{"id": &"templates", "label": "Policy Templates"},
	{"id": &"approvals", "label": "Approval Inbox"},
	{"id": &"decisions", "label": "Decisions"},
	{"id": &"performance", "label": "Performance"},
	{"id": &"escalations", "label": "Escalations"},
]

var _active_tab: StringName = &"assignments"
var _selected_branch_id: int = -1
var _tab_buttons: Dictionary = {}
var _branch_picker: OptionButton
var _rail: PanelContainer
var _rail_list: VBoxContainer
var _workspace: VBoxContainer
var _workspace_scroll: ScrollContainer
var _main: HBoxContainer
var _status: Label
var _header_context: Label
var _is_phone: bool = false
var _refresh_queued: bool = false


func screen_title() -> String:
	return "Managers & Automation"


func screen_icon() -> StringName:
	return &"briefcase"


func _build() -> void:
	custom_minimum_size = Vector2(360, 520)
	var base_header := _content.get_child(0) as HBoxContainer
	if base_header != null and base_header.get_child_count() > 0:
		var close_button := base_header.get_child(base_header.get_child_count() - 1) as Button
		if close_button != null:
			close_button.custom_minimum_size = Vector2(44, 44)
	add_theme_stylebox_override("panel", TycoonTheme.wood_frame_lg_box())
	_build_context_header()
	_build_tab_bar()
	_main = HBoxContainer.new()
	_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main.add_theme_constant_override("separation", 12)
	_content.add_child(_main)
	_build_branch_rail()
	_workspace_scroll = ScrollContainer.new()
	_workspace_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_workspace = VBoxContainer.new()
	_workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace.add_theme_constant_override("separation", 12)
	_workspace_scroll.add_child(_workspace)
	_main.add_child(_workspace_scroll)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", INK_SOFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status)
	_connect_manager_signals()
	_select_initial_branch()
	_apply_responsive_layout()
	resized.connect(_apply_responsive_layout)


func refresh() -> void:
	_refresh_queued = false
	var manager: Node = _management()
	if manager == null or CompanyManager.player == null:
		_render_unavailable("Management services are still starting.")
		return
	_ensure_selected_branch()
	_populate_branch_picker()
	_render_branch_rail()
	_refresh_tabs()
	_header_context.text = _branch_name(_selected_branch_id)
	_clear(_workspace)
	match _active_tab:
		&"templates":
			_render_templates(manager)
		&"approvals":
			_render_approvals(manager)
		&"decisions":
			_render_decisions(manager)
		&"performance":
			_render_performance(manager)
		&"escalations":
			_render_escalations(manager)
		_:
			_render_assignments(manager)


func _build_context_header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_content.add_child(row)
	var title := Label.new()
	title.text = "Branch Desk"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", INK)
	row.add_child(title)
	_header_context = Label.new()
	_header_context.text = "Choose a branch"
	_header_context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_context.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_header_context.add_theme_font_size_override("font_size", 15)
	_header_context.add_theme_color_override("font_color", INK_SOFT)
	row.add_child(_header_context)
	_branch_picker = OptionButton.new()
	_branch_picker.custom_minimum_size = Vector2(190, 44)
	_branch_picker.item_selected.connect(_on_branch_picked)
	_content.add_child(_branch_picker)


func _build_tab_bar() -> void:
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
		button.custom_minimum_size = Vector2(128, 44)
		button.pressed.connect(_select_tab.bind(StringName(tab["id"])))
		BellaUi.style_chip(button, StringName(tab["id"]) == _active_tab)
		row.add_child(button)
		_tab_buttons[StringName(tab["id"])] = button


func _build_branch_rail() -> void:
	_rail = PanelContainer.new()
	_rail.custom_minimum_size.x = RAIL_WIDTH
	_rail.add_theme_stylebox_override("panel", BellaUi.sunk_box())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_rail.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	var heading := Label.new()
	heading.text = "Branch Managers"
	heading.add_theme_font_size_override("font_size", 17)
	heading.add_theme_color_override("font_color", INK)
	stack.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rail_list = VBoxContainer.new()
	_rail_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rail_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_rail_list)
	stack.add_child(scroll)
	_main.add_child(_rail)


func _connect_manager_signals() -> void:
	var manager := _management()
	if manager != null:
		for signal_name: StringName in [
			&"assignments_changed", &"policies_changed", &"approvals_changed",
			&"decision_recorded", &"escalation_created", &"performance_changed",
		]:
			if manager.has_signal(signal_name):
				var callback := Callable(self, "_queue_refresh")
				if not manager.is_connected(signal_name, callback):
					manager.connect(signal_name, callback)


func _queue_refresh(_unused: Variant = null) -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	refresh.call_deferred()


func _apply_responsive_layout() -> void:
	if not is_inside_tree() or _rail == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var phone: bool = viewport_size.x < BREAKPOINT_PHONE
	var target_size: Vector2 = Vector2(
		maxf(340.0, viewport_size.x - 24.0),
		minf(780.0, maxf(600.0, viewport_size.y - 32.0))) if phone else Vector2(
			minf(1180.0, maxf(780.0, viewport_size.x - 48.0)),
			minf(920.0, maxf(680.0, viewport_size.y - 48.0)))
	if phone == _is_phone and custom_minimum_size.is_equal_approx(target_size):
		return
	_is_phone = phone
	_rail.visible = not phone
	_branch_picker.visible = phone
	custom_minimum_size = target_size
	_force_layout_sort()


func _force_layout_sort() -> void:
	notification(Container.NOTIFICATION_SORT_CHILDREN)
	var paper := get_child(0) as Container
	if paper != null:
		paper.notification(Container.NOTIFICATION_SORT_CHILDREN)
	_content.notification(Container.NOTIFICATION_SORT_CHILDREN)
	_main.notification(Container.NOTIFICATION_SORT_CHILDREN)
	_workspace_scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)


func _select_initial_branch() -> void:
	if building_id >= 0 and RestaurantManager.by_building.has(building_id):
		_selected_branch_id = building_id
	elif CompanyManager.player != null and not CompanyManager.player.restaurants.is_empty():
		_selected_branch_id = (CompanyManager.player.restaurants[0] as RestaurantState).building_id


func _ensure_selected_branch() -> void:
	if CompanyManager.player == null:
		_selected_branch_id = -1
		return
	for rest: RestaurantState in CompanyManager.player.restaurants:
		if rest.building_id == _selected_branch_id:
			return
	_selected_branch_id = -1 if CompanyManager.player.restaurants.is_empty() else (
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
		if rest.building_id == _selected_branch_id:
			selected_index = index
	if _branch_picker.item_count > 0:
		_branch_picker.select(selected_index)


func _render_branch_rail() -> void:
	_clear(_rail_list)
	if CompanyManager.player == null or CompanyManager.player.restaurants.is_empty():
		_rail_list.add_child(_message("No branches yet.", MUTED))
		return
	var manager := _management()
	for rest: RestaurantState in CompanyManager.player.restaurants:
		var assignment := manager.call("assignment_for_branch", CompanyManager.player.id, rest.building_id) as ManagerAssignment
		var state_text := "No manager"
		if assignment != null:
			if assignment.founder_assistance:
				state_text = "Founder assistance"
			elif not assignment.active or assignment.is_paused():
				state_text = "Paused"
			else:
				state_text = _manager_name(assignment.manager_employee_uid)
		var button := Button.new()
		button.text = "%s\n%s" % [rest.restaurant_name, state_text]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(RAIL_WIDTH - 20.0, 64)
		button.pressed.connect(_select_branch.bind(rest.building_id))
		BellaUi.style_chip(button, rest.building_id == _selected_branch_id)
		_rail_list.add_child(button)


func _refresh_tabs() -> void:
	var manager := _management()
	var approvals := (manager.call("pending_approvals", CompanyManager.player.id) as Array).size()
	var escalations := (manager.call("open_escalations", CompanyManager.player.id) as Array).size()
	for tab: Dictionary in TABS:
		var id := StringName(tab["id"])
		var text_value := String(tab["label"])
		if id == &"approvals" and approvals > 0:
			text_value += "  %d" % approvals
		elif id == &"escalations" and escalations > 0:
			text_value += "  %d" % escalations
		var button: Button = _tab_buttons[id]
		button.text = text_value
		BellaUi.style_chip(button, id == _active_tab)


func _render_assignments(manager: Node) -> void:
	var rest := _selected_restaurant()
	if rest == null:
		_workspace.add_child(_empty_card("No Branch Selected", "Choose a restaurant to configure its manager."))
		return
	var assignment := manager.call("assignment_for_branch", CompanyManager.player.id, rest.building_id) as ManagerAssignment
	_workspace.add_child(_section_heading("Assignment", "Who runs this branch and within which policy."))
	if assignment == null or assignment.founder_assistance:
		_render_unassigned(manager, rest, assignment)
		return
	var member := _staff_member(assignment.manager_employee_uid)
	var policy := manager.call("policy_by_uid", assignment.policy_uid) as BranchPolicy
	var card := _card()
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	var title := _label(_manager_name(assignment.manager_employee_uid), 21, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var state_text := "Active" if assignment.active and not assignment.is_paused() else "Paused"
	title_row.add_child(_pill(state_text, GREEN if state_text == "Active" else ORANGE))
	card.add_child(title_row)
	if member != null:
		card.add_child(_message("%s contract  ·  $%.2f/h  ·  %s" % [
			String(member.contract_type).capitalize(), member.hourly_wage,
			_condition_summary(member)], INK_SOFT))
		card.add_child(_metric_line("Decision skill", "%.0f%%" % (_manager_skill(member) * 100.0),
			"Experience %.0f  ·  motivation %.0f%%  ·  stress %.0f%%" % [
				member.experience, member.motivation * 100.0, member.stress * 100.0]))
	card.add_child(_metric_line("Branch target", rest.restaurant_name,
		"%s preset  ·  assigned day %d" % [
			policy.display_name if policy != null else "Missing policy", assignment.assigned_day]))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var pause := _action_button("Pause" if assignment.active else "Activate", assignment.active)
	pause.pressed.connect(_toggle_assignment.bind(assignment))
	actions.add_child(pause)
	var reassign := _action_button("Reassign", false)
	reassign.pressed.connect(_show_reassign.bind(manager, assignment))
	actions.add_child(reassign)
	card.add_child(actions)
	_mount_card(_workspace, card)
	if policy == null:
		_workspace.add_child(_empty_card("Policy Missing", "Apply a policy template to resume decisions."))
		return
	_workspace.add_child(_section_heading("Authority Matrix",
		"Recommend observes, Approval asks first, Automatic acts within every guardrail."))
	var authority_card := _card()
	for category: StringName in CATEGORIES:
		authority_card.add_child(_authority_row(manager, policy, category))
	_mount_card(_workspace, authority_card)
	_workspace.add_child(_section_heading("Budgets & Guardrails",
		"Hard limits win even when a category is automatic."))
	_render_policy_controls(manager, policy)
	_render_previewed_actions(manager, assignment)


func _render_unassigned(manager: Node, rest: RestaurantState,
		founder: ManagerAssignment) -> void:
	if founder != null:
		var founder_card: VBoxContainer = _card(ORANGE)
		founder_card.add_child(_label("Founder Assistance", 20, INK))
		founder_card.add_child(_message(
			"This branch receives recommend-only assistance. Hire a manager and assign a policy to unlock approvals and automatic actions.", INK_SOFT))
		_mount_card(_workspace, founder_card)
	else:
		_workspace.add_child(_empty_card("No Manager Assigned",
			"Choose a manager employee and a policy. Assignments use the employee record; condition and salary stay in Staff."))
	var managers: Array[StaffMember] = _manager_candidates()
	var manager_option: OptionButton = OptionButton.new()
	manager_option.custom_minimum_size.y = 44
	for member: StaffMember in managers:
		var index: int = manager_option.item_count
		manager_option.add_item("%s  ·  %.0f%% skill" % [member.staff_name, _manager_skill(member) * 100.0])
		manager_option.set_item_metadata(index, member.uid)
	var preset_option: OptionButton = OptionButton.new()
	preset_option.custom_minimum_size.y = 44
	var templates: Array = manager.get("policy_templates") as Array
	for template: BranchPolicy in templates:
		var index: int = preset_option.item_count
		preset_option.add_item(template.display_name)
		preset_option.set_item_metadata(index, template.uid)
	var form: VBoxContainer = _card()
	form.add_child(_field("Manager", manager_option))
	form.add_child(_field("Policy preset", preset_option))
	var assign: Button = _action_button("Assign Manager", false, true)
	assign.disabled = managers.is_empty() or preset_option.item_count == 0
	assign.pressed.connect(_assign_selected.bind(manager, rest, manager_option, preset_option))
	form.add_child(assign)
	if managers.is_empty():
		var hire: Button = _action_button("Open Staff Job Market", false)
		hire.pressed.connect(func() -> void: request_screen.emit(&"staff"))
		form.add_child(_message("No manager employees are available.", MUTED))
		form.add_child(hire)
	_mount_card(_workspace, form)


func _authority_row(manager: Node, policy: BranchPolicy, category: StringName) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 48
	row.add_theme_constant_override("separation", 8)
	var name_label := _label(String(category).capitalize(), 15, INK)
	name_label.custom_minimum_size.x = 150
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var choice := OptionButton.new()
	choice.custom_minimum_size = Vector2(170, 44)
	for authority: StringName in [
		BranchPolicy.AUTHORITY_RECOMMEND,
		BranchPolicy.AUTHORITY_APPROVAL,
		BranchPolicy.AUTHORITY_AUTOMATIC,
	]:
		choice.add_item(String(authority).capitalize())
		choice.set_item_metadata(choice.item_count - 1, authority)
		if policy.authority_for(category) == authority:
			choice.select(choice.item_count - 1)
	choice.item_selected.connect(func(index: int) -> void:
		var authority: StringName = choice.get_item_metadata(index)
		_apply_result(manager.call("set_policy_authority", policy.uid, category, authority) as CommandResult))
	row.add_child(choice)
	return row


func _render_policy_controls(manager: Node, policy: BranchPolicy) -> void:
	var card := _card()
	card.add_child(_number_control(manager, policy, &"cash_reserve", "Cash reserve",
		policy.cash_reserve, 0.0, 50000.0, 250.0))
	for category: StringName in [&"inventory", &"staffing", &"maintenance", &"marketing", &"emergency"]:
		card.add_child(_budget_control(manager, policy, category))
	card.add_child(_message("Suppliers: %s" % (
		"Any approved supplier" if policy.supplier_allowlist.is_empty()
		else _names(policy.supplier_allowlist)), INK_SOFT))
	card.add_child(_message("Price range: $%.2f–$%.2f  ·  quality tiers %d–%d" % [
		policy.minimum_price, policy.maximum_price,
		policy.minimum_quality_tier, policy.maximum_quality_tier], INK_SOFT))
	card.add_child(_message("Protected staff: %d  ·  approved layouts: %s" % [
		policy.protected_staff_uids.size(),
		"None" if policy.approved_layout_templates.is_empty() else _names(policy.approved_layout_templates)], INK_SOFT))
	if not policy.local_overrides.is_empty():
		card.add_child(_message("Local overrides are active for this branch.", RED))
	_mount_card(_workspace, card)


func _number_control(manager: Node, policy: BranchPolicy, field_name: StringName,
		label_text: String, value: float, minimum: float, maximum: float, step: float) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size.y = 48
	var label: Label = _label(label_text, 15, INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin: SpinBox = SpinBox.new()
	spin.custom_minimum_size = Vector2(160, 44)
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.prefix = "$"
	spin.get_line_edit().add_theme_color_override("font_color", INK)
	spin.value_changed.connect(func(next_value: float) -> void:
		_apply_result(manager.call("update_policy_override", policy.uid, field_name, next_value) as CommandResult))
	row.add_child(spin)
	return row


func _budget_control(manager: Node, policy: BranchPolicy, category: StringName) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size.y = 48
	var label: Label = _label("%s daily budget" % String(category).capitalize(), 15, INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin: SpinBox = SpinBox.new()
	spin.custom_minimum_size = Vector2(160, 44)
	spin.min_value = 0.0
	spin.max_value = 25000.0
	spin.step = 100.0
	spin.value = policy.budget_for(category)
	spin.prefix = "$"
	spin.value_changed.connect(func(next_value: float) -> void:
		var budgets := policy.daily_budget_by_category.duplicate(true)
		budgets[category] = next_value
		_apply_result(manager.call("update_policy_override", policy.uid,
			&"daily_budget_by_category", budgets) as CommandResult))
	row.add_child(spin)
	return row


func _render_previewed_actions(manager: Node, assignment: ManagerAssignment) -> void:
	_workspace.add_child(_section_heading("Previewed Actions",
		"The latest legal alternatives from the manager's report-only decision window."))
	var card := _card()
	var found := false
	var decisions: Array = manager.get("decisions") as Array
	for index: int in range(decisions.size() - 1, -1, -1):
		var decision := decisions[index] as ManagerDecisionRecord
		if decision == null or decision.assignment_uid != assignment.uid:
			continue
		for alternative: Dictionary in decision.alternatives.slice(0, 3):
			card.add_child(_metric_line(_command_label(StringName(alternative.get("command_id", &"unknown"))),
				"Score %.2f" % float(alternative.get("score", 0.0)),
				String(alternative.get("explanation", "Legal under current policy."))))
		found = true
		break
	if not found:
		card.add_child(_message("No decision window has produced a legal action yet.", MUTED))
	_mount_card(_workspace, card)


func _render_templates(manager: Node) -> void:
	_workspace.add_child(_section_heading("Policy Templates",
		"Versioned presets are copied before branch-specific changes are made."))
	var templates: Array = manager.get("policy_templates") as Array
	for template: BranchPolicy in templates:
		var card := _card()
		var row := HBoxContainer.new()
		var title := _label(template.display_name, 20, INK)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		row.add_child(_pill("Version %d" % template.template_version, GOLD))
		card.add_child(row)
		card.add_child(_message(_preset_summary(template), INK_SOFT))
		card.add_child(_message("Reserve $%.0f  ·  automatic: %s" % [
			template.cash_reserve, _automatic_categories(template)], MUTED))
		var apply := _action_button("Copy to This Branch", false, true)
		apply.disabled = _selected_restaurant() == null
		apply.pressed.connect(_copy_template.bind(manager, template))
		card.add_child(apply)
		_mount_card(_workspace, card)
	var local_policies: Array = manager.get("policies") as Array
	var local_count := 0
	for policy: BranchPolicy in local_policies:
		if policy.company_id == CompanyManager.player.id:
			local_count += 1
	if local_count > 0:
		_workspace.add_child(_message("%d branch-specific policy copies. Local changes remain visibly marked." % local_count, MUTED))


func _render_approvals(manager: Node) -> void:
	_workspace.add_child(_section_heading("Approval Inbox",
		"Each request shows its evidence, expected impact, exact cost, and deadline."))
	var approvals: Array = manager.call("pending_approvals", CompanyManager.player.id) as Array
	var shown := 0
	for approval: ManagerApproval in approvals:
		if _selected_branch_id >= 0 and approval.branch_building_id != _selected_branch_id:
			continue
		shown += 1
		var card := _card(ORANGE)
		var heading := HBoxContainer.new()
		var title := _label(_command_label(approval.command_id), 20, INK)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(title)
		heading.add_child(_pill("Approval", ORANGE))
		card.add_child(heading)
		card.add_child(_message(approval.explanation, INK_SOFT))
		card.add_child(_metric_line("Expected impact", approval.expected_impact,
			"Exact cost $%.2f  ·  deadline in %d hours" % [
				approval.exact_cost, maxi(0, approval.deadline_window - _window())]))
		if not approval.evidence.is_empty():
			card.add_child(_message("Evidence\n- %s" % "\n- ".join(PackedStringArray(approval.evidence)), MUTED))
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		var approve := _action_button("Approve", false, true)
		approve.pressed.connect(_approve.bind(manager, approval.uid))
		actions.add_child(approve)
		var reject := _action_button("Reject", true)
		reject.pressed.connect(_reject.bind(manager, approval.uid))
		actions.add_child(reject)
		var edit := _action_button("Edit", false)
		edit.pressed.connect(_edit_approval.bind(manager, approval))
		actions.add_child(edit)
		card.add_child(actions)
		_mount_card(_workspace, card)
	if shown == 0:
		_workspace.add_child(_empty_card("Inbox Clear",
			"Approval-mode decisions will stay here across saves until you act or their deadline passes."))


func _render_decisions(manager: Node) -> void:
	_workspace.add_child(_section_heading("Decision History",
		"Plain-language records show what the manager saw, considered, expected, and later learned."))
	var filter_row := HBoxContainer.new()
	filter_row.add_child(_message("Showing this branch", MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_child(spacer)
	filter_row.add_child(_pill("Newest first", GOLD))
	_workspace.add_child(filter_row)
	var decisions: Array = manager.get("decisions") as Array
	var shown := 0
	for index: int in range(decisions.size() - 1, -1, -1):
		var decision := decisions[index] as ManagerDecisionRecord
		if decision == null or decision.company_id != CompanyManager.player.id:
			continue
		if _selected_branch_id >= 0 and decision.branch_building_id != _selected_branch_id:
			continue
		shown += 1
		if shown > 40:
			break
		var color := GREEN if decision.command_result_code == &"ok" else (
			ORANGE if decision.permission_category == BranchPolicy.AUTHORITY_APPROVAL else RED)
		var card := _card(color)
		var heading := HBoxContainer.new()
		var title := _label(_command_label(decision.selected_command), 18, INK)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(title)
		heading.add_child(_pill(String(decision.permission_category).capitalize(), color))
		card.add_child(heading)
		card.add_child(_message(decision.explanation, INK_SOFT))
		card.add_child(_message("Expected: %s" % _dictionary_sentence(decision.expected_result), MUTED))
		var actual := "Pending evaluation"
		if decision.evaluation_status == &"evaluated":
			actual = _dictionary_sentence(decision.actual_result)
		card.add_child(_message("Actual: %s" % actual, MUTED))
		card.add_child(_message("Estimated $%.2f  ·  actual $%.2f  ·  %s" % [
			decision.estimated_cost, decision.actual_cost,
			"overridden" if decision.overridden else "not overridden"], INK_SOFT))
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		if decision.can_undo(_window()):
			var undo := _action_button("Safe Undo", true)
			undo.pressed.connect(_undo_decision.bind(manager, decision.uid))
			actions.add_child(undo)
		if not decision.selected_command.is_empty():
			var override := _action_button("Repeat Manually", false)
			override.tooltip_text = "Execute the recorded command as an explicit player override."
			override.pressed.connect(_repeat_override.bind(manager, decision))
			actions.add_child(override)
		if actions.get_child_count() > 0:
			card.add_child(actions)
		_mount_card(_workspace, card)
	if shown == 0:
		_workspace.add_child(_empty_card("No Decisions Yet",
			"Active managers evaluate hourly, at shift boundaries, and after urgent operational events."))


func _render_performance(manager: Node) -> void:
	_workspace.add_child(_section_heading("Manager Performance",
		"Targets are compared with later branch reports. Managers never receive raw output bonuses."))
	var assignments: Array = manager.get("assignments") as Array
	var shown := 0
	for assignment: ManagerAssignment in assignments:
		if assignment.company_id != CompanyManager.player.id:
			continue
		if _selected_branch_id >= 0 and assignment.branch_building_id != _selected_branch_id:
			continue
		shown += 1
		var report: Dictionary = manager.call("performance_for_assignment", assignment.uid)
		var card := _card(GREEN)
		var title := _label(_branch_name(assignment.branch_building_id), 20, INK)
		card.add_child(title)
		card.add_child(_message("%s  ·  %s" % [
			_manager_name(assignment.manager_employee_uid),
			"Founder assistance" if assignment.founder_assistance else "Assigned manager"], INK_SOFT))
		card.add_child(_metric_line("Evaluated decisions",
			"%d" % int(report.get("evaluated_decisions", 0)),
			"%d improved the selected goal  ·  %.0f%% success" % [
				int(report.get("successful_decisions", 0)),
				float(report.get("success_rate", 0.0)) * 100.0]))
		card.add_child(_metric_line("Cost forecast",
			"$%.2f" % float(report.get("estimated_cost", 0.0)),
			"Actual $%.2f  ·  overrides %d" % [
				float(report.get("actual_cost", 0.0)), int(report.get("overrides", 0))]))
		card.add_child(_message(String(report.get("note", "")), MUTED))
		_mount_card(_workspace, card)
	if shown == 0:
		_workspace.add_child(_empty_card("No Performance Window",
			"Assign a manager and let a command reach its evaluation horizon."))


func _render_escalations(manager: Node) -> void:
	_workspace.add_child(_section_heading("Escalations",
		"Blocked and expired actions stop retrying and wait for a player decision here."))
	var escalations: Array = manager.call("open_escalations", CompanyManager.player.id) as Array
	var shown := 0
	for escalation: ManagerEscalation in escalations:
		if _selected_branch_id >= 0 and escalation.branch_building_id != _selected_branch_id:
			continue
		shown += 1
		var card := _card(RED)
		var heading := HBoxContainer.new()
		var title := _label(_command_label(escalation.command_id), 19, INK)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(title)
		heading.add_child(_pill(String(escalation.reason_code).replace("_", " ").capitalize(), RED))
		card.add_child(heading)
		card.add_child(_message(escalation.explanation, INK_SOFT))
		if not escalation.evidence.is_empty():
			card.add_child(_message("Evidence\n- %s" % "\n- ".join(PackedStringArray(escalation.evidence)), MUTED))
		var resolve := _action_button("Mark Resolved", false, true)
		resolve.pressed.connect(_resolve_escalation.bind(manager, escalation.uid))
		card.add_child(resolve)
		_mount_card(_workspace, card)
	if shown == 0:
		_workspace.add_child(_empty_card("No Open Escalations",
			"Guardrail blocks, missing capabilities, and expired approvals will appear here."))


func _assign_selected(manager: Node, rest: RestaurantState, manager_option: OptionButton,
		preset_option: OptionButton) -> void:
	if manager_option.selected < 0 or preset_option.selected < 0:
		return
	var employee_uid: int = int(manager_option.get_item_metadata(manager_option.selected))
	var template_uid: String = String(preset_option.get_item_metadata(preset_option.selected))
	var policy: BranchPolicy = manager.call("create_policy_from_template", template_uid,
		CompanyManager.player.id, rest.building_id, "") as BranchPolicy
	if policy == null:
		_status.text = "The policy copy could not be created."
		return
	_apply_result(manager.call("assign_manager", CompanyManager.player.id,
		rest.building_id, employee_uid, policy.uid) as CommandResult)


func _show_reassign(manager: Node, assignment: ManagerAssignment) -> void:
	var candidates := _manager_candidates()
	for member: StaffMember in candidates:
		if member.uid != assignment.manager_employee_uid:
			_apply_result(manager.call("reassign_manager", assignment.uid, member.uid, -1) as CommandResult)
			return
	_status.text = "Hire another manager employee before reassigning this branch."


func _toggle_assignment(assignment: ManagerAssignment) -> void:
	_apply_result(_management().call("set_assignment_active", assignment.uid, not assignment.active) as CommandResult)


func _copy_template(manager: Node, template: BranchPolicy) -> void:
	var rest := _selected_restaurant()
	if rest == null:
		return
	var copy := manager.call("create_policy_from_template", template.uid,
		CompanyManager.player.id, rest.building_id, "") as BranchPolicy
	if copy == null:
		_status.text = "The policy copy could not be created."
		return
	var assignment := manager.call("assignment_for_branch",
		CompanyManager.player.id, rest.building_id) as ManagerAssignment
	if assignment != null:
		_apply_result(manager.call("set_assignment_policy", assignment.uid, copy.uid) as CommandResult)
	else:
		_status.text = "%s copied. Assign a manager to activate it." % copy.display_name
		refresh()


func _approve(manager: Node, approval_uid: String) -> void:
	_apply_result(manager.call("approve", approval_uid, "player") as CommandResult)


func _reject(manager: Node, approval_uid: String) -> void:
	_apply_result(manager.call("reject", approval_uid, "player") as CommandResult)


func _edit_approval(manager: Node, approval: ManagerApproval) -> void:
	var edits := approval.command_arguments.duplicate(true)
	var changed := false
	for key: String in ["quantity", "delivery_cap", "daily_budget", "price"]:
		if edits.has(key) and edits[key] is float or edits.has(key) and edits[key] is int:
			edits[key] = maxf(1.0, float(edits[key]) * 0.9)
			changed = true
			break
	if not changed:
		_status.text = "This request has no safely editable numeric field."
		return
	_apply_result(manager.call("edit_approval", approval.uid, edits) as CommandResult)


func _undo_decision(manager: Node, decision_uid: String) -> void:
	_apply_result(manager.call("undo_decision", decision_uid) as CommandResult)


func _repeat_override(manager: Node, decision: ManagerDecisionRecord) -> void:
	var arguments := decision.selected_arguments.duplicate(true)
	_apply_result(manager.call("override_decision", decision.uid,
		decision.selected_command, arguments) as CommandResult)


func _resolve_escalation(manager: Node, escalation_uid: String) -> void:
	_apply_result(manager.call("resolve_escalation", escalation_uid,
		"Reviewed and resolved by the player.") as CommandResult)


func _apply_result(result: CommandResult) -> void:
	if result == null:
		_status.text = "That action is unavailable."
	elif result.ok:
		_status.text = result.explanation if not result.explanation.is_empty() else (
			result.message if not result.message.is_empty() else "Management updated.")
	else:
		_status.text = result.message
	_queue_refresh()


func _select_tab(tab_id: StringName) -> void:
	_active_tab = tab_id
	refresh()
	if is_instance_valid(_workspace_scroll):
		_workspace_scroll.scroll_vertical = 0


func _select_branch(next_building_id: int) -> void:
	_selected_branch_id = next_building_id
	refresh()


func _on_branch_picked(index: int) -> void:
	if index >= 0:
		_selected_branch_id = int(_branch_picker.get_item_metadata(index))
		refresh()


func _selected_restaurant() -> RestaurantState:
	return RestaurantManager.by_building.get(_selected_branch_id) as RestaurantState


func _management() -> Node:
	return get_node_or_null("/root/ManagementManager")


func _staff_service() -> Node:
	return get_node_or_null("/root/StaffManager")


func _staff_member(uid: int) -> StaffMember:
	var service := _staff_service()
	if service == null or CompanyManager.player == null:
		return null
	return service.call("staff_member", CompanyManager.player.id, uid) as StaffMember


func _manager_candidates() -> Array[StaffMember]:
	var result: Array[StaffMember] = []
	if CompanyManager.player == null:
		return result
	for rest: RestaurantState in CompanyManager.player.restaurants:
		for member: StaffMember in rest.staff:
			var definition := RestaurantManager.staff_type(member.type_id)
			if definition != null and definition.is_manager and member.employment_status == &"active":
				result.append(member)
	return result


func _manager_name(uid: int) -> String:
	if uid < 0:
		return "Founder"
	var member := _staff_member(uid)
	return member.staff_name if member != null else "Manager unavailable"


func _manager_skill(member: StaffMember) -> float:
	if member == null:
		return 0.0
	var judgment := member.competency(&"management")
	var planning := member.competency(&"planning")
	if judgment <= 0.0:
		judgment = member.attr("quality")
	if planning <= 0.0:
		planning = member.attr("service")
	return clampf((judgment * 0.55 + planning * 0.25 + member.condition_score() * 0.20), 0.0, 1.0)


func _condition_summary(member: StaffMember) -> String:
	return "condition %.0f%%" % (member.condition_score() * 100.0)


func _branch_name(branch_id: int) -> String:
	var rest := RestaurantManager.by_building.get(branch_id) as RestaurantState
	return rest.restaurant_name if rest != null else "Company overview"


func _preset_summary(policy: BranchPolicy) -> String:
	var top: Array[String] = []
	for key: Variant in policy.goal_weights:
		top.append("%s %.1f" % [String(key).capitalize(), float(policy.goal_weights[key])])
	return "Goals: %s" % ("Balanced" if top.is_empty() else ", ".join(top))


func _automatic_categories(policy: BranchPolicy) -> String:
	var values: Array[String] = []
	for key: Variant in policy.authority_by_category:
		if policy.authority_by_category[key] == BranchPolicy.AUTHORITY_AUTOMATIC:
			values.append(String(key).capitalize())
	return "None" if values.is_empty() else ", ".join(values)


func _command_label(command_id: StringName) -> String:
	return String(command_id).replace(".", " ").replace("_", " ").capitalize()


func _dictionary_sentence(values: Dictionary) -> String:
	if values.is_empty():
		return "No measured result yet."
	var parts: Array[String] = []
	for key: Variant in values:
		parts.append("%s %s" % [String(key).replace("_", " "), str(values[key])])
	return ", ".join(parts)


func _names(values: Array) -> String:
	var strings: Array[String] = []
	for value: Variant in values:
		strings.append(String(value).replace("_", " ").capitalize())
	return ", ".join(strings)


func _window() -> int:
	return int(GameClock.total_minutes() / 60)


func _section_heading(title_text: String, explanation: String) -> Control:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	stack.add_child(_label(title_text, 21, INK))
	stack.add_child(_message(explanation, MUTED))
	return stack


func _card(accent: Color = Color.TRANSPARENT) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",
		BellaUi.tile_box(accent if accent.a > 0.0 else BellaUi.PAPER_EDGE, 3 if accent.a > 0.0 else 2))
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.set_meta("card_panel", panel)
	return stack


func _mount_card(parent: Container, stack: VBoxContainer) -> void:
	var panel := stack.get_meta("card_panel") as PanelContainer
	if panel != null:
		parent.add_child(panel)


func _empty_card(title_text: String, explanation: String) -> PanelContainer:
	var stack := _card()
	stack.add_child(_label(title_text, 20, INK))
	stack.add_child(_message(explanation, MUTED))
	return stack.get_meta("card_panel") as PanelContainer


func _field(label_text: String, control: Control) -> Control:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	stack.add_child(_label(label_text, 13, MUTED))
	stack.add_child(control)
	return stack


func _metric_line(label_text: String, value_text: String, detail: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 1)
	stack.add_child(_label(label_text, 14, MUTED))
	stack.add_child(_message(detail, INK_SOFT))
	row.add_child(stack)
	var value := _label(value_text, 17, INK)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size.x = 120
	row.add_child(value)
	return row


func _pill(text_value: String, color: Color) -> PanelContainer:
	return BellaUi.pill(text_value, INK, color.lightened(0.45), color.darkened(0.18))


func _action_button(text_value: String, danger: bool = false, primary: bool = false) -> Button:
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


func _render_unavailable(explanation: String) -> void:
	if _workspace != null:
		_clear(_workspace)
		_workspace.add_child(_empty_card("Managers Unavailable", explanation))


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
