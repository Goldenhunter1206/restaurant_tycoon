class_name GovernmentReconciliation
extends RefCounted
## Static acceptance suite for feature 13 (government, mayor & police).
##
## Maps to the feature-plan acceptance criteria: every checklist finding is a
## live restaurant fact with a concrete corrective (and fixing the fact flips
## the check), scoring/grading is deterministic with influence bounded to a
## clamped band, police dispatch picks the nearest available unit and the
## enforcement ladder needs evidence, development approval is bounded and
## seeded, and the v13 save section round-trips / migrates.
##
## Headless caveat (see tests/awards_reconciliation.gd): SaveGame and
## RestaurantState pull the CompanyState compile chain, so sim-state objects
## are built via load().new() at run time and passed around untyped. The
## government data/service classes are autoload-free and safe to name.
## Run via scripts/tests/test_government.gd.

const SG_SCRIPT: String = "res://scripts/data/save_game.gd"
const SS_SCRIPT: String = "res://scripts/data/save_system.gd"
const REST_SCRIPT: String = "res://scripts/data/restaurant_state.gd"
const INVENTORY_SCRIPT: String = "res://scripts/data/inventory_state.gd"
const LOT_SCRIPT: String = "res://scripts/data/stock_lot.gd"
const LAYOUT_SCRIPT: String = "res://scripts/data/interior_layout_state.gd"
const FURNITURE_SCRIPT: String = "res://scripts/data/placed_furniture_state.gd"
const STAFF_SCRIPT: String = "res://scripts/data/staff_member.gd"
const TMP_PATH: String = "user://test_government_roundtrip.tres"

static var _checks: int = 0


static func run() -> Dictionary:
	_checks = 0
	var failures: Array[String] = []
	_test_checklist_reads_live_state(failures)
	_test_checklist_determinism(failures)
	_test_scoring_and_bias_band(failures)
	_test_influence_bounded(failures)
	_test_police_dispatch(failures)
	_test_enforcement_ladder(failures)
	_test_development_bounds(failures)
	_test_state_helpers(failures)
	_test_state_roundtrip(failures)
	_test_migration_v13(failures)
	return {"ok": failures.is_empty(), "checks": _checks, "failures": failures}


static func _expect(cond: bool, message: String, failures: Array[String]) -> void:
	_checks += 1
	if not cond:
		failures.append(message)


# --- Builders --------------------------------------------------------------

static func _tuning() -> Callable:
	return func(_path: String, fallback: Variant) -> Variant: return fallback


static func _checklist() -> ChecklistService:
	var service: ChecklistService = ChecklistService.new()
	service.configure(_tuning())
	return service


## A healthy restaurant that passes every food_safety check.
static func _clean_restaurant(now_minutes: int):
	var rest = load(REST_SCRIPT).new()
	rest.building_id = 7
	rest.company_id = &"test_co"
	rest.restaurant_name = "Test Trattoria"
	rest.open_hour = 10.0
	rest.close_hour = 22.0
	rest.inventory = load(INVENTORY_SCRIPT).new()
	var lot = load(LOT_SCRIPT).new()
	lot.ingredient_id = &"tomato"
	lot.qty = 10.0
	lot.supplier_id = &"fresh_farms"
	lot.expiry_minute = now_minutes + 4000
	lot.acquired_minute = now_minutes - 100
	rest.inventory.lots.append(lot)
	rest.interior_layout = load(LAYOUT_SCRIPT).new()
	var chair = load(FURNITURE_SCRIPT).new()
	chair.def_id = &"chair"
	chair.durability = 90.0
	chair.cleanliness = 0.9
	rest.interior_layout.placed.append(chair)
	var cook = load(STAFF_SCRIPT).new()
	cook.shift_start = 9.0
	cook.shift_hours = 8.0
	rest.staff.append(cook)
	return rest


static func _civic(day: int) -> CompanyCivicState:
	var civic: CompanyCivicState = CompanyCivicState.new()
	civic.company_id = &"test_co"
	civic.permits.append({"permit_id": &"business_license", "status": "active",
		"granted_day": day, "expires_day": day + 42, "cost": 500.0})
	civic.permits.append({"permit_id": &"food_handling", "status": "active",
		"granted_day": day, "expires_day": day + 42, "cost": 350.0})
	return civic


