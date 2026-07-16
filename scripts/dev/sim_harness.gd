extends SceneTree
## Headless multi-company simulation harness. Drives the REAL autoload
## singletons (which --script mode instantiates) over an injected tiny city,
## pumping GameClock signals for N in-game days — no rendering, no citizens,
## no real time. One scenario per process; seeded determinism is verified by
## comparing the FINGERPRINT line across runs:
##
##   godot --headless --path . --script res://scripts/dev/sim_harness.gd -- sim 1234 15
##   godot --headless --path . --script res://scripts/dev/sim_harness.gd -- commands
##
## Covers the rival-AI acceptance criteria that need no customer demand:
## profile-driven expansion, command permission boundaries, ownership
## consistency, honest ledgers, and bankruptcy + liquidation under the same
## rules as the player. (Rival profitability with live demand is verified in
## the running game — headless has no citizens.)
##
## NOTE: no custom class-name type annotations in this file — the main
## script compiles at engine boot, before class/autoload resolution settles.

var _failures: int = 0
var _checks: int = 0

# Autoload singletons, resolved at runtime — the main --script compiles
# before autoload identifiers exist, so direct names don't parse here.
var _clock: Node
var _setup: Node
var _city: Node
var _economy: Node
var _companies: Node
var _marketing: Node
var _restaurants: Node
var _demand: Node
var _delivery: Node
var _analytics: Node
var _awards: Node
var _crime: Node
var _government: Node


func _initialize() -> void:
	_clock = root.get_node("GameClock")
	_setup = root.get_node("GameSetup")
	_city = root.get_node("CityData")
	_economy = root.get_node("EconomyManager")
	_companies = root.get_node("CompanyManager")
	_marketing = root.get_node("MarketingManager")
	_restaurants = root.get_node("RestaurantManager")
	_demand = root.get_node("DemandManager")
	_delivery = root.get_node("DeliveryManager")
	_analytics = root.get_node("AnalyticsManager")
	_awards = root.get_node("AwardsManager")
	_crime = root.get_node_or_null("CrimeManager")
	_government = root.get_node_or_null("GovernmentManager")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scenario: String = args[0] if args.size() > 0 else "sim"
	match scenario:
		"commands":
			_scenario_commands()
		"crime":
			_scenario_crime(int(args[1]) if args.size() > 1 else 1234)
		"government":
			_scenario_government(int(args[1]) if args.size() > 1 else 1234)
		_:
			var world_seed: int = int(args[1]) if args.size() > 1 else 1234
			var days: int = int(args[2]) if args.size() > 2 else 15
			_scenario_sim(world_seed, days)
	print("---")
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s" % label)


# --- Setup ----------------------------------------------------------------------


func _boot(world_seed: int, rivals: Array) -> void:
	_setup.configured = true
	_setup.from_save = false
	_setup.world_seed = world_seed
	_setup.player_name = "Harness Test Co."
	_setup.selected_rivals.assign(rivals)
	_inject_city()
	# Autoload _ready never fires in --script mode; RecipeManager self-inits
	# there, so give it the same chance before menus are built. (book is
	# non-null at declaration — the reliable "catalogs missing" signal is an
	# empty starter set.)
	var recipes: Node = root.get_node("RecipeManager")
	if recipes.starter_recipes.is_empty():
		recipes._ready()
	# Same order the City scene uses. Analytics enrichment stays off so the
	# bucket pipeline runs without booting staff/supply (see feature 10 tests).
	_economy.initialize()
	_companies.initialize()
	_marketing.initialize()
	_analytics._enrich_enabled = false
	_analytics.initialize()
	_awards.initialize()
	_restaurants.initialize()
	_demand.initialize()
	_delivery.initialize()
	# Crime hooks minute_ticked + buckets_closed and registers a daily cost
	# provider; without an Underworld department (HQ isn't booted here) it stays
	# inert, so its presence must not change the base fingerprint — only the
	# dedicated crime scenario grants capability and drives operations.
	if _crime != null:
		_crime.initialize()
	if _government != null:
		_government.initialize()
	_companies.start_ai()


