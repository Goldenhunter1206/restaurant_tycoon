class_name RestaurantInteriorView
extends Node3D
## Live interior view of one restaurant: a read-only projection of the sim.
## Reconciles RestaurantState raw queues (dine_queue / cooking / dining) and
## DeliveryManager ready orders into visual actor slots on every
## restaurant_updated tick; order/delivery state signals drive the
## between-tick choreography (waiter carries, driver pickups).
## Never writes sim state; nothing here is persisted.

signal view_invalidated

const ACTOR_SCRIPT: String = "res://scripts/world/interior_actor.gd"
const FOOD_DIR: String = "res://RestaurantAssets/gLTF/Food/"

const STATION_SLOTS: int = 4
const TABLE_SLOTS: int = 8
const QUEUE_SLOTS: int = 6
const PICKUP_SLOTS: int = 4
const ORDER_TICKETS: int = 6
const WAITER_SLOTS: int = 3
const DRIVER_ACTOR_CAP: int = 3

const DISH_MODELS: Dictionary = {
	&"margherita": {
		"stages": ["Pizza_LV_1.glb", "Pizza_LV_2.glb", "Pizza_LV_3.glb", "Pizza_LV_4.glb"],
		"ready": "Pizza_Ready.glb",
	},
	&"pepperoni": {
		"stages": ["Pizza_LV_1.glb", "Pizza_LV_2.glb", "Pizza_LV_3.glb", "Pizza_LV_4.glb"],
		"ready": "Pizza_Ready.glb",
	},
	&"classic_burger": {
		"stages": ["ChessBurger_LV1.glb", "ChessBurger_LV2.glb", "ChessBurger_LV5.glb"],
		"ready": "ChessBurger_Ready.glb",
	},
	&"cheeseburger": {
		"stages": ["ChessBurger_LV1.glb", "ChessBurger_LV2.glb", "ChessBurger_LV5.glb"],
		"ready": "ChessBurger_Ready.glb",
	},
	&"hotdog": {
		"stages": ["HotDog_Bread.glb", "HotDog_LV1.glb", "HotDog_LV2.glb"],
		"ready": "HotDog_Full.glb",
	},
	&"caesar_salad": {
		"stages": ["Dish_1_PlateLV1.glb", "Dish_1_PlateLV2.glb", "Dish_1_PlateLV3.glb", "Dish_1_PlateLV4.glb"],
		"ready": "Dish_1_PlateReady.glb",
	},
	&"chocolate_cake": {
		"stages": ["Cake_3_LV0.glb", "Cake_3_LV1.glb", "Cake_3_LV2.glb", "Cake_3_LV3.glb", "Cake_3_LV4.glb", "Cake_3_LV5.glb", "Cake_3_LV6.glb"],
		"ready": "Cake_3_Ready.glb",
	},
}
## Future dishes resolve by DishDef.category to one of the entries above.
const CATEGORY_FALLBACK: Dictionary = {
	&"pizza": &"margherita",
	&"burger": &"classic_burger",
	&"hotdog": &"hotdog",
	&"salad": &"caesar_salad",
	&"dessert": &"chocolate_cake",
}
const DEFAULT_DISH_MODEL: Dictionary = {
	"stages": ["Dish_2_LV_0.glb", "Dish_2_LV_1.glb", "Dish_2_LV_2.glb", "Dish_2_LV_3.glb", "Dish_2_LV_4.glb"],
	"ready": "Dish_2_Ready.glb",
}
const BAG_MODELS: Array[String] = [
	"BagFood_1_A.glb", "BagFood_1_B.glb", "BagFood_1_C.glb",
	"BagFood_2_A.glb", "BagFood_2_B.glb", "BagFood_2_C.glb",
]

## Hand-made lane graph between Waypoints/* markers; every walk target
## declares its nearest lane node so actors keep to clear corridors.
const LANE_GRAPH: Dictionary = {
	&"DoorOutside": [&"DoorInside"],
	&"DoorInside": [&"DoorOutside", &"AisleFront", &"PickupFront"],
	&"AisleFront": [&"DoorInside", &"AisleMid", &"PickupFront"],
	&"AisleMid": [&"AisleFront", &"KitchenPass"],
	&"KitchenPass": [&"AisleMid"],
	&"PickupFront": [&"DoorInside", &"AisleFront"],
}

const CAM_PIVOT: Vector3 = Vector3(0.0, 0.5, -0.5)
const CAM_YAW_LIMIT: float = 0.9
const CAM_PITCH_MIN: float = 0.44
const CAM_PITCH_MAX: float = 1.05
const CAM_DIST_MIN: float = 10.0
const CAM_DIST_MAX: float = 28.0

