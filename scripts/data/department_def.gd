class_name DepartmentDef
extends Resource
## A headquarters specialization with level-by-level costs and capabilities.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var icon_name: StringName = &"gear"
@export var required_tiers: Array[int] = []
@export var project_costs: Array[float] = []
@export var project_minutes: Array[int] = []
@export var total_upkeep: Array[float] = []
@export var grants_by_level: Array[Dictionary] = []
@export var available: bool = true
@export var unavailable_reason: String = ""


func max_level() -> int:
	return project_costs.size()


func required_tier_for(level: int) -> int:
	return required_tiers[level - 1] if level > 0 and level <= required_tiers.size() else 99


func cost_for(level: int) -> float:
	return project_costs[level - 1] if level > 0 and level <= project_costs.size() else 0.0


func minutes_for(level: int) -> int:
	return project_minutes[level - 1] if level > 0 and level <= project_minutes.size() else 0


func upkeep_for(level: int) -> float:
	return total_upkeep[level - 1] if level > 0 and level <= total_upkeep.size() else 0.0


func grants_for(level: int) -> Dictionary:
	return grants_by_level[level - 1].duplicate() if level > 0 and level <= grants_by_level.size() else {}
