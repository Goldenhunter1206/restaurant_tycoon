class_name ObjectiveState
extends Resource
## Mutable, save-safe lifecycle state for one objective. Contains no Node references.

const CURRENT_SCHEMA_VERSION: int = 1

const STATE_HIDDEN: StringName = &"hidden"
const STATE_REVEALED: StringName = &"revealed"
const STATE_ACTIVE: StringName = &"active"
const STATE_COMPLETED: StringName = &"completed"
const STATE_FAILED: StringName = &"failed"
const STATE_EXPIRED: StringName = &"expired"

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var objective_id: StringName = &""
@export var lifecycle_state: StringName = STATE_HIDDEN
@export var accepted: bool = false
@export var current_value: float = 0.0
@export var target_value: float = 0.0
@export var maintain_elapsed: float = 0.0
@export var progress_snapshot: Dictionary = {}
@export var activated_at_elapsed_days: float = -1.0
@export var resolved_at_elapsed_days: float = -1.0
@export var resolution_reason: String = ""
@export var reward_applied: bool = false
@export var failure_consequence_applied: bool = false


func is_terminal() -> bool:
	return (
		lifecycle_state == STATE_COMPLETED
		or lifecycle_state == STATE_FAILED
		or lifecycle_state == STATE_EXPIRED
	)


func can_transition_to(next_state: StringName) -> bool:
	if next_state == lifecycle_state:
		return true
	if lifecycle_state == STATE_HIDDEN:
		return (
			next_state == STATE_REVEALED
			or next_state == STATE_ACTIVE
			or next_state == STATE_FAILED
			or next_state == STATE_EXPIRED
		)
	if lifecycle_state == STATE_REVEALED:
		return (
			next_state == STATE_ACTIVE
			or next_state == STATE_FAILED
			or next_state == STATE_EXPIRED
		)
	if lifecycle_state == STATE_ACTIVE:
		return (
			next_state == STATE_COMPLETED
			or next_state == STATE_FAILED
			or next_state == STATE_EXPIRED
		)
	return false


func transition_to(
	next_state: StringName,
	at_elapsed_days: float = -1.0,
	reason: String = ""
) -> bool:
	if not can_transition_to(next_state):
		return false
	lifecycle_state = next_state
	if next_state == STATE_ACTIVE and activated_at_elapsed_days < 0.0:
		activated_at_elapsed_days = at_elapsed_days
	if is_terminal():
		resolved_at_elapsed_days = at_elapsed_days
		resolution_reason = reason
	return true


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"objective_id": String(objective_id),
		"lifecycle_state": String(lifecycle_state),
		"accepted": accepted,
		"current_value": current_value,
		"target_value": target_value,
		"maintain_elapsed": maintain_elapsed,
		"progress_snapshot": progress_snapshot.duplicate(true),
		"activated_at_elapsed_days": activated_at_elapsed_days,
		"resolved_at_elapsed_days": resolved_at_elapsed_days,
		"resolution_reason": resolution_reason,
		"reward_applied": reward_applied,
		"failure_consequence_applied": failure_consequence_applied,
	}


static func from_dict(data: Dictionary) -> Resource:
	var state: Variant = load("res://scripts/data/objective_state.gd").new()
	state.schema_version = int(data.get("schema_version", CURRENT_SCHEMA_VERSION))
	state.objective_id = StringName(String(data.get("objective_id", "")))
	state.lifecycle_state = StringName(String(data.get("lifecycle_state", STATE_HIDDEN)))
	state.accepted = bool(data.get("accepted", false))
	state.current_value = float(data.get("current_value", 0.0))
	state.target_value = float(data.get("target_value", 0.0))
	state.maintain_elapsed = maxf(float(data.get("maintain_elapsed", 0.0)), 0.0)
	state.progress_snapshot = _copy_dictionary(data.get("progress_snapshot", {}))
	state.activated_at_elapsed_days = float(
		data.get("activated_at_elapsed_days", -1.0)
	)
	state.resolved_at_elapsed_days = float(data.get("resolved_at_elapsed_days", -1.0))
	state.resolution_reason = String(data.get("resolution_reason", ""))
	state.reward_applied = bool(data.get("reward_applied", false))
	state.failure_consequence_applied = bool(
		data.get("failure_consequence_applied", false)
	)
	return state as Resource


static func _copy_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}
