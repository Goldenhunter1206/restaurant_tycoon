extends Node
## Marketing: campaigns raise awareness per (company, district, segment); the
## demand loop reads awareness (plus a local coverage bump) as extra offer
## utility. One system shared by the player's Marketing screen and the rival
## AI — both go through start_campaign() and pay the same costs. Channels are
## data-driven (data/marketing_channels/*.tres); billboards additionally rent
## AdPlacement sites, contended between companies.

signal campaigns_changed
signal placements_changed
signal trends_changed

const CHANNELS_DIR: String = "res://data/marketing_channels"

## Awareness gain scale per exposure tick; steady state ~2x daily gain.
const GAIN_SCALE: float = 0.25
## Reference daily spend for the diminishing spend-efficiency curve.
const REF_DAILY_SPEND: float = 300.0
const NOVELTY_DECAY_DAYS: float = 30.0
const NOVELTY_FLOOR: float = 0.4
const FATIGUE_RATE: float = 0.02
const FATIGUE_CAP: float = 0.8
## Untargeted campaigns speak to everyone, quietly; wrong segments barely listen.
const FIT_BROAD: float = 0.75
const FIT_MISS: float = 0.3
const FIT_RECIPE_WEIGHT: float = 0.35
## Cumulative citywide exposure needed before a promoted recipe trends.
const TREND_THRESHOLD: float = 3.0
const TREND_DAYS: int = 5
const TREND_BONUS: float = 0.1
const FALSE_CLAIM_GRACE_DAYS: int = 3
const FALSE_CLAIM_FINE_CHANCE: float = 0.15
const FINE_BASE: float = 400.0
const CREDIBILITY_FALSE: float = 0.5
const CREDIBILITY_NEUTRAL: float = 0.85
## Billboard site network.
const MAX_PLACEMENT_SITES: int = 24
const PLACEMENT_MIN_SPACING: float = 140.0
const PLACEMENT_BASE_RENT: float = 100.0

var channels: Dictionary = {}
var campaigns: Array[MarketingCampaign] = []
var placements: Array[AdPlacement] = []
var city_trends: Array[CityTrend] = []
var awareness: AwarenessModel = AwarenessModel.new()

var _initialized: bool = false
## district -> PackedVector3Array of building positions (coverage math).
var _district_positions: Dictionary = {}
## recipe_id -> cumulative promotion exposure toward TREND_THRESHOLD.
var _trend_exposure: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_load_channels()
	# Daily charge/expiry runs inside each company's ledger day; the awareness
	# tick is global, once per day.
	EconomyManager.daily_cost_providers.append(_charge_daily)
	GameClock.day_changed.connect(_on_day_changed)
	var save: SaveGame = CompanyManager.loaded_save
	if save != null:
		for campaign: MarketingCampaign in save.active_campaigns:
			campaigns.append(campaign)
		for placement: AdPlacement in save.ad_placements:
			placements.append(placement)
		awareness.restore(save.marketing_awareness)
		for trend: CityTrend in save.city_trends:
			city_trends.append(trend)
	if placements.is_empty():
		_generate_placement_sites()


func channel(id: StringName) -> MarketingChannelDef:
	return channels.get(id)


## Catalog sorted cheap-to-grand for pickers.
func channel_list() -> Array[MarketingChannelDef]:
	var result: Array[MarketingChannelDef] = []
	for def: MarketingChannelDef in channels.values():
		result.append(def)
	result.sort_custom(func(a: MarketingChannelDef, b: MarketingChannelDef) -> bool:
		return a.cost_per_day < b.cost_per_day)
	return result


# --- Campaign lifecycle -------------------------------------------------------


