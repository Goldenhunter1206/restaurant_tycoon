class_name CompetitionState
extends Resource
## One live or archived competition run. Entries hold frozen RecipeDef
## duplicates made at submit time — later edits to the source recipe can
## never mutate an entry. seed_day freezes the judging RNG at announce time.

@export var uid: int = 0
@export var def_id: StringName = &""
@export var status: StringName = &"announced"  ## announced entry locked judged closed
@export var announced_day: int = 0
@export var deadline_day: int = 0
@export var judging_day: int = 0
@export var seed_day: int = 0
@export var challenger_id: StringName = &""
@export var challengee_id: StringName = &""
@export var entries: Array[Dictionary] = []  ## {company_id, recipe: RecipeDef, tier, entry_day}
@export var results: Array[Dictionary] = []  ## per entry: rank + every scoring component
@export var winner_company_id: StringName = &""
@export var event_log: Array[Dictionary] = []  ## {day, text}
@export var reward_applied: bool = false


func entry_for(company_id_in: StringName) -> Dictionary:
	for entry: Dictionary in entries:
		if StringName(entry.get("company_id", &"")) == company_id_in:
			return entry
	return {}


func has_entry(company_id_in: StringName) -> bool:
	return not entry_for(company_id_in).is_empty()