func _inject_city() -> void:
	var districts: Array = ["N", "N", "C", "C", "N", "C", "R", "P"]
	for i: int in districts.size():
		var pos: Vector3 = Vector3(float(i) * 400.0, 0.0, float(i % 3) * 400.0)
		_city.register_building({
			"id": 100 + i,
			"district": districts[i],
			"type": "shop",
			"family": "shop",
			"position": pos,
			"door_pos": pos + Vector3(0, 0, 8),
			"side_node": -1,
			"lane_node": -1,
			"capacity_residents": 0,
			"capacity_workers": 4,
			"node_path": NodePath(),
		})


## Replicates _clock._process hour-by-hour without real time. Two minute
## ticks per hour drain the AI execution queues.
func _advance_days(days: int) -> void:
	for _d: int in days:
		for _h: int in 24:
			_clock.game_hours += 1.0
			if _clock.game_hours >= 24.0:
				_clock.game_hours -= 24.0
				_clock.day += 1
				_clock.day_changed.emit(_clock.day)
			var hour: int = int(_clock.game_hours)
			_clock.hour_changed.emit(_clock.day, hour)
			_clock.minute_ticked.emit(_clock.day, hour, 0)
			_clock.minute_ticked.emit(_clock.day, hour, 30)


# --- Scenarios --------------------------------------------------------------------


func _scenario_sim(world_seed: int, days: int) -> void:
	print("== sim: seed %d, %d days ==" % [world_seed, days])
	_boot(world_seed, [&"pronto", &"nonna"])
	# Headless has no guests, so every guest-gated award category filters out.
	# Delivery-enable the boot-time branches so Best Delivery keeps a field and
	# the quarterly reward path (transact + claim-once) runs under the harness.
	for company: Resource in _companies.companies:
		for rest: Resource in company.restaurants:
			rest.delivery_enabled = true
	_advance_days(days)

	var pronto: Resource = _companies.company(&"pronto")
	var nonna: Resource = _companies.company(&"nonna")
	if days <= 60:
		# Short runs: expansion + staffing behavior. (Long demand-less runs end
		# in legitimate bankruptcies — nobody can profit without customers.)
		print("profiles:")
		_check(pronto.restaurants.size() >= 1,
			"aggressive Pronto expanded (%d branches)" % pronto.restaurants.size())
		_check(pronto.restaurants.size() >= nonna.restaurants.size(),
			"Pronto (%d) expands at least as fast as defensive Nonna (%d)" % [
				pronto.restaurants.size(), nonna.restaurants.size()])
		var pronto_staff: int = 0
		for rest: Resource in pronto.restaurants:
			pronto_staff += rest.staff.size()
		_check(pronto_staff > 0, "Pronto hired staff from the shared market (%d)" % pronto_staff)
	else:
		print("long-run stability:")
		# Since feature 11, contest prizes are a legitimate non-demand income
		# source — a demand-less rival survives only while trophy money lasts.
		# (Bankruptcy-rule parity itself is proven in the commands scenario.)
		var rivals_accounted: bool = true
		for rival: Resource in [pronto, nonna]:
			if rival.is_bankrupt:
				continue
			var prize_income: float = 0.0
			for summary: Dictionary in rival.history:
				var ledger: Dictionary = summary.get("ledger", {})
				prize_income += float(ledger.get(&"award_prize", 0.0)) + float(ledger.get(&"competition_prize", 0.0))
			if prize_income <= 0.0:
				rivals_accounted = false
		_check(rivals_accounted,
			"demand-less rivals fail under shared rules unless prize money sustains them")
		var bounded: bool = true
		for company: Resource in _companies.companies:
			if company.recent_moves.size() > 30 or company.history.size() > days + 2:
				bounded = false
		for brain: RefCounted in _companies._ai:
			if brain.journal.size() > 60 or brain._queue.size() > 24:
				bounded = false
		_check(bounded, "journals, queues and move logs stay bounded over %d days" % days)

	_check_consistency()
	_check_ledgers()
	_check_ratings(days)
	_check_competitions(days)

	# Deterministic fingerprint for cross-process comparison.
	var journals: Dictionary = {}
	for rival_id: StringName in [&"pronto", &"nonna"]:
		var brain: RefCounted = _companies.ai_for(rival_id)
		journals[rival_id] = brain.journal if brain != null else []
	var comp_fp: Array = []
	for comp: Resource in _awards.competitions:
		var totals: Array = []
		for row: Dictionary in comp.results:
			totals.append([String(row["company_id"]), snappedf(float(row["total"]), 0.0001)])
		comp_fp.append([comp.uid, String(comp.def_id), String(comp.status), String(comp.winner_company_id), totals])
	var stars: Dictionary = {}
	for rival_id: StringName in [&"pronto", &"nonna"]:
		var company: Resource = _companies.company(rival_id)
		var values: Array = []
		for rest: Resource in company.restaurants:
			values.append(snappedf(rest.star_rating, 0.001))
		stars[rival_id] = values
	var fingerprint: Dictionary = {
		"branches": {"pronto": pronto.restaurants.size(), "nonna": nonna.restaurants.size()},
		"cash": {"pronto": snappedf(pronto.cash, 0.01), "nonna": snappedf(nonna.cash, 0.01)},
		"journals": journals,
		"stars": stars,
		"competitions": comp_fp,
	}
	print("FINGERPRINT %s" % JSON.stringify(fingerprint))


