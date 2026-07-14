class_name RecipeDef
extends Resource
## A player- or starter-authored recipe. Starter recipes live as .tres in
## data/recipes/starters/ and reuse legacy dish ids; player recipes exist only
## inside RecipeBookState (serialized with the save). Components are the
## source of truth — cached_* fields are display accelerators recomputed by
## RecipeManager on load and on every edit.

@export var id: StringName = &""  ## starter ids or "rcp_%06d"
@export var owner_company_id: StringName = &"player"
@export var display_name: String = ""
@export var product_type: StringName = &"pizza"  ## &"pizza" | &"burger"
@export var base_id: StringName = &""
@export var components: Array[RecipeComponent] = []
@export var suggested_price: float = 0.0  ## 0 = auto (cost-based)
@export var version: int = 1
@export var created_day: int = 0
@export var unlock_source: StringName = &"custom"  ## &"starter" &"custom" &"competition"
@export var is_starter: bool = false
@export var archived: bool = false
@export_group("Cached (derived, never authoritative)")
@export var cached_cost: float = 0.0
@export var cached_prep: float = 0.0
@export var cached_appeal: Dictionary = {}  ## {segment: 0..1}
@export var cached_structure: float = 1.0  ## burger stability 0..1 (1 = stable)


func sorted_stack() -> Array[RecipeComponent]:
	var stack: Array[RecipeComponent] = []
	for c: RecipeComponent in components:
		stack.append(c)
	stack.sort_custom(func(a: RecipeComponent, b: RecipeComponent) -> bool:
		return a.stack_index < b.stack_index)
	return stack


func duplicate_recipe() -> RecipeDef:
	var copy: RecipeDef = RecipeDef.new()
	copy.id = id
	copy.owner_company_id = owner_company_id
	copy.display_name = display_name
	copy.product_type = product_type
	copy.base_id = base_id
	for c: RecipeComponent in components:
		copy.components.append(c.duplicate_component())
	copy.suggested_price = suggested_price
	copy.version = version
	copy.created_day = created_day
	copy.unlock_source = unlock_source
	copy.is_starter = is_starter
	copy.archived = archived
	copy.cached_cost = cached_cost
	copy.cached_prep = cached_prep
	copy.cached_appeal = cached_appeal.duplicate()
	copy.cached_structure = cached_structure
	return copy
