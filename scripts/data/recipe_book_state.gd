class_name RecipeBookState
extends Resource
## The company recipe book: live recipes (including starters injected at
## load), archived frozen versions, and company base-menu defaults.
## Persisted whole inside SaveGame (save_version >= 3).

@export var recipes: Array[RecipeDef] = []
@export var archived: Array[RecipeDef] = []
@export var base_menu_ids: Array[StringName] = []
@export var next_recipe_uid: int = 1
