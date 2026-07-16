class_name PermitDef
extends Resource
## Catalog entry for a company permit (data/permits/*.tres). Permits renew on
## a cadence; a lapsed gating permit suspends the named sales channel until
## renewed (handled by GovernmentManager, not RestaurantState).

@export var id: StringName = &""
@export var display_name: String = ""
@export var blurb: String = ""
@export var icon: StringName = &"permit"
@export var cost: float = 500.0
@export var renewal_days: int = 42
## Channel suspended while lapsed: &"" (none) | &"dine_in" | &"delivery"
@export var gates_channel: StringName = &""
## Minimum HQ government capability tier before this permit is offered (0 = always).
@export var required_min_tier: int = 0
