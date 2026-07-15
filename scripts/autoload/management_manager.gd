extends Node
## Policy-driven branch management built on public reports and the command router.

signal assignments_changed
signal policies_changed
signal approvals_changed
signal decision_recorded(record: ManagerDecisionRecord)
signal escalation_created(escalation: ManagerEscalation)
signal performance_changed

const POLICY_DIR: String = "res://data/management/policies"
const HISTORY_LIMIT: int = 240
const APPROVAL_LIFETIME_HOURS: int = 24

var assignments: Array[ManagerAssignment] = []
var policies: Array[BranchPolicy] = []
var policy_templates: Array[BranchPolicy] = []
var approvals: Array[ManagerApproval] = []
var decisions: Array[ManagerDecisionRecord] = []
var escalations: Array[ManagerEscalation] = []
var observations: Array[BranchObservationSnapshot] = []
var automation_rules: Dictionary = {}
var performance_cache: Dictionary = {}
var processed_windows: Dictionary = {}
var _urgent_window_by_branch: Dictionary = {}
var _router: Variant = null
var _staff: Variant = null
var _next_uid: int = 1
var _initialized: bool = false


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	if not is_instance_valid(GameClock) or not is_instance_valid(RestaurantManager):
		push_error("ManagementManager requires GameClock and RestaurantManager.")
		return
	_router = get_node_or_null("/root/BranchCommandRouter")
	_staff = get_node_or_null("/root/StaffManager")
	if _router == null or _staff == null:
		push_error("ManagementManager requires BranchCommandRouter and StaffManager.")
		return
	_load_or_seed_policy_templates()
	_seed_automation_rules()
	var save: SaveGame = CompanyManager.loaded_save
	if save != null:
		restore_from_save(save)
	GameClock.hour_changed.connect(_on_hour_changed)
	GameClock.day_changed.connect(_on_day_changed)
	RestaurantManager.restaurant_updated.connect(_on_restaurant_updated)
	_staff.resignation_warning.connect(_on_resignation_warning)
	_router.command_executed.connect(_on_command_executed)
	CapabilityRegistry.capabilities_changed.connect(_on_capabilities_changed)
	reconcile_capacity()
	_ensure_founder_assistance()


func assignment_for_branch(company_id: StringName, building_id: int) -> ManagerAssignment:
	for assignment: ManagerAssignment in assignments:
		if assignment.company_id == company_id and assignment.branch_building_id == building_id:
			return assignment
	return null


func assign_manager(company_id: StringName, building_id: int, manager_employee_uid: int,
		policy_uid: String) -> CommandResult:
	var company: CompanyState = CompanyManager.company(company_id)
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	var member: StaffMember = _staff.staff_member(company_id, manager_employee_uid)
	var definition: StaffTypeDef = RestaurantManager.staff_type(member.type_id) if member != null else null
	if company == null or rest == null or rest.company_id != company_id:
		return CommandResult.fail(&"not_owner", "That branch is not owned by the company.")
	if member == null or definition == null or not definition.is_manager:
		return CommandResult.fail(&"not_manager", "Choose an employee in the manager role.")
	var policy: BranchPolicy = policy_by_uid(policy_uid)
	if policy == null:
		return CommandResult.fail(&"unknown_policy", "Choose a valid branch policy.")
	var existing: ManagerAssignment = assignment_for_branch(company_id, building_id)
	if existing == null:
		existing = ManagerAssignment.new()
		existing.uid = _uid("assignment")
		existing.company_id = company_id
		existing.branch_building_id = building_id
		existing.assigned_day = GameClock.day
		assignments.append(existing)
	existing.manager_employee_uid = manager_employee_uid
	existing.policy_uid = policy_uid
	existing.founder_assistance = false
	existing.active = true
	existing.paused_reason = ""
	reconcile_capacity()
	assignments_changed.emit()
	return CommandResult.good(existing)


func reassign_manager(assignment_uid: String, manager_employee_uid: int,
		new_building_id: int = -1) -> CommandResult:
	var assignment: ManagerAssignment = assignment_by_uid(assignment_uid)
	if assignment == null:
		return CommandResult.fail(&"unknown_assignment", "That assignment does not exist.")
	var target_building: int = new_building_id if new_building_id >= 0 else assignment.branch_building_id
	var result: CommandResult = assign_manager(
		assignment.company_id, target_building, manager_employee_uid, assignment.policy_uid)
	if result.ok and target_building != assignment.branch_building_id:
		assignments.erase(assignment)
		assignments_changed.emit()
	return result


func set_assignment_active(assignment_uid: String, active: bool) -> CommandResult:
	var assignment: ManagerAssignment = assignment_by_uid(assignment_uid)
	if assignment == null:
		return CommandResult.fail(&"unknown_assignment", "That assignment does not exist.")
	assignment.active = active
	assignment.paused_reason = "" if active else "Paused by player"
	assignments_changed.emit()
	return CommandResult.good(assignment)


func set_assignment_policy(assignment_uid: String, policy_uid: String) -> CommandResult:
	var assignment: ManagerAssignment = assignment_by_uid(assignment_uid)
	var policy: BranchPolicy = policy_by_uid(policy_uid)
	if assignment == null:
		return CommandResult.fail(&"unknown_assignment", "That assignment does not exist.")
	if policy == null:
		return CommandResult.fail(&"unknown_policy", "That policy does not exist.")
	if policy.branch_building_id >= 0 and policy.branch_building_id != assignment.branch_building_id:
		return CommandResult.fail(&"wrong_branch", "That policy belongs to another branch.")
	assignment.policy_uid = policy_uid
	assignments_changed.emit()
	return CommandResult.good(assignment)


