class_name SupplyDisruption
extends Resource
## A temporary supplier problem (phase 4): outage (orders fail), price spike
## (goods cost up), or delay (lead time stretched). Seeded from
## SupplierDef.disruption_profile; timestamps are absolute game minutes.

@export var supplier_id: StringName = &""
@export var kind: StringName = &"outage"  ## &"outage" | &"price_spike" | &"delay"
## Meaning by kind: price_spike -> cost multiplier, delay -> lead multiplier.
@export var severity: float = 1.5
@export var start_minute: int = 0
@export var end_minute: int = 0
@export var announced: bool = false


func active(now_minute: int) -> bool:
	return now_minute >= start_minute and now_minute < end_minute
