class_name OfficialState
extends Resource
## Runtime state of one city official (seeded from OfficialDef, persisted).
## Integrity resists bribes; scrutiny scales inspection zeal; relationship is
## per-company goodwill moved by donations, sponsorships and violations.

@export var def_id: StringName = &""
@export var role: StringName = &""  ## mayor | food_inspector | labor_inspector | tax_official | police_commander
@export var display_name: String = ""
@export_range(0.0, 1.0) var integrity: float = 0.7
@export_range(0.0, 1.0) var scrutiny: float = 0.5
## Category weights biasing which checklist findings this official stresses.
@export var priorities: Dictionary = {}
## company_id (String) -> -1..1 goodwill.
@export var relationship: Dictionary = {}


func relationship_for(company_id: StringName) -> float:
	return float(relationship.get(String(company_id), 0.0))


func adjust_relationship(company_id: StringName, delta: float) -> void:
	var key: String = String(company_id)
	relationship[key] = clampf(float(relationship.get(key, 0.0)) + delta, -1.0, 1.0)
