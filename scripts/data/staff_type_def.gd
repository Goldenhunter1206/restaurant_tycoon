class_name StaffTypeDef
extends Resource
## Static definition of a hireable staff role. New roles are added by dropping
## a .tres file into data/staff_types/.

@export var id: StringName = &""
@export var display_name: String = ""
## Legacy pre-v2 field, superseded by base_hourly_wage.
@export var base_daily_wage: float = 60.0
@export var base_hourly_wage: float = 8.0
## Attribute keys candidates of this role roll (0..1 each), e.g. &"speed".
@export var attribute_keys: Array[StringName] = []
## Role capabilities — a role may provide any combination of these.
@export var cook_slots: int = 0
@export var waiter_customers_per_hour: float = 0.0
@export var is_driver: bool = false
