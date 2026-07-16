extends Node
## GovernmentManager (feature 13) — the civic layer: official reputation,
## permits, deterministic checklist inspections with remediation/appeals,
## city tax, and (phases 2-4) police dispatch, mayor influence and city
## development. Government actors follow predictable rules: every finding
## maps to live restaurant state plus a concrete corrective, and fixing it
## before the deadline provably prevents the documented escalation.
##
## Discipline (mirrors CrimeManager): idempotent initialize() driven from
## city.gd (never _ready — --script mode skips it); pure math lives in
## scripts/government/*; every cash movement goes through
## CompanyState.transact; inspections freeze uid + visit_minute at
## scheduling and resolve once (outcome_applied) via WorkforceRng streams,
## so save/load replays identically. Day-close work hooks
## AnalyticsManager.buckets_closed; visits fire on GameClock.minute_ticked
## with absolute total_minutes() diffs.
##
## NOTE: not a global identifier until the editor restarts — reach it via
## get_node_or_null("GovernmentManager") on the tree root.

signal civic_changed(company_id: StringName)
signal inspection_scheduled(inspection: InspectionState)
signal inspection_completed(building_id: int, inspection: InspectionState)
signal permit_changed(company_id: StringName)
signal fine_issued(company_id: StringName, fine: Dictionary)
signal mayor_changed()
signal development_updated(project: Resource)
signal police_dispatched(building_id: int, eta_minutes: float)
signal police_incident(payload: Dictionary)

const OFFICIALS_DIR: String = "res://data/officials"
const PERMITS_DIR: String = "res://data/permits"
const DEVELOPMENT_DIR: String = "res://data/development_projects"
const SCHEMA_VERSION: int = 1
## Permits every company holds from day one (lapse/renewal is the gameplay).
const STARTER_PERMITS: Array[StringName] = [&"business_license", &"food_handling"]

var official_defs: Dictionary = {}  ## id -> OfficialDef
var permit_catalog: Dictionary = {}  ## id -> PermitDef
var civic_states: Dictionary = {}  ## company_id -> CompanyCivicState
var officials: Array[OfficialState] = []
var inspections: Array[InspectionState] = []
var stations: Array[PoliceStationState] = []
var city_hall_building_id: int = -1
var project_defs: Dictionary = {}  ## id -> DevelopmentProjectDef
var projects: Array[DevelopmentProjectState] = []
var next_project_uid: int = 1
var next_inspection_uid: int = 1
var next_fine_uid: int = 1
var next_violation_uid: int = 1

var checklist: ChecklistService = ChecklistService.new()
var police: PoliceService = PoliceService.new()
var influence_math: InfluenceService = InfluenceService.new()
var development: DevelopmentService = DevelopmentService.new()
var next_donation_uid: int = 1
## district -> summed built-project demand bonus, cleared at day close.
var _dev_bonus_cache: Dictionary = {}

var _analytics: Node = null
var _initialized: bool = false
var _city_hall_position: Vector3 = Vector3.ZERO
## (building_id -> eta) route cache, cleared at every day close.
var _eta_cache: Dictionary = {}


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	checklist.configure(EconomyManager.tuning_value)
	police.configure(EconomyManager.tuning_value)
	influence_math.configure(EconomyManager.tuning_value)
	development.configure(EconomyManager.tuning_value)
	_load_catalogs()
	_analytics = _autoload_node("AnalyticsManager")
	var save: SaveGame = CompanyManager.loaded_save
	if save != null:
		restore_from_save(save)
	_ensure_states()
	_seed_officials()
	_seed_stations()
	_seed_city_hall()
	EconomyManager.daily_cost_providers.append(_charge_daily)
	if not GameClock.minute_ticked.is_connected(_on_minute_ticked):
		GameClock.minute_ticked.connect(_on_minute_ticked)
	if _analytics != null and _analytics.has_signal("buckets_closed") \
			and not _analytics.is_connected("buckets_closed", _on_buckets_closed):
		_analytics.connect("buckets_closed", _on_buckets_closed)
	if not CompanyManager.company_registered.is_connected(_on_company_registered):
		CompanyManager.company_registered.connect(_on_company_registered)


# --- Mode / gating ---------------------------------------------------------

func enabled() -> bool:
	# Guarded until initialize(): the HUD polls upcoming_civic from frame 1,
	# before the deferred init chain has loaded catalogs or GameSetup has
	# hydrated the session — a state created that early would miss its
	# starter permits.
	if not _initialized:
		return false
	var setup: Node = _autoload_node("GameSetup")
	if setup == null:
		return true
	if setup.has_method("government_enabled"):
		return setup.call("government_enabled")
	return true


## &"off" | &"limited" | &"rampant" — resolved by GameSetup.
func corruption_mode() -> StringName:
	var setup: Node = _autoload_node("GameSetup")
	if setup != null and setup.has_method("corruption_mode"):
		return setup.call("corruption_mode")
	return &"off"


func corruption_enabled() -> bool:
	return corruption_mode() != &"off"


# --- Read surface ----------------------------------------------------------

func civic_for(company_id: StringName) -> CompanyCivicState:
	var civic: CompanyCivicState = civic_states.get(company_id)
	if civic == null:
		civic = CompanyCivicState.new()
		civic.company_id = company_id
		_seed_starter_permits(civic)
		civic_states[company_id] = civic
	return civic


func official(role: StringName) -> OfficialState:
	for state: OfficialState in officials:
		if state.role == role:
			return state
	return null


func official_by_id(def_id: StringName) -> OfficialState:
	for state: OfficialState in officials:
		if state.def_id == def_id:
			return state
	return null


func permit_def(permit_id: StringName) -> PermitDef:
	return permit_catalog.get(permit_id)


func permit_defs() -> Array[PermitDef]:
	var out: Array[PermitDef] = []
	for key: StringName in permit_catalog:
		out.append(permit_catalog[key])
	out.sort_custom(func(a: PermitDef, b: PermitDef) -> bool: return String(a.id) < String(b.id))
	return out


func inspections_for(building_id: int) -> Array[InspectionState]:
	var out: Array[InspectionState] = []
	for insp: InspectionState in inspections:
		if insp.building_id == building_id:
			out.append(insp)
	return out


func pending_inspection_for(building_id: int) -> InspectionState:
	for insp: InspectionState in inspections:
		if insp.building_id == building_id and not insp.visit_done:
			return insp
	return null


func inspection_by_uid(uid: int) -> InspectionState:
	for insp: InspectionState in inspections:
		if insp.uid == uid:
			return insp
	return null


## Live checklist preview for the City Hall UI — what an inspector would find
## RIGHT NOW. Same code path as the real visit, minus scoring side effects.
func checklist_preview(building_id: int, kind: StringName = &"food_safety") -> Array[Dictionary]:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null:
		return []
	return checklist.run_checklist(kind, rest, _checklist_ctx(rest))


## True when the branch launching City Hall should land on the Inspections tab.
func inspection_focus(building_id: int) -> bool:
	if pending_inspection_for(building_id) != null:
		return true
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null:
		return false
	var civic: CompanyCivicState = civic_for(rest.company_id)
	return not civic.open_violations().is_empty()


