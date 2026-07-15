extends Node
## Persistent workforce ownership, scheduling, training, transfers, and condition.

signal workforce_changed(company_id: StringName, building_id: int)
signal candidate_market_changed
signal training_changed
signal resignation_warning(member: StaffMember, explanation: String)

const TRAINING_DIR: String = "res://data/training_programs"
const HISTORY_LIMIT: int = 30

var schedule_templates: Dictionary = {}
var training_programs: Dictionary = {}
var training_enrollments: Array[TrainingEnrollment] = []
var processed_completion_keys: Dictionary = {}
var absence_log: Array[Dictionary] = []
var _shift_presence: Dictionary = {}
var _initialized: bool = false


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	if not is_instance_valid(GameClock) or not is_instance_valid(RestaurantManager):
		push_error("StaffManager requires GameClock and RestaurantManager.")
		return
	_load_training_programs()
	GameClock.hour_changed.connect(_on_hour_changed)
	GameClock.day_changed.connect(_on_day_changed)
	if not RestaurantManager.job_market_changed.is_connected(_on_market_changed):
		RestaurantManager.job_market_changed.connect(_on_market_changed)
	var save: SaveGame = CompanyManager.loaded_save
	if save != null:
		restore_from_save(save)
	_normalize_existing_staff()
	_normalize_market(GameClock.day)


func candidates(company_id: StringName, filters: Dictionary = {}) -> Array[JobCandidate]:
	var result: Array[JobCandidate] = []
	for candidate: JobCandidate in RestaurantManager.job_market:
		if not candidate.is_available_for(company_id, GameClock.day):
			continue
		var role_id := StringName(filters.get("role_id", &""))
		if role_id != &"" and candidate.type_id != role_id:
			continue
		var minimum_experience := float(filters.get("minimum_experience", 0.0))
		if candidate.experience < minimum_experience:
			continue
		var maximum_wage := float(filters.get("maximum_wage", INF))
		if candidate.hourly_wage > maximum_wage:
			continue
		result.append(candidate)
	result.sort_custom(func(first: JobCandidate, second: JobCandidate) -> bool:
		return first.hourly_wage < second.hourly_wage)
	return result


func hire_candidate_cmd(company_id: StringName, building_id: int, candidate_uid: int,
		offer: Dictionary) -> CommandResult:
	var candidate: JobCandidate = _candidate(candidate_uid)
	if candidate == null or not candidate.is_available_for(company_id, GameClock.day):
		return CommandResult.fail(&"candidate_gone", "That candidate is no longer available.")
	var offered_wage: float = float(offer.get("hourly_wage", candidate.hourly_wage))
	if offered_wage + 0.01 < candidate.hourly_wage:
		return CommandResult.fail(&"offer_too_low", "The offered wage is below the candidate's asking rate.")
	var contract_type: StringName = StringName(offer.get("contract_type", &"permanent"))
	if not candidate.has_contract_preference(contract_type):
		return CommandResult.fail(&"contract_declined", "That contract does not match the candidate's preference.")
	var start: float = float(offer.get("shift_start", 10.0))
	var hours: float = float(offer.get("shift_hours", 8.0))
	var result: CommandResult = RestaurantManager.hire(company_id, building_id, candidate_uid, start, hours)
	if not result.ok:
		return result
	var member: StaffMember = result.payload
	member.hourly_wage = offered_wage
	member.experience = candidate.experience
	member.competencies = candidate.competencies.duplicate(true)
	if member.competencies.is_empty():
		member.competencies = candidate.attributes.duplicate(true)
	member.traits = candidate.traits.duplicate()
	member.availability_by_weekday = candidate.availability_by_weekday.duplicate(true)
	member.contract_type = contract_type
	member.contract_start_day = GameClock.day
	member.guaranteed_weekly_hours = float(offer.get("weekly_hours", candidate.desired_weekly_hours))
	member.current_branch_building_id = building_id
	member.employment_history.append({"day": GameClock.day, "event": &"hired", "building_id": building_id})
	workforce_changed.emit(company_id, building_id)
	return result


func fire_staff_cmd(company_id: StringName, building_id: int, staff_uid: int) -> CommandResult:
	var result: CommandResult = RestaurantManager.fire_staff(company_id, building_id, staff_uid)
	if result.ok:
		var member: StaffMember = result.payload
		member.employment_status = &"terminated"
		member.employment_history.append({"day": GameClock.day, "event": &"terminated", "building_id": building_id})
		workforce_changed.emit(company_id, building_id)
	return result