func start_campaign(campaign: MarketingCampaign) -> CommandResult:
	var company: CompanyState = CompanyManager.company(campaign.company_id)
	if company == null:
		return CommandResult.fail(&"unknown_company", "No company '%s'." % campaign.company_id)
	var def: MarketingChannelDef = channel(campaign.channel_id)
	if def == null:
		return CommandResult.fail(&"unknown_channel", "No channel '%s'." % campaign.channel_id)
	# Placement channels hang off a rented site, not a branch; everything else
	# local must belong to a company restaurant.
	if def.scope == &"local" and not def.needs_placement:
		var rest: RestaurantState = RestaurantManager.by_building.get(campaign.building_id)
		if rest == null or rest.company_id != campaign.company_id:
			return CommandResult.fail(&"not_owner", "That branch isn't owned by the company.")
	var why_locked: String = CapabilityRegistry.explain(campaign.company_id, def.required_capability)
	if why_locked != "":
		return CommandResult.fail(&"locked", why_locked)
	var slots: int = CapabilityRegistry.campaign_slots(campaign.company_id)
	if campaigns_for(campaign.company_id).size() >= slots:
		return CommandResult.fail(&"slots_full",
			"All %d campaign slots are busy. Stop one or grow the company." % slots)
	for existing: MarketingCampaign in campaigns:
		if existing.company_id != campaign.company_id or existing.channel_id != campaign.channel_id:
			continue
		if def.needs_placement:
			# Placement channels: one campaign per site.
			for placement_id: int in campaign.placement_ids:
				if existing.placement_ids.has(placement_id):
					return CommandResult.fail(&"already_running",
						"A %s campaign already runs on that site." % def.display_name)
		elif existing.building_id == campaign.building_id:
			return CommandResult.fail(&"already_running",
				"A %s campaign is already running here." % def.display_name)
	if def.needs_placement:
		if campaign.placement_ids.is_empty():
			return CommandResult.fail(&"needs_placement", "Rent a billboard site first.")
		for placement_id: int in campaign.placement_ids:
			var site: AdPlacement = placement(placement_id)
			if site == null or site.owner_company != campaign.company_id:
				return CommandResult.fail(&"placement_not_rented",
					"Billboard site %d isn't rented by the company." % placement_id)
	campaign.intensity = clampf(campaign.intensity, 0.5, 2.0)
	campaign.cost_per_day = def.cost_per_day * campaign.intensity
	campaign.days_left = clampi(campaign.days_left, def.min_days, def.max_days)
	if campaign.radius <= 0.0:
		campaign.radius = def.base_radius
	var upfront: float = def.setup_cost + campaign.cost_per_day
	if not company.can_afford(upfront):
		return CommandResult.fail(&"insufficient_cash",
			"Setup and the first day cost $%.0f." % upfront)
	company.transact(&"marketing", -upfront)
	campaign.total_spend += upfront
	campaigns.append(campaign)
	campaigns_changed.emit()
	# Comparison campaigns provoke the named rival.
	if campaign.rival_target != &"":
		var rival_ai: RefCounted = CompanyManager.ai_for(campaign.rival_target)
		if rival_ai != null and rival_ai.has_method("on_rival_comparison"):
			rival_ai.on_rival_comparison(campaign)
	return CommandResult.good(campaign)


func stop_campaign(campaign: MarketingCampaign) -> void:
	if campaigns.has(campaign):
		campaigns.erase(campaign)
		campaigns_changed.emit()


func campaigns_for(company_id: StringName) -> Array[MarketingCampaign]:
	var result: Array[MarketingCampaign] = []
	for campaign: MarketingCampaign in campaigns:
		if campaign.company_id == company_id:
			result.append(campaign)
	return result


# --- Demand hooks (called from DemandManager._best_offer) ---------------------


## Extra offer utility for a citizen at `origin` considering `rest`: the max
## of any direct local-coverage bump plus the aggregated awareness term.
func bonus_for(rest: RestaurantState, demographic: StringName, origin: Vector3) -> float:
	var direct: float = 0.0
	if not campaigns.is_empty():
		for campaign: MarketingCampaign in campaigns:
			if campaign.company_id != rest.company_id:
				continue
			if not campaign.targets_segment(demographic):
				continue
			if not _covers_point(campaign, rest, origin):
				continue
			direct = maxf(direct, campaign.utility_bonus * campaign.effectiveness)
	var known: float = awareness.value(rest.company_id, rest.district, demographic)
	return direct + known * _awareness_weight()


