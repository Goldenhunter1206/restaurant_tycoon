extends Node
## Company headquarters progression, commands, upkeep, and world visuals.

signal headquarters_changed(company_id: StringName)
signal project_started(company_id: StringName, project: UpgradeProjectState)
signal project_completed(company_id: StringName, project: UpgradeProjectState)

const MINUTES_PER_DAY: int = 1440
const ACQUISITION_TIER: int = 1
const SALE_REFUND_RATE: float = 0.35
const DECOMMISSION_REFUND_RATE: float = 0.20
const CANCEL_REFUND_RATE: float = 0.50
const VISUAL_SCENE: String = "res://scenes/world/HeadquartersVisual.tscn"

var _tiers: Dictionary = {}
var _departments: Dictionary = {}
var _visuals: Dictionary = {}
var _initialized: bool = false


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_build_definitions()
	var loaded: SaveGame = CompanyManager.loaded_save
	if loaded != null:
		CapabilityRegistry.restore_persistent_sources(loaded.capability_sources)
	for company: CompanyState in CompanyManager.companies:
		_ensure_state(company, loaded)
		_refresh_capabilities(company)
	if not EconomyManager.daily_cost_providers.has(_charge_daily_upkeep):
		EconomyManager.daily_cost_providers.append(_charge_daily_upkeep)
	GameClock.minute_ticked.connect(_on_minute_ticked)
	_sync_all_visuals.call_deferred()
	_post_migration_notice.call_deferred()


func state_for(company_id: StringName) -> HeadquartersState:
	var company: CompanyState = CompanyManager.company(company_id)
	return company.headquarters if company != null else null


func tier_def(tier: int) -> HeadquartersTierDef:
	return _tiers.get(tier)


func department_def(department_id: StringName) -> DepartmentDef:
	return _departments.get(department_id)


func department_defs() -> Array[DepartmentDef]:
	var result: Array[DepartmentDef] = []
	for def_variant: Variant in _departments.values():
		result.append(def_variant as DepartmentDef)
	result.sort_custom(func(a: DepartmentDef, b: DepartmentDef) -> bool:
		return a.display_name < b.display_name)
	return result


func slots_for(company_id: StringName) -> int:
	var state: HeadquartersState = state_for(company_id)
	var definition: HeadquartersTierDef = tier_def(state.tier) if state != null else null
	return definition.department_slots if definition != null else 0


func capacity_used(company_id: StringName, include_project: bool = true) -> int:
	var state: HeadquartersState = state_for(company_id)
	if state == null:
		return 0
	var used: int = 0
	for level_variant: Variant in state.departments.values():
		used += int(level_variant)
	if include_project and state.has_active_project():
		var project: UpgradeProjectState = state.active_project()
		if project.kind == &"department":
			used += 1
	return used


func upkeep_for(company_id: StringName) -> float:
	var state: HeadquartersState = state_for(company_id)
	if state == null or not state.is_active():
		return 0.0
	var definition: HeadquartersTierDef = tier_def(state.tier)
	var total: float = definition.base_upkeep if definition != null else 0.0
	for department_variant: Variant in state.departments:
		var department_id: StringName = department_variant
		var def: DepartmentDef = department_def(department_id)
		if def != null:
			total += def.upkeep_for(state.department_level(department_id))
	return total


func eligible_buildings(company_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for info_variant: Variant in CityData.buildings.values():
		var info: Dictionary = info_variant
		if String(info.get("type", "")) != "office":
			continue
		var building_id: int = int(info.get("id", -1))
		if _building_available(company_id, building_id):
			result.append(info)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var district_compare: int = String(a.get("district", "")).naturalnocasecmp_to(String(b.get("district", "")))
		return int(a.get("id", 0)) < int(b.get("id", 0)) if district_compare == 0 else district_compare < 0)
	return result


