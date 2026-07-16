extends Node
## Persistent workforce ownership, scheduling, training, transfers, and condition.

signal workforce_changed(company_id: StringName, building_id: int)
signal candidate_market_changed
signal training_changed
signal resignation_warning(member: StaffMember, explanation: String)
signal staff_resigned(member: StaffMember, building_id: int)
signal labor_event_started(event: Dictionary)

const TRAINING_DIR: String = "res://data/training_programs"
const HISTORY_LIMIT: int = 30
const RESIGN_WARN_RISK: float = 0.45
const RESIGN_COMMIT_RISK: float = 0.5
const RESIGN_GRACE_DAYS: int = 3
const LABOR_EVENT_TYPES: Array[Dictionary] = [
	{&"type": &"wage_spike", &"supply": -1.0, &"wage": 0.12, &"duration": 5, &"unrest": 0.0, &"message": "Wage pressure is rising across the city."},
	{&"type": &"talent_influx", &"supply": 2.0, &"wage": -0.05, &"duration": 4, &"unrest": 0.0, &"message": "A wave of fresh hospitality talent has arrived in town."},
	{&"type": &"poaching_wave", &"supply": -1.0, &"wage": 0.08, &"duration": 4, &"unrest": 0.015, &"message": "Rivals are aggressively poaching restaurant staff."},
	{&"type": &"strike_risk", &"supply": 0.0, &"wage": 0.05, &"duration": 3, &"unrest": 0.02, &"message": "Labor unrest is unsettling workers citywide."},
]

var schedule_templates: Dictionary = {}
var training_programs: Dictionary = {}
var training_enrollments: Array[TrainingEnrollment] = []
var processed_completion_keys: Dictionary = {}
var absence_log: Array[Dictionary] = []
var city_labor_events: Array[Dictionary] = []
var turnover_log: Array[Dictionary] = []
var _labor_unrest: float = 0.0
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
	_sync_training_penalties()
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
	member.home_building_id = building_id
	_assign_initial_goal(member, RestaurantManager.staff_type(member.type_id))
	member.employment_history.append({"day": GameClock.day, "event": &"hired", "building_id": building_id})
	workforce_changed.emit(company_id, building_id)
	return result


func interview_candidate_cmd(company_id: StringName, candidate_uid: int) -> CommandResult:
	var candidate: JobCandidate = _candidate(candidate_uid)
	if candidate == null or not candidate.is_available_for(company_id, GameClock.day):
		return CommandResult.fail(&"candidate_gone", "That candidate is no longer available.")
	if candidate.is_interviewed() and candidate.reserved_by_company_id == company_id:
		return CommandResult.good(candidate)
	var company: CompanyState = CompanyManager.company(company_id)
	var cost: float = float(EconomyManager.tuning_value("hiring.interview_cost", 40.0))
	if company == null or not company.can_afford(cost):
		return CommandResult.fail(&"insufficient_cash", "An interview costs $%.0f." % cost)
	company.transact(&"staff", -cost)
	candidate.interview_state = &"interviewed"
	candidate.revealed_competencies = candidate.competencies.duplicate(true)
	candidate.assessment_confidence = 1.0
	# Soft signing window: hold the candidate for a day while you decide.
	candidate.reserved_by_company_id = company_id
	candidate.reservation_expires_day = GameClock.day + 1
	candidate_market_changed.emit()
	return CommandResult.good(candidate)


func fire_staff_cmd(company_id: StringName, building_id: int, staff_uid: int) -> CommandResult:
	var result: CommandResult = RestaurantManager.fire_staff(company_id, building_id, staff_uid)
	if result.ok:
		var member: StaffMember = result.payload
		member.employment_status = &"terminated"
		member.employment_history.append({"day": GameClock.day, "event": &"terminated", "building_id": building_id})
		turnover_log.append({"day": GameClock.day, "uid": member.uid, "name": member.staff_name, "reason": &"terminated", "company_id": company_id})
		_trim_history(turnover_log)
		workforce_changed.emit(company_id, building_id)
	return result


