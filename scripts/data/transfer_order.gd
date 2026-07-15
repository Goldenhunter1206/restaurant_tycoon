class_name TransferOrder
extends Resource
## Moves stock from a company warehouse to one of its restaurants. Lots are
## picked FEFO at departure; while in transit the goods ride inside `lines`
## as concrete lot snapshots so quality/cost/expiry survive the trip.

@export var id: int = 0
@export var company_id: StringName = &""
@export var from_warehouse_id: int = 0
@export var dest_restaurant_id: int = 0
## [{ingredient_id, qty, unit_cost, quality, expiry_minute, supplier_id}].
@export var lines: Array[Dictionary] = []
@export var status: StringName = &"pending"  ## &"pending" &"in_transit" &"delivered" &"cancelled"
@export var created_minute: int = 0
@export var eta_minute: int = 0
## Vehicle cost charged on departure.
@export var cost: float = 0.0
## True while a live truck agent drives this transfer (else pure timer).
@export var vehicle_visible: bool = false
@export var auto_generated: bool = false


func total_qty() -> float:
	var total: float = 0.0
	for line: Dictionary in lines:
		total += float(line.get("qty", 0.0))
	return total


func is_open() -> bool:
	return status == &"pending" or status == &"in_transit"
