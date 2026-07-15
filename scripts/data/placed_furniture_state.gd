@tool
class_name PlacedFurnitureState
extends Resource
## One furniture instance inside a restaurant layout. Persisted with the
## save; runtime scene nodes are regenerated from this and never authoritative.
## Sim state (orders, condition decay) is keyed by instance_id, which stays
## stable across moves, saves and visual rebuilds.

@export var instance_id: int = 0
@export var def_id: StringName = &""
## Min (top-left) occupied cell in layout grid coordinates.
@export var cell: Vector2i = Vector2i.ZERO
## Yaw in degrees: 0, 90, 180 or 270.
@export var rotation: int = 0
## Colorway variant id; empty = the def's default model.
@export var variant: StringName = &""
@export var durability: float = 100.0
@export_range(0.0, 1.0) var cleanliness: float = 1.0
@export var enabled: bool = true


func duplicate_state() -> PlacedFurnitureState:
	var copy: PlacedFurnitureState = PlacedFurnitureState.new()
	copy.instance_id = instance_id
	copy.def_id = def_id
	copy.cell = cell
	copy.rotation = rotation
	copy.variant = variant
	copy.durability = durability
	copy.cleanliness = cleanliness
	copy.enabled = enabled
	return copy


func condition() -> float:
	## 0..1 blend of durability and cleanliness used by appeal/resale.
	return clampf(durability / 100.0, 0.0, 1.0) * (0.6 + 0.4 * cleanliness)