func start_acquisition_cmd(company_id: StringName, building_id: int) -> CommandResult:
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null:
		return CommandResult.fail(&"prerequisite", "Company not found.")
	var state: HeadquartersState = company.headquarters
	if state == null:
		_ensure_state(company, CompanyManager.loaded_save)
		state = company.headquarters
	if state.is_active():
		return CommandResult.fail(&"prerequisite", "This company already has a headquarters.")
	if state.has_active_project():
		return CommandResult.fail(&"project_active", "Finish or cancel the active headquarters project first.")
	if company.restaurants.is_empty():
		return CommandResult.fail(&"prerequisite", "Open a restaurant before establishing headquarters.")
	if not _building_available(company_id, building_id):
		return CommandResult.fail(&"building_reserved", "Choose an available office building.")
	var definition: HeadquartersTierDef = tier_def(ACQUISITION_TIER)
	if not company.can_afford(definition.project_cost):
		return CommandResult.fail(&"insufficient_funds", "Office construction requires $%d." % int(definition.project_cost))
	state.building_id = building_id
	return _start_project(company, &"acquisition", &"office", 0, ACQUISITION_TIER,
		building_id, definition.project_cost, definition.project_minutes)


func start_tier_upgrade_cmd(company_id: StringName) -> CommandResult:
	var company: CompanyState = CompanyManager.company(company_id)
	var state: HeadquartersState = company.headquarters if company != null else null
	if state == null or not state.is_active():
		return CommandResult.fail(&"prerequisite", "Establish a headquarters first.")
	if state.has_active_project():
		return CommandResult.fail(&"project_active", "Finish or cancel the active headquarters project first.")
	var target_tier: int = state.tier + 1
	var definition: HeadquartersTierDef = tier_def(target_tier)
	if definition == null:
		return CommandResult.fail(&"feature_unavailable", "Tier 3 is the current headquarters maximum.")
	if company.restaurants.size() < definition.min_restaurants:
		return CommandResult.fail(&"prerequisite",
			"Grow to %d restaurants before upgrading to %s." % [definition.min_restaurants, definition.display_name])
	if not company.can_afford(definition.project_cost):
		return CommandResult.fail(&"insufficient_funds",
			"%s construction requires $%d." % [definition.display_name, int(definition.project_cost)])
	return _start_project(company, &"tier", StringName(definition.scene_variant), state.tier,
		target_tier, state.building_id, definition.project_cost, definition.project_minutes)


func start_department_project_cmd(company_id: StringName, department_id: StringName) -> CommandResult:
	var company: CompanyState = CompanyManager.company(company_id)
	var state: HeadquartersState = company.headquarters if company != null else null
	if state == null or not state.is_active():
		return CommandResult.fail(&"prerequisite", "Establish a headquarters first.")
	if state.has_active_project():
		return CommandResult.fail(&"project_active", "Finish or cancel the active headquarters project first.")
	var definition: DepartmentDef = department_def(department_id)
	if definition == null or not definition.available:
		var unavailable: String = definition.unavailable_reason if definition != null else "Department not available."
		return CommandResult.fail(&"feature_unavailable", unavailable)
	var old_level: int = state.department_level(department_id)
	var new_level: int = old_level + 1
	if new_level > definition.max_level():
		return CommandResult.fail(&"feature_unavailable", "%s is already at its current maximum." % definition.display_name)
	var required_tier: int = definition.required_tier_for(new_level)
	if state.tier < required_tier:
		return CommandResult.fail(&"prerequisite",
			"%s Level %d requires headquarters Tier %d." % [definition.display_name, new_level, required_tier])
	if capacity_used(company_id, false) + 1 > slots_for(company_id):
		return CommandResult.fail(&"capacity_full", "No department capacity remains at this headquarters tier.")
	var cost: float = definition.cost_for(new_level)
	if not company.can_afford(cost):
		return CommandResult.fail(&"insufficient_funds",
			"%s Level %d requires $%d." % [definition.display_name, new_level, int(cost)])
	return _start_project(company, &"department", department_id, old_level, new_level,
		state.building_id, cost, definition.minutes_for(new_level))


