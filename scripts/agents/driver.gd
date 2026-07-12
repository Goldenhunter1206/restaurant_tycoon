class_name Driver
extends Area3D
## A hired delivery driver. Fully simulated round trip per order:
## walk from the restaurant to the company car, drive to the customer,
## walk to their door, hand over (dwell), then return the same way.
## Movement scales with GameClock.speed; dwell uses absolute game minutes.

enum DState {
	IDLE,
	TO_CAR,
	DRIVING_OUT,
	TO_CUSTOMER_DOOR,
	HANDING_OVER,
	BACK_TO_CAR,
	DRIVING_BACK,
	TO_RESTAURANT,
}

const WALK_SPEED: float = 2.0
const DELIVERY_MARKER_SCENE_PATH: String = "res://scenes/ui/DeliveryCarMarker.tscn"

var home_restaurant: RestaurantState = null
var staff_member: StaffMember = null
## Vehicle._finish_trip and inspect_info read passenger.data — provide the
## same shape a Citizen has.
var data: Dictionary = {"id": 0, "name": "Driver"}
var company_car: Node3D = null
var current_order: FoodOrder = null
## Cosmetic fleet type set at hire (DeliveryManager) — drives HUD breakdown
## counts and the world pin icon. All types still drive the company car.
var vehicle_type: StringName = &"scooter"
var state: DState = DState.IDLE
var goal_desc: String = "waiting for orders"

var _path: PackedInt32Array = PackedInt32Array()
var _path_idx: int = 0
## Walk-speed factor from the navigation attribute, cached in _ready.
var _walk_mult: float = 1.0
var _walk_done: Callable = Callable()
var _dwell_until: int = -1
var _model: Node3D
var _anim: AnimationPlayer


func _ready() -> void:
	set_meta("entity", "driver")
	monitoring = false
	TrafficManager.register_pedestrian(self)
	tree_exiting.connect(func() -> void: TrafficManager.unregister_pedestrian(self))
	if staff_member != null:
		data = {"id": staff_member.uid, "name": staff_member.staff_name}
		name = "Driver_%d" % staff_member.uid
		var walk_span: float = float(EconomyManager.tuning_value("staff.effects.walk_span", 0.3))
		_walk_mult = 1.0 + (staff_member.attr(&"navigation") - 0.5) * walk_span
	_anim = get_node_or_null("AnimationPlayer")
	_attach_model()
	_spawn_company_car()
	if home_restaurant != null:
		global_position = home_restaurant.door_pos


func is_idle() -> bool:
	return state == DState.IDLE and current_order == null


func is_on_foot() -> bool:
	return state in [
		DState.TO_CAR, DState.TO_CUSTOMER_DOOR, DState.HANDING_OVER,
		DState.BACK_TO_CAR, DState.TO_RESTAURANT,
	]


func assign_order(order: FoodOrder) -> void:
	if not is_idle():
		return
	current_order = order
	state = DState.TO_CAR
	goal_desc = "picking up an order"
	_walk_toward(_car_pos(), _on_reached_car_out)


func abort_delivery() -> void:
	## The customer cancelled. Finish any in-progress drive (the Vehicle
	## owns the trip), then head home; if on foot, turn around now.
	goal_desc = "returning (order cancelled)"
	current_order = null
	match state:
		DState.TO_CAR, DState.TO_CUSTOMER_DOOR, DState.HANDING_OVER, DState.BACK_TO_CAR:
			_dwell_until = -1
			state = DState.BACK_TO_CAR
			_walk_toward(_car_pos(), _on_reached_car_back)
		DState.IDLE, DState.TO_RESTAURANT:
			pass
		_:
			pass  # driving: on_car_trip_finished redirects home


func cleanup() -> void:
	## Called when the driver is fired: remove the company car too.
	if is_instance_valid(company_car):
		TrafficManager.vehicles.erase(company_car)
		company_car.queue_free()
	company_car = null


func on_car_trip_finished(at_pos: Vector3) -> void:
	global_position = at_pos
	visible = true
	match state:
		DState.DRIVING_OUT:
			if current_order == null or current_order.state == FoodOrder.State.CANCELLED:
				_drive_home()
				return
			state = DState.TO_CUSTOMER_DOOR
			goal_desc = "delivering to the door"
			_walk_toward(current_order.target_door, _on_reached_customer)
		DState.DRIVING_BACK:
			state = DState.TO_RESTAURANT
			goal_desc = "returning to the restaurant"
			_walk_toward(_restaurant_door(), _on_reached_restaurant)
		_:
			state = DState.IDLE


func remaining_route_points() -> PackedVector3Array:
	if state in [DState.DRIVING_OUT, DState.DRIVING_BACK] and is_instance_valid(company_car) and company_car.has_method("remaining_route_points"):
		return company_car.remaining_route_points()
	var points: PackedVector3Array = PackedVector3Array()
	points.append(global_position)
	if not _path.is_empty():
		var graph: RoadGraph = CityData.road_graph
		for i: int in range(clampi(_path_idx, 0, _path.size()), _path.size()):
			points.append(graph.side_points[_path[i]])
	return points