func _commute_ok(member: StaffMember, to_building_id: int) -> bool:
	if member.home_building_id < 0:
		return true
	var home_info: Dictionary = CityData.get_building(member.home_building_id)
	var dest_info: Dictionary = CityData.get_building(to_building_id)
	if home_info.is_empty() or dest_info.is_empty():
		return true
	var home_pos: Vector3 = home_info.get("position", Vector3.ZERO)
	var dest_pos: Vector3 = dest_info.get("position", Vector3.ZERO)
	# commute_tolerance maps to a maximum acceptable home->branch distance.
	var max_commute: float = lerpf(500.0, 3000.0, clampf(member.commute_tolerance, 0.0, 1.0))
	return home_pos.distance_to(dest_pos) <= max_commute


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
	if _has_pending_training(member.uid):
		return CommandResult.fail(&"in_training", "%s is mid-training and cannot transfer yet." % member.staff_name)
	if not _commute_ok(member, to_building_id):
		return CommandResult.fail(&"commute", "%s lives too far to commute to that branch." % member.staff_name)
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
	for prereq_key: Variant in program.prerequisite_competencies:
		if member.competency(prereq_key) < float(program.prerequisite_competencies[prereq_key]):
			return CommandResult.fail(&"prerequisite", "%s needs more %s before this program." % [member.staff_name, String(prereq_key).replace("_", " ")])
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


func _has_pending_training(staff_uid: int) -> bool:
	for enrollment: TrainingEnrollment in training_enrollments:
		if enrollment.staff_uid == staff_uid and enrollment.status in [&"queued", &"active"]:
			return true
	return false


## Picks the most valuable training a manager could enroll now: an eligible,
## affordable program for the employee furthest below mastery in its competency.
## Returns {} when there is no idle capacity, candidate, or clear skill gap.
func suggest_training(company_id: StringName, building_id: int) -> Dictionary:
	if training_capacity(company_id) - _active_training_count(company_id) <= 0:
		return {}
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	var company: CompanyState = CompanyManager.company(company_id)
	if rest == null or company == null or rest.company_id != company_id:
		return {}
	var best: Dictionary = {}
	var best_gap: float = 0.15
	for member: StaffMember in rest.staff:
		if _has_pending_training(member.uid):
			continue
		for program: TrainingProgramDef in training_programs.values():
			if not program.supports_role(member.type_id) or not company.can_afford(program.cost):
				continue
			var current: float = member.competency(program.competency_id)
			var gap: float = 1.0 - current
			if gap > best_gap:
				best_gap = gap
				var label: String = String(program.competency_id).replace("_", " ")
				best = {
					"staff_uid": member.uid,
					"program_id": program.id,
					"evidence": "%s sits at %d%% %s." % [member.staff_name, int(round(current * 100.0)), label],
					"expected": "Enroll in %s to raise %s." % [program.display_name, label],
				}
	return best


const FORECAST_DEPARTMENTS: Array[StringName] = [&"kitchen", &"service", &"delivery", &"cleaning", &"management"]


## Per-hour projected demand vs. staffed capacity for each department across the
## day. Demand is a normalised lunch/dinner curve scaled by branch size, given as
## a recommended head-count; capacity is the qualified staff on shift that hour.
## A planning aid, never a hard gate.
## Aggregate workforce KPIs for the company reports surface. Basic metrics are
## always available; richer breakdowns unlock with analytics.report_depth.
## Read-only snapshot.
func workforce_analytics(company_id: StringName) -> Dictionary:
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null:
		return {}
	var headcount: int = 0
	var payroll: float = 0.0
	var motivation_sum: float = 0.0
	var satisfaction_sum: float = 0.0
	var readiness_sum: float = 0.0
	var by_role: Dictionary = {}
	for rest: RestaurantState in company.restaurants:
		for member: StaffMember in rest.staff:
			headcount += 1
			payroll += member.daily_pay()
			motivation_sum += member.motivation
			satisfaction_sum += member.satisfaction
			readiness_sum += member.condition_score()
			by_role[member.type_id] = int(by_role.get(member.type_id, 0)) + 1
	var recent_day: int = GameClock.day - 14
	var turnover: int = 0
	for entry: Dictionary in turnover_log:
		if StringName(entry.get("company_id", &"")) == company_id and int(entry.get("day", 0)) >= recent_day:
			turnover += 1
	var absences: int = 0
	for entry: Dictionary in absence_log:
		if int(entry.get("day", 0)) < recent_day:
			continue
		var branch: RestaurantState = RestaurantManager.by_building.get(int(entry.get("building_id", -1)))
		if branch != null and branch.company_id == company_id:
			absences += 1
	var training_completed: int = 0
	for enrollment: TrainingEnrollment in training_enrollments:
		if enrollment.company_id == company_id and enrollment.status == &"complete":
			training_completed += 1
	var divisor: float = maxf(1.0, float(headcount))
	return {
		"headcount": headcount,
		"payroll_daily": payroll,
		"avg_motivation": motivation_sum / divisor,
		"avg_satisfaction": satisfaction_sum / divisor,
		"avg_readiness": readiness_sum / divisor,
		"turnover_14d": turnover,
		"absences_14d": absences,
		"training_completed": training_completed,
		"training_active": _active_training_count(company_id),
		"by_role": by_role,
		"report_depth": CapabilityRegistry.capacity(company_id, &"analytics.report_depth"),
	}


