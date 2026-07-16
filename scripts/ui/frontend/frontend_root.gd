class_name FrontendRoot
extends Control
## Frontend shell: Title → Wizard → Briefing → Simulation. GameClock remains
## paused until a committed session launches.

const MAIN_SCENE: String = "res://scenes/Main.tscn"

var _current: Control = null


func _ready() -> void:
	if not is_instance_valid(GameSetup) or not is_instance_valid(GameClock):
		return
	theme = TycoonTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameClock.set_speed(0)
	var backdrop: ColorRect = _wood_backdrop()
	add_child(backdrop)
	var pending_intro: bool = _game_setup_has_property(&"pending_intro") and bool(GameSetup.get("pending_intro"))
	var current_config: Variant = GameSetup.get("session_config") if _game_setup_has_property(&"session_config") else null
	if pending_intro and current_config is GameSessionConfig:
		GameSetup.set("pending_intro", false)
		show_intro(current_config as GameSessionConfig)
	else:
		show_title()


func _wood_backdrop() -> ColorRect:
	var shader: Shader = Shader.new()
	shader.code = """shader_type canvas_item;
void fragment() {
    vec2 uv = UV;
    float radial = distance(uv, vec2(0.42, 0.42));
    float wave = sin((uv.y + sin(uv.x * 11.0) * 0.012) * 175.0);
    float fine = sin((uv.y + sin(uv.x * 29.0) * 0.004) * 520.0);
    float grain = wave * 0.035 + fine * 0.012;
    vec3 heart = vec3(0.431, 0.239, 0.094);
    vec3 edge = vec3(0.165, 0.086, 0.031);
    vec3 wood = mix(heart, edge, smoothstep(0.08, 0.82, radial));
    float vignette = smoothstep(0.48, 0.92, distance(uv, vec2(0.5)));
    wood = wood + grain - vignette * 0.055;
    COLOR = vec4(wood, 1.0);
}
"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color.WHITE
	backdrop.material = material
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return backdrop


func _game_setup_has_property(property_name: StringName) -> bool:
	for property: Dictionary in GameSetup.get_property_list():
		if StringName(String(property.get("name", ""))) == property_name:
			return true
	return false


func show_title() -> void:
	_swap(load("res://scripts/ui/frontend/title_screen.gd").new())


func show_wizard(config: GameSessionConfig = null) -> void:
	var wizard: Control = load("res://scripts/ui/frontend/new_game_wizard.gd").new()
	if config != null and wizard.has_method("setup"):
		wizard.call("setup", config)
	_swap(wizard)


func show_intro(config: GameSessionConfig = null) -> void:
	var intro_config: GameSessionConfig = config
	if intro_config == null:
		var current: Variant = GameSetup.get("session_config")
		if current is GameSessionConfig:
			intro_config = current as GameSessionConfig
	var intro: Control = load("res://scripts/ui/frontend/scenario_intro_screen.gd").new()
	if intro_config != null and intro.has_method("setup"):
		intro.call("setup", intro_config)
	_swap(intro)


func show_load() -> void:
	_swap(load("res://scripts/ui/frontend/load_screen.gd").new())


## Launches the already-committed session from its mission briefing.
func start_new_game() -> void:
	GameSetup.from_save = false
	GameSetup.configured = true
	if GameSetup.world_seed == 0:
		GameSetup.randomize_seed()
	_launch()


## Boots the saved session when a compatible session save exists.
func load_saved_game() -> void:
	GameSetup.reset()
	GameSetup.from_save = true
	_launch()


func _launch() -> void:
	GameClock.set_speed(1)
	get_tree().change_scene_to_file(_session_scene_path())


func _session_scene_path() -> String:
	var config: Variant = GameSetup.get("session_config")
	var catalog: Variant = GameSetup.get("catalog")
	if config == null or catalog == null or not catalog.has_method("city"):
		return MAIN_SCENE
	var city: Dictionary = catalog.call("city", config.get("city_id")) as Dictionary
	var scene_path: String = String(city.get("session_scene", MAIN_SCENE))
	return scene_path if ResourceLoader.exists(scene_path) else MAIN_SCENE


func _swap(next: Control) -> void:
	if _current != null:
		remove_child(_current)
		_current.queue_free()
	_current = next
	add_child(next)
	next.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