func assignment_by_uid(assignment_uid: String) -> ManagerAssignment:
	for assignment: ManagerAssignment in assignments:
		if assignment.uid == assignment_uid:
			return assignment
	return null


func policy_by_uid(policy_uid: String) -> BranchPolicy:
	for policy: BranchPolicy in policies:
		if policy.uid == policy_uid:
			return policy
	for template: BranchPolicy in policy_templates:
		if template.uid == policy_uid:
			return template
	return null


func create_policy_from_template(template_uid: String, company_id: StringName,
		building_id: int, display_name: String = "") -> BranchPolicy:
	var template: BranchPolicy = policy_by_uid(template_uid)
	if template == null:
		return null
	var copy: BranchPolicy = template.copy_for_branch(_uid("policy"), building_id, GameClock.day)
	copy.company_id = company_id
	if not display_name.is_empty():
		copy.display_name = display_name
	policies.append(copy)
	policies_changed.emit()
	return copy


func update_policy_override(policy_uid: String, field: StringName, value: Variant) -> CommandResult:
	var policy: BranchPolicy = policy_by_uid(policy_uid)
	if policy == null or policy_templates.has(policy):
		return CommandResult.fail(&"unknown_policy", "Only branch policy copies can be changed.")
	policy.local_overrides[field] = value
	policy.set(field, value)
	policy.template_version += 1
	policy.last_modified_day = GameClock.day
	policies_changed.emit()
	return CommandResult.good(policy)


func set_policy_authority(policy_uid: String, category: StringName,
		authority: StringName) -> CommandResult:
	if authority not in [
		BranchPolicy.AUTHORITY_RECOMMEND,
		BranchPolicy.AUTHORITY_APPROVAL,
		BranchPolicy.AUTHORITY_AUTOMATIC,
	]:
		return CommandResult.fail(&"bad_authority", "Choose Recommend, Approval, or Automatic.")
	var policy: BranchPolicy = policy_by_uid(policy_uid)
	if policy == null:
		return CommandResult.fail(&"unknown_policy", "That policy does not exist.")
	policy.authority_by_category[category] = authority
	policy.local_overrides["authority:%s" % category] = authority
	policy.last_modified_day = GameClock.day
	policies_changed.emit()
	return CommandResult.good(policy)


func approve(approval_uid: String, actor_id: String = "player") -> CommandResult:
	var approval := approval_by_uid(approval_uid)
	if approval == null or approval.status != &"pending":
		return CommandResult.fail(&"approval_unavailable", "That approval is no longer pending.")
	if _window() > approval.deadline_window:
		approval.mark_resolved(&"expired", actor_id, _window())
		_escalate_from_approval(approval, &"expired", "Approval expired before a decision was made.")
		approvals_changed.emit()
		return CommandResult.fail(&"approval_expired", "That approval has expired.")
	var assignment: ManagerAssignment = assignment_by_uid(approval.assignment_uid)
	var policy: BranchPolicy = policy_by_uid(assignment.policy_uid) if assignment != null else null
	var context := {
		"kind": &"manager",
		"id": actor_id,
		"company_id": approval.company_id,
		"policy": policy,
		"approved": true,
	}
	var command_arguments := approval.edited_arguments if not approval.edited_arguments.is_empty() 		else approval.command_arguments
	var result: CommandResult = _router.execute(
		approval.command_id, command_arguments, context, approval.idempotency_key)
	approval.mark_resolved(&"approved" if result.ok else &"blocked", actor_id, _window())
	if not result.ok:
		_escalate_from_approval(approval, result.code, result.explanation)
	_update_decision_from_result(approval.idempotency_key, result)
	approvals_changed.emit()
	return result


func reject(approval_uid: String, actor_id: String = "player") -> CommandResult:
	var approval := approval_by_uid(approval_uid)
	if approval == null or approval.status != &"pending":
		return CommandResult.fail(&"approval_unavailable", "That approval is no longer pending.")
	approval.mark_resolved(&"rejected", actor_id, _window())
	_update_decision_status(approval.idempotency_key, &"rejected")
	approvals_changed.emit()
	return CommandResult.good(approval)


func edit_approval(approval_uid: String, edits: Dictionary) -> CommandResult:
	var approval := approval_by_uid(approval_uid)
	if approval == null or approval.status != &"pending":
		return CommandResult.fail(&"approval_unavailable", "That approval is no longer pending.")
	var assignment: ManagerAssignment = assignment_by_uid(approval.assignment_uid)
	var policy: BranchPolicy = policy_by_uid(assignment.policy_uid) if assignment != null else null
	var arguments := approval.command_arguments.duplicate(true)
	arguments.merge(edits, true)
	var preview: CommandResult = _router.preview(approval.command_id, arguments, {
		"kind": &"planner",
		"company_id": approval.company_id,
		"policy": policy,
	})
	if not preview.ok:
		return preview
	approval.edited_arguments = arguments
	approval.exact_cost = preview.estimated_cost
	approval.expected_impact = preview.explanation
	approvals_changed.emit()
	return CommandResult.good(approval)


