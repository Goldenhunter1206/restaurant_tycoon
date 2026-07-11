extends Node
## Citizen-side economy (wealth, daily wages, taste preferences) and the
## demand loop that turns citizens into restaurant orders.
##
## The economy is generated in a deterministic post-pass (POPULATION_SEED + 3)
## so the existing population generation stays byte-identical.
## Demand is sharded: each citizen is evaluated once per game hour, spread
## across the 60 minutes by id — no frame spikes at 550 citizens.

signal order_generated(order: FoodOrder)

const ECONOMY_TABLES_PATH: String = "res://data/economy_tables.json"
const ECON_SEED_OFFSET: int = 3

## citizen_id -> {wealth: float, daily_wage: float, tastes: {category: 0..1}}
var econ: Dictionary = {}
var tables: Dictionary = {}
## Wealth overrides from a loaded save, applied after deterministic gen.
var pending_wealth: Dictionary = {}

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


func charge_citizen(citizen_id: int, amount: float) -> void:
	if econ.has(citizen_id):
		var entry: Dictionary = econ[citizen_id]
		entry["wealth"] = maxf(0.0, float(entry["wealth"]) - amount)


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
	_econ_ready = true
	print("DemandManager: economy generated for %d citizens" % econ.size())


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
	if not _econ_ready or RestaurantManager.owned.is_empty():
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
	for rest: RestaurantState in RestaurantManager.owned:
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
		for menu_entry: MenuEntry in rest.enabled_menu():
			if menu_entry.price > budget:
				continue
			var def: DishDef = RestaurantManager.dish(menu_entry.dish_id)
			if def == null:
				continue
			var taste: float = float(tastes.get(def.category, 0.3)) * def.popularity
			var utility: float = taste * tw \
				+ rest.star_rating / 5.0 * rw \
				- menu_entry.price / budget * pw * 0.5 \
				- dist / max_dist * dw * 0.5
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
