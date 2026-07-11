extends Node
## Owns the dish/staff catalogs and every player restaurant, and advances the
## per-restaurant kitchen + dining-room simulation each game minute.
## Catalogs are directory-loaded: drop a .tres into data/dishes or
## data/staff_types and it is available without code changes.

signal restaurant_purchased(rest: RestaurantState)
signal restaurant_updated(building_id: int)
signal order_state_changed(order: FoodOrder)
signal order_ready_for_delivery(order: FoodOrder)

const DISH_DIR: String = "res://data/dishes"
const STAFF_TYPE_DIR: String = "res://data/staff_types"

var dishes: Dictionary = {}
var staff_types: Dictionary = {}
var owned: Array[RestaurantState] = []
var by_building: Dictionary = {}

var _next_order_id: int = 1
var _next_staff_uid: int = 1
var _last_tick_minute: int = -1
var _initialized: bool = false


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_load_catalogs()
	GameClock.minute_ticked.connect(_on_minute)
	GameClock.day_changed.connect(_on_day_changed)
	EconomyManager.daily_cost_providers.append(_charge_daily_costs)
	var save: SaveGame = SaveSystem.load_game()
	if save != null:
		_restore_from_save(save)
	else:
		_found_starting_restaurant()


func dish(dish_id: StringName) -> DishDef:
	return dishes.get(dish_id)


func staff_type(type_id: StringName) -> StaffTypeDef:
	return staff_types.get(type_id)


# --- Ownership / purchase -------------------------------------------------


func price_for(building_id: int) -> float:
	var info: Dictionary = CityData.get_building(building_id)
	if info.is_empty():
		return 0.0
	var base: float = float(EconomyManager.tuning_value("purchase.base_price", 14000.0))
	var mults: Dictionary = EconomyManager.tuning_value("purchase.affluence_mult", {})
	var mult: float = float(mults.get(info.get("district", "N"), 1.0))
	var body: Node3D = get_node_or_null(info.get("node_path", NodePath()))
	var area: float = 120.0
	if body != null and body.has_meta("size"):
		var size: Vector3 = body.get_meta("size")
		area = size.x * size.z
	var size_factor: float = float(EconomyManager.tuning_value("purchase.size_factor", 0.004))
	return base * mult * (1.0 + size_factor * area)


func is_purchasable(building_id: int) -> bool:
	if by_building.has(building_id):
		return false
	var info: Dictionary = CityData.get_building(building_id)
	if info.is_empty():
		return false
	var btype: String = String(info.get("type", ""))
	var district: String = String(info.get("district", ""))
	if btype == "shop":
		return district in ["C", "D", "N", "R", "P"]
	# Downtown has no dedicated shop lots — ground-floor office conversions
	# are the (expensive) way into the D district.
	if btype == "office":
		return district == "D"
	return false


func purchasable_buildings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: int in CityData.buildings:
		if is_purchasable(id):
			var info: Dictionary = CityData.get_building(id).duplicate()
			info["price"] = price_for(id)
			result.append(info)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["price"]) < float(b["price"]))
	return result


func purchase(building_id: int, restaurant_name: String = "") -> bool:
	if not is_purchasable(building_id):
		return false
	var price: float = price_for(building_id)
	if not EconomyManager.can_afford(price):
		EconomyManager.post_message("alert", "Not enough cash to buy this location ($%.0f)." % price)
		return false
	EconomyManager.transact(&"property_purchase", -price)
	var rest: RestaurantState = _add_restaurant(building_id, restaurant_name, price)
	EconomyManager.post_message("good", "Opened %s for $%.0f!" % [rest.restaurant_name, price])
	EconomyManager.post_message("info", "Hire cooks and waiters so %s can serve customers." % rest.restaurant_name)
	return true


# --- Order intake ----------------------------------------------------------