func forecast_coverage(building_id: int) -> Dictionary:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null:
		return {}
	var departments: Dictionary = {}
	for dept: StringName in FORECAST_DEPARTMENTS:
		var demand: Array = []
		var capacity: Array = []
		demand.resize(24)
		capacity.resize(24)
		for hour: int in 24:
			demand[hour] = _forecast_demand(dept, rest, hour)
			capacity[hour] = _forecast_capacity(dept, rest, float(hour))
		departments[dept] = {"demand": demand, "capacity": capacity}
	return {"open_hour": rest.open_hour, "close_hour": rest.close_hour, "departments": departments}


func _forecast_capacity(dept: StringName, rest: RestaurantState, hour: float) -> int:
	var count: int = 0
	for member: StaffMember in rest.staff:
		if not member.on_shift(hour):
			continue
		var definition: StaffTypeDef = RestaurantManager.staff_type(member.type_id)
		if definition != null and _role_serves_department(definition, dept):
			count += 1
	return count


func _role_serves_department(definition: StaffTypeDef, dept: StringName) -> bool:
	match dept:
		&"kitchen":
			return definition.cook_slots > 0
		&"service":
			return definition.waiter_customers_per_hour > 0.0
		&"delivery":
			return definition.is_driver
		&"cleaning":
			return definition.cleaning_per_hour > 0.0
		&"management":
			return definition.is_manager
	return false


func _forecast_demand(dept: StringName, rest: RestaurantState, hour: int) -> int:
	if not rest.is_open(float(hour)):
		return 0
	var intensity: float = _hour_intensity(hour)
	match dept:
		&"kitchen":
			return int(ceil(intensity * maxf(1.0, float(rest.cook_station_cap))))
		&"service":
			return int(ceil(intensity * 2.0))
		&"delivery":
			return int(ceil(intensity * maxf(1.0, float(rest.delivery_cap) * 0.5))) if rest.delivery_enabled else 0
		&"cleaning":
			return 1 if intensity > 0.35 else 0
		&"management":
			return 1
	return 0


func _hour_intensity(hour: int) -> float:
	# Two peaks: lunch (~12:30) and dinner (~19:00) over a low base.
	var lunch: float = exp(-pow(float(hour) - 12.5, 2.0) / 4.0)
	var dinner: float = exp(-pow(float(hour) - 19.0, 2.0) / 6.0)
	return clampf(0.35 + maxf(lunch, dinner) * 0.65, 0.0, 1.0)


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
	# Guard coverage (feature 12) sums across on-shift guards rather than
	# averaging — more guards means more coverage. SecurityService clamps it.
	var security_coverage: float = 0.0
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
		if definition.operational_tags.has(&"security"):
			security_coverage += 0.55 * member.operational_effect(&"vigilance")
	for key: Variant in totals:
		if int(counts[key]) > 0:
			totals[key] = float(totals[key]) / float(counts[key])
	totals["security"] = minf(1.0, security_coverage)
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
	save.set("workforce_schema_version", 2)
	save.set("schedule_templates", schedule_templates.duplicate(true))
	save.set("training_enrollments", training_enrollments.duplicate())
	save.set("training_completion_keys", processed_completion_keys.duplicate(true))
	save.set("absence_log", absence_log.duplicate(true))
	save.set("city_labor_events", city_labor_events.duplicate(true))
	save.set("turnover_log", turnover_log.duplicate(true))


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
	var saved_events: Variant = save.get("city_labor_events")
	if saved_events is Array:
		city_labor_events.assign(saved_events)
	var saved_turnover: Variant = save.get("turnover_log")
	if saved_turnover is Array:
		turnover_log.assign(saved_turnover)


func _on_hour_changed(day: int, hour: int) -> void:
	var current_window := day * 24 + hour
	_advance_training(current_window)
	for company: CompanyState in CompanyManager.companies:
		for rest: RestaurantState in company.restaurants:
			_update_branch_hour(rest, day, float(hour), current_window)


func _update_branch_hour(rest: RestaurantState, day: int, hour: float, current_window: int) -> void:
	var role_effects := role_effects_for(rest)
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
			member.add_experience(0.5 / (1.0 + member.experience / 200.0))
			_grow_competencies_from_work(member, rest)
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


