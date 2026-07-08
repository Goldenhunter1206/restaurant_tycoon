extends Node
## Generates the deterministic population (same seed -> same city) and
## spawns/drives citizen agents. City.gd calls initialize() once the
## building registry is filled.

const POPULATION_SEED: int = 20260707
const CITIZEN_COUNT: int = 300
const CAR_OWNER_TARGET: int = 60      # private cars; service vehicles come on top

const FIRST_NAMES: Array[String] = [
	"Rosa", "Milo", "Greta", "Otto", "Luna", "Felix", "Ida", "Bruno", "Clara",
	"Hugo", "Nora", "Emil", "Frida", "Oskar", "Wilma", "Anton", "Ella", "Jonas",
	"Mia", "Theo", "Lena", "Paul", "Zoe", "Karl", "Alma", "Leo", "Tilda", "Max",
	"Nina", "Erik", "Suki", "Ravi", "Aisha", "Diego", "Yuki", "Omar", "Ines",
	"Tariq", "Maya", "Kofi",
]
const LAST_NAMES: Array[String] = [
	"Klein", "Rossi", "Novak", "Weber", "Silva", "Tanaka", "Muller", "Costa",
	"Haas", "Berg", "Lund", "Kova", "Mori", "Diaz", "Wolf", "Stein", "Vidal",
	"Okafor", "Reyes", "Blum", "Falk", "Nash", "Odum", "Pram", "Quist",
]

## Service jobs: [job_type, count, day_or_night]
const SERVICE_JOBS: Array = [
	["police", 2, "day"], ["police", 2, "night"],
	["taxi", 3, "day"], ["taxi", 2, "night"],
	["ambulance", 1, "day"], ["ambulance", 1, "night"],
	["icecream", 2, "day"],
	["post", 2, "day"],
]

const CHARACTERS_DIR: String = "res://Cartoon City Massive Megapack/gLTF 2/Characters/"
const ANIMATIONS_GLB: String = "res://Cartoon City Massive Megapack/gLTF 2/Animations/Animations.glb"

var citizens_data: Array[Dictionary] = []
var citizens: Array[Node] = []

var _initialized: bool = false
var _character_models: Array[String] = []
var _anim_library: AnimationLibrary


func initialize() -> void:
	## Called by City.gd after buildings are registered.
	if _initialized:
		return
	_initialized = true
	_generate_population()
	_spawn_citizens()


func _generate_population() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = POPULATION_SEED
	var homes: Array[Dictionary] = []
	var workplaces: Array[Dictionary] = []
	var building_ids: Array = CityData.buildings.keys()
	building_ids.sort()
	for b_id: int in building_ids:
		var info: Dictionary = CityData.buildings[b_id]
		if info["capacity_residents"] > 0:
			homes.append(info)
		if info["capacity_workers"] > 0:
			workplaces.append(info)
	if homes.is_empty() or workplaces.is_empty():
		push_error("PopulationManager: no homes or workplaces registered")
		return

	var home_slots: Dictionary = {}
	var leisure_pool := _build_leisure_pool(rng)

	# Service-vehicle jobs first.
	var service_records: Array[Dictionary] = []
	for job: Array in SERVICE_JOBS:
		for k in range(job[1]):
			service_records.append({"job_type": job[0], "shift": job[2]})

	var car_owners := 0
	for idx in range(CITIZEN_COUNT):
		var home := _pick_weighted_home(rng, homes, home_slots)
		var rec := {
			"id": idx,
			"name": "%s %s" % [FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)], LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)]],
			"home_id": home["id"],
			"district": home["district"],
			"shift": "day",
			"job_type": "none",
			"work_id": -1,
			"owns_car": false,
			"wake_hour": 6.0 + rng.randf_range(0.0, 2.0),
			"work_start": 8.0 + rng.randf_range(-0.5, 1.5),
			"work_hours": 8.0 + rng.randf_range(-1.0, 1.0),
			"home_hour": 20.5 + rng.randf_range(-1.5, 2.0),
			"leisure_spots": [],
		}
		# Job assignment: service jobs go to the first N citizens, the
		# rest are employed at buildings (85%) or jobless/retired (15%).
		if idx < service_records.size():
			rec["job_type"] = service_records[idx]["job_type"]
			rec["shift"] = service_records[idx]["shift"]
			rec["work_id"] = -1
		elif rng.randf() < 0.85:
			var wp: Dictionary = workplaces[rng.randi_range(0, workplaces.size() - 1)]
			rec["work_id"] = wp["id"]
			rec["job_type"] = wp["type"]
			if wp["type"] == "factory" and rng.randf() < 0.35:
				rec["shift"] = "night"
			elif rng.randf() < 0.06:
				rec["shift"] = "night"
		if rec["shift"] == "night":
			rec["work_start"] = 22.0 + rng.randf_range(-0.5, 0.5)
			rec["wake_hour"] = 19.5 + rng.randf_range(0.0, 1.5)
			rec["home_hour"] = 7.5 + rng.randf_range(0.0, 1.0)
		# Car ownership by district wealth.
		var car_chance := 0.3
		match String(home["district"]):
			"R": car_chance = 0.8
			"N": car_chance = 0.55
			"P": car_chance = 0.2
			_: car_chance = 0.3
		if car_owners < CAR_OWNER_TARGET and rec["job_type"] != "none" and rng.randf() < car_chance:
			rec["owns_car"] = true
			car_owners += 1
		var spots := []
		for k in range(rng.randi_range(2, 3)):
			spots.append(leisure_pool[rng.randi_range(0, leisure_pool.size() - 1)])
		rec["leisure_spots"] = spots
		citizens_data.append(rec)