func transfer_staff_cmd(company_id: StringName, from_building_id: int, to_building_id: int,
		staff_uid: int) -> CommandResult:
	if from_building_id == to_building_id:
		return CommandResult.fail(&"same_branch", "Choose a different destination branch.")
	var source: RestaurantState = RestaurantManager.by_building.get(from_building_id)
	var destination: RestaurantState = RestaurantManager.by_building.get(to_building_id)
	if source == null or destination == null or source.company_id != company_id or destination.company_id != company_id:
		return CommandResult.fail(&"not_owner", "Both branches must belong to the company.")
	var member: StaffMember = _member_in(source, staff_uid)
	if member == null:
		return CommandResult.fail(&"unknown_staff", "That employee is not assigned to the source branch.")
	source.staff.erase(member)
	destination.staff.append(member)
	member.current_branch_building_id = to_building_id
	member.employment_history.append({
		"day": GameClock.day,
		"event": &"transfer",
		"from_building_id": from_building_id,
		"to_building_id": to_building_id,
	})
	var definition: StaffTypeDef = RestaurantManager.staff_type(member.type_id)
	if definition != null and definition.is_driver:
		DeliveryManager.on_driver_fired(source, member)
		DeliveryManager.on_driver_hired(destination, member)
	workforce_changed.emit(company_id, from_building_id)
	workforce_changed.emit(company_id, to_building_id)
	return CommandResult.good(member)


func promote_staff_cmd(company_id: StringName, building_id: int, staff_uid: int,
		new_role_id: StringName, new_hourly_wage: float) -> CommandResult:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null or rest.company_id != company_id:
		return CommandResult.fail(&"not_owner", "That branch is not owned by the company.")
	var member: StaffMember = _member_in(rest, staff_uid)
	var definition: StaffTypeDef = RestaurantManager.staff_type(new_role_id)
	if member == null or definition == null:
		return CommandResult.fail(&"not_eligible", "That promotion is not available.")
	if not definition.promotion_from_roles.has(member.type_id) or member.experience < definition.minimum_experience_for_promotion:
		return CommandResult.fail(&"not_eligible", "The employee needs more role experience before this promotion.")
	var old_role: StringName = member.type_id
	member.type_id = new_role_id
	member.hourly_wage = maxf(new_hourly_wage, definition.base_hourly_wage)
	member.employment_history.append({"day": GameClock.day, "event": &"promotion", "from": old_role, "to": new_role_id})
	workforce_changed.emit(company_id, building_id)
	return CommandResult.good(member)


func set_contract_cmd(company_id: StringName, building_id: int, staff_uid: int,
		contract_type: StringName, hourly_wage: float, overtime_allowed: bool,
		maximum_overtime_hours: float) -> CommandResult:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	var member: StaffMember = _member_in(rest, staff_uid) if rest != null else null
	if rest == null or rest.company_id != company_id or member == null:
		return CommandResult.fail(&"unknown_staff", "That employee does not belong to this branch.")
	if contract_type not in [&"permanent", &"part_time", &"fixed_term", &"temporary"]:
		return CommandResult.fail(&"invalid_contract", "Choose a supported contract type.")
	if hourly_wage <= 0.0:
		return CommandResult.fail(&"invalid_wage", "Hourly wage must be greater than zero.")
	member.contract_type = contract_type
	member.hourly_wage = hourly_wage
	member.overtime_allowed = overtime_allowed
	member.maximum_overtime_hours = clampf(maximum_overtime_hours, 0.0, 20.0)
	member.employment_history.append({
		"day": GameClock.day,
		"event": &"contract_updated",
		"hourly_wage": hourly_wage,
		"overtime_allowed": overtime_allowed,
	})
	while member.employment_history.size() > HISTORY_LIMIT:
		member.employment_history.remove_at(0)
	workforce_changed.emit(company_id, building_id)
	return CommandResult.good(member)