## Full attacker→resolve→ledger→enforcement path with capability granted
## directly (HQ/staff are not booted here). Prints CRIME_FINGERPRINT for
## cross-process determinism (diff two runs at the same seed).
func _scenario_crime(world_seed: int) -> void:
	print("== crime & sabotage ==")
	if _crime == null:
		printerr("  FAIL  CrimeManager autoload missing (needs an editor restart to register)")
		_checks += 1
		_failures += 1
		return
	_boot(world_seed, [&"pronto"])
	var player: Resource = _companies.player
	var rival: Resource = _companies.company(&"pronto")
	var registry: Node = root.get_node("CapabilityRegistry")
	# Grant the player an Underworld back room without an HQ department.
	registry.set_source(player.id, &"harness_crime",
		{&"crime.crew_capacity": 4, &"crime.action_tier": 3})
	# Found a target branch for the rival to hit.
	_restaurants.purchase_location(rival.id, 102, "Pronto Target")
	var target: Resource = _restaurants.by_building.get(102)
	_check(target != null and target.company_id == rival.id, "target branch founded for the rival")
	if target == null:
		return
	# Recruit crew (deterministic market).
	var market: Array = _crime.market_candidates(player.id)
	_check(not market.is_empty(), "underworld market offers recruits")
	var hired: int = 0
	for candidate: Dictionary in market:
		var result: RefCounted = _crime.hire_agent_cmd(player.id, candidate)
		if result != null and result.ok:
			hired += 1
	_check(hired > 0, "player recruited at least one crew member")
	_check(_crime.crew_of(player.id).size() <= _crime.crew_capacity(player.id),
		"crew never exceeds capacity")
	# Launch a tier-1 op that needs a single punk if available; else graffiti.
	var cash_before: float = player.cash
	var action_id: StringName = _first_launchable(player.id)
	_check(action_id != &"", "at least one action is launchable")
	if action_id == &"":
		return
	var launch: RefCounted = _crime.launch_operation_cmd(player.id, action_id, 102)
	_check(launch != null and launch.ok, "operation launches")
	if launch == null or not launch.ok:
		return
	var op: Resource = launch.payload.get("operation")
	_check(player.cash < cash_before, "launching an operation costs cash")
	# Advance just past resolution (extortion resolves within a day). Heat is
	# sampled here before the daily decay grinds it back down.
	_advance_days(2)
	_check(op.outcome_applied, "operation resolved exactly once (outcome_applied)")
	_check(op.outcome.has("success") and op.outcome.has("evidence"),
		"outcome records success and evidence independently")
	var attacker_heat: Resource = _crime.heat_for(player.id)
	_check(attacker_heat.heat > 0.0, "the operation raised the attacker's heat")
	var target_sec: Resource = _crime.security_for(102)
	_check(target_sec != null, "the target has a security state")
	# The anti-cheat: every dollar including crime categories is accounted.
	_check_ledgers()
	_check_crime()
	var fingerprint: Dictionary = {
		"op": [op.uid, String(op.action_id), String(op.phase), bool(op.outcome.get("success", false)),
			snappedf(float(op.evidence), 0.0001)],
		"heat": snappedf(attacker_heat.heat, 0.01),
		"player_cash": snappedf(player.cash, 0.01),
		"crew": _crime.crew_of(player.id).size(),
		"incidents": target_sec.incidents.size() if target_sec != null else 0,
	}
	print("CRIME_FINGERPRINT %s" % JSON.stringify(fingerprint))


