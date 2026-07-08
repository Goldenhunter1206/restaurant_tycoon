extends Node
## Registry of static city facts: calibration, buildings, lots and the
## road/sidewalk graph. Loaded once at boot; other systems query by id.

const CALIBRATION_PATH: String = "res://data/calibration.json"
const ROAD_GRAPH_PATH: String = "res://data/road_graph.tres"

## building_id -> {id, type, district, position, door_pos, curb_pos, capacity_residents, capacity_workers, node_path}
var buildings: Dictionary = {}
var calibration: Dictionary = {}
var road_graph: RoadGraph


func _ready() -> void:
	_load_calibration()
	_load_road_graph()


func register_building(info: Dictionary) -> void:
	buildings[int(info["id"])] = info


func get_building(building_id: int) -> Dictionary:
	return buildings.get(building_id, {})


func buildings_in_district(district: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for info: Dictionary in buildings.values():
		if info.get("district", "") == district:
			result.append(info)
	return result


func _load_road_graph() -> void:
	if not ResourceLoader.exists(ROAD_GRAPH_PATH):
		push_warning("CityData: road graph missing at %s" % ROAD_GRAPH_PATH)
		return
	road_graph = load(ROAD_GRAPH_PATH)
	road_graph.build_runtime()


func _load_calibration() -> void:
	if not FileAccess.file_exists(CALIBRATION_PATH):
		push_warning("CityData: calibration file missing at %s" % CALIBRATION_PATH)
		return
	var file := FileAccess.open(CALIBRATION_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		calibration = parsed
