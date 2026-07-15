extends Node
## Citizen-side economy (wealth, daily wages, taste preferences) and the
## demand loop that turns citizens into restaurant orders.
##
## The economy is generated in a deterministic post-pass (POPULATION_SEED + 3)
## so the existing population generation stays byte-identical.
## Demand is sharded: each citizen is evaluated once per game hour, spread
## across the 60 minutes by id — no frame spikes at 550 citizens.

signal order_generated(order: FoodOrder)
signal restaurant_intent_changed(citizen_id: int, restaurant_id: int, active: bool)

const ECONOMY_TABLES_PATH: String = "res://data/economy_tables.json"
const ECON_SEED_OFFSET: int = 3
## Separate RNG stream so seeding demographics never shifts wealth/tastes.
const DEMOGRAPHIC_SEED_OFFSET: int = 7

## District char -> demographic weights (customer-profile buckets).
const DEMOGRAPHIC_WEIGHTS: Dictionary = {
	"R": {&"teens": 0.10, &"students": 0.05, &"workers": 0.20, &"families": 0.40, &"seniors": 0.25},
	"N": {&"teens": 0.15, &"students": 0.10, &"workers": 0.30, &"families": 0.35, &"seniors": 0.10},
	"P": {&"teens": 0.20, &"students": 0.30, &"workers": 0.30, &"families": 0.10, &"seniors": 0.10},
	"D": {&"teens": 0.15, &"students": 0.25, &"workers": 0.40, &"families": 0.10, &"seniors": 0.10},
	"C": {&"teens": 0.20, &"students": 0.30, &"workers": 0.35, &"families": 0.10, &"seniors": 0.05},
	"I": {&"teens": 0.10, &"students": 0.15, &"workers": 0.55, &"families": 0.10, &"seniors": 0.10},
}

## citizen_id -> {wealth: float, daily_wage: float, tastes: {category: 0..1}}
var econ: Dictionary = {}
var tables: Dictionary = {}
## Wealth overrides from a loaded save, applied after deterministic gen.
var pending_wealth: Dictionary = {}
## citizen_id -> live restaurant visit intent used by operations UI and world thoughts.
var restaurant_intents: Dictionary = {}
## building_id -> cached customer-profile fractions (home positions are static).
var _profile_cache: Dictionary = {}

## Fallback meal-time weighting (index = hour, mean ~1). Overridable via
## tuning.json demand.hour_weights.
const DEFAULT_HOUR_WEIGHTS: Array[float] = [
	0.1, 0.05, 0.05, 0.05, 0.05, 0.1, 0.3, 0.6, 0.8, 0.6, 0.7, 1.8,
	2.6, 2.2, 1.0, 0.6, 0.8, 1.4, 2.4, 2.8, 2.2, 1.4, 0.8, 0.3,
]

var _initialized: bool = false
var _econ_ready: bool = false
var _last_demand_minute: int = -1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	tables = _load_json(ECONOMY_TABLES_PATH)
	GameClock.minute_ticked.connect(_on_minute)
	GameClock.day_changed.connect(_pay_wages)
	set_process(true)


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	# Wait until PopulationManager has generated the citizen records.
	if PopulationManager.citizens_data.is_empty():
		return
	_generate_econ()
	set_process(false)


func citizen_econ(citizen_id: int) -> Dictionary:
	return econ.get(citizen_id, {})


func demographic_of(citizen_id: int) -> StringName:
	return econ.get(citizen_id, {}).get("demographic", &"")


func charge_citizen(citizen_id: int, amount: float) -> void:
	if econ.has(citizen_id):
		var entry: Dictionary = econ[citizen_id]
		entry["wealth"] = maxf(0.0, float(entry["wealth"]) - amount)


func set_restaurant_intent(citizen_id: int, restaurant_id: int, dish_id: StringName, citizen: Node) -> void:
	restaurant_intents[citizen_id] = {
		"citizen_id": citizen_id,
		"restaurant_id": restaurant_id,
		"dish_id": dish_id,
		"citizen": citizen,
		"started_minute": GameClock.total_minutes(),
	}
	restaurant_intent_changed.emit(citizen_id, restaurant_id, true)


