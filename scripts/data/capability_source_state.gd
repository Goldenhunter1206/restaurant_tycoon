class_name CapabilitySourceState
extends Resource
## Serializable capability grants from one named source.

@export var company_id: StringName = &""
@export var source_id: StringName = &""
@export var grants: Dictionary = {}
@export var lock_hints: Dictionary = {}
@export var persistent: bool = true