func delivery_snapshot() -> Dictionary:
	var snapshot: Dictionary = {
		"delivery_stage": goal_desc.capitalize(),
		"driver": staff_member.staff_name if staff_member != null else "Driver",
		"restaurant": home_restaurant.restaurant_name if home_restaurant != null else "Unknown restaurant",
		"destination": "Restaurant",
		"order_detail": "No active order",
		"route_points": remaining_route_points(),
	}
	if current_order != null:
		snapshot["order_detail"] = "#%d · %s" % [current_order.order_id, String(current_order.dish_id).replace("_", " ").capitalize()]
		snapshot["destination"] = "Customer #%d" % current_order.citizen_id
		snapshot["destination_position"] = current_order.target_door
	return snapshot


func inspect_info() -> Dictionary:
	var info: Dictionary = {
		"kind": "delivery driver",
		"name": staff_member.staff_name if staff_member != null else "Driver",
		"employer": home_restaurant.restaurant_name if home_restaurant != null else "?",
		"state": DState.keys()[state],
		"goal": goal_desc,
		"order": ("#%d %s" % [current_order.order_id, String(current_order.dish_id)])
			if current_order != null else "none",
		"position": global_position,
	}
	info.merge(delivery_snapshot(), true)
	return info


# --- Walking (sidewalk graph, same conventions as Citizen) --------------------


func _process(delta: float) -> void:
	if state == DState.HANDING_OVER:
		if GameClock.total_minutes() >= _dwell_until:
			_finish_handover()
		return
	if _path_idx >= _path.size():
		return
	var graph: RoadGraph = CityData.road_graph
	var target: Vector3 = graph.side_points[_path[_path_idx]]
	if _path_idx > 0:
		var edge: int = _crossing_edge(_path[_path_idx - 1], _path[_path_idx])
		if edge >= 0 and (not TrafficManager.can_pedestrian_cross(edge)
				or not TrafficManager.is_crossing_safe(edge)):
			_set_anim("idle")
			return
	_set_anim("walk")
	# Same separation as citizens: never walk through cars or walkers.
	var push: Vector3 = PedSteering.lateral_avoid(self)
	if push != Vector3.ZERO:
		global_position += push * minf(delta * float(GameClock.speed) * 2.0, 1.0)
	var to_target: Vector3 = target - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	var step: float = WALK_SPEED * _walk_mult * delta * float(GameClock.speed)
	if step >= dist:
		global_position = target
		_path_idx += 1
		if _path_idx >= _path.size():
			_set_anim("idle")
			if _walk_done.is_valid():
				var done: Callable = _walk_done
				_walk_done = Callable()
				done.call()
	else:
		global_position += to_target.normalized() * step
		if to_target.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(to_target.x, to_target.z), 0.3)


func _walk_toward(target: Vector3, done: Callable) -> void:
	var graph: RoadGraph = CityData.road_graph
	_path = graph.find_side_path(
		graph.nearest_side_node(global_position), graph.nearest_side_node(target))
	_path_idx = 0
	_walk_done = done
	visible = true
	if _path.is_empty():
		global_position = target
		var immediate: Callable = _walk_done
		_walk_done = Callable()
		if immediate.is_valid():
			immediate.call()


func _crossing_edge(from_id: int, to_id: int) -> int:
	var graph: RoadGraph = CityData.road_graph
	for e: int in graph.side_edges(from_id):
		if graph.side_crossing[e] >= 0 and graph.side_other_end(e, from_id) == to_id:
			return e
	return -1


# --- Trip stages ---------------------------------------------------------------


func _on_reached_car_out() -> void:
	if current_order == null or current_order.state == FoodOrder.State.CANCELLED:
		state = DState.TO_RESTAURANT
		_walk_toward(_restaurant_door(), _on_reached_restaurant)
		return
	current_order.state = FoodOrder.State.PICKED_UP
	DeliveryManager.delivery_state_changed.emit(current_order)
	if TrafficManager.request_car_trip(self, company_car, current_order.target_door):
		state = DState.DRIVING_OUT
		goal_desc = "driving a delivery"
		visible = false
		current_order.state = FoodOrder.State.EN_ROUTE
		DeliveryManager.delivery_state_changed.emit(current_order)
	else:
		# No drivable route — walk it (slow, may get cancelled).
		state = DState.TO_CUSTOMER_DOOR
		_walk_toward(current_order.target_door, _on_reached_customer)


func _on_reached_customer() -> void:
	state = DState.HANDING_OVER
	goal_desc = "handing over the food"
	var dwell: float = float(EconomyManager.tuning_value("delivery.deliver_dwell_minutes", 2))
	if staff_member != null:
		var dwell_span: float = float(EconomyManager.tuning_value("staff.effects.dwell_span", 0.5))
		dwell *= 1.0 - (staff_member.attr(&"navigation") - 0.5) * dwell_span
	_dwell_until = GameClock.total_minutes() + int(maxf(1.0, dwell))


