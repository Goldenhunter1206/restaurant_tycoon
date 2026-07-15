class_name AutomationRule
extends Resource
## Data-driven manager cadence, hysteresis, cooldown, and evaluation settings.

@export var schema_version: int = 1
@export var category: StringName = &"inventory"
@export var command_id: StringName = &""
@export var enabled: bool = true
@export var minimum_severity: float = 0.25
@export var hysteresis: float = 0.08
@export var cooldown_hours: int = 4
@export var active_branch_cadence_hours: int = 1
@export var evaluation_horizon_hours: int = 24
@export var urgency_bypasses_cadence: bool = true
@export var maximum_attempts: int = 1
@export var parameter_defaults: Dictionary = {}
@export var skill_error_curve: Curve


func should_consider(severity: float, previous_severity: float) -> bool:
	if not enabled or severity < minimum_severity:
		return false
	return previous_severity <= 0.0 or absf(severity - previous_severity) >= hysteresis


func evaluation_window(start_window: int) -> int:
	return start_window + maxi(1, evaluation_horizon_hours)
