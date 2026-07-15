class_name CityTrend
extends Resource
## A temporary citywide food craze started when promotion exposure crosses a
## threshold. Boosts demand for matching dishes for EVERY company selling
## them — promotion feeds the trend, the trend feeds the market.

@export var recipe_id: StringName = &""
@export var ingredient_id: StringName = &""
@export var display_name: String = ""
## Extra offer-utility for matching dishes while the trend runs.
@export var utility_bonus: float = 0.1
@export var days_left: int = 5
## Company whose campaign tipped the trend (for news/reports).
@export var source_company: StringName = &""


## True when `dish` (a RestaurantState menu id) or its recipe matches.
func matches_recipe(recipe: StringName) -> bool:
	return recipe_id != &"" and recipe == recipe_id