func cancel_project_cmd(company_id: StringName, project_id: int) -> CommandResult:
	var company: CompanyState = CompanyManager.company(company_id)
	var state: HeadquartersState = company.headquarters if company != null else null
	var project: UpgradeProjectState = state.active_project() if state != null else null
	if project == null or project.id != project_id:
		return CommandResult.fail(&"prerequisite", "Headquarters project not found.")
	var refund: float = project.paid_amount * (1.0 - project.progress_at(GameClock.total_minutes())) * CANCEL_REFUND_RATE
	if refund > 0.0:
		company.transact(&"hq_project_refund", refund)
	if project.kind == &"acquisition":
		state.building_id = -1
	state.active_projects.clear()
	_recalculate_capacity(state)
	_refresh_capabilities(company)
	_sync_visual(company)
	headquarters_changed.emit(company_id)
	return CommandResult.good(refund)


func decommission_department_cmd(company_id: StringName, department_id: StringName) -> CommandResult:
	var company: CompanyState = CompanyManager.company(company_id)
	var state: HeadquartersState = company.headquarters if company != null else null
	if state == null or not state.is_active():
		return CommandResult.fail(&"prerequisite", "Establish a headquarters first.")
	if state.has_active_project():
		return CommandResult.fail(&"project_active", "Finish or cancel the active headquarters project first.")
	var level: int = state.department_level(department_id)
	var definition: DepartmentDef = department_def(department_id)
	if level <= 0 or definition == null:
		return CommandResult.fail(&"prerequisite", "That department is not installed.")
	var invested: float = 0.0
	for index: int in level:
		invested += definition.cost_for(index + 1)
	var refund: float = invested * DECOMMISSION_REFUND_RATE
	company.transact(&"hq_decommission_refund", refund)
	state.departments.erase(department_id)
	state.capital_invested = maxf(0.0, state.capital_invested - invested)
	_recalculate_capacity(state)
	_refresh_capabilities(company)
	headquarters_changed.emit(company_id)
	return CommandResult.good(refund)


func sell_headquarters_cmd(company_id: StringName) -> CommandResult:
	var company: CompanyState = CompanyManager.company(company_id)
	var state: HeadquartersState = company.headquarters if company != null else null
	if state == null or not state.is_active():
		return CommandResult.fail(&"prerequisite", "This company has no headquarters to sell.")
	if state.has_active_project():
		return CommandResult.fail(&"project_active", "Finish or cancel the active headquarters project first.")
	var refund: float = state.capital_invested * SALE_REFUND_RATE
	if refund > 0.0:
		company.transact(&"hq_sale", refund)
	state.building_id = -1
	state.tier = 0
	state.departments.clear()
	state.capacity_used = 0
	state.capital_invested = 0.0
	state.migration_state = &"sold"
	_refresh_capabilities(company)
	_sync_visual(company)
	headquarters_changed.emit(company_id)
	return CommandResult.good(refund)


func warehouse_limit(company_id: StringName) -> int:
	var basic: int = 1 if CapabilityRegistry.has(company_id, &"supply.warehouses") else 0
	return basic + CapabilityRegistry.capacity(company_id, &"procurement.warehouse_count")


func analytics_depth(company_id: StringName) -> int:
	return CapabilityRegistry.level(company_id, &"analytics.report_depth")


func operations_depth(company_id: StringName) -> int:
	return CapabilityRegistry.level(company_id, &"operations.portfolio_alerts")


func next_unlock_text(company_id: StringName) -> String:
	var state: HeadquartersState = state_for(company_id)
	if state == null or state.tier == 0:
		return "Establish an Office to unlock company-wide planning."
	var next: HeadquartersTierDef = tier_def(state.tier + 1)
	if next == null:
		return "Corporate Center reached — specialize through departments."
	return "Tier %d unlocks %d department slots and %s." % [
		next.tier, next.department_slots, next.description]