## Civic layer end-to-end: permits, a forced-fail inspection with a live
## checklist, remediation deadlines, fines, donations and once-only outcomes.
## Prints GOVERNMENT_FINGERPRINT for cross-process determinism.
func _scenario_government(world_seed: int) -> void:
	print("== government, mayor & police ==")
	if _government == null:
		printerr("  FAIL  GovernmentManager autoload missing (needs an editor restart to register)")
		_checks += 1
		_failures += 1
		return
	_boot(world_seed, [&"pronto"])
	var player: Resource = _companies.player
	var civic: Resource = _government.civic_for(player.id)
	_check(civic != null, "player has a civic state")
	_check(civic.has_active_permit(&"business_license", _clock.day),
		"starter business license is active")
	_check(not _government.officials.is_empty(), "officials seeded")
	_check(not _government.stations.is_empty(), "police stations seeded")
	var player_branch: Resource = null
	for rest: Resource in _restaurants.owned:
		if rest.company_id == player.id:
			player_branch = rest
			break
	_check(player_branch != null, "player owns a branch to inspect")
	if player_branch == null:
		return
	var bid: int = player_branch.building_id
	# Sabotage our own compliance. Dirty furniture flags the walk-in preview,
	# but the nightly repair crew may clean it before the visit (fixing before
	# the deadline is SUPPOSED to help) — so also lapse a permit, which nothing
	# renews for the player automatically. That failure is durable.
	if player_branch.interior_layout != null and not player_branch.interior_layout.placed.is_empty():
		for item: Resource in player_branch.interior_layout.placed:
			item.cleanliness = 0.05
	var lapsed_permit: Dictionary = civic.permit_row(&"food_handling")
	_check(not lapsed_permit.is_empty(), "starter food handling permit exists")
	if not lapsed_permit.is_empty():
		lapsed_permit["status"] = "lapsed"
	var preview: Array = _government.checklist_preview(bid, &"food_safety")
	var preview_fails: int = 0
	for row: Dictionary in preview:
		if not bool(row.get("passed", true)):
			preview_fails += 1
	_check(preview_fails > 0, "live checklist flags the dirty branch (%d fails)" % preview_fails)
	# Request a re-inspection (player-driven scheduling) and let it happen.
	var cash_before: float = player.cash
	var request: RefCounted = _government.request_reinspection_cmd(player.id, bid)
	_check(request != null and request.ok, "re-inspection can be requested")
	_check(player.cash < cash_before, "the filing fee was charged")
	_advance_days(5)
	var done: Array = []
	for insp: Resource in _government.inspections_for(bid):
		if insp.visit_done:
			done.append(insp)
	_check(not done.is_empty(), "the inspection visit happened")
	if done.is_empty():
		return
	var visit: Resource = done[0]
	_check(visit.outcome_applied, "inspection outcome applied exactly once")
	_check(visit.grade != &"clean", "the dirty branch did not grade clean (%s)" % visit.grade)
	var open_violations: Array = civic.open_violations()
	var escalated_or_open: bool = not open_violations.is_empty() or not civic.violations.is_empty()
	_check(escalated_or_open, "violations were recorded with correctives")
	if not civic.violations.is_empty():
		var violation: Dictionary = civic.violations[0]
		_check(not String(violation.get("corrective", "")).is_empty(),
			"violation carries a concrete corrective")
	# Donations: bounded civic goodwill, honest ledger.
	var rep_before: float = civic.official_reputation
	var donate: RefCounted = _government.donate_cmd(player.id, &"mayor", 1000.0, &"declared")
	_check(donate != null and donate.ok, "donation accepted")
	_check(civic.official_reputation >= rep_before, "donation never lowers reputation")
	_check(civic.influence > 0.0, "donation grants influence")
	_check(_government.award_bias(player.id) <= 0.151, "award bias stays inside its cap")
	# Police: ETA quoted from station anchors, clamped.
	var eta: float = _government.police_eta(bid)
	_check(eta >= 3.0 and eta <= 45.0, "police ETA clamped (%.1f min)" % eta)
	var dispatch: Dictionary = _government.dispatch_unit(bid, &"respond")
	_check(not dispatch.is_empty(), "a unit dispatches to the branch")
	# The anti-cheat: every civic dollar is accounted.
	_check_ledgers()
	var fingerprint: Dictionary = {
		"official_rep": snappedf(civic.official_reputation, 0.0001),
		"police_rep": snappedf(civic.police_reputation, 0.0001),
		"influence": snappedf(civic.influence, 0.0001),
		"grade": String(visit.grade),
		"score": snappedf(visit.score, 0.01),
		"violations": civic.violations.size(),
		"fines": civic.fines.size(),
		"permits_active": int(civic.has_active_permit(&"business_license", _clock.day)),
		"stations": _government.stations.size(),
		"player_cash": snappedf(player.cash, 0.01),
	}
	print("GOVERNMENT_FINGERPRINT %s" % JSON.stringify(fingerprint))


