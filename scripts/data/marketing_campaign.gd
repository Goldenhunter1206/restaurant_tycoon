class_name MarketingCampaign
extends Resource
## One running ad campaign: boosts offer utility for citizens near a branch.
## Paid daily by the owning company; expires when days_left hits zero.

@export var company_id: StringName = &"player"
@export var building_id: int = -1
## Empty targets every demographic.
@export var demographic: StringName = &""
@export var radius: float = 400.0
@export var utility_bonus: float = 0.15
@export var cost_per_day: float = 150.0
@export var days_left: int = 7
