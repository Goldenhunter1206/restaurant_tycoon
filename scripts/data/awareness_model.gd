class_name AwarenessModel
extends RefCounted
## Aggregated ad awareness per (company, district, segment), 0-1. Campaigns
## deposit daily exposure gains; everything decays toward zero so lapsed
## marketing fades. Owned by MarketingManager; pure storage + math with no
## engine dependencies so it can be tested headless.

const RETENTION: float = 0.88
const CAP: float = 1.0
const EPSILON: float = 0.005

## company_id (StringName) -> district (String) -> segment (StringName) -> float.
var cells: Dictionary = {}


func value(company_id: StringName, district: String, segment: StringName) -> float:
	var districts: Dictionary = cells.get(company_id, {})
	var segments: Dictionary = districts.get(district, {})
	return float(segments.get(segment, 0.0))


func apply_gain(company_id: StringName, district: String, segment: StringName, gain: float) -> void:
	if gain <= 0.0:
		return
	var districts: Dictionary = cells.get(company_id, {})
	var segments: Dictionary = districts.get(district, {})
	segments[segment] = clampf(float(segments.get(segment, 0.0)) + gain, 0.0, CAP)
	districts[district] = segments
	cells[company_id] = districts


## Daily forgetting. Run once per day BEFORE campaign gains are applied.
func decay_all() -> void:
	for company_id: StringName in cells:
		var districts: Dictionary = cells[company_id]
		for district: String in districts:
			var segments: Dictionary = districts[district]
			for segment: StringName in segments.keys():
				var faded: float = float(segments[segment]) * RETENTION
				if faded < EPSILON:
					segments.erase(segment)
				else:
					segments[segment] = faded


## Average awareness across a company's district cells (Results reporting).
func company_average(company_id: StringName) -> float:
	var districts: Dictionary = cells.get(company_id, {})
	var total: float = 0.0
	var count: int = 0
	for district: String in districts:
		var segments: Dictionary = districts[district]
		for segment: StringName in segments:
			total += float(segments[segment])
			count += 1
	return total / count if count > 0 else 0.0


## district -> average across segments, for one company (map overlays).
func district_averages(company_id: StringName) -> Dictionary:
	var result: Dictionary = {}
	var districts: Dictionary = cells.get(company_id, {})
	for district: String in districts:
		var segments: Dictionary = districts[district]
		if segments.is_empty():
			continue
		var total: float = 0.0
		for segment: StringName in segments:
			total += float(segments[segment])
		result[district] = total / segments.size()
	return result


## Plain-Dictionary snapshot for SaveGame (already plain, but copied deep so
## the save never aliases live state).
func serialize() -> Dictionary:
	return cells.duplicate(true)


func restore(data: Dictionary) -> void:
	cells = data.duplicate(true)