## Player-facing civic beats for the events panel.
func upcoming_civic(count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not enabled() or CompanyManager.player == null:
		return out
	var player_id: StringName = CompanyManager.player.id
	for insp: InspectionState in inspections:
		if insp.visit_done or insp.company_id != player_id:
			continue
		out.append({
			"title": "%s inspection" % _kind_label(insp.kind),
			"kind": "civic_inspection", "day": insp.scheduled_day,
			"when": GameClock.month_name_for(insp.scheduled_day),
		})
	var civic: CompanyCivicState = civic_for(player_id)
	for row: Dictionary in civic.open_violations():
		out.append({
			"title": "Violation deadline", "kind": "fine",
			"day": int(row.get("deadline_day", GameClock.day)),
			"when": GameClock.month_name_for(int(row.get("deadline_day", GameClock.day))),
		})
	for row: Dictionary in civic.unpaid_fines():
		out.append({
			"title": "Fine due", "kind": "fine",
			"day": int(row.get("appeal_deadline_day", GameClock.day)),
			"when": GameClock.month_name_for(int(row.get("appeal_deadline_day", GameClock.day))),
		})
	for project: DevelopmentProjectState in open_proposals():
		var def: DevelopmentProjectDef = project_def(project.def_id)
		out.append({
			"title": "%s decision" % (def.display_name if def != null else "Development"),
			"kind": "development", "day": project.decision_day,
			"when": GameClock.month_name_for(project.decision_day),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.day) < int(b.day))
	return out.slice(0, count)


## Standing pill for the City Hall header: text + BellaUi tone.
func standing_label(company_id: StringName) -> Dictionary:
	var civic: CompanyCivicState = civic_for(company_id)
	if civic.official_reputation >= 0.75:
		return {"text": "Standing: Excellent", "tone": &"positive"}
	if civic.official_reputation >= 0.5:
		return {"text": "Standing: Good", "tone": &"info"}
	if civic.official_reputation >= 0.3:
		return {"text": "Standing: Watched", "tone": &"warning"}
	return {"text": "Standing: Poor", "tone": &"negative"}


# --- Police ------------------------------------------------------------------

## Baseline response ETA from the nearest station (unit availability shown
## separately) — the number the coverage overlay and incident dialog quote.
func police_eta(building_id: int) -> float:
	if _eta_cache.has(building_id):
		return float(_eta_cache[building_id])
	var target: Vector3 = _building_target(building_id)
	var best: float = police.eta_max
	for station: PoliceStationState in stations:
		var eta: float = SupplyManager.route_eta(station.position, target)
		if eta > 0.0:
			best = minf(best, eta)
	best = clampf(best, police.eta_min, police.eta_max)
	_eta_cache[building_id] = best
	return best


func station_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for station: PoliceStationState in stations:
		out.append(station.position)
	return out


## Crime's police stub delegates here when the government layer is on.
func precinct_positions() -> Array[Vector3]:
	return station_positions()


func city_hall_position() -> Vector3:
	return _city_hall_position


func station_by_id(station_id: int) -> PoliceStationState:
	for station: PoliceStationState in stations:
		if station.station_id == station_id:
			return station
	return null


## Dispatches the nearest available unit. Returns {eta, station_id, wait} or
## {} when the city has no stations. purpose: &"respond" | &"investigate" | &"raid".
func dispatch_unit(building_id: int, purpose: StringName = &"respond") -> Dictionary:
	if stations.is_empty():
		return {}
	var now: int = GameClock.total_minutes()
	var pick: Dictionary = police.nearest_available(
		stations, _building_target(building_id), now, SupplyManager.route_eta)
	if pick.is_empty():
		return {}
	var station: PoliceStationState = station_by_id(int(pick.get("station_id", -1)))
	if station != null:
		police.mark_busy(station, int(pick.get("unit_index", -1)), now, float(pick.get("eta", 0.0)), purpose)
	police_dispatched.emit(building_id, float(pick.get("eta", 0.0)))
	return pick


## Civic-side police call (crime's call_police_cmd validates incidents and
## routes its dispatch through here when government is enabled).
func call_police_cmd(company_id: StringName, building_id: int, _incident_uid: int) -> CommandResult:
	if not enabled():
		return CommandResult.fail(&"government_disabled", "The civic layer is disabled.")
	var pick: Dictionary = dispatch_unit(building_id, &"respond")
	if pick.is_empty():
		return CommandResult.fail(&"no_units", "No police units available.")
	_record_event(BusinessEvent.POLICE, company_id, building_id, 0.0,
		"Police called to %s" % _branch_name(building_id))
	return CommandResult.good({"eta": float(pick.get("eta", 0.0))})


## Reporting a rival to the inspectors. Credible (the checklist would flag
## something right now) -> a complaint inspection is scheduled. Baseless ->
## the reporter's police reputation takes the documented hit instead.
func request_inspection_cmd(company_id: StringName, target_building: int) -> CommandResult:
	if not enabled():
		return CommandResult.fail(&"government_disabled", "The civic layer is disabled.")
	var rest: RestaurantState = RestaurantManager.by_building.get(target_building)
	if rest == null:
		return CommandResult.fail(&"unknown_branch", "No such branch.")
	if rest.company_id == company_id:
		return CommandResult.fail(&"own_branch", "You cannot report your own branch.")
	var fee: float = float(_tuning("government.inspection.report_fee", 100.0))
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null or not company.can_afford(fee):
		return CommandResult.fail(&"cannot_afford", "Not enough cash for the filing fee.")
	company.transact(&"legal_fee", -fee)
	var civic: CompanyCivicState = civic_for(company_id)
	var findings: Array[Dictionary] = checklist.run_checklist(&"food_safety", rest, _checklist_ctx(rest))
	var credible: bool = false
	for row: Dictionary in findings:
		if not bool(row.get("passed", true)):
			credible = true
			break
	if not credible:
		civic.police_reputation = clampf(
			civic.police_reputation - police.false_report_reputation_hit, 0.0, 1.0)
		civic_changed.emit(company_id)
		_notify_company(company_id, "alert",
			"Your report against %s found nothing — the police noted the waste of time." % rest.restaurant_name)
		return CommandResult.good({"credible": false})
	if pending_inspection_for(target_building) == null:
		var days_ahead: int = int(_tuning("government.inspection.rigged_notice_days", 2))
		_schedule_inspection(rest, &"food_safety", GameClock.day + days_ahead, &"rival_report")
	_record_event(BusinessEvent.INSPECTION, company_id, target_building, 0.0,
		"Reported %s to the inspectors" % rest.restaurant_name)
	return CommandResult.good({"credible": true})


## Enforcement decision + civic-side booking for crime heat. CrimeManager
## calls this (gov enabled) instead of its own ladder: government decides,
## books the fine under the legal ledger and publishes the news; crime then
## applies its own raid effects (frozen ops, jailed agents, cleared evidence).
func crime_enforcement(company_id: StringName, heat: float, evidence_total: float,
		day: int) -> Dictionary:
	var commander: OfficialState = official(&"police_commander")
	var scrutiny: float = commander.scrutiny if commander != null else 0.5
	var verdict: Dictionary = police.enforcement_decision(heat, evidence_total, scrutiny)
	var kind: StringName = verdict.get("action", &"none")
	if kind == &"none" or kind == &"investigate":
		return verdict
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null:
		return {"action": &"none", "fine": 0.0}
	var fine: float = float(verdict.get("fine", 0.0))
	company.transact(&"government_fine", -fine)
	var civic: CompanyCivicState = civic_for(company_id)
	civic.fines_total += fine
	civic.official_reputation = clampf(civic.official_reputation - (0.1 if kind == &"raid" else 0.05), 0.0, 1.0)
	if kind == &"raid":
		var target_building: int = _busiest_branch(company_id)
		if target_building >= 0:
			dispatch_unit(target_building, &"raid")
		_record_event(BusinessEvent.RAID, company_id, -1, -fine,
			"Police raid on %s" % _company_name(company_id))
		_news_all("Police raided %s — fines and arrests." % _company_name(company_id))
		if _is_player(company_id):
			police_incident.emit({
				"kind": &"raid", "company_id": company_id, "fine": fine, "day": day,
			})
	else:
		_record_event(BusinessEvent.FINE, company_id, -1, -fine, "Police fine over criminal ties")
		_notify_company(company_id, "alert",
			"The police fined you %s over suspected criminal ties." % _money(fine))
	civic_changed.emit(company_id)
	return verdict


# --- Commands --------------------------------------------------------------

func renew_permit_cmd(company_id: StringName, permit_id: StringName) -> CommandResult:
	if not enabled():
		return CommandResult.fail(&"government_disabled", "The civic layer is disabled.")
	var def: PermitDef = permit_def(permit_id)
	if def == null:
		return CommandResult.fail(&"unknown_permit", "No such permit.")
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null:
		return CommandResult.fail(&"unknown_company", "No such company.")
	if def.required_min_tier > CapabilityRegistry.level(company_id, &"government.permit_tier"):
		return CommandResult.fail(&"prerequisite",
			"%s needs a Government Relations department (level %d)." % [def.display_name, def.required_min_tier])
	if not company.can_afford(def.cost):
		return CommandResult.fail(&"cannot_afford", "Not enough cash for the permit fee.")
	var civic: CompanyCivicState = civic_for(company_id)
	company.transact(&"permit_fee", -def.cost)
	var day: int = GameClock.day
	var row: Dictionary = civic.permit_row(permit_id)
	var base_day: int = maxi(day, int(row.get("expires_day", 0))) if String(row.get("status", "")) == "active" else day
	if row.is_empty():
		row = {"permit_id": permit_id}
		civic.permits.append(row)
	row["status"] = "active"
	row["granted_day"] = day
	row["expires_day"] = base_day + def.renewal_days
	row["cost"] = def.cost
	permit_changed.emit(company_id)
	civic_changed.emit(company_id)
	_record_event(BusinessEvent.PERMIT, company_id, -1, -def.cost,
		"%s renewed" % def.display_name)
	return CommandResult.good({"expires_day": row["expires_day"]})


func pay_fine_cmd(company_id: StringName, fine_uid: int) -> CommandResult:
	if not enabled():
		return CommandResult.fail(&"government_disabled", "The civic layer is disabled.")
	var civic: CompanyCivicState = civic_for(company_id)
	var row: Dictionary = civic.fine_by_uid(fine_uid)
	if row.is_empty():
		return CommandResult.fail(&"unknown_fine", "No such fine.")
	if String(row.get("status", "")) != "unpaid":
		return CommandResult.fail(&"not_payable", "That fine is not open for payment.")
	var amount: float = float(row.get("amount", 0.0))
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null or not company.can_afford(amount):
		return CommandResult.fail(&"cannot_afford", "Not enough cash to pay the fine.")
	company.transact(&"government_fine", -amount)
	row["status"] = "paid"
	row["paid_day"] = GameClock.day
	civic.fines_total += amount
	civic_changed.emit(company_id)
	_record_event(BusinessEvent.FINE, company_id, -1, -amount,
		"Paid fine: %s" % String(row.get("reason", "violation")))
	return CommandResult.good({})


## Appealing costs a legal fee and freezes payment until a seeded decision at
## appeal_decision_day. Overturned fines are struck; rejected ones reopen with
## a fresh payment window.
func appeal_fine_cmd(company_id: StringName, fine_uid: int) -> CommandResult:
	if not enabled():
		return CommandResult.fail(&"government_disabled", "The civic layer is disabled.")
	var civic: CompanyCivicState = civic_for(company_id)
	var row: Dictionary = civic.fine_by_uid(fine_uid)
	if row.is_empty():
		return CommandResult.fail(&"unknown_fine", "No such fine.")
	if String(row.get("status", "")) != "unpaid":
		return CommandResult.fail(&"not_appealable", "That fine is not open for appeal.")
	if GameClock.day > int(row.get("appeal_deadline_day", 0)):
		return CommandResult.fail(&"deadline_passed", "The appeal window has closed.")
	if bool(row.get("appealed_once", false)):
		return CommandResult.fail(&"already_appealed", "A fine can only be appealed once.")
	var fee: float = float(_tuning("government.fines.appeal_fee", 250.0))
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null or not company.can_afford(fee):
		return CommandResult.fail(&"cannot_afford", "Not enough cash for the legal fee.")
	company.transact(&"legal_fee", -fee)
	row["status"] = "appealed"
	row["appealed_once"] = true
	row["appeal_decision_day"] = GameClock.day + int(_tuning("government.inspection.appeal_days", 4))
	civic_changed.emit(company_id)
	_record_event(BusinessEvent.APPEAL, company_id, -1, -fee,
		"Appealed fine: %s" % String(row.get("reason", "violation")))
	return CommandResult.good({"decision_day": row["appeal_decision_day"]})


## Marks a violation fixed IF the underlying live fact now passes its check.
## Fixing before deadline_day provably prevents the documented escalation.
func fix_violation_cmd(company_id: StringName, violation_uid: int) -> CommandResult:
	if not enabled():
		return CommandResult.fail(&"government_disabled", "The civic layer is disabled.")
	var civic: CompanyCivicState = civic_for(company_id)
	var row: Dictionary = civic.violation_by_uid(violation_uid)
	if row.is_empty():
		return CommandResult.fail(&"unknown_violation", "No such violation.")
	if String(row.get("status", "")) != "open":
		return CommandResult.fail(&"not_open", "That violation is already resolved.")
	var building_id: int = int(row.get("building_id", -1))
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null:
		return CommandResult.fail(&"unknown_branch", "That branch no longer exists.")
	var check_id: StringName = StringName(String(row.get("code", "")))
	if not checklist.check_passes_now(check_id, rest, _checklist_ctx(rest)):
		return CommandResult.fail(&"still_failing", String(row.get("corrective",
			"The underlying issue is not corrected yet.")))
	row["status"] = "fixed"
	row["fixed_day"] = GameClock.day
	civic_changed.emit(company_id)
	_notify_company(company_id, "good", "Violation cleared: %s" % String(row.get("label", "issue")))
	return CommandResult.good({})


## Requests an early follow-up visit (fee) so a clean sheet can replace a bad
## grade before the next scheduled cycle.
func request_reinspection_cmd(company_id: StringName, building_id: int) -> CommandResult:
	if not enabled():
		return CommandResult.fail(&"government_disabled", "The civic layer is disabled.")
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null or rest.company_id != company_id:
		return CommandResult.fail(&"not_owner", "That is not your branch.")
	if pending_inspection_for(building_id) != null:
		return CommandResult.fail(&"already_scheduled", "An inspection is already scheduled.")
	var fee: float = float(_tuning("government.inspection.reinspection_fee", 150.0))
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null or not company.can_afford(fee):
		return CommandResult.fail(&"cannot_afford", "Not enough cash for the filing fee.")
	company.transact(&"permit_fee", -fee)
	var days_ahead: int = int(_tuning("government.inspection.reinspection_days", 3))
	var insp: InspectionState = _schedule_inspection(rest, &"food_safety", GameClock.day + days_ahead, &"scheduled")
	return CommandResult.good({"scheduled_day": insp.scheduled_day})


## Crime seam (CrimeManager calls this via has_method guard): a bought audit
## biases the NEXT inspection at the target within a clamped band. Influence
## bends scoring; it never fabricates or erases live findings.
func schedule_rigged_inspection(building_id: int, bias: float) -> void:
	if not enabled():
		return
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null:
		return
	var insp: InspectionState = pending_inspection_for(building_id)
	if insp == null:
		var days_ahead: int = int(_tuning("government.inspection.rigged_notice_days", 2))
		insp = _schedule_inspection(rest, &"food_safety", GameClock.day + days_ahead, &"rigged")
	insp.bias = clampf(insp.bias + bias, -1.0, 1.0)
	insp.trigger = &"rigged" if insp.bias < 0.0 else insp.trigger


# --- Mayor & influence -------------------------------------------------------

## Declared donation or civic sponsorship: bounded reputation + influence +
## goodwill with the receiving official. Public record, no evidence risk.
func donate_cmd(company_id: StringName, official_id: StringName, amount: float,
		kind: StringName = &"declared") -> CommandResult:
	if not enabled():
		return CommandResult.fail(&"government_disabled", "The civic layer is disabled.")
	if amount < 100.0:
		return CommandResult.fail(&"too_small", "Donations start at $100.")
	if kind != &"declared" and kind != &"sponsorship":
		return CommandResult.fail(&"bad_kind", "Unknown donation kind.")
	var officer: OfficialState = official_by_id(official_id)
	if officer == null:
		return CommandResult.fail(&"unknown_official", "No such official.")
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null or not company.can_afford(amount):
		return CommandResult.fail(&"cannot_afford", "Not enough cash for that donation.")
	var civic: CompanyCivicState = civic_for(company_id)
	company.transact(&"civic_donation", -amount)
	var effect: Dictionary = influence_math.donation_effect(
		amount, civic.donations_total, civic.official_reputation)
	civic.donations_total += amount
	civic.official_reputation = clampf(
		civic.official_reputation + float(effect.get("reputation_gain", 0.0)), 0.0, 1.0)
	civic.influence += float(effect.get("influence_gain", 0.0))
	officer.adjust_relationship(company_id, float(effect.get("relationship_gain", 0.0)))
	if officer.role == &"mayor":
		civic.mayor_relationship = clampf(
			civic.mayor_relationship + float(effect.get("relationship_gain", 0.0)), -1.0, 1.0)
		mayor_changed.emit()
	civic.donations.append({
		"uid": next_donation_uid, "kind": String(kind), "amount": amount,
		"day": GameClock.day, "official_id": String(official_id),
		"evidence_risk": 0.0, "exposed": false,
	})
	next_donation_uid += 1
	civic_changed.emit(company_id)
	_record_event(BusinessEvent.DONATION, company_id, -1, -amount,
		"%s to %s" % ["Sponsorship" if kind == &"sponsorship" else "Donation", officer.display_name])
	if amount >= 2500.0:
		_news_all("%s donated %s to the city." % [_company_name(company_id), _money(amount)])
	return CommandResult.good({"reputation": civic.official_reputation, "influence": civic.influence})


## Illicit payment (corruption_mode gated). Success buys goodwill and heavy
## influence; failure burns the money and goodwill; either way the payment
## can leave evidence that later exposes the company. Seeded per attempt.
func bribe_cmd(company_id: StringName, official_id: StringName, amount: float) -> CommandResult:
	if not enabled():
		return CommandResult.fail(&"government_disabled", "The civic layer is disabled.")
	if not corruption_enabled():
		return CommandResult.fail(&"corruption_off", "Corruption is disabled in this scenario.")
	if amount < 500.0:
		return CommandResult.fail(&"too_small", "Nobody risks their career for less than $500.")
	var officer: OfficialState = official_by_id(official_id)
	if officer == null:
		return CommandResult.fail(&"unknown_official", "No such official.")
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null or not company.can_afford(amount):
		return CommandResult.fail(&"cannot_afford", "Not enough cash for that payment.")
	var civic: CompanyCivicState = civic_for(company_id)
	company.transact(&"illicit_payment", -amount)
	var attempt_uid: int = next_donation_uid
	next_donation_uid += 1
	var rng: RandomNumberGenerator = WorkforceRng.make(&"gov_bribe", GameClock.day,
		[String(company_id), String(official_id), attempt_uid])
	var success: bool = rng.randf() < influence_math.bribe_success(amount, officer.integrity)
	var risk: float = influence_math.evidence_risk(amount, officer.integrity)
	var traced: bool = rng.randf() < risk
	if success:
		officer.adjust_relationship(company_id, clampf(amount / 4000.0, 0.05, 0.3))
		civic.influence += amount / 50.0 * influence_math.diminishing_factor(civic.donations_total)
		if officer.role == &"mayor":
			civic.mayor_relationship = clampf(civic.mayor_relationship + amount / 6000.0, -1.0, 1.0)
			mayor_changed.emit()
		_notify_company(company_id, "info", "%s pocketed the envelope." % officer.display_name)
	else:
		officer.adjust_relationship(company_id, -0.1)
		_notify_company(company_id, "alert", "%s refused the envelope." % officer.display_name)
	civic.donations.append({
		"uid": attempt_uid, "kind": "bribe", "amount": amount, "day": GameClock.day,
		"official_id": String(official_id), "evidence_risk": risk, "exposed": traced,
	})
	if traced:
		civic.evidence.append({
			"uid": attempt_uid, "kind": "bribery",
			"strength": clampf(0.3 + amount / 10000.0, 0.3, 0.8), "day": GameClock.day,
		})
		civic.official_reputation = clampf(civic.official_reputation - 0.15, 0.0, 1.0)
		_issue_fine(civic, amount * 2.0, "Bribery investigation")
		_news_all("Corruption probe: %s tied to an illicit payment." % _company_name(company_id))
		_record_event(BusinessEvent.RAID, company_id, -1, -amount, "Bribery exposed")
	civic_changed.emit(company_id)
	return CommandResult.good({"success": success, "exposed": traced})


# --- Development -------------------------------------------------------------

func project_def(def_id: StringName) -> DevelopmentProjectDef:
	return project_defs.get(def_id)


func project_by_uid(uid: int) -> DevelopmentProjectState:
	for project: DevelopmentProjectState in projects:
		if project.uid == uid:
			return project
	return null


func open_proposals() -> Array[DevelopmentProjectState]:
	var out: Array[DevelopmentProjectState] = []
	for project: DevelopmentProjectState in projects:
		if project.status == &"proposed":
			out.append(project)
	return out


## Demand-hook: summed built-project bonus for the restaurant's district
## (clamped band). DemandManager adds this next to the marketing bonus.
func development_bonus(building_id: int) -> float:
	if not enabled():
		return 0.0
	var info: Dictionary = CityData.get_building(building_id)
	var district: String = String(info.get("district", ""))
	if district.is_empty():
		return 0.0
	if _dev_bonus_cache.has(district):
		return float(_dev_bonus_cache[district])
	var total: float = 0.0
	for project: DevelopmentProjectState in projects:
		if project.status != &"built" or project.district != district:
			continue
		var def: DevelopmentProjectDef = project_def(project.def_id)
		if def != null:
			total += development.built_bonus(def)
	total = clampf(total, -development.demand_uplift_max, development.demand_uplift_max)
	_dev_bonus_cache[district] = total
	return total


## Pledge lobbying money behind a proposal. Needs the Government Relations
## department (lobby_capacity caps concurrent backed proposals).
func lobby_development_cmd(company_id: StringName, project_uid: int, amount: float) -> CommandResult:
	if not enabled():
		return CommandResult.fail(&"government_disabled", "The civic layer is disabled.")
	var project: DevelopmentProjectState = project_by_uid(project_uid)
	if project == null or project.status != &"proposed":
		return CommandResult.fail(&"not_open", "That proposal is not taking support.")
	var def: DevelopmentProjectDef = project_def(project.def_id)
	if def == null or not def.sponsors_allowed:
		return CommandResult.fail(&"no_sponsors", "This project does not take sponsors.")
	if amount < 100.0:
		return CommandResult.fail(&"too_small", "Lobbying starts at $100.")
	var capacity: int = CapabilityRegistry.capacity(company_id, &"government.lobby_capacity")
	var backed: int = 0
	for other: DevelopmentProjectState in open_proposals():
		if other.uid != project.uid and other.support.has(String(company_id)):
			backed += 1
	if not project.support.has(String(company_id)) and backed >= capacity:
		return CommandResult.fail(&"capacity",
			"Your lobbyists can back %d proposal%s at once. %s" % [capacity,
				"" if capacity == 1 else "s",
				CapabilityRegistry.explain(company_id, &"government.lobby_capacity")])
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null or not company.can_afford(amount):
		return CommandResult.fail(&"cannot_afford", "Not enough cash for that pledge.")
	company.transact(&"lobbying", -amount)
	var key: String = String(company_id)
	project.support[key] = float(project.support.get(key, 0.0)) + amount
	development_updated.emit(project)
	_record_event(BusinessEvent.LOBBY, company_id, -1, -amount,
		"Backed %s" % (def.display_name if def != null else "a proposal"))
	return CommandResult.good({"support_total": project.support_total()})


func _tick_development(day: int) -> void:
	var cadence: int = int(_tuning("government.development.proposal_cadence_days", 30))
	if cadence > 0 and day % cadence == 0 and open_proposals().size() < 2:
		_propose_project(day)
	for project: DevelopmentProjectState in projects:
		var def: DevelopmentProjectDef = project_def(project.def_id)
		if def == null:
			continue
		if project.status == &"proposed" and day >= project.decision_day:
			_decide_project(project, def, day)
		elif project.status == &"approved" and day >= project.decision_day + def.build_days:
			project.status = &"built"
			project.applied = true
			_dev_bonus_cache.clear()
			development_updated.emit(project)
			_news_all("%s finished in district %s — the neighborhood is busier." % [
				def.display_name, project.district])
			_record_event(BusinessEvent.DEVELOPMENT, &"", -1, 1.0, "%s built" % def.display_name)


func _propose_project(day: int) -> void:
	if project_defs.is_empty():
		return
	var rng: RandomNumberGenerator = WorkforceRng.make(&"gov_dev", day, [])
	var ids: Array = project_defs.keys()
	ids.sort()
	var def: DevelopmentProjectDef = project_defs[ids[rng.randi_range(0, ids.size() - 1)]]
	var district: String = def.target_district
	if district.is_empty():
		var districts: Array[String] = []
		for rest: RestaurantState in RestaurantManager.all_restaurants():
			if not districts.has(rest.district):
				districts.append(rest.district)
		if districts.is_empty():
			districts.append("C")
		districts.sort()
		district = districts[rng.randi_range(0, districts.size() - 1)]
	var project: DevelopmentProjectState = DevelopmentProjectState.new()
	project.uid = next_project_uid
	next_project_uid += 1
	project.def_id = def.id
	project.district = district
	project.proposed_day = day
	project.decision_day = day + def.decision_days
	projects.append(project)
	development_updated.emit(project)
	_news_all("City Hall proposed a %s for district %s — decision Day %d." % [
		def.display_name.to_lower(), district, project.decision_day])
	_record_event(BusinessEvent.DEVELOPMENT, &"", -1, 0.0, "%s proposed" % def.display_name)


func _decide_project(project: DevelopmentProjectState, def: DevelopmentProjectDef, day: int) -> void:
	var top_relationship: float = 0.0
	var top_support: float = -1.0
	for key: String in project.support:
		var pledged: float = float(project.support[key])
		if pledged > top_support:
			top_support = pledged
			top_relationship = civic_for(StringName(key)).mayor_relationship
	var rng: RandomNumberGenerator = WorkforceRng.make(&"gov_dev_decide", project.decision_day, [project.uid])
	var approved: bool = development.decide(def, project, top_relationship, rng)
	var chance: float = development.approval_chance(def, project.support_total(), top_relationship)
	if approved:
		project.status = &"approved"
		project.rationale = "Approved (%d%% support-adjusted odds); construction takes %d days." % [
			int(round(chance * 100.0)), def.build_days]
		_news_all("The council approved the %s in district %s." % [def.display_name.to_lower(), project.district])
	else:
		project.status = &"rejected"
		project.rationale = "Rejected despite %d%% support-adjusted odds — the council was not convinced." % int(round(chance * 100.0))
		_news_all("The council rejected the %s in district %s." % [def.display_name.to_lower(), project.district])
	development_updated.emit(project)
	_record_event(BusinessEvent.DEVELOPMENT, &"", -1, 1.0 if approved else -1.0,
		"%s %s" % [def.display_name, "approved" if approved else "rejected"])
	var _unused: int = day


## Bounded award-jury nudge for AwardsManager (guarded has_method call).
## Zero when the layer is off; clamped by InfluenceService either way.
func award_bias(company_id: StringName) -> float:
	if not enabled():
		return 0.0
	var civic: CompanyCivicState = civic_for(company_id)
	return influence_math.award_bias(civic.influence, civic.mayor_relationship)


# --- Save ------------------------------------------------------------------

func write_save(save: SaveGame) -> void:
	save.government_schema_version = SCHEMA_VERSION
	save.police_stations = stations.duplicate()
	save.development_projects = projects.duplicate()
	var civic_list: Array[CompanyCivicState] = []
	for key: StringName in civic_states:
		civic_list.append(civic_states[key])
	save.civic_states = civic_list
	save.gov_officials = officials.duplicate()
	save.gov_inspections = inspections.duplicate()
	save.gov_next_uids = {
		"inspection": next_inspection_uid,
		"fine": next_fine_uid,
		"violation": next_violation_uid,
		"donation": next_donation_uid,
		"project": next_project_uid,
	}


func restore_from_save(save: SaveGame) -> void:
	if save.government_schema_version <= 0:
		return
	civic_states.clear()
	for civic: CompanyCivicState in save.civic_states:
		civic_states[civic.company_id] = civic
	officials = save.gov_officials.duplicate()
	inspections = save.gov_inspections.duplicate()
	stations = save.police_stations.duplicate()
	projects = save.development_projects.duplicate()
	next_inspection_uid = int(save.gov_next_uids.get("inspection", 1))
	next_fine_uid = int(save.gov_next_uids.get("fine", 1))
	next_violation_uid = int(save.gov_next_uids.get("violation", 1))
	next_donation_uid = int(save.gov_next_uids.get("donation", 1))
	next_project_uid = int(save.gov_next_uids.get("project", 1))


# --- Lifecycle -------------------------------------------------------------

func _on_minute_ticked(_day: int, _hour: int, _minute: int) -> void:
	if not enabled():
		return
	var now: int = GameClock.total_minutes()
	for insp: InspectionState in inspections:
		if not insp.visit_done and now >= insp.visit_minute:
			_conduct_inspection(insp)


func _on_buckets_closed(closed_day: int) -> void:
	if not enabled():
		return
	var day: int = closed_day + 1
	_eta_cache.clear()
	_dev_bonus_cache.clear()
	_schedule_due_inspections(day)
	_roll_complaints(day)
	_tick_development(day)
	for company_id: StringName in civic_states.keys():
		var civic: CompanyCivicState = civic_states[company_id]
		_escalate_overdue_violations(civic, day)
		_process_appeals(civic, day)
		_lapse_permits(civic, day)
		_drift_reputation(civic)
		influence_math.decay(civic)
	_reopen_civic_closures(day)
	_trim_inspections()


## City tax accrues daily on revenue; unpayable tax becomes visible debt that
## the tax audit checklist reads. Runs inside EconomyManager's daily close.
func _charge_daily(company: CompanyState, day: int) -> void:
	if not enabled():
		return
	var rate: float = float(_tuning("government.tax.daily_revenue_rate", 0.015))
	var tax: float = company.income_today() * rate
	if tax <= 0.0:
		return
	var civic: CompanyCivicState = civic_for(company.id)
	if company.cash >= tax:
		company.transact(&"city_tax", -tax)
		civic.tax_paid_total += tax
		# Paying down old debt happens alongside regular payments.
		if civic.tax_debt > 0.0 and company.cash >= civic.tax_debt:
			company.transact(&"city_tax", -civic.tax_debt)
			civic.tax_paid_total += civic.tax_debt
			civic.tax_debt = 0.0
			_notify_company(company.id, "good", "Back taxes settled with the city.")
	else:
		civic.tax_debt += tax
		if company.is_player:
			EconomyManager.post_message("alert",
				"You could not cover today's city tax — the shortfall is on record.")
	var _unused: int = day


# --- Inspections -----------------------------------------------------------

func _schedule_due_inspections(day: int) -> void:
	var period: int = int(_tuning("government.inspection.period_days", 21))
	var notice: int = int(_tuning("government.inspection.notice_days", 5))
	for rest: RestaurantState in RestaurantManager.all_restaurants():
		if pending_inspection_for(rest.building_id) != null:
			continue
		var last: int = _last_inspection_day(rest.building_id)
		if last <= 0:
			# New branches get their first visit half a cycle in.
			last = day - period / 2
		if day - last < period - notice:
			continue
		_schedule_inspection(rest, &"food_safety", day + notice, &"scheduled")


func _schedule_inspection(rest: RestaurantState, kind: StringName, visit_day: int,
		trigger: StringName) -> InspectionState:
	var insp: InspectionState = InspectionState.new()
	insp.uid = next_inspection_uid
	next_inspection_uid += 1
	insp.building_id = rest.building_id
	insp.company_id = rest.company_id
	insp.kind = kind
	insp.trigger = trigger
	insp.scheduled_day = visit_day
	var officer: OfficialState = official(_official_role_for(kind))
	insp.official_id = officer.def_id if officer != null else &""
	# Freeze the visit minute now: 09:00-15:00, seeded per inspection.
	var rng: RandomNumberGenerator = WorkforceRng.make(&"gov_inspection", visit_day, [insp.uid])
	insp.visit_minute = (visit_day - 1) * 1440 + 9 * 60 + rng.randi_range(0, 6 * 60)
	inspections.append(insp)
	inspection_scheduled.emit(insp)
	_notify_company(rest.company_id, "info", "%s inspection at %s — Day %d." % [
		_kind_label(kind), rest.restaurant_name, visit_day])
	_record_event(BusinessEvent.INSPECTION, rest.company_id, rest.building_id, 0.0,
		"%s inspection scheduled" % _kind_label(kind))
	return insp


## The visit: findings frozen from LIVE state, scored once (outcome_applied),
## grade effects applied immediately and idempotently.
func _conduct_inspection(insp: InspectionState) -> void:
	if insp.outcome_applied:
		insp.visit_done = true
		return
	var rest: RestaurantState = RestaurantManager.by_building.get(insp.building_id)
	insp.visit_done = true
	insp.outcome_applied = true
	if rest == null:
		insp.grade = &"clean"
		return
	insp.findings = checklist.run_checklist(insp.kind, rest, _checklist_ctx(rest))
	var verdict: Dictionary = checklist.score_findings(insp.findings, insp.bias)
	insp.score = float(verdict.get("score", 100.0))
	insp.grade = verdict.get("grade", &"clean")
	insp.appeal_deadline_day = GameClock.day + int(_tuning("government.inspection.appeal_days", 4))
	var civic: CompanyCivicState = civic_for(insp.company_id)
	_open_violations_from(insp, civic)
	_apply_grade(insp, civic, rest)
	civic_changed.emit(insp.company_id)
	inspection_completed.emit(insp.building_id, insp)


func _open_violations_from(insp: InspectionState, civic: CompanyCivicState) -> void:
	var remediation: int = int(_tuning("government.inspection.remediation_days", 5))
	for row: Dictionary in insp.failed_findings():
		civic.violations.append({
			"uid": next_violation_uid,
			"inspection_uid": insp.uid,
			"building_id": insp.building_id,
			"code": String(row.get("check_id", "")),
			"label": String(row.get("label", "")),
			"severity": int(row.get("severity", 1)),
			"day": GameClock.day,
			"corrective": String(row.get("corrective", "")),
			"needed": String(row.get("needed", "")),
			"deadline_day": GameClock.day + remediation,
			"status": "open",
			"outcome_applied": false,
		})
		next_violation_uid += 1


func _apply_grade(insp: InspectionState, civic: CompanyCivicState, rest: RestaurantState) -> void:
	var company_is_player: bool = _is_player(insp.company_id)
	match insp.grade:
		&"clean":
			civic.official_reputation = clampf(civic.official_reputation + 0.05, 0.0, 1.0)
			_notify_company(insp.company_id, "good",
				"%s passed its %s inspection." % [rest.restaurant_name, _kind_label(insp.kind)])
			_record_event(BusinessEvent.INSPECTION, insp.company_id, insp.building_id,
				0.0, "Clean inspection at %s" % rest.restaurant_name)
		&"warning":
			civic.official_reputation = clampf(civic.official_reputation - 0.02, 0.0, 1.0)
			_notify_company(insp.company_id, "alert",
				"Inspection warning at %s — fix the findings before Day %d." % [
					rest.restaurant_name, GameClock.day + int(_tuning("government.inspection.remediation_days", 5))])
		&"remediation":
			civic.official_reputation = clampf(civic.official_reputation - 0.04, 0.0, 1.0)
			_notify_company(insp.company_id, "alert",
				"Remediation ordered at %s — correct the violations before the deadline." % rest.restaurant_name)
		&"fine":
			civic.official_reputation = clampf(civic.official_reputation - 0.06, 0.0, 1.0)
			var amount: float = _fine_amount(insp)
			_issue_fine(civic, amount, "Failed %s inspection" % _kind_label(insp.kind))
			_notify_company(insp.company_id, "alert",
				"Failed inspection at %s — fined %s." % [rest.restaurant_name, _money(amount)])
		&"closure":
			civic.official_reputation = clampf(civic.official_reputation - 0.12, 0.0, 1.0)
			var amount: float = _fine_amount(insp)
			_issue_fine(civic, amount, "Severe %s violations" % _kind_label(insp.kind))
			var days: int = int(_tuning("government.fines.closure_days", 3))
			_close_branch(rest, days, "inspection")
			if company_is_player:
				EconomyManager.post_message("alert",
					"%s was closed for %d days by the %s inspector." % [
						rest.restaurant_name, days, _kind_label(insp.kind)])
			_news_all("%s shut down %s after a failed inspection." % [
				"The city", rest.restaurant_name])


func _fine_amount(insp: InspectionState) -> float:
	var base: float = float(_tuning("government.fines.base", 2000.0))
	var per_severity: float = float(_tuning("government.fines.per_severity", 800.0))
	var severity_sum: int = 0
	for row: Dictionary in insp.failed_findings():
		severity_sum += int(row.get("severity", 1))
	return base + per_severity * float(maxi(severity_sum - 1, 0))


func _issue_fine(civic: CompanyCivicState, amount: float, reason: String) -> Dictionary:
	var row: Dictionary = {
		"uid": next_fine_uid,
		"amount": amount,
		"reason": reason,
		"day": GameClock.day,
		"status": "unpaid",
		"appeal_deadline_day": GameClock.day + int(_tuning("government.inspection.appeal_days", 4)),
		"appealed_once": false,
		"late_applied": false,
		"outcome_applied": true,
	}
	next_fine_uid += 1
	civic.fines.append(row)
	fine_issued.emit(civic.company_id, row)
	_record_event(BusinessEvent.FINE, civic.company_id, -1, -amount, reason)
	return row


func _close_branch(rest: RestaurantState, days: int, _reason: String) -> void:
	rest.closed_until_day = maxi(rest.closed_until_day, GameClock.day + days)
	RestaurantManager.set_channels(rest.building_id, false, false)
	var civic: CompanyCivicState = civic_for(rest.company_id)
	civic.closures.append({
		"building_id": rest.building_id,
		"reason": _reason,
		"until_day": rest.closed_until_day,
	})


# --- Day-close bookkeeping -------------------------------------------------

## Open violations past their deadline escalate exactly as documented: a fine
## sized by severity, plus an official-reputation hit. outcome_applied guards
## the once-only escalation across save/load.
func _escalate_overdue_violations(civic: CompanyCivicState, day: int) -> void:
	for row: Dictionary in civic.violations:
		if String(row.get("status", "")) != "open":
			continue
		if day <= int(row.get("deadline_day", 0)):
			continue
		if bool(row.get("outcome_applied", false)):
			continue
		row["status"] = "escalated"
		row["outcome_applied"] = true
		var severity: int = int(row.get("severity", 1))
		var amount: float = float(_tuning("government.fines.base", 2000.0)) * 0.5 \
			+ float(_tuning("government.fines.per_severity", 800.0)) * float(severity)
		_issue_fine(civic, amount, "Uncorrected violation: %s" % String(row.get("label", "")))
		civic.official_reputation = clampf(civic.official_reputation - 0.03, 0.0, 1.0)
		_notify_company(civic.company_id, "alert",
			"Violation escalated — %s. A fine of %s was issued." % [
				String(row.get("label", "")), _money(amount)])
	civic_changed.emit(civic.company_id)


func _process_appeals(civic: CompanyCivicState, day: int) -> void:
	for row: Dictionary in civic.fines:
		if String(row.get("status", "")) != "appealed":
			continue
		if day < int(row.get("appeal_decision_day", 0)):
			continue
		var rng: RandomNumberGenerator = WorkforceRng.make(&"gov_appeal",
			int(row.get("appeal_decision_day", day)), [int(row.get("uid", 0))])
		var overturn_chance: float = float(_tuning("government.fines.appeal_overturn_chance", 0.35))
		# Good standing helps a little; the band stays bounded.
		overturn_chance = clampf(overturn_chance + (civic.official_reputation - 0.5) * 0.2, 0.05, 0.75)
		if rng.randf() < overturn_chance:
			row["status"] = "overturned"
			_notify_company(civic.company_id, "good",
				"Appeal won — the %s fine was overturned." % _money(float(row.get("amount", 0.0))))
		else:
			row["status"] = "unpaid"
			row["appeal_deadline_day"] = day + int(_tuning("government.inspection.appeal_days", 4))
			_notify_company(civic.company_id, "alert",
				"Appeal rejected — the %s fine stands." % _money(float(row.get("amount", 0.0))))
	# Unpaid fines past their window grow once by the late multiplier.
	for row: Dictionary in civic.fines:
		if String(row.get("status", "")) != "unpaid" or bool(row.get("late_applied", false)):
			continue
		if day <= int(row.get("appeal_deadline_day", 0)):
			continue
		row["late_applied"] = true
		row["amount"] = float(row.get("amount", 0.0)) * float(_tuning("government.fines.late_multiplier", 1.5))
		civic.official_reputation = clampf(civic.official_reputation - 0.02, 0.0, 1.0)
		_notify_company(civic.company_id, "alert",
			"Overdue fine increased to %s." % _money(float(row.get("amount", 0.0))))


func _lapse_permits(civic: CompanyCivicState, day: int) -> void:
	var grace: int = int(_tuning("government.permits.lapse_grace_days", 3))
	for row: Dictionary in civic.permits:
		if String(row.get("status", "")) != "active":
			continue
		if day <= int(row.get("expires_day", 0)) + grace:
			if day == int(row.get("expires_day", 0)):
				var def: PermitDef = permit_def(StringName(String(row.get("permit_id", ""))))
				_notify_company(civic.company_id, "alert", "%s expires today — renew it at City Hall." % (
					def.display_name if def != null else "A permit"))
			continue
		row["status"] = "lapsed"
		permit_changed.emit(civic.company_id)
		var lapsed_def: PermitDef = permit_def(StringName(String(row.get("permit_id", ""))))
		_notify_company(civic.company_id, "alert", "%s has lapsed." % (
			lapsed_def.display_name if lapsed_def != null else "A permit"))
		_record_event(BusinessEvent.PERMIT, civic.company_id, -1, 0.0, "%s lapsed" % (
			lapsed_def.display_name if lapsed_def != null else "Permit"))


## Reputation drifts gently toward neutral so old sins and old favors fade.
func _drift_reputation(civic: CompanyCivicState) -> void:
	var drift: float = float(_tuning("government.inspection.reputation_drift", 0.005))
	civic.official_reputation = clampf(
		civic.official_reputation + signf(0.5 - civic.official_reputation) * drift, 0.0, 1.0)


func _reopen_civic_closures(day: int) -> void:
	for rest: RestaurantState in RestaurantManager.all_restaurants():
		if rest.closed_until_day > 0 and day >= rest.closed_until_day:
			rest.closed_until_day = 0
			RestaurantManager.set_channels(rest.building_id, true, rest.delivery_enabled)
			_notify_company(rest.company_id, "good", "%s reopened." % rest.restaurant_name)
	for company_id: StringName in civic_states.keys():
		var civic: CompanyCivicState = civic_states[company_id]
		var kept: Array[Dictionary] = []
		for row: Dictionary in civic.closures:
			if day < int(row.get("until_day", 0)):
				kept.append(row)
		civic.closures = kept


func _trim_inspections() -> void:
	if inspections.size() <= 80:
		return
	var kept: Array[InspectionState] = []
	var finished_budget: int = 50
	for i: int in range(inspections.size() - 1, -1, -1):
		var insp: InspectionState = inspections[i]
		if not insp.visit_done:
			kept.append(insp)
		elif finished_budget > 0:
			kept.append(insp)
			finished_budget -= 1
	kept.reverse()
	inspections = kept


# --- Seeding / internals ---------------------------------------------------

func _ensure_states() -> void:
	for company: CompanyState in CompanyManager.companies:
		# Re-seeding is idempotent (per-permit presence check), so states that
		# were created before the catalogs loaded still get their starter permits.
		_seed_starter_permits(civic_for(company.id))


func _on_company_registered(_company: CompanyState) -> void:
	_ensure_states()


func _seed_starter_permits(civic: CompanyCivicState) -> void:
	var day: int = GameClock.day if GameClock != null else 1
	for permit_id: StringName in STARTER_PERMITS:
		var def: PermitDef = permit_def(permit_id)
		if def == null or not civic.permit_row(permit_id).is_empty():
			continue
		civic.permits.append({
			"permit_id": permit_id,
			"status": "active",
			"granted_day": day,
			"expires_day": day + def.renewal_days,
			"cost": def.cost,
		})


## Complaint-triggered visits: a small seeded daily chance per branch, tripled
## when the branch would visibly fail a walk-in check today — unhappy
## customers talk. Deterministic per (day, building).
func _roll_complaints(day: int) -> void:
	var base_chance: float = float(_tuning("government.inspection.complaint_chance_per_day", 0.03))
	if base_chance <= 0.0:
		return
	for rest: RestaurantState in RestaurantManager.all_restaurants():
		if pending_inspection_for(rest.building_id) != null:
			continue
		var rng: RandomNumberGenerator = WorkforceRng.make(&"gov_complaint", day, [rest.building_id])
		var roll: float = rng.randf()
		if roll >= base_chance * 3.0:
			continue
		var chance: float = base_chance
		if roll < base_chance * 3.0:
			var findings: Array[Dictionary] = checklist.run_checklist(&"food_safety", rest, _checklist_ctx(rest))
			for row: Dictionary in findings:
				if not bool(row.get("passed", true)):
					chance = base_chance * 3.0
					break
		if roll < chance:
			var notice: int = int(_tuning("government.inspection.rigged_notice_days", 2))
			_schedule_inspection(rest, &"food_safety", day + notice, &"complaint")


## Stations and City Hall anchor on deterministic civic-leaning buildings
## (sorted ids + seeded picks), replacing crime's two random precincts.
func _seed_stations() -> void:
	if not stations.is_empty():
		for station: PoliceStationState in stations:
			station.ensure_units()
		return
	var count: int = int(_tuning("government.police.station_count", 2))
	var units: int = int(_tuning("government.police.units_per_station", 2))
	var picks: Array[int] = _pick_civic_buildings(&"gov_station", count)
	var station_id: int = 1
	for building_id: int in picks:
		var info: Dictionary = CityData.get_building(building_id)
		var station: PoliceStationState = PoliceStationState.new()
		station.station_id = station_id
		station_id += 1
		station.building_id = building_id
		station.position = info.get("position", Vector3.ZERO)
		station.unit_count = units
		station.ensure_units()
		stations.append(station)
	if stations.is_empty():
		var fallback: PoliceStationState = PoliceStationState.new()
		fallback.station_id = 1
		fallback.unit_count = units
		fallback.ensure_units()
		stations.append(fallback)


func _seed_city_hall() -> void:
	if city_hall_building_id >= 0:
		var known: Dictionary = CityData.get_building(city_hall_building_id)
		_city_hall_position = known.get("position", _city_hall_position)
		return
	var picks: Array[int] = _pick_civic_buildings(&"gov_city_hall", 1)
	if picks.is_empty():
		return
	city_hall_building_id = picks[0]
	var info: Dictionary = CityData.get_building(city_hall_building_id)
	_city_hall_position = info.get("position", Vector3.ZERO)


## Deterministic anchor picks: prefer civic-typed buildings, then downtown
## offices, spread by taking seeded picks from the sorted candidate list.
func _pick_civic_buildings(domain: StringName, count: int) -> Array[int]:
	var out: Array[int] = []
	var ids: Array = CityData.buildings.keys()
	if ids.is_empty():
		return out
	ids.sort()
	var civic: Array[int] = []
	var downtown: Array[int] = []
	for id: int in ids:
		var info: Dictionary = CityData.get_building(id)
		var btype: String = String(info.get("type", ""))
		if btype == "civic":
			civic.append(id)
		elif btype == "office" and String(info.get("district", "")) == "D":
			downtown.append(id)
	var pool: Array[int] = civic if civic.size() >= count else civic + downtown
	if pool.is_empty():
		for id: int in ids:
			pool.append(int(id))
	var rng: RandomNumberGenerator = WorkforceRng.make(domain, 0, [])
	var taken: Dictionary = {}
	while out.size() < count and taken.size() < pool.size():
		var index: int = rng.randi_range(0, pool.size() - 1)
		if taken.has(index):
			continue
		taken[index] = true
		out.append(pool[index])
	return out


func _building_target(building_id: int) -> Vector3:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest != null and rest.door_pos != Vector3.ZERO:
		return rest.door_pos
	var info: Dictionary = CityData.get_building(building_id)
	return info.get("position", Vector3.ZERO)


func _busiest_branch(company_id: StringName) -> int:
	var best: int = -1
	var best_sales: float = -1.0
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null:
		return -1
	for rest: RestaurantState in company.restaurants:
		var sales: float = rest.today.get("sales", 0.0) if "today" in rest else 0.0
		if sales > best_sales:
			best_sales = sales
			best = rest.building_id
	return best


## Officials are seeded once per world, deterministically jittered around the
## catalog baselines. Rampant corruption drops everyone's integrity a notch.
func _seed_officials() -> void:
	if not officials.is_empty():
		return
	var rng: RandomNumberGenerator = WorkforceRng.make(&"gov_officials", 0, [])
	var integrity_shift: float = -0.15 if corruption_mode() == &"rampant" else 0.0
	var ids: Array = official_defs.keys()
	ids.sort()
	for def_id: StringName in ids:
		var def: OfficialDef = official_defs[def_id]
		var state: OfficialState = OfficialState.new()
		state.def_id = def.id
		state.role = def.role
		state.display_name = def.display_name
		state.integrity = clampf(def.base_integrity + rng.randf_range(-0.1, 0.1) + integrity_shift, 0.05, 1.0)
		state.scrutiny = clampf(def.base_scrutiny + rng.randf_range(-0.1, 0.1), 0.1, 1.0)
		state.priorities = def.priorities.duplicate(true)
		officials.append(state)


func _load_catalogs() -> void:
	official_defs.clear()
	permit_catalog.clear()
	_load_dir(OFFICIALS_DIR, func(res: Resource) -> void:
		var def: OfficialDef = res as OfficialDef
		if def != null and def.id != &"":
			official_defs[def.id] = def)
	_load_dir(PERMITS_DIR, func(res: Resource) -> void:
		var def: PermitDef = res as PermitDef
		if def != null and def.id != &"":
			permit_catalog[def.id] = def)
	_load_dir(DEVELOPMENT_DIR, func(res: Resource) -> void:
		var def: DevelopmentProjectDef = res as DevelopmentProjectDef
		if def != null and def.id != &"":
			project_defs[def.id] = def)


func _load_dir(dir_path: String, sink: Callable) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for file: String in dir.get_files():
		if file.ends_with(".tres") or file.ends_with(".res"):
			sink.call(load("%s/%s" % [dir_path, file]))


func _checklist_ctx(rest: RestaurantState) -> Dictionary:
	var civic: CompanyCivicState = civic_for(rest.company_id)
	var paid: float = civic.tax_paid_total
	var owed: float = paid + civic.tax_debt
	return {
		"day": GameClock.day,
		"hour": GameClock.game_hours,
		"now_minutes": GameClock.total_minutes(),
		"civic": civic,
		"tax_ratio": 1.0 if owed <= 0.0 else paid / owed,
	}


func _last_inspection_day(building_id: int) -> int:
	var last: int = 0
	for insp: InspectionState in inspections:
		if insp.building_id == building_id and insp.visit_done:
			last = maxi(last, insp.scheduled_day)
	return last


func _official_role_for(kind: StringName) -> StringName:
	match kind:
		&"labor":
			return &"labor_inspector"
		&"tax":
			return &"tax_official"
	return &"food_inspector"


func _kind_label(kind: StringName) -> String:
	match kind:
		&"labor":
			return "Labor"
		&"tax":
			return "Tax"
	return "Health"


func _is_player(company_id: StringName) -> bool:
	var company: CompanyState = CompanyManager.company(company_id)
	return company != null and company.is_player


func _branch_name(building_id: int) -> String:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	return rest.restaurant_name if rest != null else "a local business"


func _company_name(company_id: StringName) -> String:
	var company: CompanyState = CompanyManager.company(company_id)
	return company.display_name if company != null else String(company_id)


func _record_event(ev_type: StringName, company_id: StringName, building_id: int,
		amount: float, title: String) -> void:
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
	EconomyManager.post_company_message(Color(0.28, 0.42, 0.6), "news", text)


func _money(amount: float) -> String:
	return "$%s" % String("%.0f" % amount)


func _tuning(path: String, fallback: Variant) -> Variant:
	return EconomyManager.tuning_value(path, fallback)


func _autoload_node(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(NodePath(node_name))