static func _ctx(day: int, now_minutes: int, civic: CompanyCivicState) -> Dictionary:
	return {"day": day, "hour": 12.0, "now_minutes": now_minutes,
		"civic": civic, "tax_ratio": 1.0}


static func _station(id: int, pos: Vector3, units: int = 2) -> PoliceStationState:
	var station: PoliceStationState = PoliceStationState.new()
	station.station_id = id
	station.position = pos
	station.unit_count = units
	station.ensure_units()
	return station


## Straight-line minutes stand-in for SupplyManager.route_eta.
static func _eta_fn() -> Callable:
	return func(from: Vector3, to: Vector3) -> float: return from.distance_to(to) / 10.0


# --- Checklist reads live state ---------------------------------------------

static func _test_checklist_reads_live_state(failures: Array[String]) -> void:
	var now: int = 10_000
	var day: int = 8
	var service: ChecklistService = _checklist()
	var rest = _clean_restaurant(now)
	var civic: CompanyCivicState = _civic(day)
	var ctx: Dictionary = _ctx(day, now, civic)
	var clean_findings: Array[Dictionary] = service.run_checklist(&"food_safety", rest, ctx)
	var clean_fails: int = 0
	for row: Dictionary in clean_findings:
		if not bool(row.get("passed", true)):
			clean_fails += 1
	_expect(clean_fails == 0, "healthy restaurant fails %d checks" % clean_fails, failures)
	# Spoil a lot -> expired_stock fails with a corrective; discard -> passes.
	rest.inventory.lots[0].expiry_minute = now - 1
	_expect(not service.check_passes_now(&"expired_stock", rest, ctx),
		"expired lot not flagged", failures)
	var expired_row: Dictionary = {}
	for row: Dictionary in service.run_checklist(&"food_safety", rest, ctx):
		if row.get("check_id") == &"expired_stock":
			expired_row = row
	_expect(not String(expired_row.get("corrective", "")).is_empty(),
		"expired_stock finding carries no corrective", failures)
	rest.inventory.lots[0].qty = 0.0
	_expect(service.check_passes_now(&"expired_stock", rest, ctx),
		"discarding expired stock does not clear the check", failures)
	# Dirty furniture -> cleanliness fails; cleaning fixes it.
	rest.interior_layout.placed[0].cleanliness = 0.2
	_expect(not service.check_passes_now(&"kitchen_cleanliness", rest, ctx),
		"dirty furniture not flagged", failures)
	rest.interior_layout.placed[0].cleanliness = 0.9
	_expect(service.check_passes_now(&"kitchen_cleanliness", rest, ctx),
		"cleaned furniture still flagged", failures)
	# Injured staff on duty -> labor check fails; sending them on leave fixes it.
	rest.staff[0].injury_until_day = day + 3
	_expect(not service.check_passes_now(&"injured_on_duty", rest, ctx),
		"injured staff on duty not flagged", failures)
	rest.staff[0].absence_until_day = day + 3
	_expect(service.check_passes_now(&"injured_on_duty", rest, ctx),
		"absent injured staff still flagged", failures)
	# Lapsed permit -> paperwork check fails.
	civic.permit_row(&"food_handling")["status"] = "lapsed"
	_expect(not service.check_passes_now(&"food_handling_permit", rest, ctx),
		"lapsed permit not flagged", failures)


static func _test_checklist_determinism(failures: Array[String]) -> void:
	var now: int = 20_000
	var service: ChecklistService = _checklist()
	var rest = _clean_restaurant(now)
	rest.inventory.lots[0].expiry_minute = now - 1
	rest.interior_layout.placed[0].cleanliness = 0.3
	var civic: CompanyCivicState = _civic(14)
	var ctx: Dictionary = _ctx(14, now, civic)
	var first: String = str(service.run_checklist(&"food_safety", rest, ctx))
	for i: int in range(2):
		var again: String = str(service.run_checklist(&"food_safety", rest, ctx))
		_expect(again == first, "checklist run %d differs for identical state" % (i + 2), failures)