func project_label(project: UpgradeProjectState) -> String:
	if project == null:
		return ""
	if project.kind == &"department":
		var definition: DepartmentDef = department_def(project.target_id)
		return "%s Level %d" % [definition.display_name if definition != null else project.target_id, project.to_level]
	var definition: HeadquartersTierDef = tier_def(project.to_level)
	return definition.display_name if definition != null else "Headquarters project"


func _start_project(
	company: CompanyState,
	kind: StringName,
	target_id: StringName,
	from_level: int,
	to_level: int,
	building_id: int,
	cost: float,
	duration: int
) -> CommandResult:
	var state: HeadquartersState = company.headquarters
	company.transact(&"hq_construction", -cost)
	var project: UpgradeProjectState = UpgradeProjectState.new()
	project.id = state.next_project_id
	state.next_project_id += 1
	project.kind = kind
	project.target_id = target_id
	project.target_building_id = building_id
	project.from_level = from_level
	project.to_level = to_level
	project.start_minute = GameClock.total_minutes()
	project.end_minute = project.start_minute + duration
	project.paid_amount = cost
	state.active_projects.append(project)
	_recalculate_capacity(state)
	project_started.emit(company.id, project)
	headquarters_changed.emit(company.id)
	_sync_visual(company)
	return CommandResult.good(project)


func _complete_project(company: CompanyState, project: UpgradeProjectState) -> void:
	if project.completion_applied:
		return
	project.completion_applied = true
	var state: HeadquartersState = company.headquarters
	match project.kind:
		&"acquisition", &"tier":
			state.tier = project.to_level
		&"department":
			state.departments[project.target_id] = project.to_level
	state.capital_invested += project.paid_amount
	state.active_projects.erase(project)
	state.migration_state = &"current"
	_recalculate_capacity(state)
	_refresh_capabilities(company)
	_sync_visual(company)
	company.log_move(GameClock.day, "news", "%s completed %s." % [company.display_name, project_label(project)])
	project_completed.emit(company.id, project)
	headquarters_changed.emit(company.id)


func _on_minute_ticked(_day: int, _hour: int, _minute: int) -> void:
	var now: int = GameClock.total_minutes()
	for company: CompanyState in CompanyManager.companies:
		var state: HeadquartersState = company.headquarters
		var project: UpgradeProjectState = state.active_project() if state != null else null
		if project != null and not project.paused and now >= project.end_minute:
			_complete_project(company, project)


func _charge_daily_upkeep(company: CompanyState, _day: int) -> void:
	var upkeep: float = upkeep_for(company.id)
	if upkeep > 0.0:
		company.transact(&"hq_upkeep", -upkeep)


func _ensure_state(company: CompanyState, loaded: SaveGame) -> void:
	if company.headquarters != null:
		company.headquarters.company_id = company.id
		_recalculate_capacity(company.headquarters)
		return
	var state: HeadquartersState = HeadquartersState.new()
	state.company_id = company.id
	if loaded != null and loaded.save_version < 6:
		state.migration_state = &"legacy_v5_founder"
		state.migration_notice_pending = company.is_player
	elif loaded != null:
		state.migration_state = &"repaired_v6"
	else:
		state.migration_state = &"new_game"
	company.headquarters = state


func _recalculate_capacity(state: HeadquartersState) -> void:
	var used: int = 0
	for level_variant: Variant in state.departments.values():
		used += int(level_variant)
	state.capacity_used = used


func _refresh_capabilities(company: CompanyState) -> void:
	var state: HeadquartersState = company.headquarters
	var grants: Dictionary = {}
	var tier_definition: HeadquartersTierDef = tier_def(state.tier)
	if tier_definition != null:
		_merge_grants(grants, tier_definition.capability_grants)
	for department_variant: Variant in state.departments:
		var department_id: StringName = department_variant
		var definition: DepartmentDef = department_def(department_id)
		if definition != null:
			_merge_grants(grants, definition.grants_for(state.department_level(department_id)))
	var source_id: StringName = StringName("headquarters:%s" % company.id)
	CapabilityRegistry.set_source(company.id, source_id, grants)
	CapabilityRegistry.set_lock_hints(company.id, source_id, _capability_hints())