func _pick_weighted_home(rng: RandomNumberGenerator, homes: Array[Dictionary], slots: Dictionary) -> Dictionary:
	for attempt in range(40):
		var home: Dictionary = homes[rng.randi_range(0, homes.size() - 1)]
		var used: int = slots.get(home["id"], 0)
		if used < home["capacity_residents"]:
			slots[home["id"]] = used + 1
			return home
	return homes[rng.randi_range(0, homes.size() - 1)]


func _build_leisure_pool(rng: RandomNumberGenerator) -> Array:
	## Leisure targets: park anchors + a sample of shops.
	var pool := []
	pool.append({"kind": "park", "pos": Vector3(340, 0, 400)})   # central park (interior x 324..396, z 372..460)
	pool.append({"kind": "park", "pos": Vector3(375, 0, 435)})
	pool.append({"kind": "basketball", "pos": Vector3(358, 0, 415)})
	pool.append({"kind": "park", "pos": Vector3(416, 0, 132)})   # pocket park (9,2)
	pool.append({"kind": "park", "pos": Vector3(338, 0, 584)})   # pocket park (7,12)
	pool.append({"kind": "plaza", "pos": Vector3(260, 0, 272)})  # downtown plaza superblock
	var shops := []
	for info: Dictionary in CityData.buildings.values():
		if info["type"] == "shop":
			shops.append(info)
	shops.sort_custom(func(a, b): return a["id"] < b["id"])
	for k in range(mini(24, shops.size())):
		var s: Dictionary = shops[rng.randi_range(0, shops.size() - 1)]
		pool.append({"kind": "shop", "pos": s["door_pos"], "building_id": s["id"]})
	return pool


func _spawn_citizens() -> void:
	var citizen_scene: PackedScene = load("res://scenes/agents/Citizen.tscn")
	if citizen_scene == null:
		push_warning("PopulationManager: Citizen.tscn missing, sim data only")
		return
	_collect_character_models()
	_load_animation_library()
	var model_rng := RandomNumberGenerator.new()
	model_rng.seed = POPULATION_SEED + 1
	var parent := get_tree().current_scene.get_node("Agents/Citizens")
	for rec: Dictionary in citizens_data:
		var citizen := citizen_scene.instantiate()
		citizen.setup(rec)
		parent.add_child(citizen)
		if not _character_models.is_empty():
			var model: String = _character_models[model_rng.randi_range(0, _character_models.size() - 1)]
			citizen.set_model(model, _anim_library)
		citizens.append(citizen)


func _collect_character_models() -> void:
	var dir := DirAccess.open(CHARACTERS_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".glb"):
			_character_models.append(CHARACTERS_DIR + f)


func _load_animation_library() -> void:
	var anim_scene: PackedScene = load(ANIMATIONS_GLB)
	if anim_scene == null:
		return
	var inst := anim_scene.instantiate()
	var player: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	if player:
		var libs := player.get_animation_library_list()
		if libs.size() > 0:
			_anim_library = player.get_animation_library(libs[0])
	inst.free()


func citizen_by_id(citizen_id: int) -> Node:
	if citizen_id >= 0 and citizen_id < citizens.size():
		return citizens[citizen_id]
	return null
