class_name RecipeComponent
extends Resource
## One ingredient placement inside a RecipeDef. Components are authoritative;
## all derived recipe values are recomputed from them. Pizza components use the
## normalized surface fields, burger components the stack fields — unused
## fields keep their defaults so one resource serves both product types.

@export var ingredient_id: StringName = &""
@export var role: StringName = &"topping"
@export var quantity: float = 1.0  ## portions (grouped repeated burger layers)
@export var prep_choice: StringName = &"raw"
@export_group("Pizza placement (normalized)")
@export var pos: Vector2 = Vector2(0.5, 0.5)  ## 0..1 within the unit disc
@export var radius: float = 0.25  ## distribution spread 0..1
@export var rotation: float = 0.0
@export var scale: float = 1.0
@export_group("Burger placement")
@export var stack_index: int = 0  ## 0 = just above bottom bun, ascending
@export var thickness: float = 1.0
@export var coverage: float = 0.0  ## sauce/spread coverage 0..1


func duplicate_component() -> RecipeComponent:
	var copy: RecipeComponent = RecipeComponent.new()
	copy.ingredient_id = ingredient_id
	copy.role = role
	copy.quantity = quantity
	copy.prep_choice = prep_choice
	copy.pos = pos
	copy.radius = radius
	copy.rotation = rotation
	copy.scale = scale
	copy.stack_index = stack_index
	copy.thickness = thickness
	copy.coverage = coverage
	return copy
