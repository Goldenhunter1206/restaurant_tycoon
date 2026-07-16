class_name CompanyCivicState
extends Resource
## Civic/legal standing of one company with the city government (feature 13).
## Official reputation is deliberately separate from customer reputation
## (CompanyState.reputation) and criminal heat (CompanyHeatState.heat): a
## company can be loved by diners while regulators distrust it.

@export var company_id: StringName = &""
@export_range(0.0, 1.0) var official_reputation: float = 0.5
@export_range(0.0, 1.0) var police_reputation: float = 0.5
@export_range(-1.0, 1.0) var mayor_relationship: float = 0.0
## Spent-down lobbying capital built by donations/sponsorships; decays daily.
@export var influence: float = 0.0
## {permit_id, status: active|lapsed|suspended, granted_day, expires_day, cost}
@export var permits: Array[Dictionary] = []
## {uid, inspection_uid, code, severity, day, corrective, deadline_day,
##  status: open|fixed|escalated|waived, outcome_applied}
@export var violations: Array[Dictionary] = []
## {uid, amount, reason, day, status: unpaid|paid|appealed|overturned,
##  appeal_deadline_day, outcome_applied}
@export var fines: Array[Dictionary] = []
## {uid, kind: declared|sponsorship|bribe, amount, day, official_id,
##  evidence_risk, exposed}
@export var donations: Array[Dictionary] = []
## Civic-ordered branch closures: {building_id, reason, until_day}
@export var closures: Array[Dictionary] = []
## Corruption evidence held AGAINST this company: {uid, kind, strength, day}
@export var evidence: Array[Dictionary] = []
@export var fines_total: float = 0.0
@export var donations_total: float = 0.0
## City tax the company could not pay when charged (drives the tax audit check).
@export var tax_debt: float = 0.0
@export var tax_paid_total: float = 0.0


func permit_row(permit_id: StringName) -> Dictionary:
	for row: Dictionary in permits:
		if StringName(row.get("permit_id", &"")) == permit_id:
			return row
	return {}


func has_active_permit(permit_id: StringName, day: int) -> bool:
	var row: Dictionary = permit_row(permit_id)
	if row.is_empty():
		return false
	return String(row.get("status", "")) == "active" and day < int(row.get("expires_day", 0))


func open_violations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in violations:
		if String(row.get("status", "")) == "open":
			out.append(row)
	return out


func unpaid_fines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in fines:
		if String(row.get("status", "")) == "unpaid":
			out.append(row)
	return out


func violation_by_uid(uid: int) -> Dictionary:
	for row: Dictionary in violations:
		if int(row.get("uid", -1)) == uid:
			return row
	return {}


func fine_by_uid(uid: int) -> Dictionary:
	for row: Dictionary in fines:
		if int(row.get("uid", -1)) == uid:
			return row
	return {}


func evidence_total() -> float:
	var total: float = 0.0
	for row: Dictionary in evidence:
		total += float(row.get("strength", 0.0))
	return total


func closure_for(building_id: int) -> Dictionary:
	for row: Dictionary in closures:
		if int(row.get("building_id", -1)) == building_id:
			return row
	return {}