func set_schedule_cmd(company_id: StringName, building_id: int, staff_uid: int,
		start: float, hours: float, weekday: int = -1) -> CommandResult:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null or rest.company_id != company_id:
		return CommandResult.fail(&"not_owner", "That branch is not owned by the company.")
	var member: StaffMember = _member_in(rest, staff_uid)
	if member == null:
		return CommandResult.fail(&"unknown_staff", "That employee is not in the branch roster.")
	var checked_weekday: int = weekday if weekday >= 0 else posmod(GameClock.day - 1, 7)
	if not member.is_available(checked_weekday):
		return CommandResult.fail(&"unavailable", "The employee is unavailable on that day.")
	var weekly_hours: float = hours * 5.0
	var overtime: float = maxf(0.0, weekly_hours - member.guaranteed_weekly_hours)
	if overtime > member.maximum_overtime_hours or (overtime > 0.0 and not member.overtime_allowed):
		return CommandResult.fail(&"overtime_limit", "This shift would exceed the employee's overtime limit.")
	var result: CommandResult = RestaurantManager.set_shift_cmd(company_id, building_id, staff_uid, start, hours)
	if result.ok:
		member.schedule_overrides[checked_weekday] = {"start": member.shift_start, "hours": member.shift_hours}
		workforce_changed.emit(company_id, building_id)
	return result


func bulk_schedule_cmd(company_id: StringName, building_id: int,
		assignments: Array[Dictionary]) -> CommandResult:
	var changed: Array[int] = []
	for assignment: Dictionary in assignments:
		var result: CommandResult = set_schedule_cmd(
			company_id,
			building_id,
			int(assignment.get("staff_uid", -1)),
			float(assignment.get("start", 10.0)),
			float(assignment.get("hours", 8.0)),
			int(assignment.get("weekday", -1)))
		if not result.ok:
			return CommandResult.fail(result.code, "%s No schedules were changed after employee %d." % [
				result.message, int(assignment.get("staff_uid", -1))])
		changed.append(int(assignment.get("staff_uid", -1)))
	return CommandResult.good(changed)


func save_schedule_template(company_id: StringName, template_id: String,
		template: Dictionary) -> void:
	schedule_templates[_template_key(company_id, template_id)] = template.duplicate(true)


func apply_schedule_template_cmd(company_id: StringName, building_id: int,
		template_id: String) -> CommandResult:
	var key: String = _template_key(company_id, template_id)
	if not schedule_templates.has(key):
		return CommandResult.fail(&"unknown_template", "That schedule template does not exist.")
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null or rest.company_id != company_id:
		return CommandResult.fail(&"not_owner", "That branch is not owned by the company.")
	var template: Dictionary = schedule_templates[key]
	var source_assignments: Array = template.get("assignments", []) as Array
	var mapped_assignments: Array[Dictionary] = []
	var used_staff: Dictionary = {}
	for source_assignment: Dictionary in source_assignments:
		var role_id := StringName(source_assignment.get("role_id", &""))
		var target := _member_in(rest, int(source_assignment.get("staff_uid", -1)))
		if target == null or used_staff.has(target.uid) or (
				not role_id.is_empty() and target.type_id != role_id):
			target = null
			for candidate: StaffMember in rest.staff:
				if used_staff.has(candidate.uid):
					continue
				if role_id.is_empty() or candidate.type_id == role_id:
					target = candidate
					break
		if target == null:
			continue
		var mapped: Dictionary = source_assignment.duplicate(true)
		mapped["staff_uid"] = target.uid
		mapped["role_id"] = target.type_id
		mapped_assignments.append(mapped)
		used_staff[target.uid] = true
	if mapped_assignments.is_empty():
		return CommandResult.fail(&"no_matching_staff",
			"No employees in this branch match the template roles.")
	var result := bulk_schedule_cmd(company_id, building_id, mapped_assignments)
	if result.ok and mapped_assignments.size() < source_assignments.size():
		result.explanation = "The template was applied to %d matching employees; unmatched roles were left unchanged." % mapped_assignments.size()
	return result


func enroll_training_cmd(company_id: StringName, building_id: int, staff_uid: int,
		program_id: StringName) -> CommandResult:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	var company: CompanyState = CompanyManager.company(company_id)
	var program: TrainingProgramDef = training_programs.get(program_id)
	if rest == null or company == null or rest.company_id != company_id:
		return CommandResult.fail(&"not_owner", "That branch is not owned by the company.")
	var member: StaffMember = _member_in(rest, staff_uid)
	if member == null or program == null or not program.supports_role(member.type_id):
		return CommandResult.fail(&"not_eligible", "That training program is not available to this employee.")
	for existing: TrainingEnrollment in training_enrollments:
		if existing.staff_uid == staff_uid and existing.status in [&"queued", &"active"]:
			return CommandResult.fail(&"already_enrolled", "The employee already has active training.")
	if not company.can_afford(program.cost):
		return CommandResult.fail(&"insufficient_cash", "Training costs $%.0f." % program.cost)
	company.transact(&"training", -program.cost)
	var enrollment: TrainingEnrollment = TrainingEnrollment.new()
	enrollment.uid = "training:%s:%d:%d" % [company_id, staff_uid, GameClock.total_minutes()]
	enrollment.company_id = company_id
	enrollment.branch_building_id = building_id
	enrollment.staff_uid = staff_uid
	enrollment.program_id = program_id
	enrollment.queued_window = _window()
	enrollment.cost_paid = program.cost
	enrollment.work_penalty = program.work_penalty
	enrollment.completion_key = "%s:complete" % enrollment.uid
	training_enrollments.append(enrollment)
	_start_queued_training(company_id)
	training_changed.emit()
	return CommandResult.good(enrollment)


