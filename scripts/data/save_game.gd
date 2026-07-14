class_name SaveGame
extends Resource
## Serializable snapshot of a play session (format v4: multi-company).
## In-flight orders are not saved — kitchens restart empty on load.

@export var save_version: int = 4
@export var day: int = 1
@export var game_hours: float = 7.0
## Every competing company (player + rivals), each carrying its own finances,
## restaurants and — player only — recipe book. Empty means pre-v4 save;
## pre-v4 saves are not migrated and load as "incompatible".
@export var companies: Array[CompanyState] = []
@export var active_campaigns: Array[MarketingCampaign] = []
@export var job_market: Array[JobCandidate] = []
@export var next_candidate_uid: int = 1
## citizen_id -> wealth (tastes/wages regenerate deterministically).
@export var citizen_wealth: Dictionary = {}
## World seed chosen in the New Game Wizard (drives AI determinism).
@export var world_seed: int = 0
@export var difficulty: StringName = &"medium"
