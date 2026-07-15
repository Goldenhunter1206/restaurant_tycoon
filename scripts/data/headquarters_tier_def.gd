class_name HeadquartersTierDef
extends Resource
## Balance and unlock definition for one headquarters tier.

@export var tier: int = 0
@export var display_name: String = "Founder"
@export var description: String = ""
@export var min_restaurants: int = 0
@export var project_cost: float = 0.0
@export var project_minutes: int = 0
@export var base_upkeep: float = 0.0
@export var department_slots: int = 0
@export var scene_variant: StringName = &"founder"
@export var capability_grants: Dictionary = {}