func approval_by_uid(approval_uid: String) -> ManagerApproval:
	for approval: ManagerApproval in approvals:
		if approval.uid == approval_uid:
			return approval
	return null


func pending_approvals(company_id: StringName = &"player") -> Array[ManagerApproval]:
	var result: Array[ManagerApproval] = []
	for approval: ManagerApproval in approvals:
		if approval.company_id == company_id and approval.status == &"pending":
			result.append(approval)
	return result


func override_decision(decision_uid: String, command_id: StringName,
		arguments: Dictionary) -> CommandResult:
	var decision: ManagerDecisionRecord = decision_by_uid(decision_uid)
	if decision == null:
		return CommandResult.fail(&"unknown_decision", "That decision does not exist.")
	var result: CommandResult = _router.execute(command_id, arguments, {
		"kind": &"player",
		"id": "override",
		"company_id": decision.company_id,
	}, "override:%s:%d" % [decision_uid, _window()])
	if result.ok:
		decision.overridden = true
		decision.override_command_uid = result.idempotency_key
		decision_recorded.emit(decision)
	return result


func undo_decision(decision_uid: String) -> CommandResult:
	var decision: ManagerDecisionRecord = decision_by_uid(decision_uid)
	if decision == null or not decision.can_undo(_window()) or not _router.can_undo(decision.undo_token):
		return CommandResult.fail(&"undo_unavailable", "That decision can no longer be safely undone.")
	var result: CommandResult = _router.undo(decision.undo_token, {
		"kind": &"player",
		"id": "decision_history",
		"company_id": decision.company_id,
	})
	if result.ok:
		decision.evaluation_status = &"undone"
		decision_recorded.emit(decision)
	return result


func decision_by_uid(decision_uid: String) -> ManagerDecisionRecord:
	for decision: ManagerDecisionRecord in decisions:
		if decision.uid == decision_uid:
			return decision
	return null


func performance_for_assignment(assignment_uid: String) -> Dictionary:
	if performance_cache.has(assignment_uid):
		return performance_cache[assignment_uid].duplicate(true)
	var evaluated := 0
	var successful := 0
	var estimated_cost := 0.0
	var actual_cost := 0.0
	var overrides := 0
	for decision: ManagerDecisionRecord in decisions:
		if decision.assignment_uid != assignment_uid:
			continue
		if decision.evaluation_status == &"evaluated":
			evaluated += 1
			successful += int(bool(decision.actual_result.get("goal_improved", false)))
		estimated_cost += decision.estimated_cost
		actual_cost += decision.actual_cost
		overrides += int(decision.overridden)
	var report := {
		"evaluated_decisions": evaluated,
		"successful_decisions": successful,
		"success_rate": float(successful) / float(maxi(1, evaluated)),
		"estimated_cost": estimated_cost,
		"actual_cost": actual_cost,
		"overrides": overrides,
		"note": "Performance compares decisions with later branch reports; managers receive no output bonus.",
	}
	performance_cache[assignment_uid] = report
	return report.duplicate(true)


func open_escalations(company_id: StringName = &"player") -> Array[ManagerEscalation]:
	var result: Array[ManagerEscalation] = []
	for escalation: ManagerEscalation in escalations:
		if escalation.company_id == company_id and escalation.status == &"open":
			result.append(escalation)
	return result


func resolve_escalation(escalation_uid: String, note: String) -> CommandResult:
	for escalation: ManagerEscalation in escalations:
		if escalation.uid == escalation_uid:
			escalation.resolve(note, _window())
			return CommandResult.good(escalation)
	return CommandResult.fail(&"unknown_escalation", "That escalation does not exist.")


func reconcile_capacity() -> void:
	for company: CompanyState in CompanyManager.companies:
		var capacity := CapabilityRegistry.capacity(company.id, &"management.branch_managers")
		var company_assignments: Array[ManagerAssignment] = []
		for assignment: ManagerAssignment in assignments:
			if assignment.company_id == company.id and not assignment.founder_assistance:
				company_assignments.append(assignment)
		company_assignments.sort_custom(func(first: ManagerAssignment, second: ManagerAssignment) -> bool:
			return first.assigned_day < second.assigned_day)
		for index: int in company_assignments.size():
			var assignment: ManagerAssignment = company_assignments[index]
			if index < capacity:
				if assignment.paused_reason == "Headquarters manager capacity unavailable":
					assignment.paused_reason = ""
					assignment.active = true
			else:
				assignment.active = false
				assignment.paused_reason = "Headquarters manager capacity unavailable"
	assignments_changed.emit()


func _on_capabilities_changed(_company_id: StringName) -> void:
	reconcile_capacity()


func write_save(save: SaveGame) -> void:
	save.set("management_schema_version", 1)
	save.set("manager_assignments", assignments.duplicate())
	save.set("branch_policies", policies.duplicate())
	save.set("manager_policy_templates", policy_templates.duplicate())
	save.set("manager_approvals", approvals.duplicate())
	save.set("manager_decisions", decisions.duplicate())
	save.set("manager_escalations", escalations.duplicate())
	save.set("manager_observations", observations.duplicate())
	save.set("manager_processed_windows", processed_windows.duplicate(true))
	save.set("manager_next_uid", _next_uid)