func make_order(building_id: int, citizen_id: int, dish_id: StringName, is_delivery: bool) -> FoodOrder:
	var rest: RestaurantState = by_building.get(building_id)
	if rest == null:
		return null
	var entry: MenuEntry = rest.menu_entry_for(dish_id)
	var def: DishDef = dishes.get(dish_id)
	if entry == null or def == null:
		return null
	var tier: QualityTier = def.tier_by_id(entry.tier)
	var order: FoodOrder = FoodOrder.new()
	order.order_id = _next_order_id
	_next_order_id += 1
	order.restaurant_id = building_id
	order.citizen_id = citizen_id
	order.dish_id = dish_id
	order.tier = entry.tier
	order.price = entry.price
	order.ingredient_cost = tier.ingredient_cost if tier != null else 2.0
	order.prep_minutes = def.base_prep_minutes
	order.placed_minute = GameClock.total_minutes()
	order.is_delivery = is_delivery
	return order


## Delivery intake. Returns false when the restaurant cannot take the order
## (closed, channel off, cap reached, no driver on shift).
func place_delivery_order(order: FoodOrder) -> bool:
	var rest: RestaurantState = by_building.get(order.restaurant_id)
	if rest == null or not rest.delivery_enabled:
		return false
	if not rest.is_open(GameClock.game_hours):
		return false
	if rest.active_deliveries >= rest.delivery_cap:
		return false
	if rest.staff_on_shift(&"driver", GameClock.game_hours) <= 0:
		return false
	if rest.staff_on_shift(&"cook", GameClock.game_hours) <= 0:
		return false
	order.state = FoodOrder.State.QUEUED
	rest.cook_backlog.append(order)
	rest.active_deliveries += 1
	DeliveryManager.register_order(order)
	order_state_changed.emit(order)
	return true


## Dine-in intake, called when a citizen arrives at the door.
## Returns "seated", "queued" or "rejected".
func request_seat(citizen: Node, building_id: int, dish_id: StringName) -> String:
	var rest: RestaurantState = by_building.get(building_id)
	if rest == null or not rest.dine_in_enabled:
		return "rejected"
	if not rest.is_open(GameClock.game_hours):
		return "rejected"
	if rest.staff_on_shift(&"cook", GameClock.game_hours) <= 0:
		return "rejected"
	if rest.staff_on_shift(&"waiter", GameClock.game_hours) <= 0:
		return "rejected"
	if rest.menu_entry_for(dish_id) == null:
		return "rejected"
	if _try_seat(rest, citizen, dish_id):
		return "seated"
	rest.dine_queue.append({
		"citizen": citizen,
		"dish_id": dish_id,
		"arrived_minute": GameClock.total_minutes(),
	})
	return "queued"


# --- Staff -----------------------------------------------------------------


func hire(building_id: int, type_id: StringName, shift_start: float = -1.0) -> StaffMember:
	var rest: RestaurantState = by_building.get(building_id)
	var def: StaffTypeDef = staff_types.get(type_id)
	if rest == null or def == null:
		return null
	var member: StaffMember = StaffMember.new()
	member.uid = _next_staff_uid
	_next_staff_uid += 1
	member.type_id = type_id
	member.staff_name = _random_person_name()
	member.daily_wage = def.base_daily_wage
	member.shift_hours = float(EconomyManager.tuning_value("staff.max_shift_hours", 8.0))
	member.shift_start = shift_start if shift_start >= 0.0 else rest.open_hour
	rest.staff.append(member)
	if def.is_driver:
		DeliveryManager.on_driver_hired(rest, member)
	restaurant_updated.emit(building_id)
	return member


func fire(building_id: int, uid: int) -> bool:
	var rest: RestaurantState = by_building.get(building_id)
	if rest == null:
		return false
	for i: int in rest.staff.size():
		var member: StaffMember = rest.staff[i]
		if member.uid == uid:
			rest.staff.remove_at(i)
			var def: StaffTypeDef = staff_types.get(member.type_id)
			if def != null and def.is_driver:
				DeliveryManager.on_driver_fired(rest, member)
			restaurant_updated.emit(building_id)
			return true
	return false


# --- Settings mutators (UI entry points) ------------------------------------


