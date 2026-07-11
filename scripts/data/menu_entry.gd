class_name MenuEntry
extends Resource
## One line on a restaurant's menu: which dish, at which ingredient-quality
## tier, at what player-set price.

@export var dish_id: StringName = &""
@export var tier: StringName = &"med"
@export var price: float = 8.0
@export var enabled: bool = true
