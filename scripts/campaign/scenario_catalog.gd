class_name ScenarioCatalog
extends RefCounted
## Loads and validates the campaign, scenario, and city JSON catalogs.

const CITY_PATH: String = "res://data/cities/city_catalog.json"
const SCENARIO_PATH: String = "res://data/scenarios/scenario_catalog.json"
const CAMPAIGN_PATH: String = "res://data/campaigns/campaign_catalog.json"

var cities: Dictionary = {}
var scenarios: Dictionary = {}
var campaigns: Dictionary = {}
var validation_errors: Array[String] = []


func load_all() -> bool:
	cities.clear()
	scenarios.clear()
	campaigns.clear()
	validation_errors.clear()
	_load_collection(CITY_PATH, "cities", cities)
	_load_collection(SCENARIO_PATH, "scenarios", scenarios)
	_load_collection(CAMPAIGN_PATH, "campaigns", campaigns)
	_validate_links()
	return validation_errors.is_empty()


func validate_content(metric_ids: Array[StringName], rival_ids: Array[StringName]) -> Array[String]:
	_validate_links()
	var known_metrics: Dictionary = {}
	for metric_id: StringName in metric_ids:
		known_metrics[metric_id] = true
	var known_rivals: Dictionary = {}
	for rival_id: StringName in rival_ids:
		known_rivals[rival_id] = true
	for scenario_id: StringName in scenarios:
		var scenario: Dictionary = scenarios[scenario_id]
		for rival_value: Variant in scenario.get("rivals", []):
			var rival_id: StringName = StringName(String(
				(rival_value as Dictionary).get("id", "") \
				if rival_value is Dictionary else rival_value))
			if not known_rivals.is_empty() and not known_rivals.has(rival_id):
				_add_error("Scenario %s references unknown rival %s" % [scenario_id, rival_id])
		var objective_ids: Dictionary = {}
		var objective_records: Array = _objective_records(scenario)
		for objective_value: Variant in objective_records:
			if objective_value is not Dictionary:
				_add_error("Scenario %s contains a non-object objective" % scenario_id)
				continue
			var objective: Dictionary = objective_value
			var objective_id: StringName = StringName(String(objective.get("id", "")))
			if objective_id == &"":
				_add_error("Scenario %s has an objective without an id" % scenario_id)
			elif objective_ids.has(objective_id):
				_add_error("Scenario %s repeats objective id %s" % [scenario_id, objective_id])
			objective_ids[objective_id] = true
			var metric_id: StringName = StringName(String(objective.get("metric", "")))
			if not known_metrics.has(metric_id):
				_add_error("Scenario %s objective %s uses unknown metric %s" % [scenario_id, objective_id, metric_id])
		for objective_value: Variant in objective_records:
			if objective_value is not Dictionary:
				continue
			var objective: Dictionary = objective_value
			for prerequisite_value: Variant in objective.get("prerequisites", []):
				var prerequisite: StringName = StringName(String(prerequisite_value))
				if not objective_ids.has(prerequisite):
					_add_error("Scenario %s objective %s has unknown prerequisite %s" % [
						scenario_id, objective.get("id", ""), prerequisite])
		_validate_scenario_records(scenario_id, scenario, known_metrics, objective_ids)
	for campaign_id: StringName in campaigns:
		var campaign_data: Dictionary = campaigns[campaign_id]
		for chapter_value: Variant in campaign_data.get("chapters", []):
			if chapter_value is Dictionary:
				_validate_reward_records("Campaign %s" % campaign_id,
					(chapter_value as Dictionary).get("persistent_rewards", []))
	return validation_errors.duplicate()


func city(city_id: StringName) -> Dictionary:
	return (cities.get(city_id, {}) as Dictionary).duplicate(true)


func scenario(scenario_id: StringName) -> Dictionary:
	return (scenarios.get(scenario_id, {}) as Dictionary).duplicate(true)


func campaign(campaign_id: StringName) -> Dictionary:
	return (campaigns.get(campaign_id, {}) as Dictionary).duplicate(true)


func scenarios_for_mode(mode: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for scenario_id: StringName in scenarios:
		var entry: Dictionary = scenarios[scenario_id]
		if StringName(String(entry.get("mode", ""))) == mode:
			result.append(entry.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("sort_order", 0)) < int(b.get("sort_order", 0)))
	return result


func first_scenario_for_mode(mode: StringName) -> StringName:
	var matches: Array[Dictionary] = scenarios_for_mode(mode)
	if matches.is_empty():
		return &""
	return StringName(String(matches[0].get("id", "")))


