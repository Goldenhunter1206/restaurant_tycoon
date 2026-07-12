class_name JobCandidate
extends Resource
## One applicant on the rolling job market. Hiring copies these fields onto a
## StaffMember and removes the candidate from the market.

@export var uid: int = 0
@export var type_id: StringName = &""
@export var candidate_name: String = ""
## StringName -> float 0..1, keys from StaffTypeDef.attribute_keys.
@export var attributes: Dictionary = {}
## Asking wage per scheduled hour, derived from attributes.
@export var hourly_wage: float = 8.0
@export var posted_day: int = 1
