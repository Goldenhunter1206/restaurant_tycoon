class_name ManagerEscalation
extends Resource
## Blocked, expired, or capability-paused manager action surfaced for player review.

@export var schema_version: int = 1
@export var uid: String = ""
@export var assignment_uid: String = ""
@export var company_id: StringName = &""
@export var branch_building_id: int = -1
@export var category: StringName = &""
@export var command_id: StringName = &""
@export var command_arguments: Dictionary = {}
@export var reason_code: StringName = &"blocked"
@export var explanation: String = ""
@export var evidence: Array[String] = []
@export var created_window: int = -1
@export var status: StringName = &"open"
@export var related_approval_uid: String = ""
@export var resolved_window: int = -1
@export var resolution_note: String = ""


func resolve(note: String, window: int) -> void:
	status = &"resolved"
	resolution_note = note
	resolved_window = window
