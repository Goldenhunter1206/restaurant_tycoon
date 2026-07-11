extends Node
## Delivery-order lifecycle and the simulated driver agents. Orders arrive
## cooked (READY) from RestaurantManager; this manager assigns them to idle
## on-shift drivers and cancels anything that exceeds the customer's patience.
## All timing uses absolute game minutes — pause/16x safe.

signal delivery_state_changed(order: FoodOrder)
signal delivery_completed(order: FoodOrder, success: bool)
signal active_count_changed(count: int)

const DRIVER_SCENE_PATH: String = "res://scenes/agents/Driver.tscn"

## Every delivery order not yet delivered/cancelled.
var active_orders: Array[FoodOrder] = []
## Cooked orders waiting for a free driver.
var ready_queue: Array[FoodOrder] = []
## building_id -> Array[{member: StaffMember, node: Node}] — hired drivers.
var rosters: Dictionary = {}
## Lifetime counters (objectives / reports).
var total_delivered: int = 0
var total_cancelled: int = 0

var _initialized: bool = false


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	GameClock.minute_ticked.connect(_on_minute)
	RestaurantManager.order_ready_for_delivery.connect(_on_order_ready)


func active_count() -> int:
	return active_orders.size()


## Called by RestaurantManager when a delivery order is accepted.
func register_order(order: FoodOrder) -> void:
	active_orders.append(order)
	active_count_changed.emit(active_orders.size())


## Called by a Driver agent when the food reaches the customer's door.
func complete_delivery(order: FoodOrder) -> void:
	if order.state == FoodOrder.State.CANCELLED:
		return
	order.state = FoodOrder.State.DELIVERED
	_release_order(order)
	var rest: RestaurantState = RestaurantManager.by_building.get(order.restaurant_id)
	if rest != null:
		rest.record_sale(order.price)
		RestaurantManager.record_category_sale(rest, order.dish_id)
		rest.active_deliveries = maxi(0, rest.active_deliveries - 1)
	EconomyManager.transact(&"delivery_sales", order.price)
	DemandManager.charge_citizen(order.citizen_id, order.price)
	RestaurantManager.award_service_reputation(order)
	total_delivered += 1
	delivery_state_changed.emit(order)
	delivery_completed.emit(order, true)
	_try_assign()


## Called by a Driver agent when it becomes idle again.
func driver_became_idle(_driver: Node) -> void:
	_try_assign()


# --- Hiring hooks (invoked by RestaurantManager) ------------------------------


func on_driver_hired(rest: RestaurantState, member: StaffMember) -> void:
	var roster: Array = rosters.get(rest.building_id, [])
	roster.append({"member": member, "node": _spawn_driver_agent(rest, member)})
	rosters[rest.building_id] = roster


func on_driver_fired(rest: RestaurantState, member: StaffMember) -> void:
	var roster: Array = rosters.get(rest.building_id, [])
	for i: int in range(roster.size() - 1, -1, -1):
		var slot: Dictionary = roster[i]
		if slot["member"] != member:
			continue
		var node: Node = slot["node"]
		if is_instance_valid(node):
			if node.has_method("abort_delivery"):
				node.abort_delivery()
			if node.has_method("cleanup"):
				node.cleanup()
			node.queue_free()
		roster.remove_at(i)
	rosters[rest.building_id] = roster


# --- Internals -----------------------------------------------------------------


func _on_order_ready(order: FoodOrder) -> void:
	if order.state == FoodOrder.State.CANCELLED:
		return
	ready_queue.append(order)
	_try_assign()


func _try_assign() -> void:
	for i: int in range(ready_queue.size() - 1, -1, -1):
		var order: FoodOrder = ready_queue[i]
		if order.state == FoodOrder.State.CANCELLED:
			ready_queue.remove_at(i)
			continue
		var driver: Node = _idle_driver_for(order.restaurant_id)
		if driver == null:
			continue
		ready_queue.remove_at(i)
		order.state = FoodOrder.State.ASSIGNED
		order.driver = driver
		driver.assign_order(order)
		delivery_state_changed.emit(order)


func _idle_driver_for(building_id: int) -> Node:
	var roster: Array = rosters.get(building_id, [])
	var hourf: float = GameClock.game_hours
	for slot: Dictionary in roster:
		var member: StaffMember = slot["member"]
		var node: Node = slot["node"]
		if not member.on_shift(hourf):
			continue
		if is_instance_valid(node) and node.has_method("is_idle") and node.is_idle():
			return node
	return null


func _on_minute(_day: int, _hour: int, _minute: int) -> void:
	if active_orders.is_empty():
		return
	var now: int = GameClock.total_minutes()
	var cancel_after: int = int(EconomyManager.tuning_value("delivery.cancel_minutes", 75))
	for i: int in range(active_orders.size() - 1, -1, -1):
		var order: FoodOrder = active_orders[i]
		if order.state == FoodOrder.State.DELIVERED or order.state == FoodOrder.State.CANCELLED:
			active_orders.remove_at(i)
			continue
		if now - order.placed_minute > cancel_after:
			_cancel(order)
	active_count_changed.emit(active_orders.size())


func _cancel(order: FoodOrder) -> void:
	order.state = FoodOrder.State.CANCELLED
	_release_order(order)
	ready_queue.erase(order)
	var rest: RestaurantState = RestaurantManager.by_building.get(order.restaurant_id)
	if rest != null:
		rest.active_deliveries = maxi(0, rest.active_deliveries - 1)
		rest.today["cancelled"] = int(rest.today.get("cancelled", 0)) + 1
	if is_instance_valid(order.driver) and order.driver.has_method("abort_delivery"):
		order.driver.abort_delivery()
	EconomyManager.add_reputation(
		float(EconomyManager.tuning_value("reputation.per_cancelled", -0.06)))
	total_cancelled += 1
	EconomyManager.post_message("alert", "A delivery took too long — the customer cancelled.")
	delivery_state_changed.emit(order)
	delivery_completed.emit(order, false)


func _release_order(order: FoodOrder) -> void:
	active_orders.erase(order)
	active_count_changed.emit(active_orders.size())


func _spawn_driver_agent(rest: RestaurantState, member: StaffMember) -> Node:
	if not ResourceLoader.exists(DRIVER_SCENE_PATH):
		return null
	var scene: PackedScene = load(DRIVER_SCENE_PATH)
	var driver: Node = scene.instantiate()
	driver.set("home_restaurant", rest)
	driver.set("staff_member", member)
	var agents: Node = get_tree().current_scene.get_node_or_null("Agents/Citizens")
	if agents == null:
		agents = get_tree().current_scene
	agents.add_child(driver)
	if driver is Node3D:
		(driver as Node3D).global_position = rest.door_pos
	return driver
