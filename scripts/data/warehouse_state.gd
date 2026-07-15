class_name WarehouseState
extends Resource
## One company-owned warehouse on an industrial building. Identity is
## anchored to world_pos, NOT building_id — building ids reshuffle when the
## city is rebaked (AdPlacement precedent); building_id is re-resolved to the
## nearest industrial building on load.

@export var id: int = 0
@export var company_id: StringName = &""
@export var building_id: int = -1
@export var world_pos: Vector3 = Vector3.ZERO
@export var display_name: String = "Warehouse"
@export var district: String = "I"
## 1..MAX_LEVEL — scales capacity and daily cost.
@export var expansion_level: int = 1
@export var inventory: InventoryState = null
@export var assigned_restaurant_ids: Array[int] = []
@export var purchase_price: float = 0.0
@export var purchased_day: int = 0

const MAX_LEVEL: int = 3
## Capacity units per storage class at level 1; each level multiplies by 2.
const BASE_CAPACITY: Dictionary = {&"dry": 4000.0, &"chilled": 2000.0, &"frozen": 1500.0}
const BASE_DAILY_COST: float = 90.0


func capacity_for(storage_class: StringName) -> float:
	var base: float = float(BASE_CAPACITY.get(storage_class, 0.0))
	return base * pow(2.0, float(expansion_level - 1))


func total_capacity() -> float:
	var total: float = 0.0
	for key: StringName in BASE_CAPACITY.keys():
		total += capacity_for(key)
	return total


func daily_cost() -> float:
	return BASE_DAILY_COST * float(expansion_level)


func upgrade_cost() -> float:
	return 6000.0 * float(expansion_level)
