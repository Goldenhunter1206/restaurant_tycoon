class_name RestaurantRatingState
extends Resource
## Per-branch external evaluation state (feature 11). Dimensions are rolling
## 0..100 means over the sample window; `composite` is the merit score (1..5)
## and `star_ceiling` the inspection-certified tier that caps the public
## star rating. Sampling happens only at day close (AwardsManager) — opening
## panels or reloading never changes these values.

const DIMENSION_KEYS: Array[StringName] = [
	&"food", &"service", &"atmosphere", &"cleanliness", &"value", &"consistency",
]

@export var building_id: int = -1
@export var company_id: StringName = &""
@export var dimensions: Dictionary = {}  ## {dim: 0..100 rolling mean}
@export var composite: float = 3.0  ## 1..5 merit score (uncapped by ceiling)
@export var star_ceiling: int = 3  ## inspection-certified 1..5
@export var days_at_target: int = 0  ## consecutive days qualifying for the next star
@export var loss_countdown: int = 0  ## consecutive days below the loss threshold
@export var warned: bool = false
@export var samples: Array[Dictionary] = []  ## raw daily {day, dims}
@export var history: Array[Dictionary] = []  ## {day, composite, stars, dimensions}
@export var inspections: Array[Dictionary] = []  ## {day, score, level, passed, leniency}
@export var next_inspection_day: int = 0
@export var opened_day: int = 1


func dim(key: StringName) -> float:
	return float(dimensions.get(key, 50.0))


func last_inspection() -> Dictionary:
	return {} if inspections.is_empty() else inspections[-1]