func restore_from_save(save: SaveGame) -> void:
	_assign_resource_array(save.get("manager_assignments"), assignments)
	_assign_resource_array(save.get("branch_policies"), policies)
	var saved_templates: Variant = save.get("manager_policy_templates")
	if saved_templates is Array and not saved_templates.is_empty():
		policy_templates.assign(saved_templates)
	_assign_resource_array(save.get("manager_approvals"), approvals)
	_assign_resource_array(save.get("manager_decisions"), decisions)
	_assign_resource_array(save.get("manager_escalations"), escalations)
	_assign_resource_array(save.get("manager_observations"), observations)
	var saved_windows: Variant = save.get("manager_processed_windows")
	if saved_windows is Dictionary:
		processed_windows = saved_windows.duplicate(true)
	_next_uid = maxi(_next_uid, int(save.get("manager_next_uid")))


func _on_hour_changed(day: int, hour: int) -> void:
	var current_window := day * 24 + hour
	_expire_approvals(current_window)
	_evaluate_due_decisions(current_window)
	reconcile_capacity()
	for assignment: ManagerAssignment in assignments:
		_run_assignment_window(assignment, current_window, &"hourly")


func _on_day_changed(day: int) -> void:
	var current_window := day * 24
	_evaluate_due_decisions(current_window)
	performance_cache.clear()
	for assignment: ManagerAssignment in assignments:
		_run_assignment_window(assignment, current_window, &"day_boundary")
	performance_changed.emit()


func _on_restaurant_updated(building_id: int) -> void:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null:
		return
	var assignment: ManagerAssignment = assignment_for_branch(rest.company_id, building_id)
	if assignment == null:
		return
	var report: Dictionary = RestaurantManager.operations_snapshot(building_id)
	var urgent := int(report.get("oldest_queue_wait", 0)) >= 18 		or int(report.get("oldest_kitchen_wait", 0)) >= 18 		or (int(report.get("ready_deliveries", 0)) > 0 and int(report.get("idle_drivers", 0)) == 0)
	if not urgent:
		return
	var current_window := _window()
	if int(_urgent_window_by_branch.get(building_id, -1)) == current_window:
		return
	_urgent_window_by_branch[building_id] = current_window
	_run_assignment_window(assignment, current_window, &"urgent")


func _run_assignment_window(assignment: ManagerAssignment, current_window: int,
		reason: StringName) -> void:
	if assignment.is_paused():
		return
	var rest: RestaurantState = RestaurantManager.by_building.get(assignment.branch_building_id)
	var policy: BranchPolicy = policy_by_uid(assignment.policy_uid)
	if rest == null or policy == null:
		return
	var window_key: String = "%s:%d:%s" % [assignment.uid, current_window, reason]
	if processed_windows.has(window_key):
		return
	processed_windows[window_key] = true
	var skill: float = _manager_skill(assignment)
	var delay: int = int(round(lerpf(3.0, 0.0, skill)))
	if reason == &"hourly" and posmod(current_window + assignment.manager_employee_uid, maxi(1, delay + 1)) != 0:
		return
	var observation: BranchObservationSnapshot = _build_observation(assignment, policy, rest, current_window)
	var alternatives: Array[Dictionary] = _candidate_actions(assignment, policy, observation, rest, current_window)
	if alternatives.is_empty():
		return
	var selected: Dictionary = _select_action(alternatives, assignment, policy, skill, current_window)
	var command_id: StringName = StringName(selected.get("command_id", &""))
	var arguments: Dictionary = selected.get("arguments", {})
	var spec: Dictionary = _router.describe(command_id)
	var category: StringName = StringName(spec.get("category", &""))
	if current_window < assignment.cooldown_until(category):
		return
	var rule: AutomationRule = automation_rules.get(category)
	if rule != null:
		var previous_severity: float = float(assignment.local_overrides.get("severity:%s" % category, 0.0))
		var severity: float = float(selected.get("severity", 0.0))
		if not rule.should_consider(severity, previous_severity):
			return
		assignment.local_overrides["severity:%s" % category] = severity
	var preview: CommandResult = _router.preview(command_id, arguments, {
		"kind": &"planner",
		"id": "manager:%d" % assignment.manager_employee_uid,
		"company_id": assignment.company_id,
		"policy": policy,
	})
	if not preview.ok:
		_create_escalation(assignment, command_id, arguments, preview.code, preview.explanation,
			selected.get("evidence", []), current_window)
		return
	var authority: StringName = policy.authority_for(category)
	var key: String = "manager:%s:%d:%s" % [assignment.uid, current_window, command_id]
	var decision: ManagerDecisionRecord = _new_decision(
		assignment, observation, alternatives, selected, preview, authority, key, current_window)
	decisions.append(decision)
	_trim(decisions)
	decision_recorded.emit(decision)
	if authority == BranchPolicy.AUTHORITY_RECOMMEND:
		decision.evaluation_status = &"recommended"
	elif authority == BranchPolicy.AUTHORITY_APPROVAL:
		_create_approval(assignment, selected, preview, decision, current_window)
	else:
		var result: CommandResult = _router.execute(command_id, arguments, {
			"kind": &"manager",
			"id": "manager:%d" % assignment.manager_employee_uid,
			"company_id": assignment.company_id,
			"policy": policy,
		}, key)
		_apply_result_to_decision(decision, result)
		if not result.ok:
			_create_escalation(assignment, command_id, arguments, result.code, result.explanation,
				selected.get("evidence", []), current_window)
	var cooldown: int = int(spec.get("cooldown_hours", 1))
	assignment.set_cooldown(category, current_window + maxi(1, cooldown))
	assignment.last_decision_window = current_window