static func _test_scoring_and_bias_band(failures: Array[String]) -> void:
	var service: ChecklistService = _checklist()
	var no_fails: Array[Dictionary] = [
		{"check_id": &"a", "passed": true, "severity": 3},
	]
	_expect(service.score_findings(no_fails, 0.0).get("grade") == &"clean",
		"no failures should grade clean", failures)
	var critical: Array[Dictionary] = [
		{"check_id": &"a", "passed": false, "severity": 3},
	]
	var neutral: Dictionary = service.score_findings(critical, 0.0)
	var bought: Dictionary = service.score_findings(critical, 1.0)
	var rigged: Dictionary = service.score_findings(critical, -1.0)
	_expect(absf(float(bought.get("score")) - float(neutral.get("score"))) <= 10.01,
		"bias moved the score beyond the clamped band", failures)
	_expect(float(rigged.get("score")) <= float(neutral.get("score")),
		"negative bias did not harshen the score", failures)
	_expect(bought.get("grade") != &"clean" and bought.get("grade") != &"warning",
		"max bias let a critical failure grade better than remediation", failures)
	var many: Array[Dictionary] = []
	for i: int in range(6):
		many.append({"check_id": StringName("c%d" % i), "passed": false, "severity": 3})
	_expect(service.score_findings(many, 0.0).get("grade") == &"closure",
		"total failure should grade closure", failures)


# --- Influence ----------------------------------------------------------------

static func _test_influence_bounded(failures: Array[String]) -> void:
	var service: InfluenceService = InfluenceService.new()
	service.configure(_tuning())
	# Donation-bought reputation is hard-capped.
	var effect: Dictionary = service.donation_effect(1_000_000.0, 0.0, 0.5)
	_expect(0.5 + float(effect.get("reputation_gain")) <= 0.85 + 0.0001,
		"donations pushed reputation past the cap", failures)
	# Diminishing: the same dollar buys less the second time.
	var first: Dictionary = service.donation_effect(1000.0, 0.0, 0.5)
	var later: Dictionary = service.donation_effect(1000.0, 20_000.0, 0.5)
	_expect(float(later.get("influence_gain")) < float(first.get("influence_gain")),
		"donation influence does not diminish", failures)
	# Bribes: bounded probability, integrity resists.
	var easy: float = service.bribe_success(5000.0, 0.1)
	var hard: float = service.bribe_success(5000.0, 0.95)
	_expect(easy > hard, "integrity does not resist bribery", failures)
	_expect(easy <= 0.9 and hard >= 0.02, "bribe probability left its bounds", failures)
	# Award bias is clamped.
	_expect(service.award_bias(10_000.0, 1.0) <= service.award_bias_max + 0.0001,
		"award bias exceeded its maximum", failures)
	# Influence decays.
	var civic: CompanyCivicState = CompanyCivicState.new()
	civic.influence = 5.0
	civic.mayor_relationship = 0.5
	service.decay(civic)
	_expect(civic.influence < 5.0 and civic.mayor_relationship < 0.5,
		"influence/relationship do not decay", failures)


# --- Police --------------------------------------------------------------------

