extends Node
## CrimeManager (feature 12) — the optional underworld strategy layer:
## criminal crews, sabotage operations against rival branches, defender
## security/alert/insurance, and a lightweight police heat/evidence stub
## that feature 13 (government) will absorb.
##
## Discipline (mirrors AwardsManager): idempotent initialize() driven from
## city.gd (never _ready — --script mode skips it); pure math lives in
## scripts/crime/*; every cash movement goes through CompanyState.transact;
## operations freeze seed_day+uid at launch and resolve once
## (outcome_applied) via WorkforceRng streams, so save/load replays
## identically. Day-close work hooks AnalyticsManager.buckets_closed;
## op phases advance on GameClock.minute_ticked with absolute
## total_minutes() diffs.
##
## NOTE: not a global identifier until the editor restarts — reach it via
## get_node_or_null("CrimeManager") on the tree root.

signal crew_changed(company_id: StringName)
signal operation_updated(operation: CrimeOperationState)
signal security_changed(building_id: int)
signal heat_changed(company_id: StringName)
signal incident_reported(building_id: int, incident: Dictionary)
signal extortion_updated(company_id: StringName)
## Live detection of a hostile op at a PLAYER branch — HUD shows the paused
## police-incident dialog.
signal police_incident(operation: CrimeOperationState)
signal police_dispatched(building_id: int, eta_minutes: float)

const ACTIONS_DIR: String = "res://data/crime_actions"
const SCHEMA_VERSION: int = 1
const EFFECT_WINDOW_MINUTES: int = 15
const CREW_FIRST_NAMES: Array[String] = [
	"Sal", "Vinnie", "Rocco", "Lena", "Marco", "Gia", "Tony", "Nadia", "Enzo", "Rita",
]
const CREW_NICKNAMES: Array[String] = [
	"the Quiet", "Two-Fingers", "Firenze", "the Ghost", "Palermo", "Nightshade",
	"the Weasel", "Marzipan",
]
const ROLE_WAGES: Dictionary = {&"courier": 30.0, &"punk": 40.0, &"enforcer": 75.0, &"gangster": 140.0}
const ROLE_MIN_TIER: Dictionary = {&"courier": 1, &"punk": 1, &"enforcer": 2, &"gangster": 3}

var actions: Dictionary = {}  ## id -> CrimeActionDef
var agents: Array[CriminalAgentState] = []
var operations: Array[CrimeOperationState] = []
var security_states: Dictionary = {}  ## building_id -> SecurityState
var heat_states: Dictionary = {}  ## company_id -> CompanyHeatState
## intel[attacker][target_company] = last valid day (int).
var intel: Dictionary = {}
## cooldowns["attacker|action|target"] = first day usable again.
var cooldowns: Dictionary = {}
var next_op_uid: int = 1
var next_incident_uid: int = 1

var resolver: CrimeResolver = CrimeResolver.new()
var security_math: SecurityService = SecurityService.new()
var heat_math: HeatService = HeatService.new()

var _precincts: Array[Vector3] = []
var _analytics: Node = null
var _initialized: bool = false


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	resolver.configure(EconomyManager.tuning_value)
	security_math.configure(EconomyManager.tuning_value)
	heat_math.configure(EconomyManager.tuning_value)
	_load_actions()
	_analytics = _autoload_node("AnalyticsManager")
	var save: SaveGame = CompanyManager.loaded_save
	if save != null:
		restore_from_save(save)
	_ensure_states()
	_pick_precincts()
	EconomyManager.daily_cost_providers.append(_charge_daily)
	if not GameClock.minute_ticked.is_connected(_on_minute_ticked):
		GameClock.minute_ticked.connect(_on_minute_ticked)
	if _analytics != null and _analytics.has_signal("buckets_closed") \
			and not _analytics.is_connected("buckets_closed", _on_buckets_closed):
		_analytics.connect("buckets_closed", _on_buckets_closed)
	if not CompanyManager.company_registered.is_connected(_on_company_registered):
		CompanyManager.company_registered.connect(_on_company_registered)
	if not RestaurantManager.restaurant_purchased.is_connected(_on_restaurant_purchased):
		RestaurantManager.restaurant_purchased.connect(_on_restaurant_purchased)


# --- Mode / gating ---------------------------------------------------------

## &"off" | &"standard" | &"ruthless". Scenario systems gate + free-play
## wizard choice, resolved by GameSetup (defensive: helper lands with the
## wizard work, default standard).
func crime_mode() -> StringName:
	var setup: Node = _autoload_node("GameSetup")
	if setup == null:
		return &"standard"
	if setup.has_method("crime_mode"):
		return setup.call("crime_mode")
	return &"standard"


func enabled() -> bool:
	return crime_mode() != &"off"


## Highest action tier the company's Underworld department allows (0 = none).
func action_tier(company_id: StringName) -> int:
	return CapabilityRegistry.level(company_id, &"crime.action_tier")


func crew_capacity(company_id: StringName) -> int:
	return CapabilityRegistry.capacity(company_id, &"crime.crew_capacity")


# --- Catalog / crew queries ------------------------------------------------

func action(action_id: StringName) -> CrimeActionDef:
	return actions.get(action_id)


## Actions for the underworld screen: every catalog action visible in this
## crime mode, each with availability {def, ok, reason}.
func actions_for(company_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mode: StringName = crime_mode()
	var tier: int = action_tier(company_id)
	for action_id: StringName in actions:
		var def: CrimeActionDef = actions[action_id]
		if not def.allowed_in_mode(mode):
			continue
		var ok: bool = true
		var reason: String = ""
		if def.tier > tier:
			ok = false
			reason = "Needs Underworld department level %d." % def.tier
		elif _pick_agents(company_id, def).size() < _roles_needed(def):
			ok = false
			reason = "Crew unavailable — need %s." % _roles_label(def)
		out.append({"def": def, "ok": ok, "reason": reason})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: CrimeActionDef = a["def"]
		var db: CrimeActionDef = b["def"]
		if da.tier != db.tier:
			return da.tier < db.tier
		return String(da.id) < String(db.id))
	return out


func crew_of(company_id: StringName) -> Array[CriminalAgentState]:
	var out: Array[CriminalAgentState] = []
	for agent: CriminalAgentState in agents:
		if agent.company_id == company_id:
			out.append(agent)
	return out


## Deterministic hiring market, refreshed every market_refresh_days.
func market_candidates(company_id: StringName) -> Array[Dictionary]:
	var refresh: int = maxi(1, int(_tuning("crime.crew.market_refresh_days", 4)))
	var market_day: int = GameClock.day - (GameClock.day % refresh)
	var rng: RandomNumberGenerator = WorkforceRng.make(&"crime_market", market_day, [company_id])
	var tier: int = maxi(1, action_tier(company_id))
	var out: Array[Dictionary] = []
	for i: int in range(4):
		var role: StringName = _market_role(rng, tier)
		var candidate_name: String = "%s %s" % [
			CREW_FIRST_NAMES[rng.randi_range(0, CREW_FIRST_NAMES.size() - 1)],
			CREW_NICKNAMES[rng.randi_range(0, CREW_NICKNAMES.size() - 1)],
		]
		var skill: float = clampf(rng.randf_range(0.25, 0.55) + 0.12 * float(tier - 1), 0.1, 0.95)
		var wage: float = float(ROLE_WAGES.get(role, 40.0)) * (0.8 + skill)
		if _already_hired(company_id, candidate_name):
			continue
		out.append({
			"role": role, "name": candidate_name, "skill": skill,
			"wage": snappedf(wage, 1.0),
			"hire_fee": snappedf(wage * 6.0, 10.0),
		})
	return out


