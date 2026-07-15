class_name StaffTypeDef
extends Resource
## Static definition of a hireable role loaded from data/staff_types/.

@export var schema_version: int = 2
@export var id: StringName = &""
@export var display_name: String = ""
## Legacy pre-v2 field, superseded by base_hourly_wage.
@export var base_daily_wage: float = 60.0
@export var base_hourly_wage: float = 8.0
## Competencies candidates of this role roll (0..1 each).
@export var attribute_keys: Array[StringName] = []
@export var competency_keys: Array[StringName] = []
## Existing direct capabilities.
@export var cook_slots: int = 0
@export var waiter_customers_per_hour: float = 0.0
@export var is_driver: bool = false
## Workforce-foundation responsibilities; all effects remain tuning-capped.
@export var is_manager: bool = false
@export var stock_handling_per_hour: float = 0.0
@export var cleaning_per_hour: float = 0.0
@export var operational_tags: Array[StringName] = []
@export var promotion_from_roles: Array[StringName] = []
@export var minimum_experience_for_promotion: float = 0.0


func all_competency_keys() -> Array[StringName]:
	return competency_keys if not competency_keys.is_empty() else attribute_keys