func set_menu_entry(building_id: int, dish_id: StringName, price: float, tier: StringName, enabled: bool) -> void:
	var rest: RestaurantState = by_building.get(building_id)
	if rest == null:
		return
	for entry: MenuEntry in rest.menu:
		if entry.dish_id == dish_id:
			entry.price = maxf(0.5, price)
			entry.tier = tier
			entry.enabled = enabled
			restaurant_updated.emit(building_id)
			return
	var entry: MenuEntry = MenuEntry.new()
	entry.dish_id = dish_id
	entry.price = maxf(0.5, price)
	entry.tier = tier
	entry.enabled = enabled
	rest.menu.append(entry)
	restaurant_updated.emit(building_id)


func set_hours(building_id: int, open_hour: float, close_hour: float) -> void:
	var rest: RestaurantState = by_building.get(building_id)
	if rest == null:
		return
	rest.open_hour = wrapf(open_hour, 0.0, 24.0)
	rest.close_hour = wrapf(close_hour, 0.0, 24.0)
	restaurant_updated.emit(building_id)


func set_channels(building_id: int, dine_in: bool, delivery: bool) -> void:
	var rest: RestaurantState = by_building.get(building_id)
	if rest == null:
		return
	rest.dine_in_enabled = dine_in
	rest.delivery_enabled = delivery
	restaurant_updated.emit(building_id)


func set_delivery_cap(building_id: int, cap: int) -> void:
	var rest: RestaurantState = by_building.get(building_id)
	if rest == null:
		return
	rest.delivery_cap = clampi(cap, 0, 99)
	restaurant_updated.emit(building_id)


# --- Per-minute simulation ---------------------------------------------------


func _on_minute(_day: int, hour: int, _minute: int) -> void:
	var now: int = GameClock.total_minutes()
	if _last_tick_minute < 0:
		_last_tick_minute = now
		return
	var dm: int = now - _last_tick_minute
	if dm <= 0:
		return
	_last_tick_minute = now
	for rest: RestaurantState in owned:
		_tick_restaurant(rest, now, dm, hour)
		restaurant_updated.emit(rest.building_id)


func _tick_restaurant(rest: RestaurantState, now: int, dm: int, _hour: int) -> void:
	var hourf: float = GameClock.game_hours
	# Waiters accumulate fractional serving capacity while on shift.
	var waiters: int = rest.staff_on_shift(&"waiter", hourf)
	if waiters > 0:
		var per_hour: float = 10.0
		var def: StaffTypeDef = staff_types.get(&"waiter")
		if def != null:
			per_hour = def.waiter_customers_per_hour
		var cap: float = maxf(2.0, float(waiters) * 2.0)
		rest.waiter_credits = minf(rest.waiter_credits + float(waiters) * per_hour / 60.0 * float(dm), cap)
	# Kitchen: fill free cook slots from the backlog, then advance active jobs.
	var cook_slots: int = _cook_slots(rest, hourf)
	while rest.cooking.size() < cook_slots and not rest.cook_backlog.is_empty():
		var order: FoodOrder = rest.cook_backlog.pop_front()
		if order.state == FoodOrder.State.CANCELLED:
			continue
		order.state = FoodOrder.State.COOKING
		EconomyManager.transact(&"ingredients", -order.ingredient_cost)
		rest.today["expenses"] = float(rest.today.get("expenses", 0.0)) + order.ingredient_cost
		rest.cooking.append({"order": order, "minutes_left": order.prep_minutes})
		order_state_changed.emit(order)
	var active: int = mini(cook_slots, rest.cooking.size())
	for i: int in range(rest.cooking.size() - 1, -1, -1):
		var job: Dictionary = rest.cooking[i]
		var order: FoodOrder = job["order"]
		if order.state == FoodOrder.State.CANCELLED:
			rest.cooking.remove_at(i)
			continue
		if i >= active:
			continue
		job["minutes_left"] = float(job["minutes_left"]) - float(dm)
		if float(job["minutes_left"]) <= 0.0:
			rest.cooking.remove_at(i)
			_on_cooked(rest, order)
	_tick_dining(rest, now)
	_tick_dine_queue(rest, now)