func next_scenario_id(campaign_id: StringName, current_scenario_id: StringName) -> StringName:
	var entry: Dictionary = campaigns.get(campaign_id, {})
	var chapters: Array = entry.get("chapters", [])
	for index: int in chapters.size():
		var chapter: Dictionary = chapters[index] if chapters[index] is Dictionary else {}
		var chapter_scenarios: Array[StringName] = _chapter_scenario_ids(chapter)
		var scenario_index: int = chapter_scenarios.find(current_scenario_id)
		if scenario_index < 0:
			continue
		if scenario_index + 1 < chapter_scenarios.size():
			return chapter_scenarios[scenario_index + 1]
		if index + 1 >= chapters.size():
			return &""
		var next_chapter: Dictionary = chapters[index + 1] if chapters[index + 1] is Dictionary else {}
		var next_scenarios: Array[StringName] = _chapter_scenario_ids(next_chapter)
		return next_scenarios[0] if not next_scenarios.is_empty() else &""
	return &""


func _load_collection(path: String, key: String, target: Dictionary) -> void:
	if not FileAccess.file_exists(path):
		_add_error("Missing catalog: %s" % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		_add_error("Invalid JSON catalog: %s" % path)
		return
	var records: Array = []
	if parsed is Dictionary:
		records = (parsed as Dictionary).get(key, [])
	elif parsed is Array:
		records = parsed
	else:
		_add_error("Catalog %s must contain an object or array" % path)
		return
	for value: Variant in records:
		if value is not Dictionary:
			_add_error("Catalog %s contains a non-object record" % path)
			continue
		var record: Dictionary = value
		var id: StringName = StringName(String(record.get("id", "")))
		if id == &"":
			_add_error("Catalog %s contains a record without an id" % path)
			continue
		if target.has(id):
			_add_error("Catalog %s repeats id %s" % [path, id])
			continue
		target[id] = record.duplicate(true)


func _validate_links() -> void:
	for city_id: StringName in cities:
		var city_entry: Dictionary = cities[city_id]
		var scene_path: String = String(city_entry.get("session_scene", ""))
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			_add_error("City %s has unknown session scene %s" % [city_id, scene_path])
	for scenario_id: StringName in scenarios:
		var scenario_entry: Dictionary = scenarios[scenario_id]
		var city_id: StringName = StringName(String(scenario_entry.get("city_id", "")))
		if not cities.has(city_id):
			_add_error("Scenario %s references unknown city %s" % [scenario_id, city_id])
		var next_id: StringName = _explicit_next_scenario_id(scenario_entry)
		if next_id != &"" and not scenarios.has(next_id):
			_add_error("Scenario %s references unknown next scenario %s" % [scenario_id, next_id])
	for campaign_id: StringName in campaigns:
		var campaign_entry: Dictionary = campaigns[campaign_id]
		for chapter_value: Variant in campaign_entry.get("chapters", []):
			if chapter_value is not Dictionary:
				_add_error("Campaign %s contains a non-object chapter" % campaign_id)
				continue
			var chapter: Dictionary = chapter_value
			var chapter_scenarios: Array[StringName] = _chapter_scenario_ids(chapter)
			if chapter_scenarios.is_empty():
				_add_error("Campaign %s has a chapter without scenarios" % campaign_id)
			for scenario_id: StringName in chapter_scenarios:
				if not scenarios.has(scenario_id):
					_add_error("Campaign %s references unknown scenario %s" % [campaign_id, scenario_id])


func _objective_records(scenario_entry: Dictionary) -> Array:
	var records: Array = []
	records.append_array(scenario_entry.get("objectives", []))
	records.append_array(scenario_entry.get("side_missions", []))
	return records


func _chapter_scenario_ids(chapter: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in chapter.get("scenario_ids", []):
		var scenario_id: StringName = StringName(String(value))
		if scenario_id != &"":
			result.append(scenario_id)
	if result.is_empty():
		var legacy_id: StringName = StringName(String(chapter.get("scenario_id", "")))
		if legacy_id != &"":
			result.append(legacy_id)
	return result


func _explicit_next_scenario_id(scenario_entry: Dictionary) -> StringName:
	var next_value: Variant = scenario_entry.get("next_scenario", {})
	if next_value is Dictionary:
		var next_data: Dictionary = next_value
		return StringName(String(next_data.get("scenario_id", next_data.get("id", ""))))
	return StringName(String(next_value))


func _validate_scenario_records(scenario_id: StringName, scenario_data: Dictionary,
		known_metrics: Dictionary, objective_ids: Dictionary) -> void:
	var allowed_operators: Array[String] = [">=", "<=", ">", "<", "==", "=", "!=", "gte", "lte", "eq"]
	for objective_value: Variant in _objective_records(scenario_data):
		if objective_value is not Dictionary:
			continue
		var objective: Dictionary = objective_value
		var objective_id: String = String(objective.get("id", ""))
		var operator: String = String(objective.get("operator", ">="))
		if not allowed_operators.has(operator):
			_add_error("Scenario %s objective %s uses unknown operator %s" % [
				scenario_id, objective_id, operator])
		var deadline: Variant = objective.get("deadline", {})
		if deadline is Dictionary and not (deadline as Dictionary).is_empty():
			_validate_metric_reference("Scenario %s objective %s deadline" % [
				scenario_id, objective_id], deadline as Dictionary, known_metrics)
		_validate_inline_unlocks("Scenario %s objective %s" % [scenario_id, objective_id],
			objective.get("reward", {}))
	var event_ids: Dictionary = {}
	for event_value: Variant in scenario_data.get("scripted_events", scenario_data.get("events", [])):
		if event_value is not Dictionary:
			_add_error("Scenario %s contains a non-object event" % scenario_id)
			continue
		var event: Dictionary = event_value
		var event_id: StringName = StringName(String(event.get("id", "")))
		if event_id == &"" or event_ids.has(event_id):
			_add_error("Scenario %s has a missing or repeated event id %s" % [scenario_id, event_id])
		event_ids[event_id] = true
		_validate_metric_reference("Scenario %s event %s" % [scenario_id, event_id],
			event.get("trigger", {}), known_metrics)
		var action: StringName = StringName(String(event.get("action", "message")))
		var payload: Dictionary = event.get("payload", {})
		if action == &"offer_side_mission":
			var mission_id: StringName = StringName(String(payload.get("side_mission_id", "")))
			if not objective_ids.has(mission_id):
				_add_error("Scenario %s event %s references unknown side mission %s" % [
					scenario_id, event_id, mission_id])
		elif action == &"tutorial_prompt":
			var prompt_id: StringName = StringName(String(payload.get("objective_id", "")))
			if not objective_ids.has(prompt_id):
				_add_error("Scenario %s event %s references unknown objective %s" % [
					scenario_id, event_id, prompt_id])
	for component_value: Variant in scenario_data.get("score_components", []):
		if component_value is Dictionary:
			_validate_metric_reference("Scenario %s score component" % scenario_id,
				component_value as Dictionary, known_metrics)
	var outcomes: Dictionary = scenario_data.get("outcomes", {})
	var success: Dictionary = outcomes.get("success", {}) if outcomes is Dictionary else {}
	_validate_reward_records("Scenario %s success" % scenario_id, success.get("rewards", []))
	for failure_value: Variant in outcomes.get("failure", []):
		if failure_value is Dictionary:
			_validate_metric_reference("Scenario %s failure outcome" % scenario_id,
				(failure_value as Dictionary).get("condition", {}), known_metrics)


func _validate_metric_reference(context: String, condition: Dictionary,
		known_metrics: Dictionary) -> void:
	if condition.is_empty():
		return
	var metric_id: StringName = StringName(String(condition.get("metric", "")))
	if not known_metrics.has(metric_id):
		_add_error("%s uses unknown metric %s" % [context, metric_id])


func _validate_inline_unlocks(context: String, reward_value: Variant) -> void:
	if reward_value is not Dictionary:
		return
	for unlock_value: Variant in (reward_value as Dictionary).get("unlocks", []):
		var parts: PackedStringArray = String(unlock_value).split(":", false, 1)
		if parts.size() != 2:
			_add_error("%s has invalid unlock %s" % [context, unlock_value])
			continue
		if parts[0] == "city" and not cities.has(StringName(parts[1])):
			_add_error("%s unlocks unknown city %s" % [context, parts[1]])
		elif parts[0] == "scenario" and not scenarios.has(StringName(parts[1])):
			_add_error("%s unlocks unknown scenario %s" % [context, parts[1]])


func _validate_reward_records(context: String, reward_records: Array) -> void:
	var known_types: Array[StringName] = [
		&"unlock_city", &"unlock_scenario", &"unlock_system", &"unlock_mode",
		&"unlock_cosmetic", &"profile_cash", &"profile_flag",
		&"complete_campaign", &"medal",
	]
	for reward_value: Variant in reward_records:
		if reward_value is not Dictionary:
			_add_error("%s contains a non-object reward" % context)
			continue
		var reward: Dictionary = reward_value
		var reward_type: StringName = StringName(String(reward.get("type", "")))
		var reward_id: StringName = StringName(String(reward.get("id", "")))
		if not known_types.has(reward_type):
			_add_error("%s uses unknown reward type %s" % [context, reward_type])
		elif reward_type == &"unlock_city" and not cities.has(reward_id):
			_add_error("%s unlocks unknown city %s" % [context, reward_id])
		elif reward_type == &"unlock_scenario" and not scenarios.has(reward_id):
			_add_error("%s unlocks unknown scenario %s" % [context, reward_id])
		elif reward_type == &"complete_campaign" and not campaigns.has(reward_id):
			_add_error("%s completes unknown campaign %s" % [context, reward_id])


func _add_error(message: String) -> void:
	if not validation_errors.has(message):
		validation_errors.append(message)