func clear_restaurant_intent(citizen_id: int) -> void:
	if not restaurant_intents.has(citizen_id):
		return
	var restaurant_id: int = int(restaurant_intents[citizen_id].get("restaurant_id", -1))
	restaurant_intents.erase(citizen_id)
	restaurant_intent_changed.emit(citizen_id, restaurant_id, false)


func restaurant_intents_for(building_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for citizen_id: int in restaurant_intents:
		var intent: Dictionary = restaurant_intents[citizen_id]
		if int(intent.get("restaurant_id", -1)) != building_id:
			continue
		var citizen: Node = intent.get("citizen")
		if not is_instance_valid(citizen):
			continue
		var row: Dictionary = intent.duplicate()
		var citizen_data: Variant = citizen.get("data")
		row["name"] = citizen_data.get("name", "Citizen") if citizen_data is Dictionary else "Citizen"
		row["goal"] = String(citizen.get("goal_desc"))
		row["position"] = (citizen as Node3D).global_position if citizen is Node3D else Vector3.ZERO
		result.append(row)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["started_minute"]) < int(b["started_minute"]))
	return result


# --- Generation ---------------------------------------------------------------


func _generate_econ() -> void:
	var gen: RandomNumberGenerator = RandomNumberGenerator.new()
	gen.seed = PopulationManager.POPULATION_SEED + ECON_SEED_OFFSET
	var wealth_ranges: Dictionary = tables.get("wealth_init_by_district", {})
	var taste_cfg: Dictionary = tables.get("taste", {})
	var categories: Array = taste_cfg.get("categories", [])
	var biases: Dictionary = taste_cfg.get("district_bias", {})
	var sigma: float = float(taste_cfg.get("sigma", 0.25))
	for cd: Dictionary in PopulationManager.citizens_data:
		var district: String = String(cd.get("district", "N"))
		var wealth_range: Array = wealth_ranges.get(district, [500.0, 2000.0])
		var bias: Dictionary = biases.get(district, {})
		var tastes: Dictionary = {}
		for category: String in categories:
			var value: float = 0.5 + float(bias.get(category, 0.0)) + gen.randfn(0.0, sigma)
			tastes[StringName(category)] = clampf(value, 0.05, 1.0)
		econ[int(cd["id"])] = {
			"wealth": gen.randf_range(float(wealth_range[0]), float(wealth_range[1])),
			"daily_wage": _wage_for(cd),
			"tastes": tastes,
		}
	for citizen_id: int in pending_wealth:
		if econ.has(citizen_id):
			econ[citizen_id]["wealth"] = float(pending_wealth[citizen_id])
	pending_wealth.clear()
	_seed_demographics()
	_econ_ready = true
	print("DemandManager: economy generated for %d citizens" % econ.size())


func _seed_demographics() -> void:
	## Deterministic age-group tag per citizen, weighted by home district.
	var gen: RandomNumberGenerator = RandomNumberGenerator.new()
	gen.seed = PopulationManager.POPULATION_SEED + DEMOGRAPHIC_SEED_OFFSET
	for cd: Dictionary in PopulationManager.citizens_data:
		var entry: Dictionary = econ.get(int(cd["id"]), {})
		if entry.is_empty():
			continue
		var district: String = String(cd.get("district", "N"))
		var weights: Dictionary = DEMOGRAPHIC_WEIGHTS.get(district, DEMOGRAPHIC_WEIGHTS["N"])
		entry["demographic"] = _weighted_pick(weights, gen)


func _weighted_pick(weights: Dictionary, gen: RandomNumberGenerator) -> StringName:
	var roll: float = gen.randf()
	var acc: float = 0.0
	var last: StringName = &"workers"
	for key: StringName in weights:
		acc += float(weights[key])
		last = key
		if roll <= acc:
			return key
	return last