var building_id: int = -1

var _rest: RestaurantState = null
var _guests: Dictionary = {}
var _table_by_order: Dictionary = {}
var _cook_actors: Dictionary = {}
var _station_food: Dictionary = {}
var _table_meals: Dictionary = {}
var _pickup_bags: Dictionary = {}
var _waiters: Array[Dictionary] = []
var _drivers: Dictionary = {}
var _scene_cache: Dictionary = {}
var _lane_pos: Dictionary = {}
var _visible_tables: int = TABLE_SLOTS

var _cam: Camera3D = null
var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.62
var _cam_dist: float = 25.0
var _orbiting: bool = false


func setup(id: int) -> void:
	building_id = id
	_rest = RestaurantManager.by_building.get(id)
	if _rest == null:
		view_invalidated.emit()
		return
	_cache_scene_points()
	_visible_tables = clampi(_rest.table_count, 0, TABLE_SLOTS)
	for i: int in range(TABLE_SLOTS):
		var table: Node3D = get_node_or_null("Dining/Table_%d" % i)
		if table != null:
			table.visible = i < _visible_tables
	var name_label: Label3D = get_node_or_null("Labels/RestaurantName")
	if name_label != null:
		name_label.text = _rest.restaurant_name.to_upper()
	RestaurantManager.restaurant_updated.connect(_on_restaurant_updated)
	RestaurantManager.order_state_changed.connect(_on_order_state_changed)
	DeliveryManager.delivery_state_changed.connect(_on_delivery_state_changed)
	_reconcile(true)


func _exit_tree() -> void:
	if RestaurantManager.restaurant_updated.is_connected(_on_restaurant_updated):
		RestaurantManager.restaurant_updated.disconnect(_on_restaurant_updated)
	if RestaurantManager.order_state_changed.is_connected(_on_order_state_changed):
		RestaurantManager.order_state_changed.disconnect(_on_order_state_changed)
	if DeliveryManager.delivery_state_changed.is_connected(_on_delivery_state_changed):
		DeliveryManager.delivery_state_changed.disconnect(_on_delivery_state_changed)


func _ready() -> void:
	_cam = get_node_or_null("Camera3D")
	_apply_camera()


# --- Signal entry points -------------------------------------------------------


func _on_restaurant_updated(id: int) -> void:
	if id != building_id:
		return
	if not RestaurantManager.by_building.has(building_id):
		view_invalidated.emit()
		return
	_reconcile(false)


func _on_order_state_changed(order: FoodOrder) -> void:
	if order == null or order.restaurant_id != building_id:
		return
	if order.state == FoodOrder.State.SERVED and not order.is_delivery:
		_dispatch_waiter(order)


func _on_delivery_state_changed(order: FoodOrder) -> void:
	if order == null or order.restaurant_id != building_id:
		return
	match order.state:
		FoodOrder.State.ASSIGNED:
			_driver_walk_in(order)
		FoodOrder.State.PICKED_UP, FoodOrder.State.EN_ROUTE:
			_driver_collect(order)
		FoodOrder.State.CANCELLED, FoodOrder.State.DELIVERED:
			_driver_walk_out(order.order_id, order.state == FoodOrder.State.CANCELLED)


# --- Reconciliation ------------------------------------------------------------


func _reconcile(instant: bool) -> void:
	if _rest == null:
		return
	_reconcile_guests(instant)
	_reconcile_cooks()
	_reconcile_station_food()
	_reconcile_pickup_bags()
	_reconcile_waiters()
	_prune_drivers()
	_refresh_labels()


