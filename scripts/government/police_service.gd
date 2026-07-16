class_name PoliceService
extends RefCounted
## Pure police dispatch + enforcement math (feature 13). Stations hold finite
## units; dispatch picks the nearest station with a free unit (route ETA via a
## caller-provided Callable so this stays autoload-free). The enforcement
## decision reuses crime's heat ladder thresholds so gov-on and gov-off games
## escalate at the same pace — only the decision maker and the ledger differ.

var eta_min: float = 3.0
var eta_max: float = 45.0
var fine_evidence_min: float = 0.6
var raid_evidence_min: float = 1.5
var fine_threshold: float = 40.0
var raid_threshold: float = 75.0
var fine_base: float = 2000.0
var fine_per_evidence: float = 2000.0
var respond_busy_minutes: int = 90
var raid_busy_minutes: int = 240
var false_report_reputation_hit: float = 0.08


## tuning = Callable(path: String, fallback) -> Variant.
func configure(tuning: Callable) -> void:
	eta_min = float(tuning.call("government.police.eta_min", eta_min))
	eta_max = float(tuning.call("government.police.eta_max", eta_max))
	fine_evidence_min = float(tuning.call("government.police.fine_evidence_min", fine_evidence_min))
	raid_evidence_min = float(tuning.call("government.police.raid_evidence_min", raid_evidence_min))
	# Shared ladder with the crime layer — one escalation pace for the city.
	fine_threshold = float(tuning.call("crime.heat.fine_threshold", fine_threshold))
	raid_threshold = float(tuning.call("crime.heat.raid_threshold", raid_threshold))
	fine_base = float(tuning.call("government.fines.base", fine_base))
	fine_per_evidence = float(tuning.call("crime.heat.fine_per_evidence", fine_per_evidence))
	respond_busy_minutes = int(tuning.call("government.police.respond_busy_minutes", respond_busy_minutes))
	raid_busy_minutes = int(tuning.call("government.police.raid_busy_minutes", raid_busy_minutes))
	false_report_reputation_hit = float(tuning.call(
		"government.police.false_report_reputation_hit", false_report_reputation_hit))


## Picks the responding unit. eta_fn = Callable(from: Vector3, to: Vector3)
## -> float (route minutes; SupplyManager.route_eta in the live game).
## Returns {} when there are no stations at all. When every unit is busy the
## nearest station still responds — after its earliest unit frees up, with the
## wait folded into the ETA, so response rules stay visible and predictable.
func nearest_available(stations: Array[PoliceStationState], target: Vector3,
		now_minutes: int, eta_fn: Callable) -> Dictionary:
	var best: Dictionary = {}
	var best_cost: float = INF
	for station: PoliceStationState in stations:
		station.ensure_units()
		var route: float = clampf(float(eta_fn.call(station.position, target)), eta_min, eta_max)
		var unit: int = station.free_unit_index(now_minutes)
		var wait: float = 0.0
		if unit < 0:
			var earliest: int = 0
			for i: int in range(station.units_busy_until.size()):
				if unit < 0 or station.units_busy_until[i] < station.units_busy_until[earliest]:
					earliest = i
			unit = earliest
			wait = maxf(0.0, float(station.units_busy_until[unit] - now_minutes))
		var cost: float = route + wait
		if cost < best_cost:
			best_cost = cost
			best = {
				"station_id": station.station_id,
				"unit_index": unit,
				"eta": route + wait,
				"route_eta": route,
				"wait": wait,
			}
	return best


## Books the dispatched unit until the job (travel + on-scene work) is done.
func mark_busy(station: PoliceStationState, unit_index: int, now_minutes: int,
		eta: float, purpose: StringName) -> void:
	station.ensure_units()
	if unit_index < 0 or unit_index >= station.units_busy_until.size():
		return
	var on_scene: int = raid_busy_minutes if purpose == &"raid" else respond_busy_minutes
	station.units_busy_until[unit_index] = now_minutes + int(ceilf(eta)) + on_scene


## Enforcement against accumulated criminal heat/evidence. The commander's
## scrutiny bends thresholds inside a bounded band (±15%) — pressure, not
## caprice. Returns {action: &"none"|&"investigate"|&"fine"|&"raid", fine}.
func enforcement_decision(heat: float, evidence_total: float, scrutiny: float) -> Dictionary:
	var zeal: float = clampf(1.15 - 0.3 * clampf(scrutiny, 0.0, 1.0), 0.85, 1.15)
	if heat >= raid_threshold * zeal and evidence_total >= raid_evidence_min:
		return {"action": &"raid", "fine": fine_amount(evidence_total)}
	if heat >= fine_threshold * zeal and evidence_total >= fine_evidence_min:
		return {"action": &"fine", "fine": fine_amount(evidence_total)}
	if heat >= fine_threshold * zeal:
		return {"action": &"investigate", "fine": 0.0}
	return {"action": &"none", "fine": 0.0}


func fine_amount(evidence_total: float) -> float:
	return fine_base + fine_per_evidence * evidence_total
