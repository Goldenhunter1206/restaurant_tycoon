class_name CompanyHeatState
extends Resource
## Police attention + evidence ledger for one company (attacker side), plus
## extortion demands and detected plots against it (victim side). Kept
## self-contained so the Government feature (plan 13) can absorb it into
## CompanyCivicState without touching operation records.

@export var company_id: StringName = &""
@export_range(0.0, 100.0) var heat: float = 0.0
@export_range(0.0, 1.0) var official_reputation: float = 0.5  ## stub for feature 13
## Evidence the police hold AGAINST this company:
## {incident_uid, victim_company, action_id, strength, day}
@export var evidence: Array[Dictionary] = []
## Demands made AGAINST this company (victim side):
## {uid, from_company, amount, deadline_day, status: open|paid|refused|expired|reported, building_id}
@export var outstanding_extortion: Array[Dictionary] = []
## Counterintel warnings about ops targeting this company:
## {op_uid, day_detected, action_id, attacker_shown, eta_day, building_id}
@export var known_plots: Array[Dictionary] = []
@export var fines_total: float = 0.0
## Raid history: {day, fine, frozen_until_day, agents_jailed}
@export var raids: Array[Dictionary] = []
@export var ops_frozen_until_day: int = 0


func evidence_total() -> float:
	var total: float = 0.0
	for row: Dictionary in evidence:
		total += float(row.get("strength", 0.0))
	return total


func is_frozen(day: int) -> bool:
	return day < ops_frozen_until_day


func open_extortion() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in outstanding_extortion:
		if String(row.get("status", "")) == "open":
			out.append(row)
	return out