func _reconcile_guests(instant: bool) -> void:
	var desired_queue: Dictionary = {}
	for i: int in range(_rest.dine_queue.size()):
		var row: Dictionary = _rest.dine_queue[i]
		var citizen: Node = row.get("citizen")
		if not is_instance_valid(citizen):
			continue
		var cid: int = citizen.data.get("id", 0)
		desired_queue[cid] = {"index": i, "name": str(citizen.data.get("name", "Guest"))}
	var desired_dining: Dictionary = {}
	for row: Dictionary in _rest.dining:
		var order: FoodOrder = row.get("order")
		if order == null:
			continue
		var cname: String = "Guest"
		var citizen: Node = row.get("citizen")
		if is_instance_valid(citizen):
			cname = str(citizen.data.get("name", "Guest"))
		desired_dining[order.citizen_id] = {"order": order, "name": cname}
	# Departures first: anyone we track who is in neither set walks out.
	for cid: int in _guests.keys():
		if desired_queue.has(cid) or desired_dining.has(cid):
			continue
		_guest_leave(cid, instant)
	# Queue placement / shuffling.
	for cid: int in desired_queue.keys():
		var info: Dictionary = desired_queue[cid]
		if int(info["index"]) >= QUEUE_SLOTS:
			# Overflow: no puppet, the "+N waiting" label counts them; the
			# actor appears once the queue shuffles them into a visible slot.
			if _guests.has(cid) and _guests[cid]["state"] == "queue":
				_despawn_guest(cid)
			continue
		var idx: int = int(info["index"])
		var spot: Vector3 = _queue_spot(idx)
		if not _guests.has(cid):
			var actor: Node3D = _spawn_actor("Guest_%d" % cid, cid, info["name"])
			_guests[cid] = {"actor": actor, "state": "queue", "queue_idx": idx, "table": -1}
			if instant:
				actor.snap_to(spot, PI * 0.5)
			else:
				actor.snap_to(_lane_pos[&"DoorOutside"], 0.0)
				actor.walk_along(_route_points(actor.global_position, spot, &"DoorInside"))
		else:
			var guest: Dictionary = _guests[cid]
			if guest["state"] == "queue" and guest["queue_idx"] != idx:
				guest["queue_idx"] = idx
				var actor: Node3D = guest["actor"]
				if instant:
					actor.snap_to(spot, PI * 0.5)
				else:
					if actor.is_walking():
						actor.finish_walk_now()
					actor.walk_along([spot] as Array[Vector3])
	# Seating.
	for cid: int in desired_dining.keys():
		var order: FoodOrder = desired_dining[cid]["order"]
		if not _guests.has(cid):
			var actor: Node3D = _spawn_actor("Guest_%d" % cid, cid, desired_dining[cid]["name"])
			_guests[cid] = {"actor": actor, "state": "arriving", "queue_idx": -1, "table": -1}
			actor.snap_to(_lane_pos[&"DoorOutside"], 0.0)
		var guest: Dictionary = _guests[cid]
		if guest["state"] in ["seated", "to_seat"]:
			continue
		var table_idx: int = _claim_table(order.order_id)
		if table_idx < 0:
			# More seated guests than visible tables: drop the puppet, the
			# status board still counts them.
			_despawn_guest(cid)
			continue
		guest["table"] = table_idx
		guest["order_id"] = order.order_id
		var actor: Node3D = guest["actor"]
		var seat: Transform3D = _seat_xform(table_idx)
		if instant:
			guest["state"] = "seated"
			actor.sit(seat)
		else:
			guest["state"] = "to_seat"
			if actor.is_walking():
				actor.finish_walk_now()
			var lane: StringName = _table_lane(table_idx)
			var points: Array[Vector3] = _route_points(actor.global_position, seat.origin, lane)
			points.insert(points.size() - 1, Vector3(seat.origin.x, seat.origin.y, _lane_pos[lane].z))
			actor.walk_along(points, func() -> void:
				if _guests.has(cid):
					_guests[cid]["state"] = "seated"
					actor.sit(seat))
	# Meal-on-table fallback: SERVED orders whose meal never got carried.
	for row: Dictionary in _rest.dining:
		var order: FoodOrder = row.get("order")
		if order == null or order.state != FoodOrder.State.SERVED:
			continue
		if _table_meals.has(order.order_id) or _waiter_carrying(order.order_id):
			continue
		var table_idx: int = int(_table_by_order.get(order.order_id, -1))
		if table_idx >= 0:
			_place_meal(order, table_idx)


func _guest_leave(cid: int, instant: bool) -> void:
	var guest: Dictionary = _guests.get(cid, {})
	if guest.is_empty() or guest["state"] == "leaving":
		return
	var table_idx: int = guest.get("table", -1)
	if table_idx >= 0:
		_release_table(table_idx)
	if instant:
		_despawn_guest(cid)
		return
	guest["state"] = "leaving"
	var actor: Node3D = guest["actor"]
	if actor.is_walking():
		actor.finish_walk_now()
	var out: Vector3 = _lane_pos[&"DoorOutside"]
	actor.walk_along(_route_points(actor.global_position, out, &"DoorInside"), func() -> void:
		_despawn_guest(cid))


func _despawn_guest(cid: int) -> void:
	var guest: Dictionary = _guests.get(cid, {})
	if guest.is_empty():
		return
	var table_idx: int = guest.get("table", -1)
	if table_idx >= 0:
		_release_table(table_idx)
	var actor: Node3D = guest["actor"]
	if is_instance_valid(actor):
		actor.queue_free()
	_guests.erase(cid)