## Extra utility for one dish: promoted-recipe uplift where the company has
## awareness, plus any citywide trend for that recipe (helps every seller).
func dish_bonus_for(rest: RestaurantState, dish_id: StringName, demographic: StringName) -> float:
	var bonus: float = 0.0
	for trend: CityTrend in city_trends:
		if trend.matches_recipe(dish_id):
			bonus += trend.utility_bonus
	for campaign: MarketingCampaign in campaigns:
		if campaign.company_id != rest.company_id or campaign.promoted_recipe != dish_id:
			continue
		if not campaign.targets_segment(demographic):
			continue
		var known: float = awareness.value(rest.company_id, rest.district, demographic)
		bonus += known * _awareness_weight() * 0.5
	return bonus


## Last-touch attribution, called where a sale completes (dine-in serve /
## delivery hand-off). An estimate by design — reported as such.
func attribute_sale(building_id: int, citizen_id: int, revenue: float) -> void:
	if campaigns.is_empty():
		return
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null:
		return
	var segment: StringName = DemandManager.demographic_of(citizen_id)
	var best: MarketingCampaign = null
	var best_score: float = 0.0
	for campaign: MarketingCampaign in campaigns:
		if campaign.company_id != rest.company_id:
			continue
		if not campaign.targets_segment(segment):
			continue
		var score: float = campaign.effectiveness * campaign.credibility
		if _campaign_reaches_district(campaign, rest.district) and score > best_score:
			best = campaign
			best_score = score
	if best == null:
		return
	best.attributed_visits += 1
	best.attributed_revenue += revenue
	best.segment_visits[segment] = int(best.segment_visits.get(segment, 0)) + 1


# --- Placements (billboard sites) ---------------------------------------------


func placement(placement_id: int) -> AdPlacement:
	for site: AdPlacement in placements:
		if site.id == placement_id:
			return site
	return null


func vacant_placements() -> Array[AdPlacement]:
	var result: Array[AdPlacement] = []
	for site: AdPlacement in placements:
		if site.vacant():
			result.append(site)
	return result


func placements_for(company_id: StringName) -> Array[AdPlacement]:
	var result: Array[AdPlacement] = []
	for site: AdPlacement in placements:
		if site.owner_company == company_id:
			result.append(site)
	return result


func rent_placement(company_id: StringName, placement_id: int, days: int) -> CommandResult:
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null:
		return CommandResult.fail(&"unknown_company", "No company '%s'." % company_id)
	var site: AdPlacement = placement(placement_id)
	if site == null:
		return CommandResult.fail(&"unknown_placement", "No billboard site %d." % placement_id)
	if not site.vacant() and site.owner_company != company_id:
		return CommandResult.fail(&"occupied", "%s already rents this site." %
			_company_name(site.owner_company))
	var why_locked: String = CapabilityRegistry.explain(company_id, &"marketing.billboards")
	if why_locked != "":
		return CommandResult.fail(&"locked", why_locked)
	if not company.can_afford(site.rent_per_day):
		return CommandResult.fail(&"insufficient_cash",
			"The first day's rent is $%.0f." % site.rent_per_day)
	company.transact(&"marketing", -site.rent_per_day)
	site.owner_company = company_id
	site.days_left = maxi(days, 1)
	placements_changed.emit()
	return CommandResult.good(site)


func release_placement(placement_id: int) -> void:
	var site: AdPlacement = placement(placement_id)
	if site == null or site.vacant():
		return
	site.owner_company = &""
	site.days_left = 0
	for campaign: MarketingCampaign in campaigns:
		campaign.placement_ids.erase(placement_id)
	placements_changed.emit()


# --- Previews (shared by the Marketing screen and the rival AI) ---------------


## Reach/cost estimate for a campaign that is not running yet. `noise` lets AI
## callers degrade the forecast; the UI passes 0.
func preview(campaign: MarketingCampaign, noise: float = 0.0) -> Dictionary:
	var def: MarketingChannelDef = channel(campaign.channel_id)
	if def == null:
		return {}
	var cover: Dictionary = coverage_districts(campaign)
	var people: int = est_reach_people(campaign)
	if noise > 0.0:
		people = int(people * (1.0 + _rng.randf_range(-noise, noise)))
	var daily: float = def.cost_per_day * clampf(campaign.intensity, 0.5, 2.0)
	var days: int = clampi(campaign.days_left, def.min_days, def.max_days)
	return {
		"people": people,
		"uncertainty": 0.2 + noise,
		"districts": cover,
		"setup_cost": def.setup_cost,
		"daily_cost": daily,
		"days": days,
		"total_cost": def.setup_cost + daily * days,
		"fit": _preview_fit(campaign),
	}


