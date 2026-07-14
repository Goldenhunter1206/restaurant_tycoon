class_name CompetitorProfile
extends Resource
## Personality + difficulty definition for one AI rival company. Behavior
## params are 0-1 biases; difficulty only adjusts information quality and
## reaction speed — never cash or demand bonuses.

@export var id: StringName = &""
@export var display_name: String = ""
@export var brand_color: Color = Color.WHITE
## One-line public descriptor, e.g. "Strength: fastest expansion in the city".
@export var tagline: String = ""
## &"easy" | &"medium" | &"hard" — shown in the competitor picker.
@export var difficulty: StringName = &"medium"

@export_group("Behavior biases")
@export_range(0.0, 1.0) var risk_tolerance: float = 0.5
@export_range(0.0, 1.0) var expansion_appetite: float = 0.5
## Below 0.5 undercuts the market, above 0.5 charges a premium.
@export_range(0.0, 1.0) var price_bias: float = 0.5
@export_range(0.0, 1.0) var quality_bias: float = 0.5
@export_range(0.0, 1.0) var marketing_style: float = 0.4
@export_range(0.0, 1.0) var operational_skill: float = 0.6
@export_range(0.0, 1.0) var aggression: float = 0.5
@export var target_demographics: Array[StringName] = []

@export_group("Difficulty knobs")
## Lower means noisier forecasts and worse rival estimates.
@export_range(0.0, 1.0) var forecast_accuracy: float = 0.7
## Game minutes between deciding on an action and executing it.
@export var reaction_delay_min: int = 240
## Random jitter applied to action scores while planning.
@export_range(0.0, 1.0) var planning_noise: float = 0.2
@export var starting_cash: float = 20000.0
