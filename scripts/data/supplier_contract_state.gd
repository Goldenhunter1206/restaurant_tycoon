class_name SupplierContractState
extends Resource
## Live relationship between one company and one supplier: negotiated terms
## plus service history. Created lazily on first order; a signed contract
## adds a discount and routes recurring deliveries to a warehouse.

@export var company_id: StringName = &""
@export var supplier_id: StringName = &""
## Signed contracts get a discount on SupplierDef.price_mult (1.0 = none).
@export var discount_mult: float = 1.0
@export var signed: bool = false
@export var signed_day: int = 0
## Preferred destination for contract deliveries. -1 = per-order choice.
@export var warehouse_dest_id: int = -1
@export_group("Service history")
@export var deliveries_total: int = 0
@export var deliveries_on_time: int = 0
@export var deliveries_late: int = 0
@export var deliveries_failed: int = 0
## 0..1, drifts with service outcomes and order volume (phase 4).
@export var relationship: float = 0.5


func on_time_rate() -> float:
	if deliveries_total <= 0:
		return 1.0
	return float(deliveries_on_time) / float(deliveries_total)