func _build_observation(assignment: ManagerAssignment, policy: BranchPolicy,
		rest: RestaurantState, current_window: int) -> BranchObservationSnapshot:
	var observation: BranchObservationSnapshot = BranchObservationSnapshot.new()
	observation.uid = _uid("observation")
	observation.company_id = assignment.company_id
	observation.branch_building_id = rest.building_id
	observation.report_window = current_window
	observation.report_day = GameClock.day
	observation.report_hour = int(GameClock.game_hours)
	observation.operations_report = RestaurantManager.operations_snapshot(rest.building_id)
	observation.forecast_report = {
		"warnings": SupplyManager.forecast_warnings(rest),
		"stockout_risks": SupplyManager.stockout_risks(rest),
	}
	observation.daily_results = {
		"today": rest.today.duplicate(true),
		"sales_history": rest.sales_history.duplicate(),
		"expense_history": rest.expense_history.duplicate(),
	}
	observation.policy_summary = {
		"preset": policy.preset_id,
		"goal_weights": policy.goal_weights.duplicate(true),
		"cash_reserve": policy.cash_reserve,
		"authority": policy.authority_by_category.duplicate(true),
	}
	observation.report_sources = [&"operations_report", &"supply_forecast", &"daily_results", &"branch_policy"]
	observations.append(observation)
	_trim(observations)
	return observation


func _candidate_actions(_assignment: ManagerAssignment, policy: BranchPolicy,
		observation: BranchObservationSnapshot, rest: RestaurantState,
		current_window: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var operations: Dictionary = observation.operations_report
	var stockout_risks: Array = observation.forecast_report.get("stockout_risks", [])
	if not stockout_risks.is_empty():
		var ingredient_id: StringName = StringName(stockout_risks[0])
		candidates.append(_candidate_action(
			&"inventory.reorder",
			{"building_id": rest.building_id, "ingredient_id": ingredient_id, "quantity": 20.0},
			0.9,
			["The supply forecast shows %s at risk." % String(ingredient_id).replace("_", " ")],
			"Restore several days of ingredient cover."))
	if int(operations.get("cooks_on_shift", 0)) <= 0:
		_add_hiring_candidate(candidates, policy.company_id, rest.building_id, &"cook", 1.0,
			"No cook is currently on shift.")
	if int(operations.get("waiters_on_shift", 0)) <= 0:
		_add_hiring_candidate(candidates, policy.company_id, rest.building_id, &"waiter", 0.95,
			"No waiter is currently on shift.")
	if rest.delivery_enabled and int(operations.get("active_deliveries", 0)) >= rest.delivery_cap:
		candidates.append(_candidate_action(
			&"delivery.set_cap",
			{"building_id": rest.building_id, "cap": mini(99, rest.delivery_cap + 2)},
			0.7,
			["The branch is at its current delivery cap."],
			"Allow two more simultaneous deliveries."))
	if int(operations.get("oldest_queue_wait", 0)) >= 18 or int(operations.get("oldest_kitchen_wait", 0)) >= 18:
		candidates.append(_candidate_action(
			&"operations.emergency_close",
			{"building_id": rest.building_id},
			0.58,
			["A reported wait has exceeded 18 minutes."],
			"Pause new service while the branch clears its backlog."))
	var at_risk: StaffMember = _highest_resignation_risk(rest)
	if at_risk != null and at_risk.resignation_risk >= 0.4:
		var raised_wage: float = snappedf(at_risk.hourly_wage * 1.08, 0.05)
		candidates.append(_candidate_action(
			&"staff.set_contract",
			{
				"building_id": rest.building_id,
				"staff_uid": at_risk.uid,
				"contract_type": at_risk.contract_type,
				"hourly_wage": raised_wage,
				"overtime_allowed": at_risk.overtime_allowed,
				"maximum_overtime_hours": at_risk.maximum_overtime_hours,
			},
			clampf(at_risk.resignation_risk, 0.0, 0.9),
			["%s is at risk of resigning (%d%%)." % [at_risk.staff_name, int(round(at_risk.resignation_risk * 100.0))]],
			"Raise pay to retain a valued employee."))
	var training_hint: Dictionary = _staff.suggest_training(policy.company_id, rest.building_id)
	if not training_hint.is_empty():
		candidates.append(_candidate_action(
			&"staff.train",
			{
				"building_id": rest.building_id,
				"staff_uid": int(training_hint.get("staff_uid", -1)),
				"program_id": StringName(training_hint.get("program_id", &"")),
			},
			0.32,
			[String(training_hint.get("evidence", ""))],
			String(training_hint.get("expected", "Develop an employee's skills."))))
	if candidates.is_empty() and current_window % 24 == 0:
		candidates.append(_candidate_action(
			&"delivery.set_cap",
			{"building_id": rest.building_id, "cap": rest.delivery_cap},
			0.05,
			["The daily review found no urgent policy breach."],
			"Keep the current delivery capacity."))
	return candidates


func _add_hiring_candidate(candidates: Array[Dictionary], company_id: StringName,
		building_id: int, role_id: StringName, severity: float, evidence: String) -> void:
	var market: Array[JobCandidate] = _staff.candidates(company_id, {"role_id": role_id})
	if market.is_empty():
		return
	var candidate: JobCandidate = market[0]
	candidates.append(_candidate_action(
		&"staff.hire",
		{
			"building_id": building_id,
			"candidate_uid": candidate.uid,
			"offer": {
				"hourly_wage": candidate.hourly_wage,
				"shift_start": 10.0,
				"shift_hours": 8.0,
				"contract_type": &"permanent",
			},
		},
		severity,
		[evidence, "%s is available at $%.2f per hour." % [candidate.candidate_name, candidate.hourly_wage]],
		"Add reliable shift coverage."))


func _candidate_action(command_id: StringName, arguments: Dictionary, severity: float,
		evidence: Array[String], expected: String) -> Dictionary:
	return {
		"command_id": command_id,
		"arguments": arguments,
		"severity": severity,
		"base_score": severity,
		"evidence": evidence,
		"expected": expected,
	}


func _highest_resignation_risk(rest: RestaurantState) -> StaffMember:
	var worst: StaffMember = null
	for member: StaffMember in rest.staff:
		if member.resignation_committed_day >= 0:
			continue
		if worst == null or member.resignation_risk > worst.resignation_risk:
			worst = member
	return worst


func _select_action(alternatives: Array[Dictionary], assignment: ManagerAssignment,
		policy: BranchPolicy, skill: float, current_window: int) -> Dictionary:
	var scored: Array[Dictionary] = alternatives.duplicate(true)
	for alternative: Dictionary in scored:
		var command_id: StringName = StringName(alternative.get("command_id", &""))
		var category: StringName = StringName(_router.describe(command_id).get("category", &""))
		var goal_weight: float = float(policy.goal_weights.get(category, 1.0))
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = hash("%s:%d:%s" % [assignment.uid, current_window, command_id])
		var noise: float = rng.randf_range(-1.0, 1.0) * (1.0 - skill) * 0.3
		alternative["score"] = float(alternative.get("base_score", 0.0)) * goal_weight + noise
	scored.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return float(first.get("score", 0.0)) > float(second.get("score", 0.0)))
	var best_score: float = float(scored[0].get("score", 0.0))
	var near_best: Array[Dictionary] = []
	var tolerance: float = lerpf(0.25, 0.04, skill)
	for alternative: Dictionary in scored:
		if best_score - float(alternative.get("score", 0.0)) <= tolerance:
			near_best.append(alternative)
	var selection_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	selection_rng.seed = hash("%s:%d:selection" % [assignment.uid, current_window])
	var index: int = int(floor(selection_rng.randf() * near_best.size() * (1.0 - skill)))
	return near_best[clampi(index, 0, near_best.size() - 1)]