## district code -> covered fraction (0-1) of that district's buildings.
func coverage_districts(campaign: MarketingCampaign) -> Dictionary:
	var def: MarketingChannelDef = channel(campaign.channel_id)
	if def == null:
		return {}
	_ensure_district_positions()
	if def.reach_shape == &"city":
		var all: Dictionary = {}
		for district: String in _district_positions:
			all[district] = 1.0
		return all
	var centers: Array[Vector3] = _campaign_centers(campaign)
	if centers.is_empty():
		return {}
	var radius: float = campaign.radius if campaign.radius > 0.0 else def.base_radius
	var result: Dictionary = {}
	for district: String in _district_positions:
		var points: PackedVector3Array = _district_positions[district]
		if points.is_empty():
			continue
		var covered: int = 0
		for point: Vector3 in points:
			for center: Vector3 in centers:
				if point.distance_to(center) <= radius:
					covered += 1
					break
		if covered > 0:
			result[district] = float(covered) / points.size()
	return result


## Citizens inside coverage whose segment the campaign targets.
func est_reach_people(campaign: MarketingCampaign) -> int:
	var cover: Dictionary = coverage_districts(campaign)
	if cover.is_empty():
		return 0
	var expected: float = 0.0
	for data: Dictionary in PopulationManager.citizens_data:
		var citizen_id: int = int(data.get("id", -1))
		var home: Dictionary = CityData.get_building(int(data.get("home_id", -1)))
		if home.is_empty():
			continue
		var district: String = String(home.get("district", ""))
		if not cover.has(district):
			continue
		if campaign.targets_segment(DemandManager.demographic_of(citizen_id)):
			expected += float(cover[district])
	return int(expected)


## Term-by-term multipliers for tooltips/results (anti-opacity control).
func contribution_breakdown(campaign: MarketingCampaign) -> Dictionary:
	var def: MarketingChannelDef = channel(campaign.channel_id)
	if def == null:
		return {}
	return {
		"reach_weight": def.reach_weight,
		"frequency": def.frequency,
		"fit": _preview_fit(campaign),
		"credibility": campaign.credibility,
		"spend_efficiency": _spend_efficiency(campaign),
		"novelty": _novelty(campaign),
		"fatigue": campaign.fatigue,
		"effectiveness": campaign.effectiveness,
	}


## Company's active exposure share vs everyone advertising (0-1).
func share_of_voice(company_id: StringName) -> float:
	var mine: float = 0.0
	var total: float = 0.0
	for campaign: MarketingCampaign in campaigns:
		var def: MarketingChannelDef = channel(campaign.channel_id)
		if def == null:
			continue
		var weight: float = def.reach_weight * def.frequency * campaign.intensity \
			* campaign.effectiveness
		if def.reach_shape == &"city":
			weight *= 3.0
		total += weight
		if campaign.company_id == company_id:
			mine += weight
	return mine / total if total > 0.0 else 0.0


# --- Daily simulation ----------------------------------------------------------


## Global awareness/exposure tick, once per day for every company's campaigns.
func _on_day_changed(_day: int) -> void:
	awareness.decay_all()
	for campaign: MarketingCampaign in campaigns:
		campaign.days_run += 1
		_update_credibility(campaign)
		campaign.fatigue = clampf(
			campaign.fatigue + FATIGUE_RATE * _campaign_frequency(campaign) * campaign.intensity,
			0.0, FATIGUE_CAP)
		campaign.effectiveness = _novelty(campaign) * (1.0 - campaign.fatigue)
		_apply_exposure(campaign)
		_roll_government_risk(campaign)
	_tick_trends()


