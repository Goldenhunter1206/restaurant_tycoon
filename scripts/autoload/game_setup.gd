extends Node
## Carries the selected game mode and deterministic session contract across
## frontend/gameplay scene changes. It also owns campaign services so profile
## progression survives scene reloads while session saves remain rollback-able.

signal services_ready()
signal session_configured(config: GameSessionConfig)
signal session_initialized(config: GameSessionConfig)

const PENDING_TRANSITION_PATH: String = "user://pending_session_transition.json"

var from_save: bool = false
var mode: StringName = &"free_play"
var player_name: String = ""
var player_color: Color = Color("#EA4A2F")
var city_id: StringName = &"riverside"
var world_seed: int = 0
var difficulty: StringName = &"medium"
var selected_rivals: Array[StringName] = []
var configured: bool = false
var pending_intro: bool = false

var session_config: GameSessionConfig
var catalog: ScenarioCatalog
var campaign_manager: CampaignManager
var scenario_manager: ScenarioManager


func _ready() -> void:
	_ensure_services()
	_consume_pending_transition()


func _ensure_services() -> void:
	if catalog != null and campaign_manager != null and scenario_manager != null:
		return
	var catalog_script: GDScript = load("res://scripts/campaign/scenario_catalog.gd")
	catalog = catalog_script.new() as ScenarioCatalog
	if not catalog.load_all():
		push_warning("GameSetup: campaign catalog contains errors: %s" % catalog.validation_errors)
	var campaign_script: GDScript = load("res://scripts/campaign/campaign_manager.gd")
	campaign_manager = campaign_script.new() as CampaignManager
	campaign_manager.name = "CampaignManager"
	add_child(campaign_manager)
	campaign_manager.setup(catalog)
	var scenario_script: GDScript = load("res://scripts/campaign/scenario_manager.gd")
	scenario_manager = scenario_script.new() as ScenarioManager
	scenario_manager.name = "ScenarioManager"
	add_child(scenario_manager)
	scenario_manager.setup(catalog, campaign_manager)
	services_ready.emit()


func create_config(mode_id: StringName, scenario_id: StringName = &"") -> GameSessionConfig:
	_ensure_services()
	var config_script: GDScript = load("res://scripts/data/game_session_config.gd")
	var created: GameSessionConfig = config_script.new() as GameSessionConfig
	created.mode = mode_id
	created.scenario_id = scenario_id if scenario_id != &"" \
		else catalog.first_scenario_for_mode(mode_id)
	_hydrate_config(created)
	return created


func configure_session(new_config: GameSessionConfig) -> bool:
	_ensure_services()
	if new_config == null:
		return false
	_hydrate_config(new_config)
	if catalog.scenario(new_config.scenario_id).is_empty():
		push_warning("GameSetup: cannot configure unknown scenario %s" % new_config.scenario_id)
		return false
	session_config = new_config
	from_save = false
	configured = true
	_sync_legacy_fields()
	session_configured.emit(session_config)
	return true


func initialize_session() -> bool:
	_ensure_services()
	var saved_state: Dictionary = {}
	var saved_result: Dictionary = {}
	var loaded: SaveGame = CompanyManager.loaded_save
	if loaded != null and not loaded.session_config.is_empty():
		var config_script: GDScript = load("res://scripts/data/game_session_config.gd")
		session_config = config_script.call("from_dict", loaded.session_config) as GameSessionConfig
		from_save = true
		configured = true
		_sync_legacy_fields()
		saved_state = loaded.scenario_state.duplicate(true)
		saved_result = loaded.scenario_result.duplicate(true)
	elif session_config == null:
		var default_config: GameSessionConfig = create_config(&"free_play", &"sandbox_free_play")
		default_config.victory_rules = []
		configure_session(default_config)
	if session_config == null:
		return false
	if not from_save:
		_apply_starting_locations()
	var initialized: bool = scenario_manager.initialize(
		session_config, saved_state, saved_result)
	if initialized:
		session_initialized.emit(session_config)
	return initialized


func write_save(save: SaveGame) -> void:
	if save == null or session_config == null:
		return
	save.session_schema_version = 1
	save.session_config = session_config.to_dict()
	save.scenario_state = scenario_manager.session_state_dict() \
		if scenario_manager != null else {}
	save.scenario_result = scenario_manager.result_dict() \
		if scenario_manager != null else {}