func _manager_skill(assignment: ManagerAssignment) -> float:
	if assignment.founder_assistance:
		return 0.35
	var member: StaffMember = _staff.staff_member(assignment.company_id, assignment.manager_employee_uid)
	if member == null:
		assignment.active = false
		assignment.paused_reason = "Manager employee is unavailable"
		return 0.0
	var decision_skill := (member.competency(&"judgment") + member.competency(&"forecasting")) * 0.5
	return clampf(decision_skill * (0.85 + member.condition_score() * 0.15), 0.0, 1.0)


func _new_decision(assignment: ManagerAssignment, observation: BranchObservationSnapshot,
		alternatives: Array[Dictionary], selected: Dictionary, preview: CommandResult,
		authority: StringName, idempotency_key: String, current_window: int) -> ManagerDecisionRecord:
	var record: ManagerDecisionRecord = ManagerDecisionRecord.new()
	record.uid = _uid("decision")
	record.assignment_uid = assignment.uid
	record.company_id = assignment.company_id
	record.branch_building_id = assignment.branch_building_id
	record.manager_employee_uid = assignment.manager_employee_uid
	record.decision_window = current_window
	record.category = StringName(preview.metadata.get("category", &""))
	record.observation_uid = observation.uid
	record.alternatives = alternatives.duplicate(true)
	record.selected_command = StringName(selected.get("command_id", &""))
	record.selected_arguments = selected.get("arguments", {}).duplicate(true)
	record.expected_result = {"summary": selected.get("expected", "")}
	record.explanation = "%s %s" % [
		" ".join(PackedStringArray(selected.get("evidence", []))),
		preview.explanation,
	]
	record.estimated_cost = preview.estimated_cost
	record.permission_category = authority
	record.idempotency_key = idempotency_key
	var rule: AutomationRule = automation_rules.get(record.category)
	record.evaluation_due_window = current_window + (
		rule.evaluation_horizon_hours if rule != null else 24)
	return record


func _create_approval(assignment: ManagerAssignment, selected: Dictionary,
		preview: CommandResult, decision: ManagerDecisionRecord, current_window: int) -> void:
	var approval: ManagerApproval = ManagerApproval.new()
	approval.uid = _uid("approval")
	approval.assignment_uid = assignment.uid
	approval.company_id = assignment.company_id
	approval.branch_building_id = assignment.branch_building_id
	approval.category = decision.category
	approval.command_id = decision.selected_command
	approval.command_arguments = decision.selected_arguments.duplicate(true)
	approval.evidence.assign(selected.get("evidence", []))
	approval.expected_impact = str(selected.get("expected", ""))
	approval.exact_cost = preview.estimated_cost
	approval.created_window = current_window
	approval.deadline_window = current_window + APPROVAL_LIFETIME_HOURS
	approval.idempotency_key = decision.idempotency_key
	approval.explanation = decision.explanation
	approvals.append(approval)
	approvals_changed.emit()


