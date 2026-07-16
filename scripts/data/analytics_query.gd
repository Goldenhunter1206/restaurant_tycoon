class_name ReportQuery
extends RefCounted
## A lightweight description of a report request the AnalyticsManager answers.
## Not a generic query engine — it just carries the filter/interval/compare
## choices the report controls expose, and AnalyticsManager.query() maps it to
## the stored daily/weekly fact buckets.

var metric_id: StringName = &"profit"
## &"company" | &"restaurant" | &"recipe".
var scope_kind: StringName = &"company"
## Company id ("player"), building_id as string, or "recipe_id@version".
var scope_id: String = "player"
var days: int = 7
## &"day" | &"week".
var interval: StringName = &"day"
## Extra scope_ids overlaid on the same chart (compare tray).
var compare_ids: Array[String] = []


func _init(p_metric: StringName = &"profit", p_scope_kind: StringName = &"company", p_scope_id: String = "player", p_days: int = 7, p_interval: StringName = &"day") -> void:
	metric_id = p_metric
	scope_kind = p_scope_kind
	scope_id = p_scope_id
	days = p_days
	interval = p_interval
