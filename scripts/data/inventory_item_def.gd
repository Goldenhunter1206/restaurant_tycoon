class_name InventoryItemDef
extends Resource
## Storage/logistics profile for one ingredient. Pairs with IngredientDef
## (same id) — that file owns cost/appeal, this one owns how the ingredient
## behaves as physical stock. Loaded from data/inventory_items/*.tres.

@export var id: StringName = &""
## &"dry" | &"chilled" | &"frozen" — decides which capacity pool a lot uses.
@export var storage_class: StringName = &"dry"
## Game minutes a fresh lot lasts before it expires (1 day = 1440).
@export var shelf_life_minutes: int = 10080
## Capacity units one portion occupies in an inventory.
@export var unit_volume: float = 1.0
## Ingredient ids that may stand in when this one runs out (phase 4).
@export var substitutes: Array[StringName] = []
## Display unit for UI copy ("portions", "kg", ...).
@export var display_unit: String = "portions"


func expiry_for(acquired_minute: int) -> int:
	return acquired_minute + shelf_life_minutes
