class_name SecurityState
extends Resource
## Per-restaurant defensive posture + incident journal. Guard headcount is
## NOT stored here — guards are ordinary staff (data/staff_types/guard.tres)
## counted live via StaffManager; this holds equipment, alert policy,
## insurance and the incident reports the Security & Incidents screen shows.

const MAX_INCIDENTS: int = 40

@export var building_id: int = -1
@export var company_id: StringName = &""
@export_range(0, 3) var equipment_level: int = 0  ## 0 none, 1 locks, 2 cameras, 3 alarm suite
@export var alert_level: StringName = &"normal"  ## normal | elevated | lockdown
@export var alert_until_day: int = 0  ## elevated/lockdown auto-relaxes after this day (0 = sticky)
@export var insurance_level: int = 0  ## 0 none, 1 basic, 2 full
@export var last_incident_day: int = -1
## Incident report rows, newest first:
## {uid, day, minute, kind_shown, title, effect_summary, loss, active,
##  suspected_company, confidence, known_facts: Array, suspicions: Array,
##  repair_cost, repaired_day, investigation_until_day, source_action}
@export var incidents: Array[Dictionary] = []
## Live temporary debuffs: {kind, magnitude, until_day, source_action, incident_uid}
## Kinds: demand_debuff, appeal_debuff.
@export var active_effects: Array[Dictionary] = []


func active_incidents() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in incidents:
		if bool(row.get("active", false)):
			out.append(row)
	return out


func add_incident(row: Dictionary) -> void:
	incidents.push_front(row)
	if incidents.size() > MAX_INCIDENTS:
		incidents.resize(MAX_INCIDENTS)
	last_incident_day = int(row.get("day", last_incident_day))


func incident_by_uid(uid: int) -> Dictionary:
	for row: Dictionary in incidents:
		if int(row.get("uid", -1)) == uid:
			return row
	return {}


func effect_total(kind: StringName, day: int) -> float:
	var total: float = 0.0
	for row: Dictionary in active_effects:
		if StringName(row.get("kind", &"")) == kind and day <= int(row.get("until_day", 0)):
			total += float(row.get("magnitude", 0.0))
	return total


func prune_effects(day: int) -> void:
	var kept: Array[Dictionary] = []
	for row: Dictionary in active_effects:
		if day <= int(row.get("until_day", 0)):
			kept.append(row)
	active_effects = kept
