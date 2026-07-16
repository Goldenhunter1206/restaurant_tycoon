class_name DevelopmentProjectDef
extends Resource
## Catalog entry for a city development proposal (data/development_projects/).
## demand_delta feeds DemandManager's per-district attraction term once the
## project is BUILT; demographic_shift nudges who shows up in the district.

@export var id: StringName = &""
@export var display_name: String = ""
@export var blurb: String = ""
@export var icon: StringName = &"city_hall"
@export var kind: StringName = &"attraction"  ## attraction | transit | housing | industry | entertainment
## "" = the proposal rolls a district when announced.
@export var target_district: String = ""
## Additive attraction bonus for restaurants in the district (can be negative).
@export_range(-0.3, 0.3) var demand_delta: float = 0.1
## Demographic weight nudges, e.g. {&"families": 0.1, &"workers": -0.05}.
@export var demographic_shift: Dictionary = {}
## Reference lobbying sum at which support stops mattering much.
@export var support_cost_base: float = 1500.0
@export var decision_days: int = 14
@export var build_days: int = 7
@export var sponsors_allowed: bool = true