func _claim_table(order_id: int) -> int:
	if _table_by_order.has(order_id):
		return _table_by_order[order_id]
	var used: Array = _table_by_order.values()
	for i: int in range(_visible_tables):
		if not used.has(i):
			_table_by_order[order_id] = i
			return i
	return -1


func _release_table(table_idx: int) -> void:
	for order_id: int in _table_by_order.keys():
		if _table_by_order[order_id] == table_idx:
			_table_by_order.erase(order_id)
			break
	var meal_ids: Array = _table_meals.keys()
	for order_id: int in meal_ids:
		if _table_meals[order_id]["table"] == table_idx:
			var node: Node3D = _table_meals[order_id]["node"]
			if is_instance_valid(node):
				node.queue_free()
			_table_meals.erase(order_id)


func _reconcile_cooks() -> void:
	var hour: float = GameClock.game_hours
	var slots: Array[Dictionary] = _station_cooks(hour)
	var keep: Array[int] = []
	for i: int in range(mini(slots.size(), STATION_SLOTS)):
		var uid: int = slots[i]["uid"]
		keep.append(uid)
		var entry: Dictionary = _cook_actors.get(uid, {})
		if entry.is_empty():
			var actor: Node3D = _spawn_actor("Cook_%d" % uid, uid, slots[i]["name"])
			actor.snap_to(_cook_spot(i), PI)
			actor.set_tag("")  # The station's CookLabel already names them.
			_cook_actors[uid] = {"actor": actor, "station": i}
		elif entry["station"] != i:
			entry["station"] = i
			entry["actor"].snap_to(_cook_spot(i), PI)
	for uid: int in _cook_actors.keys():
		if keep.has(uid):
			continue
		var actor: Node3D = _cook_actors[uid]["actor"]
		if is_instance_valid(actor):
			actor.queue_free()
		_cook_actors.erase(uid)


func _station_cooks(hour: float) -> Array[Dictionary]:
	## Mirrors the sim's cook-slot descriptors: one slot per cook on shift
	## times that staff type's cook_slots, in staff order.
	var slots: Array[Dictionary] = []
	for member: StaffMember in _rest.staff:
		var type_def: StaffTypeDef = RestaurantManager.staff_type(member.type_id)
		if type_def == null or type_def.cook_slots <= 0 or not member.on_shift(hour):
			continue
		for _slot: int in range(type_def.cook_slots):
			slots.append({"uid": member.uid, "name": member.staff_name})
	return slots


func _reconcile_station_food() -> void:
	var desired: Dictionary = {}
	# The sim's slot_index is per-cook; the global station is simply the
	# row's position in the cooking array (first N rows are the live slots).
	for station: int in range(mini(_rest.cooking.size(), STATION_SLOTS)):
		var row: Dictionary = _rest.cooking[station]
		var order: FoodOrder = row.get("order")
		if order == null:
			continue
		var progress: float = 1.0
		if order.prep_minutes > 0.0:
			progress = clampf(1.0 - float(row.get("minutes_left", 0)) / order.prep_minutes, 0.0, 1.0)
		desired[station] = {"order": order, "row": row, "progress": progress}
	for station: int in _station_food.keys():
		var current: Dictionary = _station_food[station]
		var want: Dictionary = desired.get(station, {})
		if want.is_empty() or want["order"].order_id != current["order_id"]:
			if is_instance_valid(current["node"]):
				current["node"].queue_free()
			_station_food.erase(station)
	for station: int in desired.keys():
		var order: FoodOrder = desired[station]["order"]
		var stages: Array = _dish_entry(order.dish_id)["stages"]
		var stage: int = clampi(int(desired[station]["progress"] * stages.size()), 0, stages.size() - 1)
		var current: Dictionary = _station_food.get(station, {})
		if not current.is_empty() and current["stage"] == stage:
			continue
		if not current.is_empty() and is_instance_valid(current["node"]):
			current["node"].queue_free()
		var node: Node3D = _spawn_food(String(stages[stage]))
		if node == null:
			continue
		var spot: Node3D = get_node_or_null("Kitchen/Station_%d/FoodSpot" % station)
		(spot if spot != null else get_node("Meals")).add_child(node)
		_station_food[station] = {"order_id": order.order_id, "stage": stage, "node": node}
	# Station labels: cook name + what they're making.
	for i: int in range(STATION_SLOTS):
		var label: Label3D = get_node_or_null("Kitchen/Station_%d/CookLabel" % i)
		if label == null:
			continue
		var text: String = ""
		if i < _rest.cooking.size():
			var row: Dictionary = _rest.cooking[i]
			var order: FoodOrder = row.get("order")
			if order != null:
				text = "%s\n%s · %dm" % [str(row.get("cook_name", "Cook")), _dish_name(order.dish_id), int(row.get("minutes_left", 0))]
		if text.is_empty():
			var slots: Array[Dictionary] = _station_cooks(GameClock.game_hours)
			if i < slots.size():
				text = "%s\nidle" % slots[i]["name"]
		label.text = text


