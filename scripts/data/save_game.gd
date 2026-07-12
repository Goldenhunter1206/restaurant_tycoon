class_name SaveGame
extends Resource
## Serializable snapshot of a play session. In-flight orders are not saved —
## kitchens restart empty on load.

@export var save_version: int = 2
@export var day: int = 1
@export var game_hours: float = 7.0
@export var cash: float = 0.0
@export var loan: float = 0.0
@export var reputation: float = 3.0
@export var history: Array[Dictionary] = []
@export var restaurants: Array[RestaurantState] = []
@export var job_market: Array[JobCandidate] = []
@export var next_candidate_uid: int = 1
## citizen_id -> wealth (tastes/wages regenerate deterministically).
@export var citizen_wealth: Dictionary = {}
