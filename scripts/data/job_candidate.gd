class_name JobCandidate
extends Resource
## Shared, time-limited applicant used by player and rival companies.

@export var schema_version: int = 3
@export var uid: int = 0
@export var type_id: StringName = &""
@export var candidate_name: String = ""
## StringName -> float 0..1, keys from StaffTypeDef.attribute_keys.
@export var attributes: Dictionary = {}
@export var competencies: Dictionary = {}
@export var experience: float = 0.0
@export var traits: Array[StringName] = []
## Asking wage per scheduled hour, derived from attributes.
@export var hourly_wage: float = 8.0
@export var posted_day: int = 1
@export var expires_day: int = 8
@export var availability_by_weekday: Dictionary = {}
@export var desired_weekly_hours: float = 32.0
@export var contract_preferences: Array[StringName] = [&"permanent"]
@export var manager_eligible: bool = false
@export var promotion_role_ids: Array[StringName] = []
@export var source_company_id: StringName = &""
@export var source_branch_building_id: int = -1
@export var competing_offers: Array[Dictionary] = []
@export var reserved_by_company_id: StringName = &""
@export var reservation_expires_day: int = -1
## Interview / imperfect information (v3).
@export var interview_state: StringName = &"unseen"
@export var revealed_competencies: Dictionary = {}
@export_range(0.0, 1.0, 0.01) var assessment_confidence: float = 0.35


func is_available_for(company_id: StringName, day: int) -> bool:
	if day > expires_day:
		return false
	return reserved_by_company_id.is_empty() or reserved_by_company_id == company_id or day > reservation_expires_day


func competency(key: StringName) -> float:
	return clampf(float(competencies.get(key, attributes.get(key, 0.5))), 0.0, 1.0)


func has_contract_preference(contract_type: StringName) -> bool:
	return contract_preferences.is_empty() or contract_preferences.has(contract_type)


func is_interviewed() -> bool:
	return interview_state == &"interviewed"


## Competency the player currently sees: a noised estimate until interviewed.
func shown_competency(key: StringName) -> float:
	if interview_state == &"interviewed":
		return competency(key)
	return clampf(float(revealed_competencies.get(key, competency(key))), 0.0, 1.0)