func _first_launchable(company_id: StringName) -> StringName:
	for entry: Dictionary in _crime.actions_for(company_id):
		if bool(entry.get("ok", false)):
			var def: Resource = entry.get("def")
			if def != null and def.target_kind == &"restaurant":
				var preview: Dictionary = _crime.preview_operation(company_id, def.id, 102)
				if bool(preview.get("ok", false)):
					return def.id
	return &""


func _check_crime() -> void:
	# Heat state exists for every company (seeded on init / registration).
	var missing: int = 0
	for company: Resource in _companies.companies:
		if _crime.heat_for(company.id) == null:
			missing += 1
	_check(missing == 0, "every company has a heat state")
	# No operation is ever resolved twice.
	var double_resolved: int = 0
	for op: Resource in _crime.operations:
		if op.phase == &"done" and not op.outcome_applied and not op.outcome.is_empty():
			double_resolved += 1
	_check(double_resolved == 0, "no operation resolves without its once-only guard")


func _scenario_commands() -> void:
	print("== command boundaries + bankruptcy ==")
	_boot(4242, [&"pronto"])

	var bad: RefCounted = _restaurants.purchase_location(&"ghost", 100)
	_check(bad.code == &"unknown_company", "unknown company rejected")

	var pronto_buy: RefCounted = _restaurants.purchase_location(&"pronto", 100, "Pronto Test")
	_check(pronto_buy.ok, "rival can buy a free location")
	_check(not _restaurants.is_purchasable(100), "bought location leaves the market")

	var steal: RefCounted = _restaurants.purchase_location(&"player", 100)
	_check(steal.code == &"not_purchasable", "player cannot buy an owned building")
	var meddle: RefCounted = _restaurants.set_hours_cmd(&"player", 100, 8.0, 20.0)
	_check(meddle.code == &"not_owner", "player cannot change a rival branch")
	var wrong_close: RefCounted = _restaurants.close_branch(&"player", 100)
	_check(wrong_close.code == &"not_owner", "player cannot close a rival branch")

	var own_close: RefCounted = _restaurants.close_branch(&"pronto", 100)
	_check(own_close.ok, "owner can close its branch")
	_check(_restaurants.is_purchasable(100), "closed location returns to the market")

	# Bankruptcy: a legitimate ledger shock pushes Pronto under the floor;
	# the next day-close liquidates it under the same rules as the player.
	var pronto: Resource = _companies.company(&"pronto")
	var rebuy: RefCounted = _restaurants.purchase_location(&"pronto", 101, "Pronto Doomed")
	_check(rebuy.ok, "rival buys the branch it is about to lose")
	pronto.transact(&"test_shock", -150000.0)
	_advance_days(1)
	_check(pronto.is_bankrupt, "rival goes bankrupt under player rules")
	_check(pronto.restaurants.is_empty(), "bankrupt rival liquidated")
	_check(_restaurants.is_purchasable(101), "liquidated building returns to the market")
	_check_consistency()


