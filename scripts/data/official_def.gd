class_name OfficialDef
extends Resource
## Catalog entry for a city official (data/officials/*.tres). Base integrity
## and scrutiny are deterministic-jittered per world seed when the runtime
## OfficialState is created.

@export var id: StringName = &""
@export var display_name: String = ""
@export var blurb: String = ""
@export var icon: StringName = &"people"
@export var role: StringName = &""  ## mayor | food_inspector | labor_inspector | tax_official | police_commander
@export_range(0.0, 1.0) var base_integrity: float = 0.7
@export_range(0.0, 1.0) var base_scrutiny: float = 0.5
## Category weights biasing which checklist findings this official stresses:
## {&"food": w, &"safety": w, &"labor": w, &"paperwork": w}
@export var priorities: Dictionary = {}
## 1 clerk .. 3 mayor — caps which decisions this official can move.
@export_range(1, 3) var authority: int = 1