func _merge_grants(target: Dictionary, additions: Dictionary) -> void:
	for cap_variant: Variant in additions:
		var cap_id: StringName = cap_variant
		if CapabilityRegistry.ADDITIVE_CAPS.has(cap_id):
			target[cap_id] = int(target.get(cap_id, 0)) + int(additions[cap_id])
		else:
			target[cap_id] = maxi(int(target.get(cap_id, 0)), int(additions[cap_id]))


func _capability_hints() -> Dictionary:
	return {
		&"marketing.campaign_slots": "Build the Marketing department for additional campaign capacity.",
		&"marketing.billboards": "Build Marketing Level 2 in a Tier 2 headquarters.",
		&"marketing.citywide": "Build Marketing Level 3 in a Tier 3 headquarters.",
		&"procurement.warehouse_count": "Build Procurement in a Tier 3 headquarters.",
		&"analytics.report_depth": "Build Analytics in a Tier 2 headquarters.",
		&"operations.portfolio_alerts": "Build Operations in a Tier 1 headquarters.",
		&"workforce.training_slots": "Build People Ops to train more staff at once.",
		&"management.branch_managers": "Build People Ops to delegate more branches to managers.",
		&"security.guard_capacity": "Security specialization is not installed in this build.",
		&"crime.crew_capacity": "Underworld specialization is disabled in this scenario.",
	}


func _building_available(company_id: StringName, building_id: int) -> bool:
	var info: Dictionary = CityData.get_building(building_id)
	if info.is_empty() or String(info.get("type", "")) != "office":
		return false
	for company: CompanyState in CompanyManager.companies:
		var state: HeadquartersState = company.headquarters
		if state != null and state.building_id == building_id and company.id != company_id:
			return false
	if RestaurantManager.by_building.has(building_id):
		return false
	for warehouse: WarehouseState in SupplyManager.warehouses:
		if warehouse.building_id == building_id:
			return false
	return true


func _sync_all_visuals() -> void:
	for company: CompanyState in CompanyManager.companies:
		_sync_visual(company)


func _sync_visual(company: CompanyState) -> void:
	var existing: Node = _visuals.get(company.id)
	var state: HeadquartersState = company.headquarters
	if state == null or state.building_id < 0:
		if is_instance_valid(existing):
			existing.queue_free()
		_visuals.erase(company.id)
		return
	if not is_instance_valid(existing):
		var scene: PackedScene = load(VISUAL_SCENE)
		if scene == null or get_tree().current_scene == null:
			return
		existing = scene.instantiate()
		get_tree().current_scene.add_child(existing)
		_visuals[company.id] = existing
	if existing.has_method("setup"):
		existing.setup(state, company)


func _post_migration_notice() -> void:
	var state: HeadquartersState = state_for(&"player")
	if state != null and state.migration_notice_pending:
		state.migration_notice_pending = false
		EconomyManager.post_message("info",
			"Headquarters progression is now available. Existing chain unlocks remain active.")


