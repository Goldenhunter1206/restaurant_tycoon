extends Node
## Carries New Game Wizard choices (or load intent) across the scene change
## from the frontend into Main.tscn. Autoload, so it survives
## change_scene_to_file. `configured` stays false when the game boots straight
## into Main.tscn (dev flow) — managers then fall back to tuning defaults.

var from_save: bool = false
var mode: StringName = &"free_play"
var player_name: String = ""
var player_color: Color = Color("#EA4A2F")
var city_id: StringName = &"riverside"
var world_seed: int = 0
var difficulty: StringName = &"medium"
var selected_rivals: Array[StringName] = []
var configured: bool = false


func randomize_seed() -> void:
	world_seed = randi()


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