## Demographic mix of potential customers around a restaurant (delivery reach):
## {teens, students, workers, families, seniors} fractions summing to ~1.
## Cached per building — home positions never move.
func customer_profile(building_id: int) -> Dictionary:
	if _profile_cache.has(building_id):
		return _profile_cache[building_id]
	if not _econ_ready:
		return {}
	var rest_building: Dictionary = CityData.get_building(building_id)
	if rest_building.is_empty():
		return {}
	var door: Vector3 = rest_building.get("door_pos", rest_building.get("position", Vector3.ZERO))
	var radius: float = float(EconomyManager.tuning_value("distance.delivery_max_m", 600.0))
	var counts: Dictionary = {
		&"teens": 0, &"students": 0, &"workers": 0, &"families": 0, &"seniors": 0,
	}
	var total: int = 0
	for cd: Dictionary in PopulationManager.citizens_data:
		var home: Dictionary = CityData.get_building(int(cd.get("home_id", -1)))
		if home.is_empty():
			continue
		var home_pos: Vector3 = home.get("position", Vector3.ZERO)
		if home_pos.distance_to(door) > radius:
			continue
		var entry: Dictionary = econ.get(int(cd["id"]), {})
		var demo: StringName = entry.get("demographic", &"workers")
		counts[demo] = int(counts.get(demo, 0)) + 1
		total += 1
	if total == 0:
		return {}
	var profile: Dictionary = {}
	for key: StringName in counts:
		profile[key] = float(counts[key]) / float(total)
	_profile_cache[building_id] = profile
	return profile


func _wage_for(cd: Dictionary) -> float:
	var wages: Dictionary = tables.get("wage_by_job_type", {})
	var job: String = String(cd.get("job_type", "none"))
	if job.is_empty() or int(cd.get("work_id", -1)) < 0 and not wages.has(job):
		job = "none"
	if wages.has(job):
		return float(wages[job])
	return float(wages.get("default", 80.0))


func _pay_wages(_day: int) -> void:
	if not _econ_ready:
		return
	for cd: Dictionary in PopulationManager.citizens_data:
		var entry: Dictionary = econ.get(int(cd["id"]), {})
		if not entry.is_empty():
			entry["wealth"] = float(entry["wealth"]) + float(entry["daily_wage"])


# --- Demand loop ---------------------------------------------------------------


func _on_minute(_day: int, _hour: int, _minute: int) -> void:
	if not _econ_ready or RestaurantManager.by_building.is_empty():
		return
	var now: int = GameClock.total_minutes()
	if _last_demand_minute < 0:
		_last_demand_minute = now
		return
	# Walk every skipped minute so demand stays consistent at 16x speed.
	var from: int = maxi(_last_demand_minute + 1, now - 59)
	for minute_abs: int in range(from, now + 1):
		var shard: int = minute_abs % 60
		var hour: int = (minute_abs / 60) % 24
		for cd: Dictionary in PopulationManager.citizens_data:
			if int(cd["id"]) % 60 == shard:
				_evaluate_citizen(cd, hour)
	_last_demand_minute = now


func _evaluate_citizen(cd: Dictionary, hour: int) -> void:
	var citizen_id: int = int(cd["id"])
	var entry: Dictionary = econ.get(citizen_id, {})
	if entry.is_empty():
		return
	var occasions: float = float(EconomyManager.tuning_value(
		"demand.meal_occasions_per_citizen_per_day", 1.4))
	var weights: Array = EconomyManager.tuning_value("demand.hour_weights", DEFAULT_HOUR_WEIGHTS)
	var weight: float = float(weights[hour]) if hour < weights.size() else 1.0
	if _rng.randf() > occasions / 24.0 * weight:
		return
	var wealth: float = float(entry["wealth"])
	var budget: float = maxf(
		float(EconomyManager.tuning_value("demand.min_meal_budget", 6.0)),
		wealth * float(EconomyManager.tuning_value("demand.meal_budget_wealth_fraction", 0.02)))
	if wealth < budget:
		return
	var dinein_share: float = float(EconomyManager.tuning_value("demand.dinein_share", 0.45))
	var want_dine_in: bool = _rng.randf() < dinein_share
	if want_dine_in and _try_dine_in(cd, entry, budget):
		return
	_try_delivery(cd, entry, budget)


func _try_dine_in(cd: Dictionary, entry: Dictionary, budget: float) -> bool:
	var citizen: Node = PopulationManager.citizen_by_id(int(cd["id"]))
	if citizen == null or not citizen.has_method("go_dine"):
		return false
	var origin: Vector3 = citizen.global_position
	var owns_car: bool = bool(cd.get("owns_car", false))
	var max_dist: float = float(EconomyManager.tuning_value(
		"distance.drive_max_m" if owns_car else "distance.walk_max_m",
		900.0 if owns_car else 150.0))
	var pick: Dictionary = _best_offer(entry, budget, origin, max_dist, true)
	if pick.is_empty():
		return false
	var rest: RestaurantState = pick["rest"]
	return citizen.go_dine(rest.building_id, rest.door_pos, pick["dish_id"])


