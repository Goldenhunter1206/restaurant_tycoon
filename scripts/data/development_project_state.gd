class_name DevelopmentProjectState
extends Resource
## One city development proposal moving through propose -> decide -> build.
## `applied` guards the once-only demand effect across save/load; `support`
## records pledged lobbying money per company (String id -> float).

@export var uid: int = 0
@export var def_id: StringName = &""
@export var district: String = ""
@export var status: StringName = &"proposed"  ## proposed | approved | rejected | built
@export var proposed_day: int = 0
@export var decision_day: int = 0
@export var support: Dictionary = {}
@export var applied: bool = false
@export var rationale: String = ""


func support_total() -> float:
	var total: float = 0.0
	for key: String in support:
		total += float(support[key])
	return total