func _grow_competencies_from_work(member: StaffMember, rest: RestaurantState) -> void:
	var definition: StaffTypeDef = RestaurantManager.staff_type(member.type_id)
	if definition == null:
		return
	var weights: Dictionary = definition.weighted_competencies()
	# Learning-by-doing: each shift-hour nudges the role's competencies toward
	# mastery with sharp diminishing returns, self-capping below 1.0 so raw
	# practice never replaces training or a promotion.
	for key_variant: Variant in weights:
		var key: StringName = key_variant
		var current: float = member.competency(key)
		var weight: float = clampf(float(weights[key]), 0.0, 2.0)
		member.competencies[key] = clampf(current + 0.0025 * weight * (1.0 - current), 0.0, 0.98)


func _branch_condition_bonus(rest: RestaurantState) -> float:
	if rest.interior_layout == null or rest.interior_layout.placed.is_empty():
		return 0.0
	var total: float = 0.0
	for item: PlacedFurnitureState in rest.interior_layout.placed:
		total += item.cleanliness
	var avg: float = total / float(rest.interior_layout.placed.size())
	return (avg - 0.6) * 0.03


func _on_day_changed(day: int) -> void:
	_update_labor_events(day)
	var resignations: Array[Dictionary] = []
	for company: CompanyState in CompanyManager.companies:
		for rest: RestaurantState in company.restaurants:
			for member: StaffMember in rest.staff:
				if _update_daily_condition(member, rest, day):
					resignations.append({"company_id": company.id, "rest": rest, "member": member})
	for entry: Dictionary in resignations:
		_resign_member(entry["company_id"], entry["rest"], entry["member"], day)
	_normalize_market(day)
	for company: CompanyState in CompanyManager.companies:
		_start_queued_training(company.id)


func _update_daily_condition(member: StaffMember, rest: RestaurantState, day: int) -> bool:
	var definition: StaffTypeDef = RestaurantManager.staff_type(member.type_id)
	var fair_wage := definition.base_hourly_wage if definition != null else member.hourly_wage
	var fairness := member.hourly_wage / maxf(0.01, fair_wage)
	member.satisfaction = clampf(member.satisfaction + clampf(fairness - 1.0, -0.08, 0.06), 0.0, 1.0)
	member.loyalty = clampf(member.loyalty + (member.satisfaction - 0.5) * 0.01, 0.0, 1.0)
	member.desired_wage = maxf(member.desired_wage, fair_wage * (1.0 + member.experience / 800.0))
	member.stress = clampf(member.stress + _labor_unrest, 0.0, 1.0)
	_check_goals(member)
	# Motivation responds to wage fairness, stress, workload, injury, loyalty, and
	# how well-kept the branch is. The net daily move is bounded so no single
	# factor can spike morale.
	var motivation_delta: float = (member.satisfaction - 0.5) * 0.04 - member.stress * 0.02 - member.fatigue * 0.02
	motivation_delta += (member.loyalty - 0.5) * 0.02 + _branch_condition_bonus(rest)
	if member.is_injured(day):
		motivation_delta -= 0.03
	member.motivation = clampf(member.motivation + clampf(motivation_delta, -0.08, 0.08), 0.0, 1.0)
	member.health = clampf(member.health + 0.02 - member.fatigue * 0.025, 0.0, 1.0)
	member.resignation_risk = clampf((0.55 - member.satisfaction) * 0.8 + member.stress * 0.35 + member.fatigue * 0.2 - (member.loyalty - 0.5) * 0.3, 0.0, 0.75)
	var absence_risk := clampf((1.0 - member.health) * 0.22 + member.fatigue * 0.12 + member.stress * 0.08, 0.0, 0.35)
	var rng := WorkforceRng.make(&"absence", day, [rest.building_id, member.uid])
	if rng.randf() < absence_risk:
		member.absence_until_day = day
		absence_log.append({"day": day, "staff_uid": member.uid, "building_id": rest.building_id, "reason": &"health"})
		_trim_history(absence_log)
	# Resignations are always telegraphed by a warning, then resolved by a graced,
	# seeded quit roll so the player can react. Committed exactly once.
	if member.resignation_risk >= RESIGN_WARN_RISK:
		if member.resignation_warning_day < 0:
			member.resignation_warning_day = day
			resignation_warning.emit(member, "%s may resign unless conditions improve." % member.staff_name)
		elif member.resignation_committed_day < 0 \
				and day - member.resignation_warning_day >= RESIGN_GRACE_DAYS \
				and member.resignation_risk >= RESIGN_COMMIT_RISK:
			var quit_rng := WorkforceRng.make(&"resign", day, [rest.building_id, member.uid])
			var quit_chance := clampf((member.resignation_risk - RESIGN_COMMIT_RISK) * 0.8, 0.0, 0.35)
			if quit_rng.randf() < quit_chance:
				member.resignation_committed_day = day
				return true
	elif member.resignation_risk < RESIGN_WARN_RISK * 0.7:
		member.resignation_warning_day = -1
	return false