func _build_definitions() -> void:
	_tiers.clear()
	_departments.clear()
	_add_tier(0, "Founder", 0, 0.0, 0, 0.0, 0, &"founder",
		{&"management.branch_managers": 1, &"workforce.training_slots": 1},
		"hands-on restaurant management")
	_add_tier(1, "Office", 1, 6000.0, 2 * MINUTES_PER_DAY, 80.0, 1, &"office",
		{&"headquarters.dashboard": 1}, "company dashboard and one department")
	_add_tier(2, "Regional HQ", 2, 12000.0, 4 * MINUTES_PER_DAY, 160.0, 3, &"regional",
		{&"headquarters.regional": 1}, "regional coordination")
	_add_tier(3, "Corporate Center", 5, 18000.0, 6 * MINUTES_PER_DAY, 300.0, 5, &"corporate",
		{&"headquarters.corporate": 1}, "corporate-scale specialization")
	_add_department(&"operations", "Operations", "Portfolio alerts and company-wide operating detail.", &"gear",
		[1, 2], [2500.0, 4000.0], [2 * MINUTES_PER_DAY, 3 * MINUTES_PER_DAY],
		[50.0, 70.0], [
			{&"operations.portfolio_alerts": 1},
			{&"operations.portfolio_alerts": 2},
		])
	_add_department(&"marketing", "Marketing", "Coordinate more campaigns and larger media.", &"megaphone",
		[1, 2, 3], [3500.0, 5000.0, 7500.0],
		[3 * MINUTES_PER_DAY, 4 * MINUTES_PER_DAY, 5 * MINUTES_PER_DAY],
		[50.0, 90.0, 150.0], [
			{&"marketing.campaign_slots": 1},
			{&"marketing.campaign_slots": 2, &"marketing.billboards": 1},
			{&"marketing.campaign_slots": 4, &"marketing.billboards": 1, &"marketing.citywide": 1},
		])
	_add_department(&"analytics", "Analytics", "Reveal deeper company and competitor comparisons.", &"chart_bars",
		[2, 3], [4500.0, 6500.0], [3 * MINUTES_PER_DAY, 4 * MINUTES_PER_DAY],
		[50.0, 90.0], [
			{&"analytics.report_depth": 1},
			{&"analytics.report_depth": 2},
		])
	_add_department(&"procurement", "Procurement", "Expand the central warehouse network.", &"truck",
		[3, 3], [6000.0, 8500.0], [4 * MINUTES_PER_DAY, 5 * MINUTES_PER_DAY],
		[90.0, 150.0], [
			{&"procurement.warehouse_count": 1},
			{&"procurement.warehouse_count": 2},
		])
	_add_department(&"people", "People Ops", "Delegate more branches to managers and train more staff at once.", &"people",
		[1, 2, 3], [3000.0, 5000.0, 7500.0],
		[2 * MINUTES_PER_DAY, 3 * MINUTES_PER_DAY, 4 * MINUTES_PER_DAY],
		[50.0, 90.0, 150.0], [
			{&"management.branch_managers": 2, &"workforce.training_slots": 1},
			{&"management.branch_managers": 4, &"workforce.training_slots": 2},
			{&"management.branch_managers": 8, &"workforce.training_slots": 3},
		])


func _add_tier(
	tier: int,
	display_name: String,
	min_restaurants: int,
	cost: float,
	minutes: int,
	upkeep: float,
	slots: int,
	variant: StringName,
	grants: Dictionary,
	description: String
) -> void:
	var definition: HeadquartersTierDef = HeadquartersTierDef.new()
	definition.tier = tier
	definition.display_name = display_name
	definition.min_restaurants = min_restaurants
	definition.project_cost = cost
	definition.project_minutes = minutes
	definition.base_upkeep = upkeep
	definition.department_slots = slots
	definition.scene_variant = variant
	definition.capability_grants = grants
	definition.description = description
	_tiers[tier] = definition


func _add_department(
	id: StringName,
	display_name: String,
	description: String,
	icon_name: StringName,
	required_tiers: Array[int],
	costs: Array[float],
	minutes: Array[int],
	upkeep: Array[float],
	grants: Array[Dictionary]
) -> void:
	var definition: DepartmentDef = DepartmentDef.new()
	definition.id = id
	definition.display_name = display_name
	definition.description = description
	definition.icon_name = icon_name
	definition.required_tiers = required_tiers
	definition.project_costs = costs
	definition.project_minutes = minutes
	definition.total_upkeep = upkeep
	definition.grants_by_level = grants
	_departments[id] = definition
