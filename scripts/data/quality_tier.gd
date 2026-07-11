class_name QualityTier
extends Resource
## One ingredient-quality option for a dish: what it costs us per serving and
## how much it contributes to perceived quality/reputation.

@export var tier: StringName = &"med"
@export var display_name: String = "Standard"
@export var ingredient_cost: float = 2.0
@export var quality_score: float = 0.5
