class_name StockLot
extends Resource
## One batch of a single ingredient inside an InventoryState. Lots keep
## quality/cost/freshness auditable; consumption is FEFO (first expiring
## first). All timestamps are absolute game minutes (GameClock.total_minutes).

@export var ingredient_id: StringName = &""
@export var qty: float = 0.0
@export var quality: float = 0.5
@export var acquired_minute: int = 0
@export var expiry_minute: int = 0
@export var unit_cost: float = 0.0
@export var supplier_id: StringName = &""
## Portion count promised to accepted-but-not-yet-cooked orders.
@export var reserved: float = 0.0


func available() -> float:
	return maxf(qty - reserved, 0.0)


func is_expired(now_minute: int) -> bool:
	return expiry_minute <= now_minute


## 1.0 fresh -> 0.0 at expiry.
func freshness(now_minute: int) -> float:
	var life: int = expiry_minute - acquired_minute
	if life <= 0:
		return 0.0
	return clampf(float(expiry_minute - now_minute) / float(life), 0.0, 1.0)