func _apply_exposure(campaign: MarketingCampaign) -> void:
	var def: MarketingChannelDef = channel(campaign.channel_id)
	if def == null:
		return
	var cover: Dictionary = coverage_districts(campaign)
	if cover.is_empty():
		return
	var base: float = def.reach_weight * def.frequency * campaign.credibility \
		* _spend_efficiency(campaign) * campaign.effectiveness * GAIN_SCALE
	var exposure_total: float = 0.0
	for district: String in cover:
		var frac: float = float(cover[district])
		for segment: StringName in RecipeManager.SEGMENTS:
			var gain: float = base * frac * _message_fit(campaign, segment)
			awareness.apply_gain(campaign.company_id, district, segment, gain)
			exposure_total += gain
	if campaign.promoted_recipe != &"":
		var prior: float = float(_trend_exposure.get(campaign.promoted_recipe, 0.0))
		_trend_exposure[campaign.promoted_recipe] = prior + exposure_total
		_maybe_spawn_trend(campaign)


func _maybe_spawn_trend(campaign: MarketingCampaign) -> void:
	var recipe_id: StringName = campaign.promoted_recipe
	if float(_trend_exposure.get(recipe_id, 0.0)) < TREND_THRESHOLD:
		return
	for trend: CityTrend in city_trends:
		if trend.recipe_id == recipe_id:
			return
	var trend: CityTrend = CityTrend.new()
	trend.recipe_id = recipe_id
	trend.display_name = _recipe_name(recipe_id)
	trend.utility_bonus = TREND_BONUS
	trend.days_left = TREND_DAYS
	trend.source_company = campaign.company_id
	city_trends.append(trend)
	_trend_exposure[recipe_id] = 0.0
	EconomyManager.post_message("news", "The city is craving %s!" % trend.display_name)
	trends_changed.emit()


## Public trend hook for awards/competitions: a winning recipe becomes a
## short city-wide craving. Mirrors _maybe_spawn_trend without the exposure
## threshold — the win itself is the trigger.
func create_trend(recipe_id: StringName, trend_name: String, days: int, source_company: StringName, bonus: float = TREND_BONUS) -> void:
	for existing: CityTrend in city_trends:
		if existing.recipe_id == recipe_id:
			existing.days_left = maxi(existing.days_left, days)
			return
	var trend: CityTrend = CityTrend.new()
	trend.recipe_id = recipe_id
	trend.display_name = trend_name if not trend_name.is_empty() else _recipe_name(recipe_id)
	trend.utility_bonus = bonus
	trend.days_left = maxi(1, days)
	trend.source_company = source_company
	city_trends.append(trend)
	EconomyManager.post_message("news", "The city is craving %s!" % trend.display_name)
	trends_changed.emit()


func _tick_trends() -> void:
	var changed: bool = false
	for i: int in range(city_trends.size() - 1, -1, -1):
		city_trends[i].days_left -= 1
		if city_trends[i].days_left <= 0:
			city_trends.remove_at(i)
			changed = true
	if changed:
		trends_changed.emit()


## Claims earn credibility from real reports; false claims lose it and build
## government risk.
func _update_credibility(campaign: MarketingCampaign) -> void:
	if campaign.claim == &"":
		campaign.credibility = CREDIBILITY_NEUTRAL
		campaign.false_claim_days = 0
		return
	var truthful: bool = _claim_is_true(campaign)
	if truthful:
		campaign.credibility = 1.0
		campaign.false_claim_days = 0
	else:
		campaign.credibility = CREDIBILITY_FALSE
		campaign.false_claim_days += 1


## Public truth probe so UI/AI can warn before launching a false claim.
func claim_check(company_id: StringName, claim: StringName) -> bool:
	var probe: MarketingCampaign = MarketingCampaign.new()
	probe.company_id = company_id
	probe.claim = claim
	return _claim_is_true(probe)


func _claim_is_true(campaign: MarketingCampaign) -> bool:
	# A named rival narrows the comparison to that one company (easier to be
	# true, but provokes a response).
	var opponent: CompanyState = CompanyManager.company(campaign.rival_target) \
		if campaign.rival_target != &"" else null
	match campaign.claim:
		&"lowest_price":
			return _company_rank(campaign.company_id, _avg_menu_price, true, opponent)
		&"best_staff":
			return _company_rank(campaign.company_id, _avg_staff_strength, false, opponent)
		&"highest_quality":
			return _company_rank(campaign.company_id, _avg_star_rating, false, opponent)
		&"award_winner":
			# True only for companies holding at least one trophy or medal —
			# false award claims run the credibility/fine gauntlet.
			var tree: SceneTree = Engine.get_main_loop() as SceneTree
			var awards: Node = tree.root.get_node_or_null(^"AwardsManager") if tree != null else null
			if awards == null:
				return false
			return int(awards.trophies_for(campaign.company_id)) > 0
	return true


