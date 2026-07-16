class_name CivicProps
extends Node3D
## Cosmetic world layer for the government system (feature 13). Authority
## always stays with GovernmentManager's game-minute timers — pure
## presentation, skippable without changing outcomes:
##   - police signs (and an officer) marking each station anchor;
##   - an inspector walking up to a branch ahead of the scheduled visit;
##   - a police car driving from the nearest station on every dispatch.
## First-time GLB loads happen behind call_deferred (a synchronous import can
## wedge the frame); every spawn is capped and self-cleans. If bespoke
## city-hall / police-station models are imported later at the paths below,
## they are placed automatically on the next boot.

const POLICE_CAR: String = "res://Cartoon City Massive Megapack/gLTF/Vehicles/Police Car/Car_Police_1_A_1.gltf"
const POLICEMAN: String = "res://Cartoon City Massive Megapack/gLTF/Characters/PoliceMan_A_1_1.glb"
const INSPECTOR: String = "res://Cartoon City Massive Megapack/gLTF/Characters/Character_15_1_1.glb"
const POLICE_SIGN: String = "res://Cartoon City Massive Megapack/gLTF/Other/PoliceSign.glb"
## Optional bespoke landmark models (Tripo imports) — placed when present.
const CITY_HALL_MODEL: String = "res://assets/models/city_hall.glb"
const STATION_MODEL: String = "res://assets/models/police_station.glb"
const MAX_JOBS: int = 6
## The inspector starts walking this many game-minutes before the visit.
const INSPECTOR_LEAD_MINUTES: float = 35.0

var _gov: Node
var _jobs: Array[Dictionary] = []  ## {node, from, to, start_min, dur, kind}
## inspection uid -> true once its walker has been spawned.
var _walked: Dictionary = {}
var _scene_cache: Dictionary = {}
var _markers_placed: bool = false


func _ready() -> void:
	_gov = get_tree().root.get_node_or_null("GovernmentManager")
	if _gov == null or not bool(_gov.call("enabled")):
		return
	if _gov.has_signal("police_dispatched"):
		_gov.connect("police_dispatched", _on_police_dispatched)
	_place_markers.call_deferred()


func _process(_delta: float) -> void:
	if _gov == null:
		return
	var minute_now: float = float((GameClock.day - 1) * 1440) + GameClock.game_hours * 60.0
	_maybe_walk_inspectors(minute_now)
	if _jobs.is_empty():
		return
	for i: int in range(_jobs.size() - 1, -1, -1):
		var job: Dictionary = _jobs[i]
		var t: float = clampf((minute_now - float(job["start_min"])) / float(job["dur"]), 0.0, 1.0)
		var node: Node3D = job["node"]
		if not is_instance_valid(node):
			_jobs.remove_at(i)
			continue
		var from: Vector3 = job["from"]
		var to: Vector3 = job["to"]
		node.global_position = from.lerp(to, t)
		var dir: Vector3 = (to - from)
		if dir.length() > 0.01:
			node.look_at(node.global_position + dir, Vector3.UP)
		if t >= 1.0:
			node.queue_free()
			_jobs.remove_at(i)


# --- Inspector walkers -------------------------------------------------------

func _maybe_walk_inspectors(minute_now: float) -> void:
	if _jobs.size() >= MAX_JOBS:
		return
	for insp in _gov.get("inspections"):
		if bool(insp.get("visit_done")):
			continue
		var uid: int = int(insp.get("uid"))
		if _walked.has(uid):
			continue
		var visit_minute: float = float(int(insp.get("visit_minute")))
		if minute_now < visit_minute - INSPECTOR_LEAD_MINUTES or minute_now >= visit_minute:
			continue
		_walked[uid] = true
		var info: Dictionary = CityData.get_building(int(insp.get("building_id")))
		if info.is_empty():
			continue
		var to: Vector3 = info.get("door_pos", info.get("position", Vector3.ZERO))
		var hall: Vector3 = _gov.call("city_hall_position")
		var from: Vector3 = to + (hall - to).normalized() * 26.0 if hall != Vector3.ZERO \
			else to + Vector3(20, 0, 14)
		from.y = to.y
		_spawn_job.call_deferred(INSPECTOR, from, to, INSPECTOR_LEAD_MINUTES, "inspector", 1.0)
		break


# --- Police dispatch ---------------------------------------------------------

func _on_police_dispatched(building_id: int, eta_minutes: float) -> void:
	if _jobs.size() >= MAX_JOBS:
		return
	var info: Dictionary = CityData.get_building(building_id)
	if info.is_empty():
		return
	var to: Vector3 = info.get("door_pos", info.get("position", Vector3.ZERO))
	var stations: Array = _gov.call("station_positions")
	var from: Vector3 = to + Vector3(40, 0, 40)
	var best: float = INF
	for station_pos: Vector3 in stations:
		var dist: float = station_pos.distance_to(to)
		if dist < best:
			best = dist
			from = station_pos
	_spawn_job.call_deferred(POLICE_CAR, from, to, maxf(4.0, eta_minutes), "police", 2.0)


# --- Landmarks ---------------------------------------------------------------

## Marks every station anchor with a police sign + an officer, and drops the
## bespoke landmark models next to their anchors when the assets exist.
func _place_markers() -> void:
	if _markers_placed:
		return
	_markers_placed = true
	for station in _gov.get("stations"):
		var info: Dictionary = CityData.get_building(int(station.get("building_id")))
		var anchor: Vector3 = info.get("door_pos", station.get("position"))
		if anchor == Vector3.ZERO:
			continue
		var sign_node: Node3D = _instantiate(POLICE_SIGN)
		if sign_node != null:
			add_child(sign_node)
			sign_node.global_position = anchor + Vector3(1.2, 0, 0)
		var officer: Node3D = _instantiate(POLICEMAN)
		if officer != null:
			add_child(officer)
			officer.global_position = anchor + Vector3(-0.8, 0, 0.6)
			officer.rotate_y(randf_range(0.0, TAU))
		if ResourceLoader.exists(STATION_MODEL):
			var station_model: Node3D = _instantiate(STATION_MODEL)
			if station_model != null:
				add_child(station_model)
				station_model.global_position = station.get("position")
	var hall: Vector3 = _gov.call("city_hall_position")
	if hall != Vector3.ZERO and ResourceLoader.exists(CITY_HALL_MODEL):
		var hall_model: Node3D = _instantiate(CITY_HALL_MODEL)
		if hall_model != null:
			add_child(hall_model)
			hall_model.global_position = hall


# --- Shared ------------------------------------------------------------------

func _spawn_job(scene_path: String, from: Vector3, to: Vector3, dur: float,
		kind: String, scale: float) -> void:
	if _jobs.size() >= MAX_JOBS:
		return
	var node: Node3D = _instantiate(scene_path)
	if node == null:
		return
	node.scale = Vector3(scale, scale, scale)
	node.global_position = from
	add_child(node)
	var minute_now: float = float((GameClock.day - 1) * 1440) + GameClock.game_hours * 60.0
	_jobs.append({
		"node": node, "from": from, "to": to,
		"start_min": minute_now, "dur": dur, "kind": kind,
	})


func _instantiate(scene_path: String) -> Node3D:
	var packed: PackedScene = _scene_cache.get(scene_path)
	if packed == null:
		if not ResourceLoader.exists(scene_path):
			return null
		packed = load(scene_path) as PackedScene
		if packed == null:
			return null
		_scene_cache[scene_path] = packed
	return packed.instantiate() as Node3D
