class_name HeadquartersState
extends Resource
## Serializable headquarters property and progression for one company.

@export var company_id: StringName = &""
@export var building_id: int = -1
@export var tier: int = 0
@export var departments: Dictionary = {}
@export var capacity_used: int = 0
@export var staff_ids: Array[int] = []
@export var security: float = 0.0
@export var condition: float = 1.0
@export var active_projects: Array[UpgradeProjectState] = []
@export var known_intelligence: Dictionary = {}
@export var migration_state: StringName = &"new_game"
@export var migration_notice_pending: bool = false
@export var capital_invested: float = 0.0
@export var next_project_id: int = 1


func active_project() -> UpgradeProjectState:
	return active_projects[0] if not active_projects.is_empty() else null


func has_active_project() -> bool:
	return not active_projects.is_empty()


func department_level(department_id: StringName) -> int:
	return int(departments.get(department_id, 0))


func is_active() -> bool:
	return tier > 0 and building_id >= 0
