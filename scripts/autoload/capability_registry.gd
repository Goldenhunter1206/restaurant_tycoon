extends Node
## Company capability queries (feature plan 07, phase 1). Capabilities are
## passive facts derived from sources — this registry never calls the systems
## that consume them. Until headquarters exist, grants come from defaults plus
## a company-scale stand-in (restaurant count); an HQ system can later register
## itself as an extra source without consumers changing.

## Capability requirements. `min_restaurants` is the company-scale stand-in;
## `hint` is the exact missing prerequisite shown by UI locks.
const DEFAULTS: Dictionary = {
	&"marketing.local_campaigns": {"min_restaurants": 0, "hint": ""},
	&"marketing.billboards": {
		"min_restaurants": 2,
		"hint": "Open a 2nd restaurant to coordinate billboards.",
	},
	&"marketing.citywide": {
		"min_restaurants": 5,
		"hint": "Grow to 5 restaurants for citywide media.",
	},
	&"interior.designer": {
		"min_restaurants": 2,
		"hint": "Open a 2nd restaurant to hire an interior designer.",
	},
	&"interior.expansion": {"min_restaurants": 0, "hint": ""},
	&"supply.warehouses": {
		"min_restaurants": 2,
		"hint": "Open a 2nd restaurant to unlock warehouses.",
	},
}

## Simultaneous campaigns: one, plus one per two restaurants.
const SLOT_BASE: int = 1
const RESTAURANTS_PER_SLOT: int = 2

## Runtime grants from other systems (scenarios, awards, later HQ):
## company_id -> {capability_id: level}. Sources re-register after load;
## nothing here is serialized.
var extra_grants: Dictionary = {}


func has(company_id: StringName, cap_id: StringName) -> bool:
	return level(company_id, cap_id) > 0


func level(company_id: StringName, cap_id: StringName) -> int:
	var granted: Dictionary = extra_grants.get(company_id, {})
	var extra: int = int(granted.get(cap_id, 0))
	if extra > 0:
		return extra
	var req: Dictionary = DEFAULTS.get(cap_id, {})
	if req.is_empty():
		return 0
	if _restaurant_count(company_id) >= int(req.get("min_restaurants", 0)):
		return 1
	return 0


## Max simultaneous campaigns for a company.
func campaign_slots(company_id: StringName) -> int:
	var extra: int = int(extra_grants.get(company_id, {}).get(&"marketing.campaign_slots", 0))
	return SLOT_BASE + _restaurant_count(company_id) / RESTAURANTS_PER_SLOT + extra


## "" when granted, otherwise the exact missing prerequisite for UI locks.
func explain(company_id: StringName, cap_id: StringName) -> String:
	if has(company_id, cap_id):
		return ""
	var req: Dictionary = DEFAULTS.get(cap_id, {})
	if req.is_empty():
		return "Not available in this game."
	return String(req.get("hint", "Locked."))


func grant(company_id: StringName, cap_id: StringName, cap_level: int = 1) -> void:
	var granted: Dictionary = extra_grants.get(company_id, {})
	granted[cap_id] = cap_level
	extra_grants[company_id] = granted


## Developer inspection: every known capability for one company.
func dump(company_id: StringName) -> Dictionary:
	var result: Dictionary = {}
	for cap_id: StringName in DEFAULTS:
		result[cap_id] = {
			"granted": has(company_id, cap_id),
			"why_not": explain(company_id, cap_id),
		}
	result[&"marketing.campaign_slots"] = {"capacity": campaign_slots(company_id)}
	return result


func _restaurant_count(company_id: StringName) -> int:
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null:
		return 0
	return company.restaurants.size()
