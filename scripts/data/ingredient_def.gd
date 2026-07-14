class_name IngredientDef
extends Resource
## Static definition of a recipe ingredient. New ingredients are added by
## dropping a .tres file into data/ingredients/ — no code changes needed.

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = &"veg"  ## &"sauce" &"cheese" &"veg" &"meat" &"extra"
@export var unit_cost: float = 0.25
@export var prep_mod: float = 0.2  ## minutes added per portion
@export var quality: float = 0.5  ## 0..1 baseline quality contribution
@export_group("Traits")
@export var nutrition: float = 0.5
@export var spice: float = 0.0
@export var oil: float = 0.2
@export var novelty: float = 0.1
@export_group("Compatibility")
@export var compatible_tiers: Array[StringName] = []  ## empty = all tiers
@export var products: Array[StringName] = [&"pizza", &"burger"]
@export var roles: Array[StringName] = [&"topping"]  ## &"sauce" &"cheese" &"topping" &"patty" &"layer" &"spread"
@export_group("Visuals")
@export var swatch_color: Color = Color(0.8, 0.6, 0.4)
@export var marker_shape: StringName = &"dot"  ## &"dot" &"ring" &"square" &"triangle" — color-independent marker
@export_group("Appeal")
## Per-demographic affinity, -1..1. Keys: teens, students, workers, families, seniors.
@export var affinity: Dictionary = {}


func affinity_for(segment: StringName) -> float:
	return float(affinity.get(segment, 0.0))


func allows_product(product_type: StringName) -> bool:
	return products.is_empty() or products.has(product_type)


func allows_role(role: StringName) -> bool:
	return roles.has(role)