func _reconcile_pickup_bags() -> void:
	var desired: Dictionary = {}
	for order: FoodOrder in DeliveryManager.ready_queue:
		if order.restaurant_id == building_id:
			desired[order.order_id] = order
	for order: FoodOrder in DeliveryManager.active_orders:
		if order.restaurant_id == building_id and order.state == FoodOrder.State.ASSIGNED:
			desired[order.order_id] = order
	for order_id: int in _pickup_bags.keys():
		if desired.has(order_id):
			continue
		var bag: Dictionary = _pickup_bags[order_id]
		if is_instance_valid(bag["node"]):
			bag["node"].queue_free()
		_pickup_bags.erase(order_id)
	for order_id: int in desired.keys():
		if _pickup_bags.has(order_id):
			continue
		var slot: int = _free_pickup_slot()
		if slot < 0:
			continue
		var order: FoodOrder = desired[order_id]
		var node: Node3D = _spawn_food(BAG_MODELS[order_id % BAG_MODELS.size()])
		if node == null:
			continue
		node.scale = Vector3(2.2, 2.2, 2.2)  # Bag models are ~18cm; readable from the room camera.
		var spot: Node3D = get_node_or_null("Counters/PickupCounter/PickupSlot_%d" % slot)
		(spot if spot != null else get_node("Meals")).add_child(node)
		_pickup_bags[order_id] = {"node": node, "slot": slot, "dish_id": order.dish_id}
	for i: int in range(PICKUP_SLOTS):
		var label: Label3D = get_node_or_null("Counters/PickupCounter/PickupLabel_%d" % i)
		if label == null:
			continue
		label.text = ""
		for order_id: int in _pickup_bags.keys():
			if _pickup_bags[order_id]["slot"] == i:
				label.text = "#%d %s" % [order_id, _dish_name(_pickup_bags[order_id]["dish_id"])]
				break


func _free_pickup_slot() -> int:
	var used: Array[int] = []
	for order_id: int in _pickup_bags.keys():
		used.append(int(_pickup_bags[order_id]["slot"]))
	for i: int in range(PICKUP_SLOTS):
		if not used.has(i):
			return i
	return -1


func _reconcile_waiters() -> void:
	var hour: float = GameClock.game_hours
	var want: int = mini(_rest.staff_on_shift(&"waiter", hour), WAITER_SLOTS)
	var names: Array[String] = []
	for member: StaffMember in _rest.staff:
		if member.type_id == &"waiter" and member.on_shift(hour):
			names.append(member.staff_name)
	while _waiters.size() > want:
		var entry: Dictionary = _waiters.pop_back()
		if is_instance_valid(entry["actor"]):
			entry["actor"].queue_free()
	while _waiters.size() < want:
		var i: int = _waiters.size()
		var display: String = names[i] if i < names.size() else "Waiter"
		var actor: Node3D = _spawn_actor("Waiter_%d" % i, i + 7000, display)
		actor.snap_to(_waiter_idle_spot(i), 0.0)
		_waiters.append({"actor": actor, "busy": false, "order_id": -1, "idle": i})


func _waiter_carrying(order_id: int) -> bool:
	for entry: Dictionary in _waiters:
		if entry["busy"] and entry["order_id"] == order_id:
			return true
	return false


func _dispatch_waiter(order: FoodOrder) -> void:
	var table_idx: int = int(_table_by_order.get(order.order_id, -1))
	if table_idx < 0 or _table_meals.has(order.order_id):
		return
	var free: Dictionary = {}
	for entry: Dictionary in _waiters:
		if not entry["busy"] and is_instance_valid(entry["actor"]):
			free = entry
			break
	if free.is_empty():
		return
	free["busy"] = true
	free["order_id"] = order.order_id
	var actor: Node3D = free["actor"]
	if actor.is_walking():
		actor.finish_walk_now()
	var serve: Vector3 = _lane_pos.get(&"ServeSpot", _lane_pos[&"KitchenPass"])
	actor.walk_along(_route_points(actor.global_position, serve, &"KitchenPass"), func() -> void:
		var meal: Node3D = _spawn_food(String(_dish_entry(order.dish_id)["ready"]))
		if meal != null:
			actor.set_carried(meal)
		var drop: Vector3 = _meal_drop_point(table_idx)
		var lane: StringName = _table_lane(table_idx)
		var points: Array[Vector3] = _route_points(actor.global_position, drop, lane)
		points.insert(points.size() - 1, Vector3(drop.x, drop.y, _lane_pos[lane].z))
		actor.walk_along(points, func() -> void:
			var prop: Node3D = actor.take_carried()
			if prop != null:
				prop.queue_free()
			if not _table_meals.has(order.order_id) and _table_by_order.get(order.order_id, -1) == table_idx:
				_place_meal(order, table_idx)
			free["busy"] = false
			free["order_id"] = -1
			actor.walk_along(_route_points(actor.global_position, _waiter_idle_spot(free["idle"]), &"KitchenPass"))))