func _finish_handover() -> void:
	_dwell_until = -1
	if current_order != null and current_order.state != FoodOrder.State.CANCELLED:
		DeliveryManager.complete_delivery(current_order)
	current_order = null
	state = DState.BACK_TO_CAR
	goal_desc = "walking back to the car"
	_walk_toward(_car_pos(), _on_reached_car_back)


func _on_reached_car_back() -> void:
	_drive_home()


func _drive_home() -> void:
	current_order = null
	if TrafficManager.request_car_trip(self, company_car, _restaurant_curb()):
		state = DState.DRIVING_BACK
		goal_desc = "driving back"
		visible = false
	else:
		state = DState.TO_RESTAURANT
		_walk_toward(_restaurant_door(), _on_reached_restaurant)


func _on_reached_restaurant() -> void:
	state = DState.IDLE
	goal_desc = "waiting for orders"
	DeliveryManager.driver_became_idle(self)


# --- Setup helpers ---------------------------------------------------------------


func _car_pos() -> Vector3:
	if is_instance_valid(company_car):
		return company_car.global_position
	return _restaurant_curb()


func _restaurant_door() -> Vector3:
	return home_restaurant.door_pos if home_restaurant != null else global_position


func _restaurant_curb() -> Vector3:
	return home_restaurant.curb_pos if home_restaurant != null else global_position


func _spawn_company_car() -> void:
	if home_restaurant == null:
		return
	var graph: RoadGraph = CityData.road_graph
	var node: int = graph.nearest_lane_node(home_restaurant.door_pos)
	var lane_pos: Vector3 = graph.lane_points[node]
	company_car = TrafficManager.spawn_ambient_car(lane_pos)
	if company_car == null:
		return
	var heading: Vector3 = Vector3.FORWARD
	var out_edges: Array = graph.lane_out_edges(node)
	if not out_edges.is_empty():
		var e: int = out_edges[0]
		heading = (graph.lane_points[graph.lane_to[e]] - lane_pos).normalized()
	if not TrafficManager.park_vehicle_near(company_car, home_restaurant.curb_pos):
		var jitter: float = float((staff_member.uid % 5) - 2) * 2.6 if staff_member != null else 0.0
		company_car.park_at(lane_pos, heading, jitter)
	if home_restaurant != null:
		company_car.set("owner_desc", "%s — our delivery car" % home_restaurant.restaurant_name)
	company_car.set("kind", "delivery")
	company_car.set("delivery_driver", self)
	if staff_member != null:
		var drive_span: float = float(EconomyManager.tuning_value("staff.effects.drive_span", 0.3))
		company_car.set("speed_multiplier", 1.0 + (staff_member.attr(&"driving") - 0.5) * drive_span)
	if ResourceLoader.exists(DELIVERY_MARKER_SCENE_PATH):
		var marker_scene: PackedScene = load(DELIVERY_MARKER_SCENE_PATH)
		var marker: Node = marker_scene.instantiate()
		marker.name = "OurDeliveryMarker"
		# Teardrop pin matching the fleet type (car -> boxy delivery truck pin).
		var assets: GDScript = load("res://scripts/ui/ui_assets.gd")
		var pin_name: StringName = &"truck" if vehicle_type == &"car" else vehicle_type
		var pin_tex: Texture2D = assets.pin(pin_name)
		var sprite: Sprite3D = marker.get_node_or_null("PizzaBadge")
		if pin_tex != null and sprite != null:
			sprite.texture = pin_tex
			# Zoom-aware pin: shrinks when the camera is close so the car
			# stays visible; script attached before entering the tree.
			sprite.set_script(load("res://scripts/ui/zoom_scaled_pin.gd"))
			sprite.set("base_pixel_size", 0.0008)
			# Overlay-marker layer, excluded from the minimap bake camera.
			sprite.layers = 1 << 19
		company_car.add_child(marker)


func _attach_model() -> void:
	PopulationManager.ensure_assets_loaded()
	var models: Array[String] = PopulationManager.character_model_paths()
	if models.is_empty():
		return
	var pick: String = models[(staff_member.uid if staff_member != null else 0) % models.size()]
	var scene: PackedScene = load(pick)
	if scene == null:
		return
	_model = scene.instantiate()
	_model.name = "Model"
	_model.rotation_degrees = Vector3(0, 180, 0)
	add_child(_model)
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visibility_range_end = 350.0
	var lib: AnimationLibrary = PopulationManager.animation_library()
	if _anim != null and lib != null:
		if not _anim.has_animation_library(""):
			_anim.add_animation_library("", lib)
		_anim.root_node = NodePath("../Model")
		_set_anim("idle")


func _set_anim(kind: String) -> void:
	if _anim == null:
		return
	var target: String = "Walk_A" if kind == "walk" else "Idle_A"
	if not _anim.has_animation(target):
		return
	if _anim.current_animation != target or not _anim.is_playing():
		_anim.play(target)