func hire_agent_cmd(company_id: StringName, candidate: Dictionary) -> CommandResult:
	if not enabled():
		return CommandResult.fail(&"crime_disabled", "The underworld is closed in this game.")
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null:
		return CommandResult.fail(&"unknown_company", "Unknown company.")
	if crew_of(company_id).size() >= crew_capacity(company_id):
		return CommandResult.fail(&"crew_full", CapabilityRegistry.explain(company_id, &"crime.crew_capacity"))
	var role: StringName = StringName(String(candidate.get("role", "punk")))
	if int(ROLE_MIN_TIER.get(role, 1)) > action_tier(company_id):
		return CommandResult.fail(&"role_locked", "That crew type needs a bigger back room.")
	var fee: float = float(candidate.get("hire_fee", 0.0))
	if not company.can_afford(fee):
		return CommandResult.fail(&"cannot_afford", "Not enough cash for the signing fee.")
	company.transact(&"underworld_wages", -fee)
	var agent: CriminalAgentState = CriminalAgentState.new()
	agent.uid = next_incident_uid
	next_incident_uid += 1
	agent.company_id = company_id
	agent.role = role
	agent.display_name = String(candidate.get("name", "Nobody"))
	agent.skill = float(candidate.get("skill", 0.4))
	agent.daily_wage = float(candidate.get("wage", 40.0))
	agent.hired_day = GameClock.day
	agents.append(agent)
	crew_changed.emit(company_id)
	return CommandResult.good({"agent": agent})


func dismiss_agent_cmd(company_id: StringName, agent_uid: int) -> CommandResult:
	for i: int in range(agents.size()):
		var agent: CriminalAgentState = agents[i]
		if agent.company_id != company_id or agent.uid != agent_uid:
			continue
		if agent.assignment_op_uid >= 0:
			return CommandResult.fail(&"on_assignment", "That crew member is out on a job.")
		agents.remove_at(i)
		crew_changed.emit(company_id)
		return CommandResult.good({})
	return CommandResult.fail(&"unknown_agent", "No such crew member.")


# --- Operations ------------------------------------------------------------

func ops_of(company_id: StringName) -> Array[CrimeOperationState]:
	var out: Array[CrimeOperationState] = []
	for op: CrimeOperationState in operations:
		if op.attacker_company == company_id:
			out.append(op)
	return out


func live_ops_against(company_id: StringName) -> Array[CrimeOperationState]:
	var out: Array[CrimeOperationState] = []
	for op: CrimeOperationState in operations:
		if op.target_company == company_id and op.is_live():
			out.append(op)
	return out


func operation_by_uid(op_uid: int) -> CrimeOperationState:
	for op: CrimeOperationState in operations:
		if op.uid == op_uid:
			return op
	return null


## Deterministic pre-launch review for the UI rail and AI judgment.
func preview_operation(company_id: StringName, action_id: StringName, target_building: int) -> Dictionary:
	var def: CrimeActionDef = action(action_id)
	if def == null:
		return {"ok": false, "reason": "Unknown action."}
	var check: CommandResult = _can_launch(company_id, def, target_building)
	var target_company: StringName = _target_company_for(def, target_building)
	var ctx: Dictionary = _resolve_ctx(company_id, def, target_building)
	var odds: Dictionary = resolver.preview(def, ctx)
	var has_intel: bool = intel_level(company_id, target_company) > 0.0
	return {
		"ok": check.ok,
		"reason": "" if check.ok else check.message,
		"cost": def.cost,
		"travel_minutes": _travel_minutes(company_id, target_building),
		"success_chance": float(odds["success_chance"]),
		"detection_chance": float(odds["detection_chance"]),
		"evidence_risk": float(odds["evidence_risk"]),
		"heat_gain": float(odds["heat_gain"]),
		"intel_level": intel_level(company_id, target_company),
		"uncertain": not has_intel,
		"known_defenses": _known_defenses(company_id, target_company, target_building),
		"collateral": _collateral_text(def),
	}


func launch_operation_cmd(company_id: StringName, action_id: StringName, target_building: int) -> CommandResult:
	var def: CrimeActionDef = action(action_id)
	if def == null:
		return CommandResult.fail(&"unknown_action", "Unknown action.")
	var check: CommandResult = _can_launch(company_id, def, target_building)
	if not check.ok:
		return check
	var company: CompanyState = CompanyManager.company(company_id)
	company.transact(&"crime_ops", -def.cost)
	var op: CrimeOperationState = CrimeOperationState.new()
	op.uid = next_op_uid
	next_op_uid += 1
	op.action_id = def.id
	op.attacker_company = company_id
	op.target_company = _target_company_for(def, target_building)
	op.target_building = target_building
	op.phase = &"planning"
	var now: int = GameClock.total_minutes()
	op.start_minute = now
	op.phase_start_minute = now
	op.phase_end_minute = now + maxi(1, def.prep_minutes)
	op.travel_minutes = _travel_minutes(company_id, target_building)
	op.launched_day = GameClock.day
	op.seed_day = GameClock.day
	var picked: Array[CriminalAgentState] = _pick_agents(company_id, def)
	for agent: CriminalAgentState in picked:
		agent.assignment_op_uid = op.uid
		op.agent_uids.append(agent.uid)
	operations.append(op)
	cooldowns[_cooldown_key(company_id, def.id, target_building)] = GameClock.day + def.cooldown_days
	company.log_move(GameClock.day, &"crime", "Underworld op: %s" % def.display_name)
	var setup: Node = _autoload_node("GameSetup")
	if setup != null and setup.has_method("observe_action"):
		setup.call("observe_action", &"crime.launch", {"action": String(def.id), "tier": def.tier})
	crew_changed.emit(company_id)
	operation_updated.emit(op)
	return CommandResult.good({"operation": op})


func cancel_operation_cmd(company_id: StringName, op_uid: int) -> CommandResult:
	var op: CrimeOperationState = operation_by_uid(op_uid)
	if op == null or op.attacker_company != company_id:
		return CommandResult.fail(&"unknown_operation", "No such operation.")
	if not op.can_cancel():
		return CommandResult.fail(&"too_late", "The crew is already inside — no way to call it off.")
	var def: CrimeActionDef = action(op.action_id)
	if op.phase == &"planning" and def != null:
		CompanyManager.company(company_id).transact(&"crime_ops", def.cost * 0.5)
	op.phase = &"cancelled"
	_release_agents(op)
	crew_changed.emit(company_id)
	operation_updated.emit(op)
	return CommandResult.good({})


# --- Defender: security, insurance, counterintel, extortion ----------------

func security_for(building_id: int) -> SecurityState:
	if security_states.has(building_id):
		return security_states[building_id]
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null:
		return null
	var state: SecurityState = SecurityState.new()
	state.building_id = building_id
	state.company_id = rest.company_id
	security_states[building_id] = state
	return state


func heat_for(company_id: StringName) -> CompanyHeatState:
	if heat_states.has(company_id):
		return heat_states[company_id]
	var state: CompanyHeatState = CompanyHeatState.new()
	state.company_id = company_id
	heat_states[company_id] = state
	return state


func guard_effect(building_id: int) -> float:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null:
		return 0.0
	var staff_manager: Node = _autoload_node("StaffManager")
	if staff_manager == null or not staff_manager.has_method("role_effects_for"):
		return 0.0
	var effects: Dictionary = staff_manager.call("role_effects_for", rest)
	return clampf(float(effects.get(&"security", 0.0)), 0.0, 1.0)


func security_score_for(building_id: int) -> float:
	var state: SecurityState = security_for(building_id)
	if state == null:
		return 0.0
	return security_math.security_score(state, guard_effect(building_id))


## Demand-hook penalty (crime debuffs + lockdown opportunity cost), 0..0.6.
## DemandManager subtracts this in _best_offer next to the marketing bonus.
func attraction_penalty(building_id: int) -> float:
	if not enabled() or not security_states.has(building_id):
		return 0.0
	var state: SecurityState = security_states[building_id]
	var day: int = GameClock.day
	var penalty: float = state.effect_total(&"demand_debuff", day)
	penalty += state.effect_total(&"appeal_debuff", day) * 0.6
	penalty += security_math.alert_penalty(state)
	return clampf(penalty, 0.0, 0.6)


func upgrade_security_cmd(company_id: StringName, building_id: int) -> CommandResult:
	var state: SecurityState = _owned_security(company_id, building_id)
	if state == null:
		return CommandResult.fail(&"not_owner", "That is not your branch.")
	if state.equipment_level >= 3:
		return CommandResult.fail(&"maxed", "Security is already fully equipped.")
	var costs: Array = _tuning("crime.security.equipment_costs", [400.0, 900.0, 1600.0])
	var cost: float = float(costs[mini(state.equipment_level, costs.size() - 1)])
	var company: CompanyState = CompanyManager.company(company_id)
	if not company.can_afford(cost):
		return CommandResult.fail(&"cannot_afford", "Not enough cash.")
	company.transact(&"security_upkeep", -cost)
	state.equipment_level += 1
	security_changed.emit(building_id)
	return CommandResult.good({"level": state.equipment_level})