func training_capacity(company_id: StringName) -> int:
	return maxi(1, CapabilityRegistry.capacity(company_id, &"workforce.training_slots"))


func role_effects_for(rest: RestaurantState) -> Dictionary:
	var totals := {
		"cook": 0.0,
		"service": 0.0,
		"delivery": 0.0,
		"stock": 0.0,
		"cleanliness": 0.0,
		"management": 0.0,
	}
	var counts := totals.duplicate(true)
	for key: Variant in counts:
		counts[key] = 0
	for member: StaffMember in rest.staff:
		if member.is_absent(GameClock.day) or not member.on_shift(GameClock.game_hours):
			continue
		var definition: StaffTypeDef = RestaurantManager.staff_type(member.type_id)
		if definition == null:
			continue
		if definition.cook_slots > 0:
			totals["cook"] += member.operational_effect(&"consistency")
			counts["cook"] += 1
		if definition.waiter_customers_per_hour > 0.0:
			totals["service"] += member.operational_effect(&"service")
			counts["service"] += 1
		if definition.is_driver:
			totals["delivery"] += member.operational_effect(&"reliability")
			counts["delivery"] += 1
		if definition.stock_handling_per_hour > 0.0:
			totals["stock"] += member.operational_effect(&"stock_handling")
			counts["stock"] += 1
		if definition.cleaning_per_hour > 0.0:
			totals["cleanliness"] += member.operational_effect(&"cleaning")
			counts["cleanliness"] += 1
		if definition.is_manager:
			totals["management"] += member.operational_effect(&"judgment")
			counts["management"] += 1
	for key: Variant in totals:
		if int(counts[key]) > 0:
			totals[key] = float(totals[key]) / float(counts[key])
	return totals


func staff_member(company_id: StringName, staff_uid: int) -> StaffMember:
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null:
		return null
	for rest: RestaurantState in company.restaurants:
		var member: StaffMember = _member_in(rest, staff_uid)
		if member != null:
			return member
	return null


func write_save(save: SaveGame) -> void:
	save.set("workforce_schema_version", 1)
	save.set("schedule_templates", schedule_templates.duplicate(true))
	save.set("training_enrollments", training_enrollments.duplicate())
	save.set("training_completion_keys", processed_completion_keys.duplicate(true))
	save.set("absence_log", absence_log.duplicate(true))


func restore_from_save(save: SaveGame) -> void:
	var saved_templates: Variant = save.get("schedule_templates")
	if saved_templates is Dictionary:
		schedule_templates = saved_templates.duplicate(true)
	var saved_enrollments: Variant = save.get("training_enrollments")
	if saved_enrollments is Array:
		training_enrollments.assign(saved_enrollments)
	var saved_keys: Variant = save.get("training_completion_keys")
	if saved_keys is Dictionary:
		processed_completion_keys = saved_keys.duplicate(true)
	var saved_absences: Variant = save.get("absence_log")
	if saved_absences is Array:
		absence_log.assign(saved_absences)


func _on_hour_changed(day: int, hour: int) -> void:
	var current_window := day * 24 + hour
	_advance_training(current_window)
	for company: CompanyState in CompanyManager.companies:
		for rest: RestaurantState in company.restaurants:
			_update_branch_hour(rest, day, float(hour), current_window)


