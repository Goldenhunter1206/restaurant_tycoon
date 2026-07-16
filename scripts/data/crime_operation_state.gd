class_name CrimeOperationState
extends Resource
## One underworld operation. seed_day + uid freeze the resolution RNG at
## launch so results replay identically across save/load; outcome_applied
## guards once-only effect application (UpgradeProjectState pattern).
## Phase timing uses absolute GameClock.total_minutes() diffs.

const PHASES: Array[StringName] = [
	&"planning", &"travel", &"infiltration", &"effect", &"escape", &"investigation",
]

@export var uid: int = 0
@export var action_id: StringName = &""
@export var attacker_company: StringName = &""
@export var target_company: StringName = &""
@export var target_building: int = -1
@export var agent_uids: Array[int] = []
@export var phase: StringName = &"planning"  ## PHASES, then done | cancelled
@export var start_minute: int = 0
@export var phase_start_minute: int = 0
@export var phase_end_minute: int = 0
@export var travel_minutes: int = 30
@export var launched_day: int = 0
@export var seed_day: int = 0
@export var discovered: bool = false  ## target detected the op while it was live
@export var evidence: float = 0.0
## {success, detected, captured: Array, injured: Array, loss, summary}
@export var outcome: Dictionary = {}
@export var outcome_applied: bool = false
@export var incident_uid: int = -1


func is_live() -> bool:
	return phase != &"done" and phase != &"cancelled"


func can_cancel() -> bool:
	return phase == &"planning" or phase == &"travel"


func phase_index() -> int:
	return PHASES.find(phase)


func progress_at(now_minute: int) -> float:
	var duration: int = maxi(1, phase_end_minute - phase_start_minute)
	return clampf(float(now_minute - phase_start_minute) / float(duration), 0.0, 1.0)