static func _test_police_dispatch(failures: Array[String]) -> void:
	var service: PoliceService = PoliceService.new()
	service.configure(_tuning())
	var near: PoliceStationState = _station(1, Vector3(100, 0, 0))
	var far: PoliceStationState = _station(2, Vector3(500, 0, 0))
	var stations: Array[PoliceStationState] = [near, far]
	var target: Vector3 = Vector3.ZERO
	var pick: Dictionary = service.nearest_available(stations, target, 0, _eta_fn())
	_expect(int(pick.get("station_id", -1)) == 1, "nearest station not chosen", failures)
	# Book both of the near station's units -> the far one responds instead
	# (or the near one with a visible wait, whichever is quicker).
	service.mark_busy(near, 0, 0, 10.0, &"respond")
	service.mark_busy(near, 1, 0, 10.0, &"respond")
	var second: Dictionary = service.nearest_available(stations, target, 0, _eta_fn())
	var busy_handled: bool = int(second.get("station_id", -1)) == 2 \
		or float(second.get("wait", 0.0)) > 0.0
	_expect(busy_handled, "busy units not reflected in dispatch", failures)
	_expect(near.available_units(0) == 0 and near.available_units(100_000) == 2,
		"unit booking/freeing broken", failures)
	# ETA clamps.
	var lone: Array[PoliceStationState] = [_station(3, Vector3(90_000, 0, 0))]
	var far_pick: Dictionary = service.nearest_available(lone, target, 0, _eta_fn())
	_expect(float(far_pick.get("route_eta")) <= service.eta_max + 0.001,
		"route ETA not clamped to the maximum", failures)


static func _test_enforcement_ladder(failures: Array[String]) -> void:
	var service: PoliceService = PoliceService.new()
	service.configure(_tuning())
	_expect(service.enforcement_decision(10.0, 5.0, 0.5).get("action") == &"none",
		"low heat should not trigger enforcement", failures)
	_expect(service.enforcement_decision(50.0, 1.0, 0.5).get("action") == &"fine",
		"fine rung did not fire", failures)
	_expect(service.enforcement_decision(85.0, 2.0, 0.5).get("action") == &"raid",
		"raid rung did not fire", failures)
	_expect(service.enforcement_decision(85.0, 0.1, 0.5).get("action") == &"investigate",
		"raids must need evidence, not just heat", failures)
	var lenient: Dictionary = service.enforcement_decision(41.0, 1.0, 0.0)
	var zealous: Dictionary = service.enforcement_decision(41.0, 1.0, 1.0)
	_expect(lenient.get("action") == &"none" and zealous.get("action") == &"fine",
		"commander scrutiny should bend thresholds inside the band", failures)


# --- Development ----------------------------------------------------------------

static func _test_development_bounds(failures: Array[String]) -> void:
	var service: DevelopmentService = DevelopmentService.new()
	service.configure(_tuning())
	var def: DevelopmentProjectDef = DevelopmentProjectDef.new()
	def.id = &"test_project"
	def.demand_delta = 0.9  # deliberately over the clamp
	def.support_cost_base = 1500.0
	_expect(service.built_bonus(def) <= service.demand_uplift_max + 0.0001,
		"built bonus not clamped", failures)
	var no_support: float = service.approval_chance(def, 0.0, 0.0)
	var heavy_support: float = service.approval_chance(def, 1_000_000.0, 1.0)
	_expect(heavy_support > no_support, "support does not help approval", failures)
	_expect(heavy_support <= 0.9 and no_support >= 0.15,
		"approval chance left its bounds — money must not guarantee outcomes", failures)
	var project: DevelopmentProjectState = DevelopmentProjectState.new()
	project.uid = 3
	project.support = {"a": 500.0, "b": 250.0}
	_expect(absf(project.support_total() - 750.0) < 0.001, "support tally wrong", failures)
	var rng_a: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_a.seed = 1234
	var rng_b: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_b.seed = 1234
	_expect(service.decide(def, project, 0.0, rng_a) == service.decide(def, project, 0.0, rng_b),
		"development decision not deterministic for a fixed seed", failures)


# --- State helpers ----------------------------------------------------------------

static func _test_state_helpers(failures: Array[String]) -> void:
	var civic: CompanyCivicState = _civic(10)
	_expect(civic.has_active_permit(&"business_license", 20), "active permit not seen", failures)
	_expect(not civic.has_active_permit(&"business_license", 60), "expired permit passes", failures)
	civic.violations.append({"uid": 4, "status": "open", "outcome_applied": false})
	civic.fines.append({"uid": 9, "status": "unpaid", "amount": 500.0})
	_expect(civic.open_violations().size() == 1 and civic.unpaid_fines().size() == 1,
		"open violation / unpaid fine filters broken", failures)
	_expect(int(civic.violation_by_uid(4).get("uid", -1)) == 4, "violation lookup broken", failures)
	var insp: InspectionState = InspectionState.new()
	insp.scheduled_day = 12
	insp.findings.append({"check_id": &"x", "passed": false})
	insp.findings.append({"check_id": &"y", "passed": true})
	_expect(insp.failed_findings().size() == 1, "failed_findings filter broken", failures)
	_expect(insp.days_until(10) == 2 and insp.is_due(12), "inspection due math broken", failures)