func _update_branch_hour(rest: RestaurantState, day: int, hour: float, current_window: int) -> void:
	var role_effects := role_effects_for(rest)
	rest.today["stock_handling_capacity"] = float(rest.today.get("stock_handling_capacity", 0.0)) + float(role_effects["stock"])
	for member: StaffMember in rest.staff:
		if member.last_condition_update_window == current_window:
			continue
		member.last_condition_update_window = current_window
		var present := member.on_shift(hour) and not member.is_absent(day)
		var key := "%d:%d" % [rest.building_id, member.uid]
		var was_present := bool(_shift_presence.get(key, false))
		if present:
			var training_penalty := _training_penalty(member.uid)
			member.energy = clampf(member.energy - 0.045 - training_penalty * 0.02, 0.0, 1.0)
			member.fatigue = clampf(member.fatigue + 0.04 + training_penalty * 0.02, 0.0, 1.0)
			member.stress = clampf(member.stress + 0.01, 0.0, 1.0)
			member.add_experience(0.5)
		else:
			member.energy = clampf(member.energy + 0.035, 0.0, 1.0)
			member.fatigue = clampf(member.fatigue - 0.03, 0.0, 1.0)
			member.stress = clampf(member.stress - 0.015, 0.0, 1.0)
		if present != was_present:
			_record_attendance(member, day, hour, present)
		_shift_presence[key] = present
	if float(role_effects["cleanliness"]) > 0.0 and rest.interior_layout != null:
		for item: PlacedFurnitureState in rest.interior_layout.placed:
			item.cleanliness = clampf(item.cleanliness + 0.006 * float(role_effects["cleanliness"]), 0.0, 1.0)
	workforce_changed.emit(rest.company_id, rest.building_id)


func _on_day_changed(day: int) -> void:
	for company: CompanyState in CompanyManager.companies:
		for rest: RestaurantState in company.restaurants:
			for member: StaffMember in rest.staff:
				_update_daily_condition(member, rest, day)
	_normalize_market(day)
	for company: CompanyState in CompanyManager.companies:
		_start_queued_training(company.id)


func _update_daily_condition(member: StaffMember, rest: RestaurantState, day: int) -> void:
	var definition: StaffTypeDef = RestaurantManager.staff_type(member.type_id)
	var fair_wage := definition.base_hourly_wage if definition != null else member.hourly_wage
	var fairness := member.hourly_wage / maxf(0.01, fair_wage)
	member.satisfaction = clampf(member.satisfaction + clampf(fairness - 1.0, -0.08, 0.06), 0.0, 1.0)
	member.motivation = clampf(member.motivation + (member.satisfaction - 0.5) * 0.04 - member.stress * 0.02, 0.0, 1.0)
	member.health = clampf(member.health + 0.02 - member.fatigue * 0.025, 0.0, 1.0)
	member.resignation_risk = clampf((0.55 - member.satisfaction) * 0.8 + member.stress * 0.35 + member.fatigue * 0.2, 0.0, 0.75)
	var absence_risk := clampf((1.0 - member.health) * 0.22 + member.fatigue * 0.12 + member.stress * 0.08, 0.0, 0.35)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d:%d:%d" % [GameSetup.world_seed, day, rest.building_id, member.uid])
	if rng.randf() < absence_risk:
		member.absence_until_day = day
		absence_log.append({"day": day, "staff_uid": member.uid, "building_id": rest.building_id, "reason": &"health"})
		_trim_history(absence_log)
	if member.resignation_risk >= 0.45 and member.resignation_warning_day != day:
		member.resignation_warning_day = day
		resignation_warning.emit(member, "%s may resign unless conditions improve." % member.staff_name)


func _advance_training(current_window: int) -> void:
	for enrollment: TrainingEnrollment in training_enrollments:
		if not enrollment.ready_to_complete(current_window):
			continue
		if processed_completion_keys.has(enrollment.completion_key):
			enrollment.completion_applied = true
			enrollment.status = &"complete"
			continue
		var program: TrainingProgramDef = training_programs.get(enrollment.program_id)
		var member := staff_member(enrollment.company_id, enrollment.staff_uid)
		if program == null or member == null:
			enrollment.status = &"blocked"
			continue
		member.competencies[program.competency_id] = clampf(
			member.competency(program.competency_id) + program.competency_gain, 0.0, 1.0)
		member.add_experience(program.experience_gain)
		member.training_history.append({
			"program_id": program.id,
			"completed_window": current_window,
			"competency_gain": program.competency_gain,
		})
		_trim_history(member.training_history)
		processed_completion_keys[enrollment.completion_key] = true
		enrollment.completion_applied = true
		enrollment.completed_window = current_window
		enrollment.status = &"complete"
		training_changed.emit()
		_start_queued_training(enrollment.company_id)


