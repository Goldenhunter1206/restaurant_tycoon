class_name PurchaseOrder
extends Resource
## One order of ingredients from a supplier to a restaurant or warehouse.
## Lifecycle: draft -> placed -> confirmed -> in_transit -> delivered, with
## failed (supplier offline — order kept, retriable) and cancelled branches.
## Timestamps are absolute game minutes.

const STATUSES: Array[StringName] = [
	&"draft", &"placed", &"confirmed", &"in_transit",
	&"delivered", &"failed", &"cancelled",
]

@export var id: int = 0
@export var company_id: StringName = &""
@export var supplier_id: StringName = &""
@export var dest_kind: StringName = &"restaurant"  ## &"restaurant" | &"warehouse"
@export var dest_id: int = 0
## [{ingredient_id, qty, unit_cost, quality}] — priced at placement.
@export var lines: Array[Dictionary] = []
@export var status: StringName = &"draft"
@export var created_minute: int = 0
@export var eta_minute: int = 0
@export var fee: float = 0.0
@export var is_emergency: bool = false
@export var failure_reason: String = ""
## Set by automatic reorder so the engine can dedupe its own drafts.
@export var auto_generated: bool = false


func goods_cost() -> float:
	var total: float = 0.0
	for line: Dictionary in lines:
		total += float(line.get("qty", 0.0)) * float(line.get("unit_cost", 0.0))
	return total


func total_cost() -> float:
	return goods_cost() + fee


func qty_of(ingredient_id: StringName) -> float:
	var total: float = 0.0
	for line: Dictionary in lines:
		if line.get("ingredient_id", &"") == ingredient_id:
			total += float(line.get("qty", 0.0))
	return total


func is_open() -> bool:
	return status == &"placed" or status == &"confirmed" or status == &"in_transit"
