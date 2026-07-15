extends Node
## Passive company capability facts resolved from defaults plus named sources.

signal capabilities_changed(company_id: StringName)

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
const ADDITIVE_CAPS: Dictionary = {
	&"marketing.campaign_slots": true,
	&"procurement.warehouse_count": true,
	&"management.branch_managers": true,
	&"workforce.training_slots": true,
}
const SLOT_BASE: int = 1
const RESTAURANTS_PER_SLOT: int = 2

## Compatibility view used by grant(); company_id -> {capability_id: level}.
var extra_grants: Dictionary = {}
## company_id -> source_id -> {capability_id: level/capacity}.
var _sources: Dictionary = {}
## company_id -> source_id -> {capability_id: exact lock explanation}.
var _lock_hints: Dictionary = {}
## "company_id|source_id" -> true.
var _persistent: Dictionary = {}


func has(company_id: StringName, cap_id: StringName) -> bool:
	return level(company_id, cap_id) > 0


func level(company_id: StringName, cap_id: StringName) -> int:
	if ADDITIVE_CAPS.has(cap_id):
		return capacity(company_id, cap_id)
	var best: int = _default_level(company_id, cap_id)
	var company_sources: Dictionary = _sources.get(company_id, {})
	for grants_variant: Variant in company_sources.values():
		var grants: Dictionary = grants_variant
		best = maxi(best, int(grants.get(cap_id, 0)))
	return best


func capacity(company_id: StringName, cap_id: StringName) -> int:
	if not ADDITIVE_CAPS.has(cap_id):
		return level(company_id, cap_id)
	var total: int = 0
	var company_sources: Dictionary = _sources.get(company_id, {})
	for grants_variant: Variant in company_sources.values():
		var grants: Dictionary = grants_variant
		total += maxi(0, int(grants.get(cap_id, 0)))
	return total


func campaign_slots(company_id: StringName) -> int:
	return SLOT_BASE + _restaurant_count(company_id) / RESTAURANTS_PER_SLOT 		+ capacity(company_id, &"marketing.campaign_slots")


func explain(company_id: StringName, cap_id: StringName) -> String:
	if has(company_id, cap_id):
		return ""
	var options: Array[String] = []
	var requirement: Dictionary = DEFAULTS.get(cap_id, {})
	var default_hint: String = String(requirement.get("hint", ""))
	if not default_hint.is_empty():
		options.append(default_hint)
	var company_hints: Dictionary = _lock_hints.get(company_id, {})
	for hints_variant: Variant in company_hints.values():
		var hints: Dictionary = hints_variant
		var hint: String = String(hints.get(cap_id, ""))
		if not hint.is_empty() and not options.has(hint):
			options.append(hint)
	if options.is_empty():
		return "Not available in this game."
	return " Or ".join(options)


func set_source(
	company_id: StringName,
	source_id: StringName,
	grants: Dictionary,
	persistent: bool = false
) -> void:
	var company_sources: Dictionary = _sources.get(company_id, {})
	company_sources[source_id] = grants.duplicate()
	_sources[company_id] = company_sources
	var key: String = _source_key(company_id, source_id)
	if persistent:
		_persistent[key] = true
	else:
		_persistent.erase(key)
	capabilities_changed.emit(company_id)


func clear_source(company_id: StringName, source_id: StringName) -> void:
	var company_sources: Dictionary = _sources.get(company_id, {})
	company_sources.erase(source_id)
	_sources[company_id] = company_sources
	var company_hints: Dictionary = _lock_hints.get(company_id, {})
	company_hints.erase(source_id)
	_lock_hints[company_id] = company_hints
	_persistent.erase(_source_key(company_id, source_id))
	if source_id == &"legacy_runtime":
		extra_grants.erase(company_id)
	capabilities_changed.emit(company_id)


func set_lock_hints(company_id: StringName, source_id: StringName, hints: Dictionary) -> void:
	var company_hints: Dictionary = _lock_hints.get(company_id, {})
	company_hints[source_id] = hints.duplicate()
	_lock_hints[company_id] = company_hints
	capabilities_changed.emit(company_id)