func _place_meal(order: FoodOrder, table_idx: int) -> void:
	var node: Node3D = _spawn_food(String(_dish_entry(order.dish_id)["ready"]))
	if node == null:
		return
	var spot: Node3D = get_node_or_null("Dining/Table_%d/MealSpot" % table_idx)
	(spot if spot != null else get_node("Meals")).add_child(node)
	_table_meals[order.order_id] = {"node": node, "table": table_idx}


# --- Drivers ---------------------------------------------------------------------


func _driver_uid(order: FoodOrder) -> int:
	if is_instance_valid(order.driver) and order.driver.get("staff_member") != null:
		return order.driver.staff_member.uid
	return 90000 + order.order_id


func _driver_name(order: FoodOrder) -> String:
	if is_instance_valid(order.driver) and order.driver.get("staff_member") != null:
		return order.driver.staff_member.staff_name
	return "Driver"


func _driver_walk_in(order: FoodOrder) -> void:
	if _drivers.size() >= DRIVER_ACTOR_CAP:
		return
	var uid: int = _driver_uid(order)
	if _drivers.has(uid):
		return
	var actor: Node3D = _spawn_actor("Driver_%d" % uid, uid, _driver_name(order))
	actor.snap_to(_lane_pos[&"DoorOutside"], 0.0)
	var target: Vector3 = _pickup_stand_point(order.order_id)
	actor.walk_along(_route_points(actor.global_position, target, &"PickupFront"))
	_drivers[uid] = {"actor": actor, "order_id": order.order_id}


func _driver_collect(order: FoodOrder) -> void:
	var uid: int = _driver_uid(order)
	var entry: Dictionary = _drivers.get(uid, {})
	# The bag leaves the counter the moment the sim marks it picked up.
	var bag: Dictionary = _pickup_bags.get(order.order_id, {})
	if not bag.is_empty():
		if is_instance_valid(bag["node"]):
			bag["node"].queue_free()
		_pickup_bags.erase(order.order_id)
	if entry.is_empty():
		return
	var actor: Node3D = entry["actor"]
	if not is_instance_valid(actor):
		_drivers.erase(uid)
		return
	var carry: Node3D = _spawn_food(BAG_MODELS[order.order_id % BAG_MODELS.size()])
	if carry != null:
		actor.set_carried(carry)
	if actor.is_walking():
		actor.finish_walk_now()
	actor.walk_along(_route_points(actor.global_position, _lane_pos[&"DoorOutside"], &"PickupFront"), func() -> void:
		if is_instance_valid(actor):
			actor.queue_free()
		_drivers.erase(uid))


func _driver_walk_out(order_id: int, hurried: bool) -> void:
	for uid: int in _drivers.keys():
		if _drivers[uid]["order_id"] != order_id:
			continue
		var actor: Node3D = _drivers[uid]["actor"]
		if is_instance_valid(actor):
			if actor.is_walking():
				actor.finish_walk_now()
			actor.walk_along(
				_route_points(actor.global_position, _lane_pos[&"DoorOutside"], &"PickupFront"),
				func() -> void:
					if is_instance_valid(actor):
						actor.queue_free()
					_drivers.erase(uid),
				1.5 if hurried else 1.0)
		else:
			_drivers.erase(uid)
		return


func _prune_drivers() -> void:
	## Reconcile safety net: drop driver puppets whose orders are gone.
	var live: Array[int] = []
	for order: FoodOrder in DeliveryManager.active_orders:
		if order.restaurant_id == building_id:
			live.append(order.order_id)
	for uid: int in _drivers.keys():
		if live.has(int(_drivers[uid]["order_id"])):
			continue
		var actor: Node3D = _drivers[uid]["actor"]
		if is_instance_valid(actor):
			actor.queue_free()
		_drivers.erase(uid)


