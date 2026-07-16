class_name AwardDef
extends Resource
## Catalog entry for a periodic city award (data/awards/*.tres). Scoring
## weights reference rating dimensions (food, service, ...) or analytics
## metrics (sales, guests, deliveries, ...); AwardEvaluator normalizes each
## component across nominees before weighting.

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = &"premium"  ## premium value service delivery recipe clean newcomer
@export var cadence: StringName = &"quarter"
@export var blurb: String = ""
@export var icon: StringName = &"trophy"
## Eligibility keys: min_age_days, max_age_days, min_stars, requires_delivery, min_guests.
@export var eligibility: Dictionary = {}
## {component: weight} — components are rating dims or analytics metric ids.
@export var scoring: Dictionary = {}
@export var tiebreak_metric: StringName = &"guests"
@export var reward_cash: float = 0.0
@export var reward_reputation: float = 0.0
@export var reward_trend_days: int = 0