func set_alert_cmd(company_id: StringName, building_id: int, level: StringName) -> CommandResult:
	var state: SecurityState = _owned_security(company_id, building_id)
	if state == null:
		return CommandResult.fail(&"not_owner", "That is not your branch.")
	if not SecurityService.ALERT_LEVELS.has(level):
		return CommandResult.fail(&"bad_level", "Unknown alert level.")
	state.alert_level = level
	state.alert_until_day = 0
	security_changed.emit(building_id)
	return CommandResult.good({})


func set_insurance_cmd(company_id: StringName, building_id: int, level: int) -> CommandResult:
	var state: SecurityState = _owned_security(company_id, building_id)
	if state == null:
		return CommandResult.fail(&"not_owner", "That is not your branch.")
	state.insurance_level = clampi(level, 0, 2)
	security_changed.emit(building_id)
	return CommandResult.good({})


## Sweep for plots against any of the company's branches. Deterministic per
## (company, op, day). Returns how many new plots were uncovered.
func counterintel_sweep_cmd(company_id: StringName) -> CommandResult:
	if not enabled():
		return CommandResult.fail(&"crime_disabled", "Nothing to sweep for.")
	var company: CompanyState = CompanyManager.company(company_id)
	var cost: float = float(_tuning("crime.security.sweep_cost", 350.0))
	if company == null or not company.can_afford(cost):
		return CommandResult.fail(&"cannot_afford", "Not enough cash.")
	company.transact(&"security_upkeep", -cost)
	var heat_state: CompanyHeatState = heat_for(company_id)
	var best_equipment: int = 0
	for rest: RestaurantState in _restaurants_of(company_id):
		var sec: SecurityState = security_for(rest.building_id)
		if sec != null:
			best_equipment = maxi(best_equipment, sec.equipment_level)
	var found: int = 0
	for op: CrimeOperationState in live_ops_against(company_id):
		if op.phase == &"effect" or op.phase == &"escape" or op.phase == &"investigation":
			continue
		if _plot_known(heat_state, op.uid):
			continue
		var probe: SecurityState = SecurityState.new()
		probe.equipment_level = best_equipment
		var chance: float = security_math.counterintel_chance(probe)
		var rng: RandomNumberGenerator = WorkforceRng.make(
			&"crime_detect", GameClock.day, [company_id, op.uid])
		if rng.randf() < chance:
			var def: CrimeActionDef = action(op.action_id)
			heat_state.known_plots.append({
				"op_uid": op.uid,
				"day_detected": GameClock.day,
				"action_id": String(op.action_id),
				"attacker_shown": "",
				"eta_day": op.launched_day + 1,
				"building_id": op.target_building,
			})
			found += 1
			_notify_company(company_id, "alert",
				"Counterintel: someone is planning %s against you." % (
					def.blurb if def != null else "an operation"))
	heat_changed.emit(company_id)
	return CommandResult.good({"found": found})


func pay_extortion_cmd(company_id: StringName, demand_uid: int) -> CommandResult:
	var heat_state: CompanyHeatState = heat_for(company_id)
	for row: Dictionary in heat_state.outstanding_extortion:
		if int(row.get("uid", -1)) != demand_uid or String(row.get("status", "")) != "open":
			continue
		var amount: float = float(row.get("amount", 0.0))
		var company: CompanyState = CompanyManager.company(company_id)
		if not company.can_afford(amount):
			return CommandResult.fail(&"cannot_afford", "Not enough cash to pay them off.")
		var kind: String = String(row.get("kind", "extortion"))
		company.transact(&"ransom_paid" if kind == "ransom" else &"extortion_paid", -amount)
		var attacker: CompanyState = CompanyManager.company(StringName(String(row.get("from_company", ""))))
		if attacker != null:
			attacker.transact(&"ransom_income" if kind == "ransom" else &"extortion_income", amount)
		row["status"] = "paid"
		if kind == "ransom":
			_release_hostage(row)
		extortion_updated.emit(company_id)
		return CommandResult.good({})
	return CommandResult.fail(&"unknown_demand", "No such demand.")


func refuse_extortion_cmd(company_id: StringName, demand_uid: int) -> CommandResult:
	return _close_extortion(company_id, demand_uid, "refused")


## Reporting hands the police evidence against the extorter.
func report_extortion_cmd(company_id: StringName, demand_uid: int) -> CommandResult:
	var heat_state: CompanyHeatState = heat_for(company_id)
	for row: Dictionary in heat_state.outstanding_extortion:
		if int(row.get("uid", -1)) != demand_uid or String(row.get("status", "")) != "open":
			continue
		var attacker_id: StringName = StringName(String(row.get("from_company", "")))
		var attacker_heat: CompanyHeatState = heat_for(attacker_id)
		attacker_heat.evidence.append({
			"incident_uid": -demand_uid,
			"victim_company": String(company_id),
			"action_id": "extortion_demand",
			"strength": 0.4,
			"day": GameClock.day,
		})
		attacker_heat.heat = clampf(attacker_heat.heat + 8.0, 0.0, 100.0)
		row["status"] = "reported"
		if String(row.get("kind", "extortion")) == "ransom":
			_release_hostage(row)
		heat_changed.emit(attacker_id)
		extortion_updated.emit(company_id)
		return CommandResult.good({})
	return CommandResult.fail(&"unknown_demand", "No such demand.")


## Repair/recovery for one incident: pays the repair cost, restores what the
## action broke (furniture, cleanliness, decals), and closes the report.
func repair_incident_cmd(company_id: StringName, building_id: int, incident_uid: int) -> CommandResult:
	var state: SecurityState = _owned_security(company_id, building_id)
	if state == null:
		return CommandResult.fail(&"not_owner", "That is not your branch.")
	var row: Dictionary = state.incident_by_uid(incident_uid)
	if row.is_empty() or not bool(row.get("active", false)):
		return CommandResult.fail(&"unknown_incident", "Nothing to repair.")
	var cost: float = float(row.get("repair_cost", 0.0))
	var company: CompanyState = CompanyManager.company(company_id)
	if not company.can_afford(cost):
		return CommandResult.fail(&"cannot_afford", "Not enough cash for repairs.")
	if cost > 0.0:
		company.transact(&"incident_repair", -cost)
	_restore_after_incident(state, row)
	row["active"] = false
	row["repaired_day"] = GameClock.day
	security_changed.emit(building_id)
	incident_reported.emit(building_id, row)
	return CommandResult.good({})


## Calling the police boosts the investigation and endangers escaping crews.
func call_police_cmd(company_id: StringName, building_id: int, incident_uid: int) -> CommandResult:
	var state: SecurityState = _owned_security(company_id, building_id)
	if state == null:
		return CommandResult.fail(&"not_owner", "That is not your branch.")
	var row: Dictionary = state.incident_by_uid(incident_uid)
	if row.is_empty():
		return CommandResult.fail(&"unknown_incident", "No such incident.")
	if bool(row.get("police_called", false)):
		return CommandResult.fail(&"already_called", "The police are already on it.")
	row["police_called"] = true
	var op: CrimeOperationState = operation_by_uid(int(row.get("op_uid", -1)))
	if op != null and op.is_live():
		op.outcome["police_called"] = true
		var def: CrimeActionDef = action(op.action_id)
		var tier: int = def.tier if def != null else 1
		row["investigation_until_day"] = GameClock.day + heat_math.investigation_duration(tier, true)
	# Government dispatches a real finite unit (and emits police_dispatched
	# itself); the legacy stub keeps working when the civic layer is off.
	var gov: Node = _gov_live()
	if gov != null:
		gov.call("dispatch_unit", building_id, &"respond")
	else:
		police_dispatched.emit(building_id, police_eta(building_id))
	_record_event(BusinessEvent.POLICE, company_id, building_id, 0.0, "Police called to %s" % _branch_name(building_id))
	security_changed.emit(building_id)
	return CommandResult.good({"eta": police_eta(building_id)})