func _apply_result_to_decision(decision: ManagerDecisionRecord, result: CommandResult) -> void:
	decision.command_result_code = result.code
	decision.actual_cost = result.actual_cost
	decision.reversible = result.reversible
	decision.undo_token = result.undo_token
	decision.evaluation_status = &"pending" if result.ok else &"blocked"


func _update_decision_from_result(idempotency_key: String, result: CommandResult) -> void:
	for decision: ManagerDecisionRecord in decisions:
		if decision.idempotency_key == idempotency_key:
			_apply_result_to_decision(decision, result)
			decision_recorded.emit(decision)
			return


func _update_decision_status(idempotency_key: String, status: StringName) -> void:
	for decision: ManagerDecisionRecord in decisions:
		if decision.idempotency_key == idempotency_key:
			decision.evaluation_status = status
			decision_recorded.emit(decision)
			return


func _evaluate_due_decisions(current_window: int) -> void:
	for decision: ManagerDecisionRecord in decisions:
		if decision.evaluation_status != &"pending" or current_window < decision.evaluation_due_window:
			continue
		var rest: RestaurantState = RestaurantManager.by_building.get(decision.branch_building_id)
		if rest == null:
			decision.evaluation_status = &"blocked"
			continue
		var report: Dictionary = RestaurantManager.operations_snapshot(rest.building_id)
		var goal_improved := true
		match decision.selected_command:
			&"staff.set_contract", &"staff.train":
				goal_improved = true
			&"inventory.reorder":
				goal_improved = SupplyManager.stockout_risks(rest).is_empty()
			&"staff.hire":
				goal_improved = int(report.get("cooks_on_shift", 0)) > 0 					and int(report.get("waiters_on_shift", 0)) > 0
			&"delivery.set_cap":
				goal_improved = int(report.get("active_deliveries", 0)) < int(report.get("delivery_cap", 0))
			&"operations.emergency_close":
				goal_improved = int(report.get("oldest_queue_wait", 0)) < 18 					and int(report.get("oldest_kitchen_wait", 0)) < 18
		decision.record_evaluation({
			"goal_improved": goal_improved,
			"report_window": current_window,
			"report_summary": {
				"oldest_queue_wait": report.get("oldest_queue_wait", 0),
				"oldest_kitchen_wait": report.get("oldest_kitchen_wait", 0),
				"delivery_cap": report.get("delivery_cap", 0),
			},
		})
		performance_cache.erase(decision.assignment_uid)
		decision_recorded.emit(decision)
	performance_changed.emit()


func _expire_approvals(current_window: int) -> void:
	for approval: ManagerApproval in approvals:
		if approval.status == &"pending" and current_window > approval.deadline_window:
			approval.mark_resolved(&"expired", "system", current_window)
			_escalate_from_approval(approval, &"expired", "Approval expired before a decision was made.")
			_update_decision_status(approval.idempotency_key, &"expired")
	approvals_changed.emit()


func _create_escalation(assignment: ManagerAssignment, command_id: StringName,
		arguments: Dictionary, reason_code: StringName, explanation: String,
		evidence: Array, current_window: int) -> void:
	var escalation: ManagerEscalation = ManagerEscalation.new()
	escalation.uid = _uid("escalation")
	escalation.assignment_uid = assignment.uid
	escalation.company_id = assignment.company_id
	escalation.branch_building_id = assignment.branch_building_id
	escalation.category = StringName(_router.describe(command_id).get("category", &""))
	escalation.command_id = command_id
	escalation.command_arguments = arguments.duplicate(true)
	escalation.reason_code = reason_code
	escalation.explanation = explanation
	escalation.evidence.assign(evidence)
	escalation.created_window = current_window
	escalations.append(escalation)
	_trim(escalations)
	escalation_created.emit(escalation)


func _escalate_from_approval(approval: ManagerApproval, reason_code: StringName,
		explanation: String) -> void:
	var assignment: ManagerAssignment = assignment_by_uid(approval.assignment_uid)
	if assignment == null:
		return
	_create_escalation(
		assignment,
		approval.command_id,
		approval.command_arguments,
		reason_code,
		explanation,
		approval.evidence,
		_window())
	escalations[-1].related_approval_uid = approval.uid


func _ensure_founder_assistance() -> void:
	var player: CompanyState = CompanyManager.player
	if player == null or player.restaurants.is_empty():
		return
	for assignment: ManagerAssignment in assignments:
		if assignment.company_id == player.id and assignment.founder_assistance:
			return
	var policy: BranchPolicy = create_policy_from_template("preset:conservative", player.id,
		player.restaurants[0].building_id, "Founder Assistance")
	if policy == null:
		return
	for category: Variant in policy.authority_by_category:
		policy.authority_by_category[category] = BranchPolicy.AUTHORITY_RECOMMEND
	var assignment: ManagerAssignment = ManagerAssignment.new()
	assignment.uid = _uid("assignment")
	assignment.company_id = player.id
	assignment.branch_building_id = player.restaurants[0].building_id
	assignment.manager_employee_uid = -1
	assignment.policy_uid = policy.uid
	assignment.founder_assistance = true
	assignment.active = true
	assignments.append(assignment)
	assignments_changed.emit()