func _update_labor_events(day: int) -> void:
	for i: int in range(city_labor_events.size() - 1, -1, -1):
		if day >= int(city_labor_events[i].get(&"end_day", 0)):
			city_labor_events.remove_at(i)
	var rng: RandomNumberGenerator = WorkforceRng.make(&"labor_event", day, [])
	if city_labor_events.is_empty() and rng.randf() < 0.12:
		var template: Dictionary = LABOR_EVENT_TYPES[rng.randi() % LABOR_EVENT_TYPES.size()]
		var event: Dictionary = template.duplicate(true)
		event[&"start_day"] = day
		event[&"end_day"] = day + int(template[&"duration"])
		city_labor_events.append(event)
		labor_event_started.emit(event)
		if CompanyManager.player != null:
			EconomyManager.post_message("info", String(template[&"message"]))
	var supply: float = 0.0
	var wage: float = 0.0
	_labor_unrest = 0.0
	for event: Dictionary in city_labor_events:
		supply += float(event.get(&"supply", 0.0))
		wage += float(event.get(&"wage", 0.0))
		_labor_unrest += float(event.get(&"unrest", 0.0))
	RestaurantManager.labor_market_supply_shift = supply
	RestaurantManager.labor_market_wage_shift = wage


func _assign_initial_goal(member: StaffMember, definition: StaffTypeDef) -> void:
	if definition == null or not member.goals.is_empty():
		return
	var keys: Array = definition.all_competency_keys()
	if keys.is_empty():
		return
	var key: StringName = keys[0]
	var target: float = clampf(member.competency(key) + 0.2, 0.1, 0.95)
	member.goals.append({
		&"kind": &"skill",
		&"competency": key,
		&"target": target,
		&"reward": 0.12,
		&"completed": false,
		&"label": "Reach %d%% %s" % [int(round(target * 100.0)), String(key).replace("_", " ")],
	})


func _check_goals(member: StaffMember) -> void:
	for goal: Dictionary in member.goals:
		if bool(goal.get(&"completed", false)):
			continue
		if StringName(goal.get(&"kind", &"")) == &"skill" \
				and member.competency(StringName(goal.get(&"competency", &""))) >= float(goal.get(&"target", 1.0)):
			goal[&"completed"] = true
			member.motivation = clampf(member.motivation + float(goal.get(&"reward", 0.1)), 0.0, 1.0)
			member.loyalty = clampf(member.loyalty + 0.05, 0.0, 1.0)


func _resign_member(company_id: StringName, rest: RestaurantState, member: StaffMember, day: int) -> void:
	var result: CommandResult = RestaurantManager.fire_staff(company_id, rest.building_id, member.uid)
	if not result.ok:
		return
	member.employment_status = &"resigned"
	member.employment_history.append({"day": day, "event": &"resigned", "building_id": rest.building_id})
	turnover_log.append({"day": day, "uid": member.uid, "name": member.staff_name, "reason": &"resigned", "company_id": company_id})
	_trim_history(turnover_log)
	staff_resigned.emit(member, rest.building_id)
	workforce_changed.emit(company_id, rest.building_id)
	if CompanyManager.player != null and company_id == CompanyManager.player.id:
		EconomyManager.post_message("alert", "%s handed in their notice and left." % member.staff_name)


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
		var gains: Dictionary = program.effective_gains()
		for gain_key: Variant in gains:
			var comp_key: StringName = gain_key
			member.competencies[comp_key] = clampf(member.competency(comp_key) + float(gains[comp_key]), 0.0, 1.0)
		member.add_experience(program.experience_gain)
		member.health = clampf(member.health + program.health_effect, 0.0, 1.0)
		member.motivation = clampf(member.motivation + program.motivation_effect, 0.0, 1.0)
		member.active_training_penalty = 0.0
		member.training_history.append({
			"program_id": program.id,
			"completed_window": current_window,
			"competency_gains": gains.duplicate(),
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
		var trainee: StaffMember = staff_member(enrollment.company_id, enrollment.staff_uid)
		if trainee != null:
			trainee.active_training_penalty = program.throughput_penalty
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


func _sync_training_penalties() -> void:
	for enrollment: TrainingEnrollment in training_enrollments:
		if enrollment.status != &"active":
			continue
		var program: TrainingProgramDef = training_programs.get(enrollment.program_id)
		var member: StaffMember = staff_member(enrollment.company_id, enrollment.staff_uid)
		if program != null and member != null:
			member.active_training_penalty = program.throughput_penalty


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