func observe_action(action_id: StringName, payload: Dictionary = {}) -> void:
	if scenario_manager != null:
		scenario_manager.observe_action(action_id, payload)


func continue_after_result() -> void:
	if scenario_manager != null:
		scenario_manager.continue_in_free_play()


func restart_current_scenario() -> bool:
	if session_config == null:
		return false
	var config_script: Script = load("res://scripts/data/game_session_config.gd") as Script
	var restarted: GameSessionConfig = config_script.call(
		"from_dict", session_config.to_dict()) as GameSessionConfig
	return _queue_clean_transition(restarted, true)


func advance_to_next_scenario() -> bool:
	if session_config == null or catalog == null:
		return false
	var next_id: StringName = catalog.next_scenario_id(
		session_config.campaign_id, session_config.scenario_id)
	if next_id == &"":
		var next_data: Variant = active_scenario().get("next_scenario", {})
		if next_data is Dictionary:
			next_id = StringName(String((next_data as Dictionary).get("scenario_id", "")))
	if next_id == &"":
		return false
	var next_config: GameSessionConfig = create_config(&"campaign", next_id)
	next_config.company_identity = session_config.company_identity.duplicate(true)
	next_config.difficulty = session_config.difficulty
	return _queue_clean_transition(next_config, true)


func return_to_frontend() -> bool:
	return _queue_clean_transition(null, false)


func starting_cash(fallback: float) -> float:
	if session_config == null:
		return fallback
	return float(session_config.starting_resources.get("cash", fallback))


func starting_reputation(fallback: float) -> float:
	if session_config == null:
		return fallback
	return float(session_config.starting_resources.get("reputation", fallback))


func starting_restaurant_count(fallback: int) -> int:
	if session_config == null:
		return fallback
	return maxi(0, int(session_config.starting_resources.get(
		"restaurant_count", fallback)))


func system_enabled(system_id: StringName) -> bool:
	if session_config == null or session_config.enabled_systems.is_empty():
		return true
	return session_config.enabled_systems.has(system_id)


func scenario_rules() -> Array:
	var restrictions: Dictionary = active_scenario().get("restrictions", {})
	return (restrictions.get("rules", []) as Array).duplicate(true)


func rival_setup(rival_id: StringName) -> Dictionary:
	if session_config == null:
		return {}
	for rival: Dictionary in session_config.rivals:
		if StringName(String(rival.get("id", ""))) == rival_id:
			return rival.duplicate(true)
	return {}


func active_scenario() -> Dictionary:
	return catalog.scenario(session_config.scenario_id) \
		if catalog != null and session_config != null else {}


func active_city() -> Dictionary:
	return catalog.city(session_config.city_id) \
		if catalog != null and session_config != null else {}


func breadcrumb() -> String:
	if session_config == null:
		return "Free Play"
	var scenario_data: Dictionary = active_scenario()
	var city_data: Dictionary = active_city()
	return "%s  •  %s" % [
		String(city_data.get("name", String(session_config.city_id).capitalize())),
		String(scenario_data.get("title", String(session_config.mode).capitalize())),
	]


func randomize_seed() -> void:
	world_seed = randi()
	if session_config != null:
		session_config.seed = world_seed


func reset() -> void:
	from_save = false
	mode = &"free_play"
	player_name = ""
	player_color = Color("#EA4A2F")
	city_id = &"riverside"
	world_seed = 0
	difficulty = &"medium"
	selected_rivals = []
	configured = false
	session_config = null
	if scenario_manager != null:
		scenario_manager.reset_runtime()


