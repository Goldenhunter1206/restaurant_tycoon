class_name CompetitionDef
extends Resource
## Catalog entry for a recipe competition (data/competitions/*.tres).
## cadence_days > 0 auto-announces on the city calendar; 0 = challenge-only.

@export var id: StringName = &""
@export var display_name: String = ""
@export var brief: String = ""
@export var icon: StringName = &"trophy"
@export var product_type: StringName = &""  ## &"" = any
@export var target_demographics: Array[StringName] = []
## Constraint keys: max_price, max_cost, min_components, max_components, require_ingredient.
@export var constraints: Dictionary = {}
@export var entry_fee: float = 0.0
@export var reward_cash: float = 0.0
@export var reward_reputation: float = 0.0
@export var reward_trend_days: int = 0
## weights {recipe, compliance, novelty} + noise_range (disclosed judging range).
@export var judging: Dictionary = {}
@export var entry_window_days: int = 4
@export var judging_day_offset: int = 2
@export var cadence_days: int = 0
@export var cadence_offset: int = 0