func _roll_government_risk(campaign: MarketingCampaign) -> void:
	if campaign.false_claim_days <= FALSE_CLAIM_GRACE_DAYS:
		return
	if _rng.randf() > FALSE_CLAIM_FINE_CHANCE * campaign.intensity:
		return
	var company: CompanyState = CompanyManager.company(campaign.company_id)
	if company == null:
		return
	var fine: float = FINE_BASE + campaign.cost_per_day * 2.0
	company.transact(&"fine", -fine)
	company.add_reputation(-0.2, 1.0, 5.0)
	EconomyManager.post_company_message(company.brand_color, "alert",
		"%s fined $%.0f for misleading advertising." % [company.display_name, fine])
	campaign.false_claim_days = 0
	campaign.effectiveness *= 0.5


## Registered with EconomyManager.daily_cost_providers — runs once per company
## on day rollover. Charges campaigns and billboard rent; expires both.
func _charge_daily(company: CompanyState, _day: int) -> void:
	var changed: bool = false
	for i: int in range(campaigns.size() - 1, -1, -1):
		var campaign: MarketingCampaign = campaigns[i]
		if campaign.company_id != company.id:
			continue
		campaign.days_left -= 1
		var branch_gone: bool = campaign.building_id >= 0 \
			and not RestaurantManager.by_building.has(campaign.building_id)
		if campaign.days_left <= 0 or branch_gone or not company.can_afford(campaign.cost_per_day):
			campaigns.remove_at(i)
			changed = true
			continue
		company.transact(&"marketing", -campaign.cost_per_day)
		campaign.total_spend += campaign.cost_per_day
	for site: AdPlacement in placements:
		if site.owner_company != company.id:
			continue
		site.days_left -= 1
		if site.days_left <= 0 or not company.can_afford(site.rent_per_day):
			release_placement(site.id)
			continue
		company.transact(&"marketing", -site.rent_per_day)
	if changed:
		campaigns_changed.emit()


# --- Save ----------------------------------------------------------------------


func write_save(save: SaveGame) -> void:
	save.active_campaigns = campaigns.duplicate()
	save.ad_placements = placements.duplicate()
	save.marketing_awareness = awareness.serialize()
	save.city_trends = city_trends.duplicate()


# --- Internals -------------------------------------------------------------------


func _load_channels() -> void:
	channels.clear()
	var dir: DirAccess = DirAccess.open(CHANNELS_DIR)
	if dir == null:
		push_warning("MarketingManager: channel catalog missing at %s" % CHANNELS_DIR)
		return
	dir.list_dir_begin()
	var file: String = dir.get_next()
	while file != "":
		if file.ends_with(".tres") or file.ends_with(".res"):
			var def: MarketingChannelDef = load("%s/%s" % [CHANNELS_DIR, file])
			if def != null and def.id != &"":
				channels[def.id] = def
		file = dir.get_next()
	dir.list_dir_end()


