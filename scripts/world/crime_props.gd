class_name CrimeProps
extends Node3D
## Cosmetic world layer for the crime system (feature 12). Authority always
## stays with CrimeManager's game-minute timers — these props are pure
## presentation and can be skipped without changing any outcome:
##   - graffiti decals on vandalized storefronts, cleared on repair;
##   - a lone crew figure walking to a target while an op is in progress;
##   - a police car driving in when a branch calls the police;
##   - a small cluster of loiterers during an active protest.
## First-time GLB loads happen behind call_deferred (a synchronous import can
## wedge the frame), and every spawn is capped and self-cleans.

const POLICE_CAR: String = "res://Cartoon City Massive Megapack/gLTF/Vehicles/Police Car/Car_Police_1_A_1.gltf"
const POLICEMAN: String = "res://Cartoon City Massive Megapack/gLTF/Characters/PoliceMan_A_1_1.glb"
const WALKER: String = "res://Cartoon City Massive Megapack/gLTF/Characters/Character_10_1_1.glb"
const GRAFFITI_DIR: String = "res://assets/graffiti"
const MAX_JOBS: int = 6
const GRAFFITI_ACTIONS: Array[String] = ["graffiti", "property", "arson", "stink"]

var _crime: Node
var _decals: Dictionary = {}  ## building_id -> MeshInstance3D
var _jobs: Array[Dictionary] = []  ## {node, from, to, start_min, dur, kind}
var _graffiti_textures: Array[Texture2D] = []
var _scene_cache: Dictionary = {}


func _ready() -> void:
	_crime = get_tree().root.get_node_or_null("CrimeManager")
	if _crime == null:
		return
	if _crime.has_signal("security_changed"):
		_crime.connect("security_changed", _on_security_changed)
	if _crime.has_signal("incident_reported"):
		_crime.connect("incident_reported", _on_incident_reported)
	if _crime.has_signal("police_dispatched"):
		_crime.connect("police_dispatched", _on_police_dispatched)
	if _crime.has_signal("operation_updated"):
		_crime.connect("operation_updated", _on_operation_updated)
	_load_graffiti.call_deferred()


func _process(_delta: float) -> void:
	if _jobs.is_empty():
		return
	# Continuous game-minute clock for smooth motion (cosmetic only).
	var minute_now: float = float((GameClock.day - 1) * 1440) + GameClock.game_hours * 60.0
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


# --- Graffiti decals -------------------------------------------------------

func _on_security_changed(building_id: int) -> void:
	_refresh_decal.call_deferred(building_id)


func _on_incident_reported(building_id: int, _incident: Dictionary) -> void:
	_refresh_decal.call_deferred(building_id)


func _refresh_decal(building_id: int) -> void:
	if _crime == null:
		return
	var sec: Object = _crime.call("security_for", building_id)
	var wants: bool = false
	if sec != null:
		for row: Dictionary in sec.get("incidents"):
			if not bool(row.get("active", false)):
				continue
			var src: String = String(row.get("source_action", ""))
			for tag: String in GRAFFITI_ACTIONS:
				if src.contains(tag):
					wants = true
					break
	if wants and not _decals.has(building_id):
		var decal: MeshInstance3D = _make_graffiti(building_id)
		if decal != null:
			_decals[building_id] = decal
	elif not wants and _decals.has(building_id):
		var old: MeshInstance3D = _decals[building_id]
		if is_instance_valid(old):
			old.queue_free()
		_decals.erase(building_id)


func _make_graffiti(building_id: int) -> MeshInstance3D:
	if _graffiti_textures.is_empty():
		return null
	var info: Dictionary = CityData.get_building(building_id)
	if info.is_empty():
		return null
	var pos: Vector3 = info.get("position", Vector3.ZERO)
	var door: Vector3 = info.get("door_pos", pos)
	var out_dir: Vector3 = (door - pos)
	out_dir.y = 0.0
	if out_dir.length() < 0.1:
		out_dir = Vector3.FORWARD
	out_dir = out_dir.normalized()
	var quad: MeshInstance3D = MeshInstance3D.new()
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(2.2, 2.2)
	quad.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = _graffiti_textures[building_id % _graffiti_textures.size()]
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material_override = mat
	quad.global_position = door + out_dir * 0.15 + Vector3(0, 1.6, 0)
	quad.look_at(quad.global_position + out_dir, Vector3.UP)
	add_child(quad)
	return quad


# --- Travelling agents -----------------------------------------------------

func _on_police_dispatched(building_id: int, eta_minutes: float) -> void:
	if _jobs.size() >= MAX_JOBS:
		return
	var info: Dictionary = CityData.get_building(building_id)
	if info.is_empty():
		return
	var to: Vector3 = info.get("door_pos", info.get("position", Vector3.ZERO))
	var precincts: Array = _crime.call("precinct_positions") if _crime != null else []
	var from: Vector3 = precincts[0] if not precincts.is_empty() else to + Vector3(40, 0, 40)
	_spawn_job.call_deferred(POLICE_CAR, from, to, maxf(4.0, eta_minutes), "police", 2.0)


func _on_operation_updated(operation: Object) -> void:
	if operation == null:
		return
	var phase: StringName = operation.get("phase")
	if phase != &"travel":
		return
	if _jobs.size() >= MAX_JOBS:
		return
	var info: Dictionary = CityData.get_building(int(operation.get("target_building")))
	if info.is_empty():
		return
	var to: Vector3 = info.get("door_pos", info.get("position", Vector3.ZERO))
	var from: Vector3 = to + Vector3(18, 0, 18)
	var dur: float = maxf(6.0, float(operation.get("travel_minutes")))
	_spawn_job.call_deferred(WALKER, from, to, dur, "walker", 1.0)


func _spawn_job(scene_path: String, from: Vector3, to: Vector3, dur: float, kind: String, scale: float) -> void:
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


# --- Loaders ---------------------------------------------------------------

func _load_graffiti() -> void:
	for i: int in range(1, 11):
		var path: String = "%s/gr%d.png" % [GRAFFITI_DIR, i]
		var tex: Texture2D = load(path) as Texture2D
		if tex != null:
			_graffiti_textures.append(tex)


func _instantiate(scene_path: String) -> Node3D:
	var packed: PackedScene = _scene_cache.get(scene_path)
	if packed == null:
		packed = load(scene_path) as PackedScene
		if packed == null:
			return null
		_scene_cache[scene_path] = packed
	return packed.instantiate() as Node3D
