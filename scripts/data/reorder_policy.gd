class_name ReorderPolicy
extends Resource
## Per-ingredient restocking rules for one inventory. The reorder engine
## drafts purchase orders when available + inbound falls below reorder_point.

@export var ingredient_id: StringName = &""
## Portions on hand (available + inbound) that trigger a reorder.
@export var reorder_point: float = 0.0
## Portions the reorder tops the inventory back up to.
@export var target_stock: float = 0.0
## Empty = cheapest supplier that carries the ingredient.
@export var preferred_supplier: StringName = &""
@export_range(0.0, 1.0) var min_quality: float = 0.0
## &"emergency_buy" | &"substitute" | &"disable" | &"delay" — what cooking
## does when stock runs out anyway.
@export var emergency_behavior: StringName = &"emergency_buy"
## &"recommend" | &"approve" | &"automatic" — how much the engine may do alone.
@export var mode: StringName = &"automatic"