## Fixed billboard sites near road intersections, spread across the city.
## Deterministic per world seed; persisted wholesale in the save afterwards.
func _generate_placement_sites() -> void:
	var graph: RoadGraph = CityData.road_graph
	if graph == null or graph.intersections.is_empty():
		return
	_rng.seed = hash("ad_sites_%d" % GameSetup.world_seed)
	# Interior intersections only — edge-of-map signs face nothing.
	var lo: Vector3 = Vector3(INF, 0, INF)
	var hi: Vector3 = Vector3(-INF, 0, -INF)
	for inter: Dictionary in graph.intersections:
		var pos: Vector3 = inter.get("pos", Vector3.ZERO)
		lo.x = minf(lo.x, pos.x)
		lo.z = minf(lo.z, pos.z)
		hi.x = maxf(hi.x, pos.x)
		hi.z = maxf(hi.z, pos.z)
	var margin: float = 60.0
	var candidates: Array[Vector3] = []
	for inter: Dictionary in graph.intersections:
		var pos: Vector3 = inter.get("pos", Vector3.ZERO)
		if pos.x < lo.x + margin or pos.x > hi.x - margin \
				or pos.z < lo.z + margin or pos.z > hi.z - margin:
			continue
		candidates.append(pos)
	var shuffle_rng: RandomNumberGenerator = _rng
	for i: int in range(candidates.size() - 1, 0, -1):
		var j: int = shuffle_rng.randi_range(0, i)
		var tmp: Vector3 = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	var picked: Array[Vector3] = []
	for pos: Vector3 in candidates:
		if picked.size() >= MAX_PLACEMENT_SITES:
			break
		var too_close: bool = false
		for other: Vector3 in picked:
			if pos.distance_to(other) < PLACEMENT_MIN_SPACING:
				too_close = true
				break
		if not too_close:
			picked.append(pos)
	var next_id: int = 1
	for pos: Vector3 in picked:
		# Corner with the most clearance from buildings; skip cramped crossings.
		var best_offset: Vector3 = Vector3.ZERO
		var best_clearance: float = -1.0
		for offset: Vector3 in [Vector3(5.5, 0, 5.5), Vector3(-5.5, 0, 5.5),
				Vector3(5.5, 0, -5.5), Vector3(-5.5, 0, -5.5)]:
			var clearance: float = _building_clearance(pos + offset)
			if clearance > best_clearance:
				best_clearance = clearance
				best_offset = offset
		if best_clearance < 9.0:
			continue
		var site: AdPlacement = AdPlacement.new()
		site.id = next_id
		next_id += 1
		site.world_pos = pos + best_offset
		site.district = _district_of(pos)
		site.rent_per_day = PLACEMENT_BASE_RENT + 20.0 * _local_density(pos)
		# Face the crossing so drivers see the panel.
		var toward: Vector3 = (pos - site.world_pos).normalized()
		site.yaw = atan2(toward.z, -toward.x)
		placements.append(site)


func _campaign_centers(campaign: MarketingCampaign) -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for placement_id: int in campaign.placement_ids:
		var site: AdPlacement = placement(placement_id)
		if site != null:
			centers.append(site.world_pos)
	if centers.is_empty() and campaign.building_id >= 0:
		var rest: RestaurantState = RestaurantManager.by_building.get(campaign.building_id)
		if rest != null:
			centers.append(rest.door_pos)
	return centers


func _covers_point(campaign: MarketingCampaign, rest: RestaurantState, origin: Vector3) -> bool:
	var def: MarketingChannelDef = channel(campaign.channel_id)
	if def != null and def.reach_shape == &"city":
		return true
	if campaign.building_id != rest.building_id and campaign.placement_ids.is_empty():
		return false
	var radius: float = campaign.radius
	for center: Vector3 in _campaign_centers(campaign):
		if origin.distance_to(center) <= radius:
			return true
	return false


func _campaign_reaches_district(campaign: MarketingCampaign, district: String) -> bool:
	return coverage_districts(campaign).has(district)


func _message_fit(campaign: MarketingCampaign, segment: StringName) -> float:
	var wanted: Array[StringName] = campaign.segments()
	var fit: float
	if wanted.is_empty():
		fit = FIT_BROAD
	elif wanted.has(segment):
		fit = 1.0
	else:
		fit = FIT_MISS
	if campaign.promoted_recipe != &"" and RecipeManager.is_recipe(campaign.promoted_recipe):
		var appeal: float = RecipeManager.segment_appeal(campaign.promoted_recipe, &"med", segment)
		fit *= 1.0 - FIT_RECIPE_WEIGHT + FIT_RECIPE_WEIGHT * clampf(appeal, 0.0, 1.5)
	return fit


## Average fit across targeted segments, for previews.
func _preview_fit(campaign: MarketingCampaign) -> float:
	var total: float = 0.0
	for segment: StringName in RecipeManager.SEGMENTS:
		total += _message_fit(campaign, segment)
	return total / RecipeManager.SEGMENTS.size()


func _novelty(campaign: MarketingCampaign) -> float:
	return 1.0 - clampf(campaign.days_run / NOVELTY_DECAY_DAYS, 0.0, 1.0 - NOVELTY_FLOOR)