func _on_cooked(rest: RestaurantState, order: FoodOrder) -> void:
	if order.is_delivery:
		order.state = FoodOrder.State.READY
		order_state_changed.emit(order)
		order_ready_for_delivery.emit(order)
		return
	# Dine-in: the matching seated guest starts eating.
	var eat_minutes: float = float(EconomyManager.tuning_value("dinein.eat_minutes", 45.0))
	for seat: Dictionary in rest.dining:
		if seat["order"] == order:
			seat["done_minute"] = GameClock.total_minutes() + int(eat_minutes)
			order.state = FoodOrder.State.SERVED
			order_state_changed.emit(order)
			return
	# Guest already left — the food is wasted.
	order.state = FoodOrder.State.CANCELLED
	order_state_changed.emit(order)


func _tick_dining(rest: RestaurantState, now: int) -> void:
	var food_wait_max: int = int(EconomyManager.tuning_value("dinein.food_wait_minutes", 60))
	for i: int in range(rest.dining.size() - 1, -1, -1):
		var seat: Dictionary = rest.dining[i]
		var order: FoodOrder = seat["order"]
		var done_minute: int = int(seat["done_minute"])
		if done_minute > 0 and now >= done_minute:
			rest.dining.remove_at(i)
			rest.tables_occupied = maxi(0, rest.tables_occupied - 1)
			_complete_dine_in(rest, seat["citizen"], order)
		elif done_minute < 0 and now - order.placed_minute > food_wait_max:
			# Kitchen never delivered — the guest storms out.
			rest.dining.remove_at(i)
			rest.tables_occupied = maxi(0, rest.tables_occupied - 1)
			order.state = FoodOrder.State.CANCELLED
			rest.today["queue_leaves"] = int(rest.today.get("queue_leaves", 0)) + 1
			EconomyManager.add_reputation(float(EconomyManager.tuning_value("reputation.per_queue_leave", -0.04)))
			_notify_citizen(seat["citizen"], "on_dine_rejected")
			order_state_changed.emit(order)


func _tick_dine_queue(rest: RestaurantState, now: int) -> void:
	var leave_after: int = int(EconomyManager.tuning_value("dinein.queue_leave_minutes", 25))
	for i: int in range(rest.dine_queue.size() - 1, -1, -1):
		var waiting: Dictionary = rest.dine_queue[i]
		var citizen: Node = waiting["citizen"]
		if not is_instance_valid(citizen):
			rest.dine_queue.remove_at(i)
			continue
		if _try_seat(rest, citizen, waiting["dish_id"]):
			rest.dine_queue.remove_at(i)
			continue
		if now - int(waiting["arrived_minute"]) > leave_after:
			rest.dine_queue.remove_at(i)
			rest.today["queue_leaves"] = int(rest.today.get("queue_leaves", 0)) + 1
			EconomyManager.add_reputation(float(EconomyManager.tuning_value("reputation.per_queue_leave", -0.04)))
			_notify_citizen(citizen, "on_dine_rejected")


func _try_seat(rest: RestaurantState, citizen: Node, dish_id: StringName) -> bool:
	if rest.tables_occupied >= rest.table_count or rest.waiter_credits < 1.0:
		return false
	var citizen_id: int = -1
	var data: Variant = citizen.get("data")
	if data is Dictionary:
		citizen_id = int((data as Dictionary).get("id", -1))
	var order: FoodOrder = make_order(rest.building_id, citizen_id, dish_id, false)
	if order == null:
		return false
	rest.tables_occupied += 1
	rest.waiter_credits -= 1.0
	order.state = FoodOrder.State.QUEUED
	rest.cook_backlog.append(order)
	rest.dining.append({"citizen": citizen, "order": order, "done_minute": -1})
	rest.today["guests"] = int(rest.today.get("guests", 0)) + 1
	_notify_citizen(citizen, "on_seated")
	order_state_changed.emit(order)
	return true


func _complete_dine_in(rest: RestaurantState, citizen: Node, order: FoodOrder) -> void:
	EconomyManager.transact(&"dine_in_sales", order.price)
	rest.record_sale(order.price)
	record_category_sale(rest, order.dish_id)
	DemandManager.charge_citizen(order.citizen_id, order.price)
	award_service_reputation(order)
	order.state = FoodOrder.State.SERVED
	_notify_citizen(citizen, "on_meal_done")