# --- Invariants -------------------------------------------------------------------


## Every branch carries a live rating state; public stars respect the ceiling.
func _check_ratings(days: int) -> void:
	print("ratings:")
	var all_have_state: bool = true
	var stars_capped: bool = true
	var sampled: bool = false
	for company: Resource in _companies.companies:
		for rest: Resource in company.restaurants:
			var state: Resource = _awards.rating_for(rest.building_id)
			if state == null:
				all_have_state = false
				continue
			if not state.history.is_empty():
				sampled = true
			if rest.star_rating > float(state.star_ceiling) + 0.991:
				stars_capped = false
	_check(all_have_state, "every branch has a rating state")
	if days >= 2:
		_check(sampled, "daily rating samples accrued")
	_check(stars_capped, "public stars never exceed the certified ceiling")
	if days >= 43:
		var quarterly: int = 0
		for result: Resource in _awards.award_results:
			if result.kind == &"award":
				quarterly += 1
		_check(quarterly > 0, "quarterly awards granted (%d)" % quarterly)
		# Medals guard via CompetitionState.reward_applied; claim keys cover
		# exactly the quarterly awards.
		_check(_awards.award_claimed.size() == quarterly, "each award claimed exactly once")


## Scheduled competitions announce, collect AI entries, and produce judged
## results with full per-component breakdowns.
func _check_competitions(days: int) -> void:
	if days < 20:
		return
	print("competitions:")
	var runs: int = _awards.competitions.size()
	_check(runs > 0, "scheduled competitions announced (%d)" % runs)
	var rival_entries: int = 0
	var judged: int = 0
	var components_ok: bool = true
	for comp: Resource in _awards.competitions:
		rival_entries += comp.entries.size()
		if comp.results.is_empty():
			continue
		judged += 1
		for row: Dictionary in comp.results:
			for component: String in ["recipe_score", "compliance", "novelty", "noise", "total", "rank"]:
				if not row.has(component):
					components_ok = false
	_check(rival_entries > 0, "AI rivals entered competitions (%d entries)" % rival_entries)
	_check(judged > 0, "competitions judged with results (%d)" % judged)
	if judged > 0:
		_check(components_ok, "every result row carries all scoring components")


## by_building must mirror the per-company restaurant lists exactly.
func _check_consistency() -> void:
	var total: int = 0
	var mismatches: int = 0
	for company: Resource in _companies.companies:
		for rest: Resource in company.restaurants:
			total += 1
			if _restaurants.by_building.get(rest.building_id) != rest:
				mismatches += 1
			if rest.company_id != company.id:
				mismatches += 1
	_check(mismatches == 0 and _restaurants.by_building.size() == total,
		"ownership consistent (%d branches indexed)" % total)


## Anti-cheat: every company's cash must equal starting cash plus the sum of
## its honest ledger history — no money can appear outside transact().
func _check_ledgers() -> void:
	var dishonest: int = 0
	for company: Resource in _companies.companies:
		var moved: float = 0.0
		for summary: Dictionary in company.history:
			for amount: float in (summary.get("ledger", {}) as Dictionary).values():
				moved += amount
		for amount: float in company.ledger_today.values():
			moved += amount
		if not is_equal_approx(snappedf(company.cash, 0.01), snappedf(20000.0 + moved, 0.01)):
			dishonest += 1
	_check(dishonest == 0, "ledgers account for every dollar of cash")
