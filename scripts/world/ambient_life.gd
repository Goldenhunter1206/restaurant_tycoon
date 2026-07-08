class_name AmbientLife
extends Node
## Camera-local ambient street life: fixed pools of pedestrian/car
## extras recycled around the camera so streets read busy wherever the
## player looks, at a capped cost independent of city size. Pure set
## dressing — the simulated population lives in PopulationManager.

const WALKER_POOL: int = 120
const CAR_POOL: int = 24
const SPAWN_MIN: float = 25.0
const SPAWN_MAX: float = 170.0
const DESPAWN: float = 230.0
const CAR_RING_MIN: float = 60.0
const CAR_RING_MAX: float = 220.0
const STEER_INTERVAL: float = 0.1
const SPAWN_PER_FRAME: int = 20
const ACTIVATIONS_PER_STEER: int = 20
const RNG_SEED: int = 424242

## Zoom thinning: individual pedestrians are subpixel above ~340 m of
## zoom; keep a few cars for distant-view life.
const ZOOM_FULL: float = 140.0
const ZOOM_NONE: float = 340.0
const CAR_MIN_TARGET: int = 8

var _walkers: Array[Node3D] = []
var _cars: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _accum: float = 0.0
var _phase: int = 0        # 0 wait for city, 1 build pools, 2 steer
var _walker_scene: PackedScene
var _walker_parent: Node3D


func _ready() -> void:
	_rng.seed = RNG_SEED


func _process(delta: float) -> void:
	match _phase:
		0:
			_try_begin()
		1:
			_build_pools_step()
		2:
			_accum += delta
			if _accum >= STEER_INTERVAL:
				_accum = 0.0
				_steer()


func _try_begin() -> void:
	# City.gd fills CityData and kicks PopulationManager deferred; wait
	# until the road graph and the shared citizen assets exist.
	if CityData.road_graph == null or PopulationManager.citizens.is_empty():
		return
	PopulationManager.ensure_assets_loaded()
	_walker_scene = load("res://scenes/agents/AmbientWalker.tscn")
	if _walker_scene == null:
		push_warning("AmbientLife: AmbientWalker.tscn missing; ambient life disabled")
		set_process(false)
		return
	var agents := get_tree().current_scene.get_node("Agents")
	_walker_parent = Node3D.new()
	_walker_parent.name = "Ambient"
	agents.add_child(_walker_parent)
	_phase = 1


func _build_pools_step() -> void:
	## Spread pool construction over frames (GLB loads are the cost).
	var spawned := 0
	var models := PopulationManager.character_model_paths()
	while _walkers.size() < WALKER_POOL and spawned < SPAWN_PER_FRAME:
		var w: Node3D = _walker_scene.instantiate()
		w.name = "AmbientWalker_%d" % _walkers.size()
		_walker_parent.add_child(w)
		if not models.is_empty():
			w.call("setup", models[_rng.randi_range(0, models.size() - 1)], PopulationManager.animation_library(), int(_rng.randi()))
		_walkers.append(w)
		spawned += 1
	if _walkers.size() < WALKER_POOL:
		return
	while _cars.size() < CAR_POOL and spawned < SPAWN_PER_FRAME:
		var pos := TrafficManager.random_lane_point(int(_rng.randi()))
		var car: Node3D = TrafficManager.spawn_ambient_car(pos)
		if car == null:
			push_warning("AmbientLife: ambient cars unavailable")
			_phase = 2
			return
		car.call("begin_local_patrol", int(_rng.randi()), _camera_center)
		_cars.append(car)
		spawned += 1
	if _cars.size() >= CAR_POOL:
		_phase = 2


func _camera_center() -> Vector3:
	var rig := get_tree().current_scene.get_node_or_null("CameraRig")
	return rig.global_position if rig else Vector3.ZERO


func _steer() -> void:
	var rig := get_tree().current_scene.get_node_or_null("CameraRig")
	if rig == null:
		return
	var center: Vector3 = rig.global_position
	var zoom: float = float(rig.get("zoom_dist"))
	var f := clampf(inverse_lerp(ZOOM_NONE, ZOOM_FULL, zoom), 0.0, 1.0)
	_steer_walkers(center, int(round(WALKER_POOL * f)), f <= 0.01)
	_steer_cars(center, int(round(lerpf(float(CAR_MIN_TARGET), float(CAR_POOL), f))))


func _steer_walkers(center: Vector3, target: int, force_thin: bool) -> void:
	var graph: RoadGraph = CityData.road_graph
	var ring := graph.side_nodes_near(center, SPAWN_MIN, SPAWN_MAX)
	if ring.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var active_count := 0
	for w in _walkers:
		if not bool(w.get("active")):
			continue
		active_count += 1
		if w.global_position.distance_to(center) > DESPAWN:
			w.call("retarget", _pick_ring_node(graph, ring, cam))
	if active_count > target:
		# Thin out beyond the spawn ring first (least visible pop-out);
		# at full zoom-out pedestrians are subpixel, so drop anyone.
		for w in _walkers:
			if active_count <= target:
				break
			if bool(w.get("active")) and (force_thin or w.global_position.distance_to(center) > SPAWN_MAX):
				w.call("deactivate")
				active_count -= 1
	else:
		var budget := ACTIVATIONS_PER_STEER
		for w in _walkers:
			if active_count >= target or budget <= 0:
				break
			if not bool(w.get("active")):
				w.call("activate", _pick_ring_node(graph, ring, cam))
				active_count += 1
				budget -= 1


func _steer_cars(center: Vector3, target: int) -> void:
	var graph: RoadGraph = CityData.road_graph
	var ring := graph.lane_nodes_near(center, CAR_RING_MIN, CAR_RING_MAX)
	if ring.is_empty():
		return
	var active_count := 0
	for car in _cars:
		if not car.visible:
			continue
		active_count += 1
		if car.global_position.distance_to(center) > DESPAWN * 1.3:
			car.call("retarget", graph.lane_points[ring[_rng.randi_range(0, ring.size() - 1)]])
	if active_count > target:
		for car in _cars:
			if active_count <= target:
				break
			if car.visible and car.global_position.distance_to(center) > CAR_RING_MAX:
				car.visible = false
				car.set_process(false)
				active_count -= 1
	else:
		for car in _cars:
			if active_count >= target:
				break
			if not car.visible:
				car.visible = true
				car.call("retarget", graph.lane_points[ring[_rng.randi_range(0, ring.size() - 1)]])
				active_count += 1


func _pick_ring_node(graph: RoadGraph, ring: PackedInt32Array, cam: Camera3D) -> int:
	## Prefer spawn points outside the frustum to avoid visible pop-in.
	for attempt in range(6):
		var node := ring[_rng.randi_range(0, ring.size() - 1)]
		if cam == null or not cam.is_position_in_frustum(graph.side_points[node] + Vector3.UP):
			return node
	return ring[_rng.randi_range(0, ring.size() - 1)]