## Shared reputation payout for a successfully served/delivered order.
func award_service_reputation(order: FoodOrder) -> void:
	var base: float = float(EconomyManager.tuning_value("reputation.per_served", 0.01))
	var def: DishDef = dishes.get(order.dish_id)
	var quality: float = 0.5
	if def != null:
		var tier: QualityTier = def.tier_by_id(order.tier)
		if tier != null:
			quality = tier.quality_score
	var bonus: float = (quality - 0.5) * float(EconomyManager.tuning_value("reputation.quality_bonus_scale", 0.02))
	EconomyManager.add_reputation(base + bonus)


## Track which cuisine categories sell (customer-profile UI).
func record_category_sale(rest: RestaurantState, dish_id: StringName) -> void:
	var def: DishDef = dishes.get(dish_id)
	if def == null:
		return
	var by_cat: Dictionary = rest.today.get("by_category", {})
	by_cat[def.category] = int(by_cat.get(def.category, 0)) + 1
	rest.today["by_category"] = by_cat


func _cook_slots(rest: RestaurantState, hourf: float) -> int:
	var slots: int = 0
	for member: StaffMember in rest.staff:
		if not member.on_shift(hourf):
			continue
		var def: StaffTypeDef = staff_types.get(member.type_id)
		if def != null:
			slots += def.cook_slots
	return slots


# --- Daily rollover ----------------------------------------------------------


func _on_day_changed(_day: int) -> void:
	for rest: RestaurantState in owned:
		rest.sales_history.append(float(rest.today.get("sales", 0.0)))
		if rest.sales_history.size() > 14:
			rest.sales_history.remove_at(0)
		rest.reset_today()
		restaurant_updated.emit(rest.building_id)


## Registered with EconomyManager.daily_cost_providers.
func _charge_daily_costs(_day: int) -> void:
	var rents: Dictionary = EconomyManager.tuning_value("rent.daily_by_district", {})
	for rest: RestaurantState in owned:
		var wages: float = 0.0
		for member: StaffMember in rest.staff:
			wages += member.daily_wage
		if wages > 0.0:
			EconomyManager.transact(&"wages", -wages)
		var rent: float = float(rents.get(rest.district, 120.0))
		EconomyManager.transact(&"rent", -rent)
		rest.today["expenses"] = float(rest.today.get("expenses", 0.0)) + wages + rent


# --- Setup -------------------------------------------------------------------


func _load_catalogs() -> void:
	for res: Resource in _load_dir(DISH_DIR):
		if res is DishDef:
			dishes[res.id] = res
	for res: Resource in _load_dir(STAFF_TYPE_DIR):
		if res is StaffTypeDef:
			staff_types[res.id] = res
	print("RestaurantManager: %d dishes, %d staff types" % [dishes.size(), staff_types.size()])


func _load_dir(dir_path: String) -> Array[Resource]:
	var result: Array[Resource] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_warning("RestaurantManager: missing catalog dir %s" % dir_path)
		return result
	for file: String in dir.get_files():
		if file.ends_with(".tres") or file.ends_with(".res"):
			var res: Resource = load(dir_path.path_join(file))
			if res != null:
				result.append(res)
	return result


func _restore_from_save(save: SaveGame) -> void:
	GameClock.day = save.day
	GameClock.game_hours = save.game_hours
	EconomyManager.cash = save.cash
	EconomyManager.loan = save.loan
	EconomyManager.reputation = save.reputation
	EconomyManager.history = save.history.duplicate()
	EconomyManager.cash_changed.emit(EconomyManager.cash)
	for rest: RestaurantState in save.restaurants:
		var info: Dictionary = CityData.get_building(rest.building_id)
		if info.is_empty():
			push_warning("Save references missing building %d; skipping" % rest.building_id)
			continue
		rest.door_pos = info.get("door_pos", Vector3.ZERO)
		rest.curb_pos = info.get("position", Vector3.ZERO)
		rest.reset_today()
		owned.append(rest)
		by_building[rest.building_id] = rest
		_spawn_marker(rest)
		for member: StaffMember in rest.staff:
			_next_staff_uid = maxi(_next_staff_uid, member.uid + 1)
			var def: StaffTypeDef = staff_types.get(member.type_id)
			if def != null and def.is_driver:
				DeliveryManager.on_driver_hired(rest, member)
		restaurant_purchased.emit(rest)
	DemandManager.pending_wealth = save.citizen_wealth.duplicate()
	EconomyManager.post_message("good", "Save loaded — welcome back, boss!")


