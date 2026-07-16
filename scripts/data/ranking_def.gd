class_name RankingDef
extends RefCounted
## One ranking category (value, revenue, profit, market share, reputation,
## delivery, recipe popularity, awards, scenario score). The scoring metric is
## a Callable so AnalyticsManager can bind functions that respect the rival
## knowledge model — exact for the player, estimated for rivals (RivalIntel).

var id: StringName
var label: String
var icon: StringName = &"trophy"
var unit: int = MetricDef.Unit.RAW
## fn(company: CompanyState, exact: bool) -> float
var metric_fn: Callable
var higher_is_better: bool = true
## Fraction of the campaign scenario score this ranking contributes (0 = none).
var scenario_weight: float = 0.0


func _init(p_id: StringName, p_label: String, p_icon: StringName, p_unit: int, p_metric_fn: Callable, p_scenario_weight: float = 0.0) -> void:
	id = p_id
	label = p_label
	icon = p_icon
	unit = p_unit
	metric_fn = p_metric_fn
	scenario_weight = p_scenario_weight


func score(company: CompanyState, exact: bool) -> float:
	if metric_fn.is_valid():
		return float(metric_fn.call(company, exact))
	return 0.0
