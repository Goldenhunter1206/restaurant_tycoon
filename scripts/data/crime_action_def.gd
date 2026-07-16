class_name CrimeActionDef
extends Resource
## Catalog entry for an underworld action (data/crime_actions/*.tres).
## Effects are freeform keys interpreted by CrimeManager when the operation
## resolves; CrimeResolver only consumes the success/evidence weights.
## Countermeasures are shown in the UI review rail and damp success/evidence.

@export var id: StringName = &""
@export var display_name: String = ""
@export var blurb: String = ""
@export var icon: StringName = &"mask"
@export_range(1, 3) var tier: int = 1  ## 1 nuisance, 2 operational sabotage, 3 violent
@export var target_kind: StringName = &"restaurant"  ## restaurant | company
@export var required_dept_level: int = 1  ## Underworld department level required
@export var required_roles: Dictionary = {}  ## {role: count} e.g. {&"punk": 1}
@export var cost: float = 0.0
@export var prep_minutes: int = 240
@export var exec_minutes: int = 60
@export var base_success: float = 0.6
@export var skill_weight: float = 0.25
@export var security_weight: float = 0.35
## Effect keys (interpreted in CrimeManager._apply_effects): appeal_debuff,
## demand_debuff, effect_days, reputation_hit, clean_hit, station_count,
## stock_spoil_fraction, disruption_kind, disruption_days, loyalty_hit,
## stress_hit, injury_chance, closure_days, cash_steal, extort_factor,
## intel_days, inspection_bias, durability_hit, ransom_factor.
@export var effects: Dictionary = {}
@export var evidence_base: float = 0.2
@export var heat_base: float = 4.0
@export var cooldown_days: int = 3  ## per attacker→target pair
@export var countermeasures: Array[StringName] = []  ## guards cameras alert counterintel insurance
@export var min_crime_mode: StringName = &"standard"  ## standard | ruthless


func allowed_in_mode(mode: StringName) -> bool:
	if min_crime_mode == &"ruthless":
		return mode == &"ruthless"
	return mode == &"standard" or mode == &"ruthless"