# --- Save roundtrip / migration ----------------------------------------------------

static func _test_state_roundtrip(failures: Array[String]) -> void:
	var save = load(SG_SCRIPT).new()
	var civic: CompanyCivicState = _civic(5)
	civic.official_reputation = 0.71
	civic.tax_debt = 123.5
	civic.violations.append({"uid": 2, "status": "open", "outcome_applied": true,
		"deadline_day": 9, "code": "expired_stock"})
	save.civic_states.append(civic)
	var officer: OfficialState = OfficialState.new()
	officer.def_id = &"mayor"
	officer.role = &"mayor"
	officer.integrity = 0.62
	officer.relationship = {"test_co": 0.4}
	save.gov_officials.append(officer)
	var insp: InspectionState = InspectionState.new()
	insp.uid = 11
	insp.building_id = 7
	insp.visit_minute = 55_555
	insp.bias = -0.4
	insp.outcome_applied = true
	insp.grade = &"fine"
	save.gov_inspections.append(insp)
	save.police_stations.append(_station(1, Vector3(10, 0, 20)))
	var project: DevelopmentProjectState = DevelopmentProjectState.new()
	project.uid = 3
	project.status = &"built"
	project.applied = true
	project.support = {"test_co": 400.0}
	save.development_projects.append(project)
	save.government_schema_version = 1
	save.gov_next_uids = {"inspection": 12, "fine": 3, "violation": 5, "donation": 2, "project": 4}
	var err: int = ResourceSaver.save(save, TMP_PATH)
	_expect(err == OK, "roundtrip save failed (%d)" % err, failures)
	var loaded = ResourceLoader.load(TMP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(loaded != null, "roundtrip load failed", failures)
	if loaded == null:
		return
	_expect(loaded.civic_states.size() == 1
		and absf(loaded.civic_states[0].official_reputation - 0.71) < 0.001
		and absf(loaded.civic_states[0].tax_debt - 123.5) < 0.001,
		"civic state did not survive the roundtrip", failures)
	_expect(bool(loaded.civic_states[0].violations[0].get("outcome_applied", false)),
		"violation outcome_applied lost — effects could resolve twice", failures)
	_expect(loaded.gov_officials.size() == 1
		and absf(loaded.gov_officials[0].relationship_for(&"test_co") - 0.4) < 0.001,
		"official relationship did not survive", failures)
	_expect(loaded.gov_inspections.size() == 1
		and loaded.gov_inspections[0].visit_minute == 55_555
		and loaded.gov_inspections[0].outcome_applied
		and absf(loaded.gov_inspections[0].bias + 0.4) < 0.001,
		"inspection (visit_minute/bias/outcome_applied) did not survive", failures)
	_expect(loaded.police_stations.size() == 1
		and loaded.police_stations[0].units_busy_until.size() == 2,
		"police station units did not survive", failures)
	_expect(loaded.development_projects.size() == 1
		and loaded.development_projects[0].applied
		and absf(loaded.development_projects[0].support_total() - 400.0) < 0.001,
		"development project did not survive", failures)
	_expect(int(loaded.gov_next_uids.get("inspection", 0)) == 12,
		"uid counters did not survive", failures)


static func _test_migration_v13(failures: Array[String]) -> void:
	var save = load(SG_SCRIPT).new()
	save.save_version = 12
	save.government_schema_version = 0
	var ss: GDScript = load(SS_SCRIPT)
	ss.call("_migrate_v13", save)
	_expect(save.save_version == 13, "migration did not bump the save version", failures)
	_expect(save.government_schema_version == 1, "migration did not mark the schema", failures)