func _found_starting_restaurant() -> void:
	var best_id: int = -1
	var best_score: float = INF
	var center: Vector3 = _city_center()
	for id: int in CityData.buildings:
		var info: Dictionary = CityData.get_building(id)
		if String(info.get("type", "")) != "shop":
			continue
		if String(info.get("district", "")) not in ["N", "C"]:
			continue
		var dist: float = Vector3(info.get("position", Vector3.ZERO)).distance_to(center)
		if dist < best_score:
			best_score = dist
			best_id = id
	if best_id < 0:
		push_warning("RestaurantManager: no shop building found for the starting restaurant")
		return
	var rest: RestaurantState = _add_restaurant(best_id, "%s — Home Base" % EconomyManager.company_name, 0.0)
	# The first location opens staffed for lunch AND the dinner rush
	# (evening leisure is when most citizens dine out).
	hire(rest.building_id, &"cook", 10.0)
	hire(rest.building_id, &"waiter", 10.0)
	hire(rest.building_id, &"cook", 14.0)
	hire(rest.building_id, &"waiter", 14.0)
	EconomyManager.post_message("good", "Welcome! %s opened its first restaurant." % EconomyManager.company_name)


func _add_restaurant(building_id: int, restaurant_name: String, price: float) -> RestaurantState:
	var info: Dictionary = CityData.get_building(building_id)
	var rest: RestaurantState = RestaurantState.new()
	rest.building_id = building_id
	rest.district = String(info.get("district", "N"))
	rest.restaurant_name = restaurant_name if restaurant_name != "" else "Restaurant %d" % building_id
	rest.purchase_price = price
	rest.door_pos = info.get("door_pos", Vector3.ZERO)
	rest.curb_pos = info.get("position", Vector3.ZERO)
	rest.table_count = _table_count_for(info)
	rest.star_rating = EconomyManager.reputation
	rest.reset_today()
	for dish_id: StringName in dishes:
		var def: DishDef = dishes[dish_id]
		var entry: MenuEntry = MenuEntry.new()
		entry.dish_id = dish_id
		entry.tier = &"med"
		entry.price = def.suggested_price
		entry.enabled = def.category == &"pizza"
		rest.menu.append(entry)
	owned.append(rest)
	by_building[building_id] = rest
	_spawn_marker(rest)
	restaurant_purchased.emit(rest)
	return rest


func _spawn_marker(rest: RestaurantState) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var marker: RestaurantMarker = RestaurantMarker.new()
	marker.name = "RestaurantMarker_%d" % rest.building_id
	scene_root.add_child(marker)
	marker.setup(rest)


func _table_count_for(info: Dictionary) -> int:
	var body: Node3D = get_node_or_null(info.get("node_path", NodePath()))
	var area: float = 120.0
	if body != null and body.has_meta("size"):
		var size: Vector3 = body.get_meta("size")
		area = size.x * size.z
	var per_table: float = float(EconomyManager.tuning_value("purchase.table_area_per_table", 14.0))
	var lo: int = int(EconomyManager.tuning_value("purchase.min_tables", 4))
	var hi: int = int(EconomyManager.tuning_value("purchase.max_tables", 24))
	return clampi(int(area / per_table), lo, hi)


func _city_center() -> Vector3:
	var total: Vector3 = Vector3.ZERO
	var count: int = 0
	for id: int in CityData.buildings:
		total += Vector3(CityData.get_building(id).get("position", Vector3.ZERO))
		count += 1
	return total / float(maxi(count, 1))


func _random_person_name() -> String:
	var first: Array = PopulationManager.FIRST_NAMES
	var last: Array = PopulationManager.LAST_NAMES
	return "%s %s" % [first.pick_random(), last.pick_random()]


func _notify_citizen(citizen: Node, method: String) -> void:
	if is_instance_valid(citizen) and citizen.has_method(method):
		citizen.call(method)
