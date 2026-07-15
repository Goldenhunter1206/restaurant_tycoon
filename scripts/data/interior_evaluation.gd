class_name InteriorEvaluation
extends RefCounted
## Derived numbers of one interior layout — recomputed on demand, never
## persisted. Produced headlessly by InteriorLayoutService.evaluate() so the
## AI and the sim use it without any scene access. No single "beauty score"
## by design: capacity, flow, condition and appeal stay separate.

## Dining seats: chairs/stools/sofas paired with a reachable table.
var seats: int = 0
## Physical cook stations (valid ovens); caps concurrent cooking with staff.
var cook_stations: int = 0
var pickup_slots: int = 0
## Enabled-menu-dish capacity from kitchen gear (replaces bought menu_slots).
var menu_capacity: int = 0
## Waiting guests the entry area can hold.
var queue_capacity: int = 0

## Average comfort over seating (0..5).
var comfort: float = 0.0
## Summed entertainment value (0..).
var entertainment: float = 0.0
## Average furniture condition (0..1).
var condition: float = 1.0
## Fraction of styled items sharing the dominant style (0..1).
var style_coherence: float = 0.0
var dominant_style: StringName = &""
## segment id -> appeal delta fed into demand scoring.
var segment_appeal: Dictionary = {}
## Service speed multiplier from walkway flow (0.6 .. 1.15).
var throughput_mod: float = 1.0

## Table instance_id -> Array of paired seat instance_ids.
var table_seats: Dictionary = {}
## Oven instance_id -> {prep_id: int, throughput: float}.
var stations: Dictionary = {}
## Pickup-counter instance ids in slot order.
var pickup_counters: Array[int] = []
## Validation problems: {code: StringName, instance_id: int, message: String}.
var issues: Array[Dictionary] = []
## Total catalog value of placed furniture (for AI budgeting / reports).
var furniture_value: float = 0.0


func is_valid() -> bool:
	for issue: Dictionary in issues:
		if bool(issue.get("blocking", false)):
			return false
	return true


func blocking_issues() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for issue: Dictionary in issues:
		if bool(issue.get("blocking", false)):
			result.append(issue)
	return result
