class_name InventoryState
extends Resource
## Stock held by one restaurant or warehouse: lots, capacity, policies and
## audit totals. Lot math (reserve/consume/spoil) lives in InventoryService;
## this resource only stores state and cheap queries so it serializes whole
## inside the save (interior_layout precedent).

@export var owner_kind: StringName = &"restaurant"  ## &"restaurant" | &"warehouse"
@export var owner_id: int = 0
## storage_class -> capacity units. Empty = unlimited (legacy grace).
@export var capacity_by_class: Dictionary = {}
@export var lots: Array[StockLot] = []
## ingredient_id -> ReorderPolicy.
@export var policies: Dictionary = {}
@export_group("Audit")
@export var total_bought: float = 0.0
@export var total_consumed: float = 0.0
@export var total_wasted: float = 0.0
## ingredient_id -> portions consumed since day start (feeds forecast EWMA).
@export var consumed_today: Dictionary = {}
## ingredient_id -> smoothed daily consumption (EWMA, phase 4 forecast).
@export var daily_use: Dictionary = {}


func on_hand(ingredient_id: StringName) -> float:
	var total: float = 0.0
	for lot: StockLot in lots:
		if lot.ingredient_id == ingredient_id:
			total += lot.qty
	return total


func reserved_qty(ingredient_id: StringName) -> float:
	var total: float = 0.0
	for lot: StockLot in lots:
		if lot.ingredient_id == ingredient_id:
			total += lot.reserved
	return total


func available(ingredient_id: StringName) -> float:
	var total: float = 0.0
	for lot: StockLot in lots:
		if lot.ingredient_id == ingredient_id:
			total += lot.available()
	return total


## Lots of one ingredient, first-expiring first.
func lots_for(ingredient_id: StringName) -> Array[StockLot]:
	var found: Array[StockLot] = []
	for lot: StockLot in lots:
		if lot.ingredient_id == ingredient_id:
			found.append(lot)
	found.sort_custom(func(a: StockLot, b: StockLot) -> bool: return a.expiry_minute < b.expiry_minute)
	return found


func ingredient_ids() -> Array[StringName]:
	var seen: Dictionary = {}
	var ids: Array[StringName] = []
	for lot: StockLot in lots:
		if not seen.has(lot.ingredient_id):
			seen[lot.ingredient_id] = true
			ids.append(lot.ingredient_id)
	return ids


## Capacity units used inside one storage class (needs the item catalog to
## map ingredient -> class/volume, so the caller passes a lookup Callable).
func used_volume(storage_class: StringName, class_of: Callable, volume_of: Callable) -> float:
	var used: float = 0.0
	for lot: StockLot in lots:
		if class_of.call(lot.ingredient_id) == storage_class:
			used += lot.qty * float(volume_of.call(lot.ingredient_id))
	return used


func policy_for(ingredient_id: StringName) -> ReorderPolicy:
	return policies.get(ingredient_id, null)


## Weighted average quality of what is on hand (UI display).
func avg_quality(ingredient_id: StringName) -> float:
	var qty_sum: float = 0.0
	var weighted: float = 0.0
	for lot: StockLot in lots:
		if lot.ingredient_id == ingredient_id:
			qty_sum += lot.qty
			weighted += lot.qty * lot.quality
	return weighted / qty_sum if qty_sum > 0.0 else 0.0


## Earliest expiry among lots of one ingredient (0 = none held).
func next_expiry(ingredient_id: StringName) -> int:
	var best: int = 0
	for lot: StockLot in lots:
		if lot.ingredient_id == ingredient_id and lot.qty > 0.0:
			if best == 0 or lot.expiry_minute < best:
				best = lot.expiry_minute
	return best
