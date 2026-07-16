class_name ObjectiveMetricRegistry
extends RefCounted
## Extensible objective metric registry. Feature systems register evaluators here
## so ScenarioManager and the objectives UI never need metric-specific branches.

var _metrics: Dictionary = {}


func register_metric(metric_id: StringName, evaluator: Callable,
		formatter: Callable = Callable(), description: String = "") -> bool:
	if metric_id == &"" or not evaluator.is_valid():
		return false
	_metrics[metric_id] = {
		"evaluator": evaluator,
		"formatter": formatter,
		"description": description,
	}
	return true


func unregister_metric(metric_id: StringName) -> void:
	_metrics.erase(metric_id)


func has_metric(metric_id: StringName) -> bool:
	return _metrics.has(metric_id)


func metric_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for metric_id: StringName in _metrics:
		result.append(metric_id)
	result.sort()
	return result


func evaluate(metric_id: StringName, filters: Dictionary = {}) -> Dictionary:
	if not _metrics.has(metric_id):
		return {
			"ok": false,
			"value": 0.0,
			"explanation": "Unknown objective metric: %s" % metric_id,
		}
	var entry: Dictionary = _metrics[metric_id]
	var raw: Variant = (entry["evaluator"] as Callable).call(filters)
	if raw is Dictionary:
		var result: Dictionary = (raw as Dictionary).duplicate(true)
		result["ok"] = bool(result.get("ok", true))
		result["value"] = float(result.get("value", 0.0))
		if not result.has("explanation"):
			result["explanation"] = String(entry.get("description", metric_id))
		return result
	return {
		"ok": true,
		"value": float(raw),
		"explanation": String(entry.get("description", metric_id)),
	}


func format_value(metric_id: StringName, value: float, filters: Dictionary = {}) -> String:
	if _metrics.has(metric_id):
		var formatter: Callable = (_metrics[metric_id] as Dictionary).get("formatter", Callable())
		if formatter.is_valid():
			return String(formatter.call(value, filters))
	return "%.1f" % value


func describe(metric_id: StringName) -> String:
	if not _metrics.has(metric_id):
		return ""
	return String((_metrics[metric_id] as Dictionary).get("description", ""))
