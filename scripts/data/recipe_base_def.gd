class_name RecipeBaseDef
extends Resource
## A dough/bun/base option for a custom recipe. Added by dropping a .tres
## file into data/recipe_bases/ — no code changes needed.

@export var id: StringName = &""
@export var display_name: String = ""
@export var product_type: StringName = &"pizza"  ## &"pizza" | &"burger"
@export var assembly_mode: StringName = &"surface"  ## &"surface" | &"stack"
@export var base_cost: float = 0.6
@export var base_prep_minutes: float = 8.0
@export var station_id: StringName = &""  ## Phase-4 hook (pizza_oven/grill); stored, unused for now
@export var capacity_cost: int = 1  ## kitchen-slot weight
@export var size_scale: float = 1.0  ## pizza canvas radius / burger width factor
## Per-demographic base preference, -1..1. Keys: teens, students, workers, families, seniors.
@export var affinity: Dictionary = {}


func affinity_for(segment: StringName) -> float:
	return float(affinity.get(segment, 0.0))