## Demands this company has made against others (attacker side), for the
## underworld Extortion tab. Each row is the victim's demand dict plus
## "target_company".
func outgoing_extortion(company_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for victim_id: StringName in heat_states.keys():
		var heat_state: CompanyHeatState = heat_states[victim_id]
		for row: Dictionary in heat_state.outstanding_extortion:
			if StringName(String(row.get("from_company", ""))) == company_id:
				var copy: Dictionary = row.duplicate()
				copy["target_company"] = String(victim_id)
				out.append(copy)
	return out


## Rival branches this company could target (all restaurants it does not own).
func target_buildings(company_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rest: RestaurantState in RestaurantManager.all_restaurants():
		if rest.company_id == company_id:
			continue
		var owner: CompanyState = CompanyManager.company(rest.company_id)
		if owner == null or owner.is_bankrupt:
			continue
		out.append({
			"building_id": rest.building_id,
			"name": rest.restaurant_name,
			"company": rest.company_id,
			"company_name": _company_name(rest.company_id),
			"district": rest.district,
		})
	return out


# --- Intel -----------------------------------------------------------------

func intel_level(attacker: StringName, target_company: StringName) -> float:
	var targets: Dictionary = intel.get(String(attacker), {})
	var until: int = int(targets.get(String(target_company), 0))
	return 1.0 if GameClock.day <= until else 0.0


func grant_intel(attacker: StringName, target_company: StringName, days: int) -> void:
	var key: String = String(attacker)
	var targets: Dictionary = intel.get(key, {})
	targets[String(target_company)] = maxi(int(targets.get(String(target_company), 0)), GameClock.day + days)
	intel[key] = targets


## What the attacker can see about a rival's defenses (Target Intel tab).
func target_intel_report(attacker: StringName, target_company: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var has_intel: bool = intel_level(attacker, target_company) > 0.0
	for rest: RestaurantState in _restaurants_of(target_company):
		var row: Dictionary = {
			"building_id": rest.building_id,
			"name": rest.restaurant_name,
			"district": rest.district,
			"known": has_intel,
		}
		if has_intel:
			var sec: SecurityState = security_for(rest.building_id)
			row["security_score"] = security_score_for(rest.building_id)
			row["equipment_level"] = sec.equipment_level if sec != null else 0
			row["alert_level"] = String(sec.alert_level) if sec != null else "normal"
			row["guards"] = guard_effect(rest.building_id) > 0.01
			row["vulnerabilities"] = security_math.vulnerabilities(sec, guard_effect(rest.building_id)) if sec != null else []
		out.append(row)
	return out


# --- Police stub -----------------------------------------------------------

func police_eta(building_id: int) -> float:
	var gov: Node = _gov_live()
	if gov != null:
		return gov.call("police_eta", building_id)
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	var target: Vector3 = rest.door_pos if rest != null else Vector3.ZERO
	if rest != null and target == Vector3.ZERO:
		var info: Dictionary = CityData.get_building(building_id)
		target = info.get("position", Vector3.ZERO)
	var best: float = 12.0
	for precinct: Vector3 in _precincts:
		var eta: float = SupplyManager.route_eta(precinct, target)
		if eta > 0.0:
			best = minf(best, eta)
	return clampf(best, 3.0, 45.0)


func precinct_positions() -> Array[Vector3]:
	var gov: Node = _gov_live()
	if gov != null:
		return gov.call("precinct_positions")
	return _precincts


## Player-facing threat beats for the events panel: open extortion deadlines
## and counterintel-detected plots against the player's branches.
func upcoming_threats(count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not enabled() or CompanyManager.player == null:
		return out
	var player_id: StringName = CompanyManager.player.id
	var heat_state: CompanyHeatState = heat_states.get(player_id)
	if heat_state == null:
		return out
	for row: Dictionary in heat_state.open_extortion():
		var day: int = int(row.get("deadline_day", GameClock.day))
		out.append({
			"title": "%s deadline" % String(row.get("kind", "extortion")).capitalize(),
			"kind": "extortion", "day": day, "when": GameClock.month_name_for(day),
		})
	for plot: Dictionary in heat_state.known_plots:
		var eta: int = int(plot.get("eta_day", GameClock.day))
		if eta < GameClock.day:
			continue
		out.append({
			"title": "Suspected sabotage", "kind": "crime",
			"day": eta, "when": GameClock.month_name_for(eta),
		})
	return out.slice(0, count)


# --- Save ------------------------------------------------------------------

func write_save(save: SaveGame) -> void:
	save.crime_schema_version = SCHEMA_VERSION
	save.crime_agents = agents.duplicate()
	save.crime_operations = operations.duplicate()
	var security_list: Array[SecurityState] = []
	for key: int in security_states:
		security_list.append(security_states[key])
	save.crime_security_states = security_list
	var heat_list: Array[CompanyHeatState] = []
	for key: StringName in heat_states:
		heat_list.append(heat_states[key])
	save.crime_heat_states = heat_list
	save.crime_intel = {
		"intel": intel.duplicate(true),
		"cooldowns": cooldowns.duplicate(true),
	}
	save.crime_op_next_uid = next_op_uid
	save.crime_incident_next_uid = next_incident_uid


func restore_from_save(save: SaveGame) -> void:
	if save.crime_schema_version <= 0:
		return
	agents = save.crime_agents.duplicate()
	operations = save.crime_operations.duplicate()
	security_states.clear()
	for state: SecurityState in save.crime_security_states:
		security_states[state.building_id] = state
	heat_states.clear()
	for heat_state: CompanyHeatState in save.crime_heat_states:
		heat_states[heat_state.company_id] = heat_state
	intel = save.crime_intel.get("intel", {}).duplicate(true)
	cooldowns = save.crime_intel.get("cooldowns", {}).duplicate(true)
	next_op_uid = save.crime_op_next_uid
	next_incident_uid = save.crime_incident_next_uid


# --- Lifecycle -------------------------------------------------------------

func _on_minute_ticked(_day: int, _hour: int, _minute: int) -> void:
	if not enabled():
		return
	var now: int = GameClock.total_minutes()
	for op: CrimeOperationState in operations:
		while op.is_live() and op.phase != &"investigation" and now >= op.phase_end_minute:
			_advance_phase(op, now)


func _advance_phase(op: CrimeOperationState, now: int) -> void:
	var def: CrimeActionDef = action(op.action_id)
	if def == null:
		op.phase = &"cancelled"
		_release_agents(op)
		return
	match op.phase:
		&"planning":
			_enter_phase(op, &"travel", now, op.travel_minutes)
		&"travel":
			_enter_phase(op, &"infiltration", now, maxi(1, def.exec_minutes))
		&"infiltration":
			_resolve_operation(op, def)
			_enter_phase(op, &"effect", now, EFFECT_WINDOW_MINUTES)
		&"effect":
			_enter_phase(op, &"escape", now, op.travel_minutes)
		&"escape":
			_finish_escape(op, def)
			var days: int = heat_math.investigation_duration(
				def.tier, bool(op.outcome.get("police_called", false)))
			op.outcome["investigation_until_day"] = GameClock.day + days
			_enter_phase(op, &"investigation", now, days * 1440)
		_:
			pass
	operation_updated.emit(op)


func _enter_phase(op: CrimeOperationState, phase: StringName, now: int, duration_minutes: int) -> void:
	op.phase = phase
	op.phase_start_minute = now
	op.phase_end_minute = now + maxi(1, duration_minutes)


## Resolve ONCE with the frozen seed. Called at the infiltration→effect
## boundary; outcome_applied makes reload-safe re-entry a no-op.
func _resolve_operation(op: CrimeOperationState, def: CrimeActionDef) -> void:
	if op.outcome_applied:
		return
	var ctx: Dictionary = _resolve_ctx(op.attacker_company, def, op.target_building)
	var rng: RandomNumberGenerator = WorkforceRng.make(&"crime_resolve", op.seed_day, [op.uid])
	var outcome: Dictionary = resolver.resolve(def, ctx, rng)
	outcome["police_called"] = bool(op.outcome.get("police_called", false))
	op.outcome = outcome
	op.evidence = float(outcome.get("evidence", 0.0))
	op.discovered = bool(outcome.get("detected", false))
	_apply_outcome(op, def, rng)
	op.outcome_applied = true


func _apply_outcome(op: CrimeOperationState, def: CrimeActionDef, rng: RandomNumberGenerator) -> void:
	var success: bool = bool(op.outcome.get("success", false))
	var detected: bool = bool(op.outcome.get("detected", false))
	var victim: CompanyState = CompanyManager.company(op.target_company)
	var attacker_heat: CompanyHeatState = heat_for(op.attacker_company)
	heat_math.accrue(attacker_heat, def, detected)
	if op.evidence > 0.02:
		attacker_heat.evidence.append({
			"incident_uid": op.uid,
			"victim_company": String(op.target_company),
			"action_id": String(def.id),
			"strength": op.evidence,
			"day": GameClock.day,
		})
	heat_changed.emit(op.attacker_company)
	var loss: float = 0.0
	if success and victim != null:
		loss = _apply_effects(op, def, rng)
	if def.target_kind == &"restaurant" and (success or detected):
		_report_incident(op, def, success, loss)
	if detected:
		_auto_elevate(op.target_building)
		if victim != null and victim.is_player:
			police_incident.emit(op)
	if success and victim != null and victim.is_player and def.target_kind != &"restaurant":
		_notify_company(op.target_company, "alert", "Nasty rumors about your company are spreading.")
	var attacker: CompanyState = CompanyManager.company(op.attacker_company)
	if attacker != null and attacker.is_player:
		var word: String = "succeeded" if success else "failed"
		EconomyManager.post_message("good" if success else "alert",
			"Back room: %s %s." % [def.display_name, word])


## Interprets CrimeActionDef.effects against the live sim. Returns the
## direct monetary loss booked for the incident report.
func _apply_effects(op: CrimeOperationState, def: CrimeActionDef, rng: RandomNumberGenerator) -> float:
	var effects: Dictionary = def.effects
	var victim: CompanyState = CompanyManager.company(op.target_company)
	var attacker: CompanyState = CompanyManager.company(op.attacker_company)
	var rest: RestaurantState = RestaurantManager.by_building.get(op.target_building)
	var day: int = GameClock.day
	var loss: float = 0.0
	var effect_days: int = int(effects.get("effect_days", 3))
	var sec: SecurityState = security_for(op.target_building) if rest != null else null
	for kind: StringName in [&"demand_debuff", &"appeal_debuff"]:
		if effects.has(kind) and sec != null:
			sec.active_effects.append({
				"kind": kind,
				"magnitude": float(effects[kind]),
				"until_day": day + effect_days,
				"source_action": String(def.id),
				"incident_uid": next_incident_uid,
			})
	if effects.has("reputation_hit") and victim != null:
		victim.add_reputation(-float(effects["reputation_hit"]), 0.0, 1.0)
	if effects.has("clean_hit") and rest != null and rest.interior_layout != null:
		for item: PlacedFurnitureState in rest.interior_layout.placed:
			item.cleanliness = clampf(item.cleanliness - float(effects["clean_hit"]), 0.05, 1.0)
	if effects.has("durability_hit") and rest != null and rest.interior_layout != null:
		var count: int = int(effects.get("station_count", 2))
		var hit: float = float(effects["durability_hit"])
		var ids: Array = []
		var placements: Array = rest.interior_layout.placed
		for i: int in range(mini(count, placements.size())):
			var index: int = rng.randi_range(0, placements.size() - 1)
			var item: PlacedFurnitureState = placements[index]
			item.durability = minf(item.durability, hit)
			ids.append(index)
		op.outcome["furniture_indices"] = ids
	if effects.has("stock_spoil_fraction") and rest != null and rest.inventory != null:
		var lots: Array = rest.inventory.lots
		var spoil_count: int = ceili(float(effects["stock_spoil_fraction"]) * float(lots.size()))
		var now: int = GameClock.total_minutes()
		for i: int in range(mini(spoil_count, lots.size())):
			var lot: StockLot = lots[i]
			loss += lot.qty * lot.unit_cost
			lot.expiry_minute = now - 1
	if effects.has("disruption_days"):
		_inject_supply_disruption(op.target_company, effects, rng)
	if effects.has("loyalty_hit") or effects.has("stress_hit") or effects.has("injury_chance"):
		_hit_staff(rest, effects, rng, day)
	if effects.has("closure_days") and rest != null:
		rest.closed_until_day = day + int(effects["closure_days"])
		RestaurantManager.set_channels(rest.building_id, false, false)
	if effects.has("cash_steal") and victim != null and attacker != null:
		var amount: float = minf(float(effects["cash_steal"]), maxf(victim.cash, 0.0) * 0.1)
		if amount > 1.0:
			victim.transact(&"theft_loss", -amount)
			attacker.transact(&"theft_income", amount * 0.85)
			loss += amount
	if effects.has("intel_days"):
		grant_intel(op.attacker_company, op.target_company, int(effects["intel_days"]))
	if effects.has("inspection_bias"):
		var gov: Node = _gov()
		if gov != null and gov.has_method("schedule_rigged_inspection"):
			gov.call("schedule_rigged_inspection", op.target_building, float(effects["inspection_bias"]))
	if effects.has("extort_factor") and victim != null:
		_create_demand(op, "extortion", float(effects["extort_factor"]), -1)
	if effects.has("ransom_factor") and rest != null:
		_kidnap(op, rest, float(effects["ransom_factor"]), rng)
	return loss


func _report_incident(op: CrimeOperationState, def: CrimeActionDef, success: bool, loss: float) -> void:
	var state: SecurityState = security_for(op.target_building)
	if state == null:
		return
	var day: int = GameClock.day
	var repair_cost: float = float(def.effects.get("repair_cost", 0.0)) if success else 0.0
	var title: String = def.display_name if success else "Attempted: %s" % def.display_name
	var row: Dictionary = {
		"uid": next_incident_uid,
		"op_uid": op.uid,
		"day": day,
		"minute": GameClock.total_minutes(),
		"kind_shown": String(def.id) if success else "attempt",
		"title": title,
		"effect_summary": _collateral_text(def) if success else "The crew was driven off before doing damage.",
		"loss": loss,
		"active": success and (repair_cost > 0.0 or not def.effects.is_empty()),
		"suspected_company": "",
		"confidence": 0.0,
		"known_facts": ["Incident at %s, day %d." % [_branch_name(op.target_building), day]],
		"suspicions": [],
		"repair_cost": repair_cost,
		"repaired_day": -1,
		"investigation_until_day": int(op.outcome.get("investigation_until_day",
			day + heat_math.investigation_duration(def.tier, false))),
		"source_action": String(def.id),
		"police_called": false,
	}
	next_incident_uid += 1
	op.incident_uid = int(row["uid"])
	state.add_incident(row)
	var victim: CompanyState = CompanyManager.company(op.target_company)
	if victim != null and state.insurance_level > 0 and loss > 0.0:
		var fractions: Array = _tuning("crime.insurance.payout_fractions", [0.0, 0.5, 0.8])
		var payout: float = loss * float(fractions[mini(state.insurance_level, fractions.size() - 1)])
		if payout > 1.0:
			victim.transact(&"insurance_payout", payout)
			if victim.is_player:
				EconomyManager.post_message("good", "Insurance paid out %s for the incident." % _money(payout))
	_record_event(BusinessEvent.SABOTAGE if def.tier > 1 else BusinessEvent.INCIDENT,
		op.target_company, op.target_building, -loss, title)
	if victim != null and victim.is_player:
		EconomyManager.post_message("alert", "%s at %s!" % [title, _branch_name(op.target_building)])
	incident_reported.emit(op.target_building, row)
	security_changed.emit(op.target_building)


func _finish_escape(op: CrimeOperationState, def: CrimeActionDef) -> void:
	var outcomes: Array = op.outcome.get("agent_outcomes", [])
	var police_called: bool = bool(op.outcome.get("police_called", false))
	var day: int = GameClock.day
	var attacker_heat: CompanyHeatState = heat_for(op.attacker_company)
	var index: int = 0
	for agent_uid: int in op.agent_uids:
		var agent: CriminalAgentState = _agent_by_uid(agent_uid)
		if agent == null:
			index += 1
			continue
		var fate: StringName = StringName(outcomes[index]) if index < outcomes.size() else &"clean"
		if police_called and fate == &"clean":
			var rng: RandomNumberGenerator = WorkforceRng.make(
				&"crime_detect", op.seed_day, [op.uid, "police", agent_uid])
			if rng.randf() < 0.35:
				fate = &"captured"
		match fate:
			&"injured":
				agent.recovering_until_day = day + 5
				agent.readiness = 0.5
			&"captured":
				agent.incarcerated_until_day = day + heat_math.incarceration_days
				attacker_heat.evidence.append({
					"incident_uid": op.uid,
					"victim_company": String(op.target_company),
					"action_id": String(def.id),
					"strength": 0.5,
					"day": day,
				})
				attacker_heat.heat = clampf(attacker_heat.heat + 10.0, 0.0, 100.0)
			_:
				pass
		agent.assignment_op_uid = -1
		index += 1
	crew_changed.emit(op.attacker_company)
	heat_changed.emit(op.attacker_company)


# --- Day close (buckets_closed) --------------------------------------------

func _on_buckets_closed(closed_day: int) -> void:
	if not enabled():
		return
	var day: int = closed_day + 1
	for key: int in security_states:
		var state: SecurityState = security_states[key]
		state.prune_effects(day)
		if state.alert_until_day > 0 and day > state.alert_until_day:
			state.alert_level = &"normal"
			state.alert_until_day = 0
			security_changed.emit(state.building_id)
	for company_id: StringName in heat_states.keys():
		var heat_state: CompanyHeatState = heat_states[company_id]
		heat_math.decay(heat_state)
		_run_enforcement(heat_state, day)
		_expire_extortion(heat_state, day)
	for op: CrimeOperationState in operations:
		if op.phase == &"investigation" and day >= int(op.outcome.get("investigation_until_day", 0)):
			_finish_investigation(op, day)
	_reopen_closed_branches(day)
	_trim_operations()


func _run_enforcement(heat_state: CompanyHeatState, day: int) -> void:
	# With the civic layer on, the police commander decides and the government
	# books the fine on the legal ledger; crime still applies its own raid
	# effects below. Gov off -> the legacy self-contained ladder.
	var gov: Node = _gov_live()
	var verdict: Dictionary
	if gov != null:
		verdict = gov.call("crime_enforcement", heat_state.company_id,
			heat_state.heat, heat_state.evidence_total(), day)
	else:
		verdict = heat_math.enforcement_check(heat_state)
	var kind: StringName = verdict.get("action", &"none")
	if kind == &"none" or kind == &"investigate":
		return
	var company: CompanyState = CompanyManager.company(heat_state.company_id)
	if company == null:
		return
	var fine: float = float(verdict.get("fine", 0.0))
	if gov == null:
		company.transact(&"crime_fine", -fine)
	heat_state.fines_total += fine
	if kind == &"raid":
		heat_state.ops_frozen_until_day = day + heat_math.raid_freeze_days
		var jailed: int = 0
		for agent: CriminalAgentState in crew_of(heat_state.company_id):
			if jailed >= 2:
				break
			if agent.assignment_op_uid < 0 and not agent.is_incarcerated(day):
				agent.incarcerated_until_day = day + heat_math.incarceration_days
				jailed += 1
		for op: CrimeOperationState in ops_of(heat_state.company_id):
			if op.is_live() and op.can_cancel():
				op.phase = &"cancelled"
				_release_agents(op)
		heat_state.evidence.clear()
		heat_state.raids.append({
			"day": day, "fine": fine,
			"frozen_until_day": heat_state.ops_frozen_until_day,
			"agents_jailed": jailed,
		})
		heat_math.apply_raid_relief(heat_state)
		# Gov live -> GovernmentManager already recorded the raid + news.
		if gov == null:
			_record_event(BusinessEvent.POLICE, heat_state.company_id, -1, -fine,
				"Police raid on %s" % _company_name(heat_state.company_id))
			_news_all("Police raided %s — fines and arrests." % _company_name(heat_state.company_id))
	else:
		heat_math.apply_fine_relief(heat_state)
		if gov == null:
			_record_event(BusinessEvent.POLICE, heat_state.company_id, -1, -fine,
				"Police fine over criminal ties")
			if company.is_player:
				EconomyManager.post_message("alert",
					"The police fined you %s over suspected criminal ties." % _money(fine))
	heat_changed.emit(heat_state.company_id)
	crew_changed.emit(heat_state.company_id)


func _finish_investigation(op: CrimeOperationState, day: int) -> void:
	op.phase = &"done"
	var state: SecurityState = security_states.get(op.target_building)
	var def: CrimeActionDef = action(op.action_id)
	if state != null and op.incident_uid >= 0:
		var row: Dictionary = state.incident_by_uid(op.incident_uid)
		if not row.is_empty():
			var police_called: bool = bool(row.get("police_called", false)) \
				or bool(op.outcome.get("police_called", false))
			var confidence: float = heat_math.confidence(op.evidence, state.equipment_level, police_called)
			row["confidence"] = confidence
			if heat_math.attribution_known(confidence):
				row["suspected_company"] = String(op.attacker_company)
				row["known_facts"].append("Evidence points at %s." % _company_name(op.attacker_company))
				var victim: CompanyState = CompanyManager.company(op.target_company)
				if victim != null and victim.is_player:
					EconomyManager.post_message("alert", "Investigators tied the %s incident to %s." % [
						String(def.display_name if def != null else op.action_id),
						_company_name(op.attacker_company)])
				_news_all("%s suspected of the incident at %s." % [
					_company_name(op.attacker_company), _branch_name(op.target_building)])
			elif confidence > 0.2:
				row["suspicions"].append("Weak leads suggest a rival was involved (low confidence).")
			incident_reported.emit(op.target_building, row)
	operation_updated.emit(op)
	var _unused: int = day


func _expire_extortion(heat_state: CompanyHeatState, day: int) -> void:
	for row: Dictionary in heat_state.outstanding_extortion:
		if String(row.get("status", "")) == "open" and day > int(row.get("deadline_day", 0)):
			row["status"] = "expired"
			if String(row.get("kind", "extortion")) == "ransom":
				_release_hostage(row)
			var attacker: CompanyState = CompanyManager.company(
				StringName(String(row.get("from_company", ""))))
			if attacker != null and attacker.is_player:
				EconomyManager.post_message("alert",
					"%s let your demand expire." % _company_name(heat_state.company_id))
			extortion_updated.emit(heat_state.company_id)


func _reopen_closed_branches(day: int) -> void:
	for rest: RestaurantState in RestaurantManager.all_restaurants():
		if rest.closed_until_day > 0 and day >= rest.closed_until_day:
			rest.closed_until_day = 0
			RestaurantManager.set_channels(rest.building_id, true, rest.delivery_enabled)
			var company: CompanyState = CompanyManager.company(rest.company_id)
			if company != null and company.is_player:
				EconomyManager.post_message("good", "%s reopened." % rest.restaurant_name)


func _trim_operations() -> void:
	if operations.size() <= 60:
		return
	var kept: Array[CrimeOperationState] = []
	var finished_budget: int = 40
	for i: int in range(operations.size() - 1, -1, -1):
		var op: CrimeOperationState = operations[i]
		if op.is_live():
			kept.append(op)
		elif finished_budget > 0:
			kept.append(op)
			finished_budget -= 1
	kept.reverse()
	operations = kept


func _charge_daily(company: CompanyState, day: int) -> void:
	if not enabled():
		return
	var wages: float = 0.0
	for agent: CriminalAgentState in crew_of(company.id):
		if not agent.is_incarcerated(day):
			wages += agent.daily_wage
	if wages > 0.0:
		company.transact(&"underworld_wages", -wages)
	var upkeep: float = 0.0
	var premiums: float = 0.0
	var upkeep_rate: float = float(_tuning("crime.security.upkeep_per_level", 25.0))
	var premium_rates: Array = _tuning("crime.insurance.daily_premiums", [0.0, 45.0, 110.0])
	for rest: RestaurantState in _restaurants_of(company.id):
		var state: SecurityState = security_states.get(rest.building_id)
		if state == null:
			continue
		upkeep += upkeep_rate * float(state.equipment_level)
		premiums += float(premium_rates[mini(state.insurance_level, premium_rates.size() - 1)])
	if upkeep > 0.0:
		company.transact(&"security_upkeep", -upkeep)
	if premiums > 0.0:
		company.transact(&"insurance_premium", -premiums)


# --- Effect helpers --------------------------------------------------------

func _inject_supply_disruption(victim_id: StringName, effects: Dictionary, rng: RandomNumberGenerator) -> void:
	var supplier_id: StringName = &""
	for po: Resource in SupplyManager.open_orders(victim_id):
		var sid: Variant = po.get("supplier_id")
		if sid != null:
			supplier_id = StringName(String(sid))
			break
	if supplier_id == &"":
		var keys: Array = SupplyManager.supplier_defs.keys()
		keys.sort()
		if keys.is_empty():
			return
		supplier_id = keys[rng.randi_range(0, keys.size() - 1)]
	var disruption: SupplyDisruption = SupplyDisruption.new()
	disruption.supplier_id = supplier_id
	disruption.kind = StringName(String(effects.get("disruption_kind", "delay")))
	disruption.severity = 1.8
	disruption.start_minute = GameClock.total_minutes()
	disruption.end_minute = disruption.start_minute + int(effects.get("disruption_days", 2)) * 1440
	SupplyManager.disruptions.append(disruption)


func _hit_staff(rest: RestaurantState, effects: Dictionary, rng: RandomNumberGenerator, day: int) -> void:
	if rest == null or rest.staff.is_empty():
		return
	var member: StaffMember = rest.staff[rng.randi_range(0, rest.staff.size() - 1)]
	if effects.has("loyalty_hit"):
		member.loyalty = clampf(member.loyalty - float(effects["loyalty_hit"]), 0.0, 1.0)
	if effects.has("stress_hit"):
		member.stress = clampf(member.stress + float(effects["stress_hit"]), 0.0, 1.0)
		member.absence_until_day = maxi(member.absence_until_day, day + 1)
	if effects.has("injury_chance") and rng.randf() < float(effects["injury_chance"]):
		member.injury = {"kind": "assault", "day": day}
		member.injury_until_day = day + 4
		member.absence_until_day = maxi(member.absence_until_day, day + 4)


func _create_demand(op: CrimeOperationState, kind: String, factor: float, staff_uid: int) -> void:
	var victim: CompanyState = CompanyManager.company(op.target_company)
	if victim == null:
		return
	var base_amount: float = float(_tuning("crime.extortion.base_amount", 1200.0))
	var amount: float = snappedf(maxf(500.0, base_amount * factor + victim.cash * 0.02), 10.0)
	var heat_state: CompanyHeatState = heat_for(op.target_company)
	heat_state.outstanding_extortion.append({
		"uid": next_incident_uid,
		"kind": kind,
		"from_company": String(op.attacker_company),
		"amount": amount,
		"deadline_day": GameClock.day + int(_tuning("crime.extortion.deadline_days", 4)),
		"status": "open",
		"building_id": op.target_building,
		"staff_uid": staff_uid,
	})
	next_incident_uid += 1
	if victim.is_player:
		EconomyManager.post_message("alert", "%s demand: pay %s or face the consequences." % [
			kind.capitalize(), _money(amount)])
	_record_event(BusinessEvent.EXTORTION, op.target_company, op.target_building, -amount,
		"%s demand received" % kind.capitalize())
	extortion_updated.emit(op.target_company)


func _kidnap(op: CrimeOperationState, rest: RestaurantState, factor: float, _rng: RandomNumberGenerator) -> void:
	if rest.staff.is_empty():
		return
	var best: StaffMember = rest.staff[0]
	for member: StaffMember in rest.staff:
		if member.hourly_wage > best.hourly_wage:
			best = member
	var days: int = int(_tuning("crime.extortion.deadline_days", 4)) + 2
	best.absence_until_day = maxi(best.absence_until_day, GameClock.day + days)
	_create_demand(op, "ransom", factor, best.uid)


func _release_hostage(row: Dictionary) -> void:
	var rest: RestaurantState = RestaurantManager.by_building.get(int(row.get("building_id", -1)))
	if rest == null:
		return
	var staff_uid: int = int(row.get("staff_uid", -1))
	for member: StaffMember in rest.staff:
		if member.uid == staff_uid:
			member.absence_until_day = GameClock.day
			return


func _restore_after_incident(state: SecurityState, row: Dictionary) -> void:
	var rest: RestaurantState = RestaurantManager.by_building.get(state.building_id)
	var source: String = String(row.get("source_action", ""))
	var incident_uid: int = int(row.get("uid", -1))
	var kept: Array[Dictionary] = []
	for effect: Dictionary in state.active_effects:
		if int(effect.get("incident_uid", -1)) != incident_uid:
			kept.append(effect)
	state.active_effects = kept
	if rest == null or rest.interior_layout == null:
		return
	if source.contains("pest") or source.contains("stink"):
		for item: PlacedFurnitureState in rest.interior_layout.placed:
			item.cleanliness = maxf(item.cleanliness, 0.8)
	if source.contains("equipment") or source.contains("property") or source.contains("arson"):
		for item: PlacedFurnitureState in rest.interior_layout.placed:
			item.durability = maxf(item.durability, 60.0)


func _auto_elevate(building_id: int) -> void:
	var state: SecurityState = security_states.get(building_id)
	if state == null or state.alert_level != &"normal":
		return
	state.alert_level = &"elevated"
	state.alert_until_day = GameClock.day + 3
	security_changed.emit(building_id)


# --- Launch validation / context -------------------------------------------

func _can_launch(company_id: StringName, def: CrimeActionDef, target_building: int) -> CommandResult:
	if not enabled():
		return CommandResult.fail(&"crime_disabled", "The underworld is closed in this game.")
	if not def.allowed_in_mode(crime_mode()):
		return CommandResult.fail(&"mode_locked", "This scenario does not allow that.")
	if def.tier > action_tier(company_id):
		return CommandResult.fail(&"tier_locked",
			CapabilityRegistry.explain(company_id, &"crime.crew_capacity"))
	var heat_state: CompanyHeatState = heat_for(company_id)
	if heat_state.is_frozen(GameClock.day):
		return CommandResult.fail(&"frozen", "The police are watching — lay low for now.")
	var target_company: StringName = _target_company_for(def, target_building)
	if target_company == &"" or target_company == company_id:
		return CommandResult.fail(&"bad_target", "Pick a rival target.")
	if def.target_kind == &"restaurant" and RestaurantManager.by_building.get(target_building) == null:
		return CommandResult.fail(&"bad_target", "That location is gone.")
	var key: String = _cooldown_key(company_id, def.id, target_building)
	if int(cooldowns.get(key, 0)) > GameClock.day:
		return CommandResult.fail(&"cooldown", "Too soon to hit the same target again.")
	if _pick_agents(company_id, def).size() < _roles_needed(def):
		return CommandResult.fail(&"no_crew", "Crew unavailable — need %s." % _roles_label(def))
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null or not company.can_afford(def.cost):
		return CommandResult.fail(&"cannot_afford", "Not enough cash.")
	return CommandResult.good({})


func _resolve_ctx(company_id: StringName, def: CrimeActionDef, target_building: int) -> Dictionary:
	var picked: Array[CriminalAgentState] = _pick_agents(company_id, def)
	var skill: float = 0.0
	var equipment: int = 0
	for agent: CriminalAgentState in picked:
		skill += agent.skill * agent.readiness
		equipment = maxi(equipment, agent.equipment_tier)
	if not picked.is_empty():
		skill /= float(picked.size())
	var sec: SecurityState = security_for(target_building)
	var target_company: StringName = _target_company_for(def, target_building)
	return {
		"avg_skill": skill,
		"equipment_tier": equipment,
		"intel_level": intel_level(company_id, target_company),
		"security_score": security_score_for(target_building) if sec != null else 0.0,
		"alert_level": sec.alert_level if sec != null else &"normal",
		"has_cameras": sec != null and sec.equipment_level >= 2,
		"agent_count": maxi(1, picked.size()),
	}


func _target_company_for(def: CrimeActionDef, target_building: int) -> StringName:
	if def != null and def.target_kind == &"company":
		return _company_for_building_or_id(target_building)
	var rest: RestaurantState = RestaurantManager.by_building.get(target_building)
	return rest.company_id if rest != null else &""


## Company-target ops address targets by rival index when no building fits.
func _company_for_building_or_id(target_building: int) -> StringName:
	var rest: RestaurantState = RestaurantManager.by_building.get(target_building)
	if rest != null:
		return rest.company_id
	return &""


func _pick_agents(company_id: StringName, def: CrimeActionDef) -> Array[CriminalAgentState]:
	var day: int = GameClock.day
	var picked: Array[CriminalAgentState] = []
	for role: Variant in def.required_roles:
		var needed: int = int(def.required_roles[role])
		var pool: Array[CriminalAgentState] = []
		for agent: CriminalAgentState in crew_of(company_id):
			if agent.role == StringName(role) and agent.is_available(day) and not picked.has(agent):
				pool.append(agent)
		pool.sort_custom(func(a: CriminalAgentState, b: CriminalAgentState) -> bool:
			return a.skill > b.skill)
		for i: int in range(mini(needed, pool.size())):
			picked.append(pool[i])
	return picked


func _roles_needed(def: CrimeActionDef) -> int:
	var total: int = 0
	for role: Variant in def.required_roles:
		total += int(def.required_roles[role])
	return maxi(1, total)


func _roles_label(def: CrimeActionDef) -> String:
	var parts: Array[String] = []
	for role: Variant in def.required_roles:
		parts.append("%d %s" % [int(def.required_roles[role]), String(role)])
	return ", ".join(parts) if not parts.is_empty() else "crew"


func _travel_minutes(company_id: StringName, target_building: int) -> int:
	var target: Vector3 = Vector3.ZERO
	var rest: RestaurantState = RestaurantManager.by_building.get(target_building)
	if rest != null:
		target = rest.door_pos
	if target == Vector3.ZERO:
		target = CityData.get_building(target_building).get("position", Vector3.ZERO)
	var origin: Vector3 = Vector3.ZERO
	for own: RestaurantState in _restaurants_of(company_id):
		if own.door_pos != Vector3.ZERO:
			origin = own.door_pos
			break
	var eta: float = SupplyManager.route_eta(origin, target)
	if eta <= 0.0:
		return 45
	return clampi(int(eta), 10, 240)


func _known_defenses(company_id: StringName, target_company: StringName, target_building: int) -> Array[String]:
	var out: Array[String] = []
	if intel_level(company_id, target_company) <= 0.0:
		out.append("No current intel — scout the target first.")
		return out
	var sec: SecurityState = security_for(target_building)
	if sec == null:
		return out
	if guard_effect(target_building) > 0.01:
		out.append("Guards on shift")
	if sec.equipment_level >= 2:
		out.append("Cameras installed")
	elif sec.equipment_level >= 1:
		out.append("Reinforced locks")
	if sec.alert_level != &"normal":
		out.append("Alert: %s" % String(sec.alert_level))
	if out.is_empty():
		out.append("Soft target — minimal security")
	return out


func _collateral_text(def: CrimeActionDef) -> String:
	match def.tier:
		1:
			return "If caught: police attention, reputation damage, and retaliation."
		2:
			return "If caught: police response, a fine, −0.5 rating risk, and retaliation."
		_:
			return "If caught: raids, arrests, heavy fines, and open war with the target."


# --- Ensure / bookkeeping ---------------------------------------------------

func _ensure_states() -> void:
	for company: CompanyState in CompanyManager.companies:
		var _heat: CompanyHeatState = heat_for(company.id)
	for rest: RestaurantState in RestaurantManager.all_restaurants():
		var _sec: SecurityState = security_for(rest.building_id)


func _on_company_registered(_company: CompanyState) -> void:
	_ensure_states()


func _on_restaurant_purchased(rest: RestaurantState) -> void:
	var _sec: SecurityState = security_for(rest.building_id)


func _load_actions() -> void:
	actions.clear()
	var dir: DirAccess = DirAccess.open(ACTIONS_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		if file.ends_with(".tres") or file.ends_with(".res"):
			var def: CrimeActionDef = load("%s/%s" % [ACTIONS_DIR, file]) as CrimeActionDef
			if def != null and def.id != &"":
				actions[def.id] = def


func _pick_precincts() -> void:
	_precincts.clear()
	var ids: Array = CityData.buildings.keys()
	if ids.is_empty():
		_precincts.append(Vector3.ZERO)
		return
	ids.sort()
	var rng: RandomNumberGenerator = WorkforceRng.make(&"crime_precinct", 0, [])
	for _i: int in range(2):
		var building_id: int = ids[rng.randi_range(0, ids.size() - 1)]
		var info: Dictionary = CityData.get_building(building_id)
		_precincts.append(info.get("position", Vector3.ZERO))


func _release_agents(op: CrimeOperationState) -> void:
	for agent_uid: int in op.agent_uids:
		var agent: CriminalAgentState = _agent_by_uid(agent_uid)
		if agent != null and agent.assignment_op_uid == op.uid:
			agent.assignment_op_uid = -1


func _agent_by_uid(agent_uid: int) -> CriminalAgentState:
	for agent: CriminalAgentState in agents:
		if agent.uid == agent_uid:
			return agent
	return null


func _owned_security(company_id: StringName, building_id: int) -> SecurityState:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null or rest.company_id != company_id:
		return null
	return security_for(building_id)


func _restaurants_of(company_id: StringName) -> Array[RestaurantState]:
	var out: Array[RestaurantState] = []
	for rest: RestaurantState in RestaurantManager.all_restaurants():
		if rest.company_id == company_id:
			out.append(rest)
	return out


func _plot_known(heat_state: CompanyHeatState, op_uid: int) -> bool:
	for row: Dictionary in heat_state.known_plots:
		if int(row.get("op_uid", -1)) == op_uid:
			return true
	return false


func _already_hired(company_id: StringName, candidate_name: String) -> bool:
	for agent: CriminalAgentState in crew_of(company_id):
		if agent.display_name == candidate_name:
			return true
	return false


func _market_role(rng: RandomNumberGenerator, tier: int) -> StringName:
	var pool: Array[StringName] = [&"courier", &"punk"]
	if tier >= 2:
		pool.append(&"enforcer")
	if tier >= 3:
		pool.append(&"gangster")
	return pool[rng.randi_range(0, pool.size() - 1)]


func _cooldown_key(company_id: StringName, action_id: StringName, target_building: int) -> String:
	return "%s|%s|%d" % [company_id, action_id, target_building]


func _close_extortion(company_id: StringName, demand_uid: int, status: String) -> CommandResult:
	var heat_state: CompanyHeatState = heat_for(company_id)
	for row: Dictionary in heat_state.outstanding_extortion:
		if int(row.get("uid", -1)) == demand_uid and String(row.get("status", "")) == "open":
			row["status"] = status
			if String(row.get("kind", "extortion")) == "ransom" and status != "paid":
				pass  # hostage stays out for the full duration
			extortion_updated.emit(company_id)
			return CommandResult.good({})
	return CommandResult.fail(&"unknown_demand", "No such demand.")


func _record_event(ev_type: StringName, company_id: StringName, building_id: int, amount: float, title: String) -> void:
	if _analytics == null or not _analytics.has_method("record_event"):
		return
	_analytics.call("record_event", ev_type, company_id, {
		"restaurant_id": building_id,
		"amount": amount,
		"title": title,
	})


func _notify_company(company_id: StringName, kind: String, text: String) -> void:
	var company: CompanyState = CompanyManager.company(company_id)
	if company != null and company.is_player:
		EconomyManager.post_message(kind, text)


func _news_all(text: String) -> void:
	EconomyManager.post_company_message(Color(0.55, 0.3, 0.2), "news", text)


func _branch_name(building_id: int) -> String:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	return rest.restaurant_name if rest != null else "a local business"


func _company_name(company_id: StringName) -> String:
	var company: CompanyState = CompanyManager.company(company_id)
	return company.display_name if company != null else String(company_id)


func _money(amount: float) -> String:
	return "$%s" % String("%.0f" % amount)


func _tuning(path: String, fallback: Variant) -> Variant:
	return EconomyManager.tuning_value(path, fallback)


func _autoload_node(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(NodePath(node_name))


func _gov() -> Node:
	return _autoload_node("GovernmentManager")


## The government node only when the civic layer is actually enabled — the
## delegation switch for every police shim above.
func _gov_live() -> Node:
	var gov: Node = _gov()
	if gov != null and gov.has_method("enabled") and gov.call("enabled"):
		return gov
	return null