# --- Labels ----------------------------------------------------------------------


func _refresh_labels() -> void:
	var snapshot: Dictionary = RestaurantManager.operations_snapshot(building_id)
	var board: Label3D = get_node_or_null("Labels/StatusBoard")
	if board != null:
		var status: String = "OPEN" if _rest.is_open(GameClock.game_hours) else "CLOSED"
		var lines: Array[String] = [
			"%s · %s" % [GameClock.time_string_ampm(), status],
			"Tables %d/%d · Waiting %d" % [int(snapshot.get("tables_occupied", 0)), _rest.table_count, _rest.dine_queue.size()],
			"Kitchen %d cooking · %d queued" % [_rest.cooking.size(), _rest.cook_backlog.size()],
			"Deliveries %d/%d out" % [int(snapshot.get("active_deliveries", 0)), _rest.delivery_cap],
		]
		var bottleneck: Dictionary = snapshot.get("bottleneck", {})
		if not bottleneck.is_empty() and str(bottleneck.get("title", "")) != "":
			lines.append("! " + str(bottleneck["title"]))
		if _rest.table_count > TABLE_SLOTS:
			lines.append("(+%d tables not shown)" % (_rest.table_count - TABLE_SLOTS))
		board.text = "\n".join(lines)
	var tickets: Array[Dictionary] = []
	for row: Dictionary in _rest.cooking:
		var order: FoodOrder = row.get("order")
		if order != null:
			tickets.append({"text": "#%d %s · %dm" % [order.order_id, _dish_name(order.dish_id), int(row.get("minutes_left", 0))]})
	for order: FoodOrder in _rest.cook_backlog:
		tickets.append({"text": "#%d %s · queued" % [order.order_id, _dish_name(order.dish_id)]})
	for i: int in range(ORDER_TICKETS):
		var label: Label3D = get_node_or_null("Labels/OrderRail/Order_%d" % i)
		if label != null:
			label.text = str(tickets[i]["text"]) if i < tickets.size() else ""
	var overflow: Label3D = get_node_or_null("QueueSpots/OverflowLabel")
	if overflow != null:
		var extra: int = _rest.dine_queue.size() - QUEUE_SLOTS
		overflow.text = "+%d waiting" % extra if extra > 0 else ""
	for cid: int in _guests.keys():
		var guest: Dictionary = _guests[cid]
		if guest["state"] != "queue":
			continue
		var idx: int = guest["queue_idx"]
		if idx < _rest.dine_queue.size():
			var row: Dictionary = _rest.dine_queue[idx]
			var wait: int = GameClock.total_minutes() - int(row.get("arrived_minute", GameClock.total_minutes()))
			guest["actor"].set_tag("%s · %dm" % [guest["actor"].display_name, wait])


# --- Spawning helpers --------------------------------------------------------


func _spawn_actor(node_name: String, variant_seed: int, display: String) -> Node3D:
	var actor: Node3D = Node3D.new()
	actor.set_script(load(ACTOR_SCRIPT))
	actor.name = node_name
	get_node("Actors").add_child(actor)
	PopulationManager.ensure_assets_loaded()
	var models: Array[String] = PopulationManager.character_model_paths()
	var path: String = models[absi(variant_seed) % models.size()] if not models.is_empty() else ""
	actor.setup(path, display, variant_seed)
	return actor


func _spawn_food(file_name: String) -> Node3D:
	var path: String = FOOD_DIR + file_name
	var packed: PackedScene = _scene_cache.get(path)
	if packed == null:
		packed = load(path)
		if packed == null:
			return null
		_scene_cache[path] = packed
	return packed.instantiate()


func _dish_entry(dish_id: StringName) -> Dictionary:
	if DISH_MODELS.has(dish_id):
		return DISH_MODELS[dish_id]
	var def: DishDef = RestaurantManager.dish(dish_id)
	if def != null and CATEGORY_FALLBACK.has(def.category):
		return DISH_MODELS[CATEGORY_FALLBACK[def.category]]
	return DEFAULT_DISH_MODEL


func _dish_name(dish_id: StringName) -> String:
	var def: DishDef = RestaurantManager.dish(dish_id)
	if def != null:
		return def.display_name
	return String(dish_id).replace("_", " ").capitalize()


# --- Scene geometry lookup -----------------------------------------------------


func _cache_scene_points() -> void:
	var waypoints: Node3D = get_node_or_null("Waypoints")
	if waypoints != null:
		for child: Node in waypoints.get_children():
			if child is Node3D:
				_lane_pos[StringName(child.name)] = (child as Node3D).global_position


