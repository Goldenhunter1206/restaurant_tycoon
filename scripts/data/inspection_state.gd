class_name InspectionState
extends Resource
## One civic inspection visit (scheduled or resolved). Findings are frozen at
## visit time from LIVE restaurant state so every failure maps to a concrete,
## player-visible corrective action. outcome_applied guards once-only effects
## across save/load.

@export var uid: int = 0
@export var building_id: int = -1
@export var company_id: StringName = &""
@export var kind: StringName = &"food_safety"  ## food_safety | labor | tax
@export var official_id: StringName = &""
@export var trigger: StringName = &"scheduled"  ## scheduled | complaint | rival_report | rigged
@export var scheduled_day: int = 0
## Absolute game minute of the visit (frozen at scheduling for determinism).
@export var visit_minute: int = 0
@export var visit_done: bool = false
## Corruption-bought leniency (negative = harsher rigged audit); clamped by
## InfluenceService so influence bends outcomes without erasing facts.
@export var bias: float = 0.0
## Frozen per-check rows:
## {check_id, label, category, passed, detail, severity, corrective, needed}
@export var findings: Array[Dictionary] = []
@export var score: float = 0.0
@export var grade: StringName = &"pending"  ## pending | clean | warning | remediation | fine | closure
@export var appeal_deadline_day: int = 0
@export var outcome_applied: bool = false


func failed_findings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in findings:
		if not bool(row.get("passed", true)):
			out.append(row)
	return out


func is_due(day: int) -> bool:
	return not visit_done and day >= scheduled_day


func days_until(day: int) -> int:
	return maxi(scheduled_day - day, 0)