func _load_or_seed_policy_templates() -> void:
	var directory := DirAccess.open(POLICY_DIR)
	if directory != null:
		for file_name: String in directory.get_files():
			if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
				continue
			var resource: Resource = load(POLICY_DIR.path_join(file_name))
			if resource is BranchPolicy:
				policy_templates.append(resource)
	if policy_templates.is_empty():
		_seed_policy_templates()


func _seed_policy_templates() -> void:
	var categories: Array[StringName] = [
		&"inventory", &"maintenance", &"schedules", &"staffing", &"delivery",
		&"hours", &"menu", &"marketing", &"layout", &"emergency",
		&"training", &"channels",
	]
	policy_templates.append(_make_preset(
		&"conservative", "Conservative", categories,
		{&"inventory": 1.2, &"maintenance": 1.1, &"emergency": 1.3},
		[&"inventory", &"emergency"], 4000.0))
	policy_templates.append(_make_preset(
		&"growth", "Growth", categories,
		{&"staffing": 1.4, &"marketing": 1.3, &"inventory": 1.2},
		[&"inventory", &"schedules", &"delivery"], 2500.0))
	var premium := _make_preset(
		&"premium", "Premium", categories,
		{&"menu": 1.5, &"maintenance": 1.4, &"staffing": 1.1},
		[&"inventory", &"maintenance"], 3500.0)
	premium.minimum_quality_tier = 1
	premium.minimum_price = 8.0
	policy_templates.append(premium)
	var value := _make_preset(
		&"value", "Value", categories,
		{&"inventory": 1.3, &"schedules": 1.2, &"menu": 1.1},
		[&"inventory", &"schedules"], 3000.0)
	value.maximum_price = 22.0
	policy_templates.append(value)
	policy_templates.append(_make_preset(
		&"delivery_first", "Delivery-First", categories,
		{&"delivery": 1.6, &"inventory": 1.3, &"schedules": 1.1},
		[&"inventory", &"delivery", &"emergency"], 2800.0))
	policy_templates.append(_make_preset(
		&"custom", "Custom", categories, {}, [], 3000.0))


func _make_preset(preset_id: StringName, display_name: String,
		categories: Array[StringName], weights: Dictionary,
		automatic_categories: Array[StringName], reserve: float) -> BranchPolicy:
	var policy: BranchPolicy = BranchPolicy.new()
	policy.uid = "preset:%s" % preset_id
	policy.preset_id = preset_id
	policy.display_name = display_name
	policy.cash_reserve = reserve
	policy.goal_weights = weights.duplicate(true)
	for category: StringName in categories:
		policy.authority_by_category[category] = BranchPolicy.AUTHORITY_RECOMMEND
		policy.daily_budget_by_category[category] = 1200.0
	for category: StringName in automatic_categories:
		policy.authority_by_category[category] = BranchPolicy.AUTHORITY_AUTOMATIC
	for category: StringName in [&"staffing", &"menu", &"marketing", &"layout", &"training", &"hours"]:
		if not automatic_categories.has(category):
			policy.authority_by_category[category] = BranchPolicy.AUTHORITY_APPROVAL
	policy.approved_layout_templates = [&"starter", &"compact"]
	return policy


func _seed_automation_rules() -> void:
	var rows: Array[Dictionary] = [
		{"category": &"inventory", "cooldown": 3, "horizon": 8, "severity": 0.25},
		{"category": &"staffing", "cooldown": 12, "horizon": 24, "severity": 0.45},
		{"category": &"delivery", "cooldown": 4, "horizon": 8, "severity": 0.35},
		{"category": &"emergency", "cooldown": 2, "horizon": 4, "severity": 0.50},
		{"category": &"maintenance", "cooldown": 12, "horizon": 24, "severity": 0.30},
		{"category": &"training", "cooldown": 24, "horizon": 48, "severity": 0.30},
		{"category": &"schedules", "cooldown": 6, "horizon": 12, "severity": 0.35},
	]
	for row: Dictionary in rows:
		var rule := AutomationRule.new()
		rule.category = row["category"]
		rule.cooldown_hours = row["cooldown"]
		rule.evaluation_horizon_hours = row["horizon"]
		rule.minimum_severity = row["severity"]
		automation_rules[rule.category] = rule


func _on_resignation_warning(member: StaffMember, explanation: String) -> void:
	var assignment: ManagerAssignment = assignment_for_branch(&"player", member.current_branch_building_id)
	if assignment == null:
		return
	_create_escalation(
		assignment,
		&"staff.set_schedule",
		{"building_id": member.current_branch_building_id, "staff_uid": member.uid},
		&"resignation_warning",
		explanation,
		["Satisfaction, fatigue, and wage fairness triggered a warning."],
		_window())


func _on_command_executed(_command_id: StringName, _result: CommandResult,
		_actor_context: Dictionary) -> void:
	pass


func _assign_resource_array(source: Variant, target: Array) -> void:
	if source is Array:
		target.assign(source)


func _trim(values: Array) -> void:
	while values.size() > HISTORY_LIMIT:
		values.remove_at(0)


func _uid(prefix: String) -> String:
	var value := "%s:%d" % [prefix, _next_uid]
	_next_uid += 1
	return value


func _window() -> int:
	return int(GameClock.total_minutes() / 60)
