class_name SaveGame
extends Resource
## Serializable snapshot of a play session. In-flight orders are not saved —
## kitchens restart empty on load.

@export var save_version: int = 1
@export var day: int = 1
@export var game_hours: float = 7.0
@export var cash: float = 0.0
@export var loan: float = 0.0
@export var reputation: float = 3.0
@export var history: Array[Dictionary] = []
@export var restaurants: Array[RestaurantState] = []
## citizen_id -> wealth (tastes/wages regenerate deterministically).
@export var citizen_wealth: Dictionary = {}
