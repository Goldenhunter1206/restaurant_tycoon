class_name BranchPolicy
extends Resource
## Versioned, copyable branch automation policy with visibly separate local overrides.

const AUTHORITY_RECOMMEND: StringName = &"recommend"
const AUTHORITY_APPROVAL: StringName = &"approval"
const AUTHORITY_AUTOMATIC: StringName = &"automatic"

@export var schema_version: int = 1
@export var uid: String = ""
@export var company_id: StringName = &""
@export var display_name: String = "Custom"
@export var preset_id: StringName = &"custom"
@export var template_version: int = 1
@export var copied_from_uid: String = ""
@export var branch_building_id: int = -1
@export var goal_weights: Dictionary = {}
@export var authority_by_category: Dictionary = {}
@export var daily_budget_by_category: Dictionary = {}
@export var cash_reserve: float = 2500.0
@export var supplier_allowlist: Array[StringName] = []
@export var minimum_quality_tier: int = 0
@export var maximum_quality_tier: int = 2
@export var minimum_price: float = 1.0
@export var maximum_price: float = 100.0
@export var protected_staff_uids: Array[int] = []
@export var approved_layout_templates: Array[StringName] = []
@export var scenario_authority_caps: Dictionary = {}
@export var local_overrides: Dictionary = {}
@export var last_modified_day: int = 0


func authority_for(category: StringName) -> StringName:
	var authority := StringName(authority_by_category.get(category, AUTHORITY_RECOMMEND))
	var scenario_cap := StringName(scenario_authority_caps.get(category, AUTHORITY_AUTOMATIC))
	return _lowest_authority(authority, scenario_cap)


func budget_for(category: StringName) -> float:
	return maxf(0.0, float(daily_budget_by_category.get(category, 0.0)))


func is_staff_protected(staff_uid: int) -> bool:
	return protected_staff_uids.has(staff_uid)


func allows_supplier(supplier_id: StringName) -> bool:
	return supplier_allowlist.is_empty() or supplier_allowlist.has(supplier_id)


func allows_layout(template_id: StringName) -> bool:
	return approved_layout_templates.has(template_id)


func copy_for_branch(new_uid: String, building_id: int, day: int) -> BranchPolicy:
	var copy := duplicate(true) as BranchPolicy
	copy.uid = new_uid
	copy.copied_from_uid = uid
	copy.branch_building_id = building_id
	copy.local_overrides = {}
	copy.last_modified_day = day
	return copy


func _lowest_authority(first: StringName, second: StringName) -> StringName:
	var order: Array[StringName] = [AUTHORITY_RECOMMEND, AUTHORITY_APPROVAL, AUTHORITY_AUTOMATIC]
	return order[mini(order.find(first), order.find(second))]