func _queue_clean_transition(next_config: GameSessionConfig, show_intro: bool) -> bool:
	var file: FileAccess = FileAccess.open(PENDING_TRANSITION_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("GameSetup: could not write pending session transition")
		return false
	file.store_string(JSON.stringify({
		"show_intro": show_intro,
		"config": next_config.to_dict() if next_config != null else {},
	}))
	file.close()
	var process_id: int = OS.create_instance(PackedStringArray())
	if process_id > 0:
		get_tree().quit()
		return true
	# Editor and restricted platforms may reject a second process. Keep the
	# transition usable, while warning that autoload state could be retained.
	push_warning("GameSetup: clean relaunch unavailable; falling back to frontend")
	_consume_pending_transition()
	get_tree().change_scene_to_file("res://scenes/Frontend.tscn")
	return true


func _consume_pending_transition() -> void:
	if not FileAccess.file_exists(PENDING_TRANSITION_PATH):
		return
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(PENDING_TRANSITION_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING_TRANSITION_PATH))
	if parsed is not Dictionary:
		return
	var transition: Dictionary = parsed
	pending_intro = bool(transition.get("show_intro", false))
	var config_data: Dictionary = transition.get("config", {})
	if config_data.is_empty():
		return
	var config_script: Script = load("res://scripts/data/game_session_config.gd") as Script
	var restored: GameSessionConfig = config_script.call(
		"from_dict", config_data) as GameSessionConfig
	configure_session(restored)


func _hydrate_config(target: GameSessionConfig) -> void:
	if target.scenario_id == &"":
		target.scenario_id = catalog.first_scenario_for_mode(target.mode)
	var scenario_data: Dictionary = catalog.scenario(target.scenario_id)
	if scenario_data.is_empty():
		return
	if target.mode == &"":
		target.mode = StringName(String(scenario_data.get("mode", "free_play")))
	if target.city_id == &"":
		target.city_id = StringName(String(scenario_data.get("city_id", "riverside")))
	if target.campaign_id == &"":
		target.campaign_id = StringName(String(scenario_data.get("campaign_id", "")))
	var starting_state: Dictionary = scenario_data.get("starting_state", {})
	for key: Variant in starting_state:
		if not target.starting_resources.has(key):
			target.starting_resources[key] = starting_state[key]
	if target.rivals.is_empty():
		for value: Variant in scenario_data.get("rivals", []):
			if value is Dictionary:
				target.rivals.append((value as Dictionary).duplicate(true))
	var restrictions: Dictionary = scenario_data.get("restrictions", {})
	if target.enabled_systems.is_empty():
		for value: Variant in restrictions.get("enabled_systems", []):
			target.enabled_systems.append(StringName(String(value)))
	if target.seed == 0:
		var seed_source: String = String(starting_state.get("seed", target.scenario_id))
		target.seed = absi(seed_source.hash())
	if not target.company_identity.has("display_name"):
		target.company_identity["display_name"] = "Bella Vista"
	if not target.company_identity.has("brand_color"):
		target.company_identity["brand_color"] = "#EA4A2F"


func _sync_legacy_fields() -> void:
	if session_config == null:
		return
	mode = session_config.mode
	city_id = session_config.city_id
	world_seed = session_config.seed
	difficulty = session_config.difficulty if session_config.difficulty != &"" else &"medium"
	if difficulty == &"normal":
		difficulty = &"medium"
	player_name = String(session_config.company_identity.get("display_name", "Bella Vista"))
	var color_value: Variant = session_config.company_identity.get("brand_color", "#EA4A2F")
	player_color = color_value if color_value is Color else Color(String(color_value))
	selected_rivals.clear()
	for rival: Dictionary in session_config.rivals:
		var rival_id: StringName = StringName(String(rival.get("id", "")))
		if rival_id != &"":
			selected_rivals.append(rival_id)


func _apply_starting_locations() -> void:
	if session_config == null or CompanyManager.player == null:
		return
	var target_count: int = int(session_config.starting_resources.get("restaurant_count", 0))
	if target_count <= RestaurantManager.owned.size():
		return
	var candidates: Array[Dictionary] = RestaurantManager.purchasable_buildings()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("id", 0)) < int(b.get("id", 0)))
	var intended_cash: float = CompanyManager.player.cash
	CompanyManager.player.cash = maxf(intended_cash, 1000000000.0)
	for candidate: Dictionary in candidates:
		if RestaurantManager.owned.size() >= target_count:
			break
		var building_id: int = int(candidate.get("id", -1))
		if building_id < 0:
			continue
		RestaurantManager.purchase_location(
			CompanyManager.player.id, building_id,
			"%s %d" % [player_name, RestaurantManager.owned.size() + 1])
	CompanyManager.player.cash = intended_cash
	EconomyManager.announce_state()