func _queue_spot(idx: int) -> Vector3:
	var marker: Node3D = get_node_or_null("QueueSpots/QueueSpot_%d" % idx)
	return marker.global_position if marker != null else _lane_pos[&"DoorInside"]


func _seat_xform(table_idx: int) -> Transform3D:
	var marker: Node3D = get_node_or_null("Dining/Table_%d/SeatA" % table_idx)
	return marker.global_transform if marker != null else Transform3D.IDENTITY


func _meal_drop_point(table_idx: int) -> Vector3:
	var seat: Vector3 = _seat_xform(table_idx).origin
	return seat + Vector3(-1.1 if seat.x > 0 else 1.1, 0.0, 0.0)


func _table_lane(table_idx: int) -> StringName:
	return &"AisleMid" if table_idx < 4 else &"AisleFront"


func _cook_spot(station: int) -> Vector3:
	var marker: Node3D = get_node_or_null("Kitchen/Station_%d/CookSpot" % station)
	return marker.global_position if marker != null else Vector3.ZERO


func _waiter_idle_spot(idx: int) -> Vector3:
	var marker: Node3D = get_node_or_null("Waypoints/WaiterIdle_%d" % idx)
	return marker.global_position if marker != null else _lane_pos[&"KitchenPass"]


func _pickup_stand_point(order_id: int) -> Vector3:
	var bag: Dictionary = _pickup_bags.get(order_id, {})
	if not bag.is_empty():
		var spot: Node3D = get_node_or_null("Counters/PickupCounter/PickupSlot_%d" % int(bag["slot"]))
		if spot != null:
			return Vector3(spot.global_position.x, 0.0, spot.global_position.z - 1.1)
	return _lane_pos[&"PickupFront"]


# --- Lane routing ---------------------------------------------------------------


func _route_points(from_pos: Vector3, target: Vector3, target_lane: StringName) -> Array[Vector3]:
	var start: StringName = _nearest_lane(from_pos)
	var chain: Array[StringName] = _lane_path(start, target_lane)
	var points: Array[Vector3] = []
	for lane_name: StringName in chain:
		points.append(_lane_pos[lane_name])
	# Drop leading lane points that are behind us already.
	while points.size() > 1 and from_pos.distance_to(points[1]) < from_pos.distance_to(points[0]):
		points.remove_at(0)
	points.append(target)
	return points


func _nearest_lane(pos: Vector3) -> StringName:
	var best: StringName = &"DoorInside"
	var best_dist: float = INF
	for lane_name: StringName in LANE_GRAPH.keys():
		var d: float = pos.distance_to(_lane_pos.get(lane_name, Vector3.ZERO))
		if d < best_dist:
			best_dist = d
			best = lane_name
	return best


func _lane_path(from_lane: StringName, to_lane: StringName) -> Array[StringName]:
	if from_lane == to_lane:
		return [from_lane]
	var prev: Dictionary = {from_lane: StringName()}
	var frontier: Array[StringName] = [from_lane]
	while not frontier.is_empty():
		var current: StringName = frontier.pop_front()
		if current == to_lane:
			break
		for neighbor: StringName in LANE_GRAPH.get(current, []):
			if prev.has(neighbor):
				continue
			prev[neighbor] = current
			frontier.append(neighbor)
	if not prev.has(to_lane):
		return [from_lane, to_lane]
	var chain: Array[StringName] = []
	var walk: StringName = to_lane
	while walk != StringName():
		chain.push_front(walk)
		walk = prev[walk]
	return chain


# --- Camera ---------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = clampf(_cam_dist - 1.5, CAM_DIST_MIN, CAM_DIST_MAX)
			_apply_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = clampf(_cam_dist + 1.5, CAM_DIST_MIN, CAM_DIST_MAX)
			_apply_camera()
	elif event is InputEventMouseMotion and _orbiting:
		var mm: InputEventMouseMotion = event
		_cam_yaw = clampf(_cam_yaw - mm.relative.x * 0.005, -CAM_YAW_LIMIT, CAM_YAW_LIMIT)
		_cam_pitch = clampf(_cam_pitch + mm.relative.y * 0.005, CAM_PITCH_MIN, CAM_PITCH_MAX)
		_apply_camera()


func _apply_camera() -> void:
	if _cam == null:
		return
	var offset: Vector3 = Vector3(
		_cam_dist * sin(_cam_yaw) * cos(_cam_pitch),
		_cam_dist * sin(_cam_pitch),
		_cam_dist * cos(_cam_yaw) * cos(_cam_pitch))
	_cam.global_position = CAM_PIVOT + offset
	_cam.look_at(CAM_PIVOT, Vector3.UP)
