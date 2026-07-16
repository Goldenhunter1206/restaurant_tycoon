class_name AwardResult
extends Resource
## Finalized outcome of one award period or competition medal. Nominee
## breakdowns store every scoring component so the result can be reproduced
## from finalized metrics (never recomputed from live state).

@export var award_id: StringName = &""
@export var display_name: String = ""
@export var kind: StringName = &"award"  ## &"award" | &"medal"
@export var period: int = 0  ## quarter index (awards) or competition uid (medals)
@export var period_label: String = ""
@export var day: int = 0
@export var winner_company_id: StringName = &""
@export var winner_building_id: int = -1
@export var winner_name: String = ""
@export var nominees: Array[Dictionary] = []  ## {company_id, building_id, name, score, breakdown}
@export var explanation: String = ""
@export var reward: Dictionary = {}
@export var disputed: bool = false