func _start_queued_training(company_id: StringName) -> void:
	var available := training_capacity(company_id) - _active_training_count(company_id)
	if available <= 0:
		return
	for enrollment: TrainingEnrollment in training_enrollments:
		if available <= 0:
			break
		if enrollment.company_id != company_id or enrollment.status != &"queued":
			continue
		var program: TrainingProgramDef = training_programs.get(enrollment.program_id)
		if program == null:
			enrollment.status = &"blocked"
			continue
		enrollment.status = &"active"
		enrollment.started_window = _window()
		enrollment.completes_window = enrollment.started_window + maxi(1, program.duration_hours)
		available -= maxi(1, program.headquarters_capacity_cost)
		training_changed.emit()


func _active_training_count(company_id: StringName) -> int:
	var count := 0
	for enrollment: TrainingEnrollment in training_enrollments:
		if enrollment.company_id == company_id and enrollment.status == &"active":
			var program: TrainingProgramDef = training_programs.get(enrollment.program_id)
			count += maxi(1, program.headquarters_capacity_cost) if program != null else 1
	return count


func _training_penalty(staff_uid: int) -> float:
	for enrollment: TrainingEnrollment in training_enrollments:
		if enrollment.staff_uid == staff_uid and enrollment.status == &"active":
			return enrollment.work_penalty
	return 0.0


func _normalize_existing_staff() -> void:
	for company: CompanyState in CompanyManager.companies:
		for rest: RestaurantState in company.restaurants:
			for member: StaffMember in rest.staff:
				member.current_branch_building_id = rest.building_id
				if member.competencies.is_empty():
					member.competencies = member.attributes.duplicate(true)


func _normalize_market(day: int) -> void:
	var lifetime := int(EconomyManager.tuning_value("hiring.candidate_lifetime_days", 4))
	for candidate: JobCandidate in RestaurantManager.job_market:
		if candidate.expires_day <= candidate.posted_day:
			candidate.expires_day = candidate.posted_day + lifetime
		if candidate.competencies.is_empty():
			candidate.competencies = candidate.attributes.duplicate(true)
		if candidate.availability_by_weekday.is_empty():
			for weekday: int in 7:
				candidate.availability_by_weekday[weekday] = true
		candidate.manager_eligible = candidate.type_id == &"manager"
		if candidate.expires_day < day:
			candidate.reserved_by_company_id = &""
	candidate_market_changed.emit()


func _load_training_programs() -> void:
	var directory := DirAccess.open(TRAINING_DIR)
	if directory != null:
		for file_name: String in directory.get_files():
			if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
				continue
			var resource: Resource = load(TRAINING_DIR.path_join(file_name))
			if resource is TrainingProgramDef:
				training_programs[resource.id] = resource
	if training_programs.is_empty():
		_seed_default_training_programs()


func _seed_default_training_programs() -> void:
	var rows: Array[Dictionary] = [
		{"id": &"service_basics", "name": "Service Basics", "competency": &"service", "roles": [&"waiter"], "cost": 180.0},
		{"id": &"kitchen_consistency", "name": "Kitchen Consistency", "competency": &"consistency", "roles": [&"cook"], "cost": 240.0},
		{"id": &"stock_control", "name": "Stock Control", "competency": &"stock_handling", "roles": [&"runner"], "cost": 190.0},
		{"id": &"branch_leadership", "name": "Branch Leadership", "competency": &"judgment", "roles": [&"manager"], "cost": 420.0},
	]
	for row: Dictionary in rows:
		var program := TrainingProgramDef.new()
		program.id = row["id"]
		program.display_name = row["name"]
		program.competency_id = row["competency"]
		program.role_ids.assign(row["roles"])
		program.cost = row["cost"]
		training_programs[program.id] = program


func _candidate(candidate_uid: int) -> JobCandidate:
	for candidate: JobCandidate in RestaurantManager.job_market:
		if candidate.uid == candidate_uid:
			return candidate
	return null


func _member_in(rest: RestaurantState, staff_uid: int) -> StaffMember:
	for member: StaffMember in rest.staff:
		if member.uid == staff_uid:
			return member
	return null


func _record_attendance(member: StaffMember, day: int, hour: float, present: bool) -> void:
	member.attendance_history.append({"day": day, "hour": hour, "event": &"clock_in" if present else &"clock_out"})
	_trim_history(member.attendance_history)


func _trim_history(history: Array) -> void:
	while history.size() > HISTORY_LIMIT:
		history.remove_at(0)


func _template_key(company_id: StringName, template_id: String) -> String:
	return "%s:%s" % [company_id, template_id]


func _window() -> int:
	return int(GameClock.total_minutes() / 60)


func _on_market_changed() -> void:
	_normalize_market(GameClock.day)