func sources_for(company_id: StringName, cap_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var company_sources: Dictionary = _sources.get(company_id, {})
	for source_variant: Variant in company_sources:
		var source_id: StringName = source_variant
		var grants: Dictionary = company_sources[source_id]
		var value: int = int(grants.get(cap_id, 0))
		if value > 0:
			result.append({
				"source_id": source_id,
				"value": value,
				"persistent": _persistent.has(_source_key(company_id, source_id)),
			})
	return result


func grant(company_id: StringName, cap_id: StringName, cap_level: int = 1) -> void:
	var granted: Dictionary = extra_grants.get(company_id, {})
	granted[cap_id] = cap_level
	extra_grants[company_id] = granted
	set_source(company_id, &"legacy_runtime", granted)


func export_persistent_sources() -> Array[CapabilitySourceState]:
	var result: Array[CapabilitySourceState] = []
	for company_variant: Variant in _sources:
		var company_id: StringName = company_variant
		var company_sources: Dictionary = _sources[company_id]
		for source_variant: Variant in company_sources:
			var source_id: StringName = source_variant
			if not _persistent.has(_source_key(company_id, source_id)):
				continue
			var state: CapabilitySourceState = CapabilitySourceState.new()
			state.company_id = company_id
			state.source_id = source_id
			state.grants = (company_sources[source_id] as Dictionary).duplicate()
			state.lock_hints = (_lock_hints.get(company_id, {}) as Dictionary).get(source_id, {}).duplicate()
			state.persistent = true
			result.append(state)
	return result


func restore_persistent_sources(states: Array[CapabilitySourceState]) -> void:
	for key_variant: Variant in _persistent.keys():
		var parts: PackedStringArray = String(key_variant).split("|", true, 1)
		if parts.size() == 2:
			clear_source(StringName(parts[0]), StringName(parts[1]))
	for state: CapabilitySourceState in states:
		if state == null:
			continue
		set_source(state.company_id, state.source_id, state.grants, true)
		set_lock_hints(state.company_id, state.source_id, state.lock_hints)


func write_save(save: SaveGame) -> void:
	save.capability_sources = export_persistent_sources()


func dump(company_id: StringName) -> Dictionary:
	var ids: Dictionary = {}
	for cap_variant: Variant in DEFAULTS:
		ids[cap_variant] = true
	for cap_variant: Variant in ADDITIVE_CAPS:
		ids[cap_variant] = true
	var company_sources: Dictionary = _sources.get(company_id, {})
	for grants_variant: Variant in company_sources.values():
		for cap_variant: Variant in (grants_variant as Dictionary):
			ids[cap_variant] = true
	var result: Dictionary = {}
	for cap_variant: Variant in ids:
		var cap_id: StringName = cap_variant
		result[cap_id] = {
			"level": level(company_id, cap_id),
			"capacity": capacity(company_id, cap_id) if ADDITIVE_CAPS.has(cap_id) else 0,
			"why_not": explain(company_id, cap_id),
			"sources": sources_for(company_id, cap_id),
		}
	result[&"marketing.campaign_slots"] = {
		"capacity": campaign_slots(company_id),
		"sources": sources_for(company_id, &"marketing.campaign_slots"),
	}
	return result


func _default_level(company_id: StringName, cap_id: StringName) -> int:
	var requirement: Dictionary = DEFAULTS.get(cap_id, {})
	if requirement.is_empty():
		return 0
	return 1 if _restaurant_count(company_id) >= int(requirement.get("min_restaurants", 0)) else 0


func _restaurant_count(company_id: StringName) -> int:
	var company: CompanyState = CompanyManager.company(company_id)
	return company.restaurants.size() if company != null else 0


func _source_key(company_id: StringName, source_id: StringName) -> String:
	return "%s|%s" % [company_id, source_id]
