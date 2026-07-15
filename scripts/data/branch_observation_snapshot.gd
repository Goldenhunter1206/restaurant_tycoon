class_name BranchObservationSnapshot
extends Resource
## Manager-visible branch report. It must never contain hidden simulation state.

@export var schema_version: int = 1
@export var uid: String = ""
@export var company_id: StringName = &""
@export var branch_building_id: int = -1
@export var report_window: int = -1
@export var report_day: int = 0
@export var report_hour: int = 0
@export var operations_report: Dictionary = {}
@export var forecast_report: Dictionary = {}
@export var daily_results: Dictionary = {}
@export var policy_summary: Dictionary = {}
@export var urgent_events: Array[Dictionary] = []
@export var report_sources: Array[StringName] = []


func value(section: StringName, key: StringName, fallback: Variant = null) -> Variant:
	var report: Dictionary = get(section)
	return report.get(key, fallback)


func sanitized_copy() -> Dictionary:
	return {
		"uid": uid,
		"company_id": company_id,
		"branch_building_id": branch_building_id,
		"report_window": report_window,
		"operations_report": operations_report.duplicate(true),
		"forecast_report": forecast_report.duplicate(true),
		"daily_results": daily_results.duplicate(true),
		"policy_summary": policy_summary.duplicate(true),
		"urgent_events": urgent_events.duplicate(true),
		"report_sources": report_sources.duplicate(),
	}