func _spend_efficiency(campaign: MarketingCampaign) -> float:
	var spend: float = maxf(campaign.cost_per_day, 1.0)
	return clampf(sqrt(spend / REF_DAILY_SPEND), 0.4, 1.6)


func _campaign_frequency(campaign: MarketingCampaign) -> float:
	var def: MarketingChannelDef = channel(campaign.channel_id)
	return def.frequency if def != null else 1.0


func _awareness_weight() -> float:
	return float(EconomyManager.tuning_value("marketing.awareness_weight", 0.12))


# --- Claim truth checks ---------------------------------------------------------


## True when the company is best (lowest wins with `ascending`) on `metric`
## among companies that have restaurants — or vs one `opponent` only.
func _company_rank(company_id: StringName, metric: Callable, ascending: bool,
		opponent: CompanyState = null) -> bool:
	var mine: float = -1.0
	var best_other: float = -1.0
	for entry: CompanyState in CompanyManager.companies:
		if entry.restaurants.is_empty():
			continue
		if opponent != null and entry.id != company_id and entry.id != opponent.id:
			continue
		var value: float = metric.call(entry)
		if entry.id == company_id:
			mine = value
		elif best_other < 0.0 or (value < best_other) == ascending:
			best_other = value
	if mine < 0.0:
		return false
	if best_other < 0.0:
		return true
	return (mine <= best_other) if ascending else (mine >= best_other)


func _avg_menu_price(company: CompanyState) -> float:
	var total: float = 0.0
	var count: int = 0
	for rest: RestaurantState in company.restaurants:
		for entry: MenuEntry in rest.enabled_menu():
			total += entry.price
			count += 1
	return total / count if count > 0 else 999.0


func _avg_staff_strength(company: CompanyState) -> float:
	var total: float = 0.0
	var count: int = 0
	for rest: RestaurantState in company.restaurants:
		for member: StaffMember in rest.staff:
			for key: Variant in member.attributes:
				total += float(member.attributes[key])
				count += 1
	return total / count if count > 0 else 0.0


func _avg_star_rating(company: CompanyState) -> float:
	var total: float = 0.0
	for rest: RestaurantState in company.restaurants:
		total += rest.star_rating
	return total / company.restaurants.size() if not company.restaurants.is_empty() else 0.0


# --- Geometry helpers ------------------------------------------------------------


func _ensure_district_positions() -> void:
	if not _district_positions.is_empty():
		return
	for info: Dictionary in CityData.buildings.values():
		var district: String = String(info.get("district", ""))
		if district == "":
			continue
		if not _district_positions.has(district):
			_district_positions[district] = PackedVector3Array()
		var points: PackedVector3Array = _district_positions[district]
		points.append(info.get("position", Vector3.ZERO))
		_district_positions[district] = points


func _district_of(pos: Vector3) -> String:
	var best: String = "N"
	var best_dist: float = INF
	for info: Dictionary in CityData.buildings.values():
		var d: float = pos.distance_squared_to(info.get("position", Vector3.ZERO))
		if d < best_dist:
			best_dist = d
			best = String(info.get("district", "N"))
	return best


## Distance to the nearest building center (world prop clearance check).
func _building_clearance(pos: Vector3) -> float:
	var best: float = INF
	for info: Dictionary in CityData.buildings.values():
		best = minf(best, pos.distance_to(info.get("position", Vector3.ZERO)))
	return best


## Rough buildings-per-radius density used to price billboard rent.
func _local_density(pos: Vector3) -> float:
	var count: int = 0
	for info: Dictionary in CityData.buildings.values():
		if pos.distance_to(info.get("position", Vector3.ZERO)) < 300.0:
			count += 1
	return count / 100.0


func _company_name(company_id: StringName) -> String:
	var company: CompanyState = CompanyManager.company(company_id)
	return company.display_name if company != null else String(company_id)


func _recipe_name(recipe_id: StringName) -> String:
	var rec: RecipeDef = RecipeManager.recipe(recipe_id)
	if rec != null and "display_name" in rec:
		return rec.display_name
	return String(recipe_id).capitalize()
