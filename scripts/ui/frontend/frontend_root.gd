extends Control
## App shell shown before the city loads: hosts the Title screen, the New
## Game Wizard and the Load screen as swappable children. No simulation runs
## here; GameClock is paused until a session starts.

const MAIN_SCENE: String = "res://scenes/Main.tscn"

var _current: Control = null


func _ready() -> void:
	theme = TycoonTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameClock.set_speed(0)
	var backdrop: TextureRect = BellaUi.radial_backdrop()
	add_child(backdrop)
	show_title()


func show_title() -> void:
	_swap(load("res://scripts/ui/frontend/title_screen.gd").new())


func show_wizard() -> void:
	_swap(load("res://scripts/ui/frontend/new_game_wizard.gd").new())


func show_load() -> void:
	_swap(load("res://scripts/ui/frontend/load_screen.gd").new())


## Launches a fresh session from the wizard's collected GameSetup choices.
func start_new_game() -> void:
	GameSetup.from_save = false
	GameSetup.configured = true
	if GameSetup.world_seed == 0:
		GameSetup.randomize_seed()
	_launch()


## Boots the saved session (only reachable when a v4 save exists).
func load_saved_game() -> void:
	GameSetup.reset()
	GameSetup.from_save = true
	_launch()


func _launch() -> void:
	GameClock.set_speed(1)
	get_tree().change_scene_to_file(MAIN_SCENE)


func _swap(next: Control) -> void:
	if _current != null:
		_current.queue_free()
	_current = next
	add_child(next)
	next.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