func _try_delivery(cd: Dictionary, entry: Dictionary, budget: float) -> bool:
	var home: Dictionary = CityData.get_building(int(cd.get("home_id", -1)))
	if home.is_empty():
		return false
	var door: Vector3 = home.get("door_pos", Vector3.ZERO)
	var max_dist: float = float(EconomyManager.tuning_value("distance.delivery_max_m", 600.0))
	var pick: Dictionary = _best_offer(entry, budget, door, max_dist, false)
	if pick.is_empty():
		return false
	var rest: RestaurantState = pick["rest"]
	var order: FoodOrder = RestaurantManager.make_order(
		rest.building_id, int(cd["id"]), pick["dish_id"], true)
	if order == null:
		return false
	order.target_door = door
	if RestaurantManager.place_delivery_order(order):
		order_generated.emit(order)
		return true
	return false


## Scores every enabled dish of every open restaurant within range and returns
## {rest, dish_id, utility} for the best offer above the acceptance threshold.
func _best_offer(entry: Dictionary, budget: float, origin: Vector3,
		max_dist: float, dine_in: bool) -> Dictionary:
	var tastes: Dictionary = entry["tastes"]
	var tw: float = float(EconomyManager.tuning_value("demand.taste_weight", 1.6))
	var pw: float = float(EconomyManager.tuning_value("demand.price_weight", 1.0))
	var dw: float = float(EconomyManager.tuning_value("demand.distance_weight", 0.8))
	var rw: float = float(EconomyManager.tuning_value("demand.rating_weight", 0.6))
	var min_utility: float = float(EconomyManager.tuning_value("demand.min_utility", 0.25))
	var hourf: float = GameClock.game_hours
	var best: Dictionary = {}
	var best_utility: float = min_utility
	for rest: RestaurantState in RestaurantManager.all_restaurants():
		if not rest.is_open(hourf):
			continue
		if dine_in and not rest.dine_in_enabled:
			continue
		if not dine_in and not rest.delivery_enabled:
			continue
		# Citizens can see an unstaffed counter — don't waste trips on
		# restaurants that cannot serve right now.
		if rest.staff_on_shift(&"cook", hourf) <= 0:
			continue
		if dine_in and rest.staff_on_shift(&"waiter", hourf) <= 0:
			continue
		if not dine_in and rest.staff_on_shift(&"driver", hourf) <= 0:
			continue
		var dist: float = origin.distance_to(rest.door_pos)
		if dist > max_dist:
			continue
		# Marketing terms: per-restaurant awareness/coverage bump hoisted out of
		# the menu loop; per-dish promotion/trend uplift added per entry.
		var segment: StringName = entry.get("demographic", &"workers")
		var ad_bonus: float = MarketingManager.bonus_for(rest, segment, origin)
		for menu_entry: MenuEntry in rest.enabled_menu():
			if menu_entry.price > budget:
				continue
			var taste: float
			if RecipeManager.is_recipe(menu_entry.dish_id):
				# Custom/starter recipes: per-segment appeal replaces the
				# category-taste * popularity term.
				taste = RecipeManager.segment_appeal(menu_entry.dish_id,
					menu_entry.tier, entry.get("demographic", &"workers"))
			else:
				var def: DishDef = RestaurantManager.dish(menu_entry.dish_id)
				if def == null:
					continue
				taste = float(tastes.get(def.category, 0.3)) * def.popularity
			var utility: float = taste * tw \
				+ rest.star_rating / 5.0 * rw \
				- menu_entry.price / budget * pw * 0.5 \
				- dist / max_dist * dw * 0.5 \
				+ ad_bonus \
				+ MarketingManager.dish_bonus_for(rest, menu_entry.dish_id, segment) \
				+ clampf(float(rest.interior_appeal.get(segment, 0.0)), -0.5, 3.5) \
					* float(EconomyManager.tuning_value("demand.interior_weight", 0.12))
			if utility > best_utility:
				best_utility = utility
				best = {"rest": rest, "dish_id": menu_entry.dish_id, "utility": utility}
	return best


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("DemandManager: missing %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
