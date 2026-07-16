class_name CampaignManager
extends Node
## Owns durable player-profile progression. Profile commits are independent of
## rollback-able session saves and keyed by frozen result IDs.

signal profile_changed(profile: PlayerProfileState)
signal progression_committed(result_id: StringName, changes: Dictionary)

const PROFILE_PATH: String = "user://player_profile.tres"
const DEFAULT_PROFILE_ID: StringName = &"local"

var profile: PlayerProfileState
var catalog: ScenarioCatalog


func setup(content_catalog: ScenarioCatalog) -> void:
	catalog = content_catalog
	load_profile()
	_seed_default_unlocks()


func load_profile() -> void:
	var loaded: Resource = load(PROFILE_PATH) if ResourceLoader.exists(PROFILE_PATH) else null
	if loaded is PlayerProfileState:
		profile = loaded as PlayerProfileState
	else:
		var profile_script: GDScript = load("res://scripts/data/player_profile_state.gd")
		profile = profile_script.new() as PlayerProfileState
		profile.profile_id = DEFAULT_PROFILE_ID
	profile_changed.emit(profile)


func save_profile() -> bool:
	if profile == null:
		return false
	var error: Error = ResourceSaver.save(profile, PROFILE_PATH)
	if error != OK:
		push_warning("CampaignManager: profile save failed with error %d" % error)
	return error == OK


func reset_profile() -> void:
	var profile_script: GDScript = load("res://scripts/data/player_profile_state.gd")
	profile = profile_script.new() as PlayerProfileState
	profile.profile_id = DEFAULT_PROFILE_ID
	_seed_default_unlocks()
	save_profile()
	profile_changed.emit(profile)


func is_city_unlocked(city_id: StringName) -> bool:
	return profile != null and profile.unlocked_cities.has(city_id)


func is_campaign_unlocked(campaign_id: StringName) -> bool:
	return profile != null and profile.unlocked_campaigns.has(campaign_id)


func is_scenario_unlocked(scenario_id: StringName) -> bool:
	if profile == null or catalog == null:
		return false
	if profile.unlocked_scenarios.has(scenario_id):
		return true
	var definition: Dictionary = catalog.scenario(scenario_id)
	var mode: StringName = StringName(String(definition.get("mode", "")))
	return mode in [&"free_play", &"tutorial", &"challenge"]


func best_score(scenario_id: StringName) -> int:
	if profile == null:
		return 0
	return int(profile.best_scores.get(String(scenario_id), 0))


func medal_for(scenario_id: StringName) -> StringName:
	if profile == null:
		return &""
	return StringName(String(profile.medals.get(String(scenario_id), "")))


func commit_result(result: ScenarioResultSnapshot, scenario_definition: Dictionary,
		campaign_definition: Dictionary = {}) -> Dictionary:
	if profile == null or result == null or not result.is_frozen():
		return {"committed": false, "reason": "missing_profile_or_unfrozen_result"}
	if profile.has_committed_result(result.result_id):
		return {"committed": false, "reason": "already_committed", "result_id": result.result_id}
	profile.commit_result_id(result.result_id)
	var changes: Dictionary = {
		"committed": true,
		"result_id": result.result_id,
		"unlocked_cities": [],
		"unlocked_scenarios": [],
		"unlocked_content": [],
	}
	if result.outcome == &"success":
		_record_success(result, changes)
		_apply_success_outcome(scenario_definition, changes)
		_apply_campaign_chapter_rewards(result.scenario_id, campaign_definition, changes)
		var next_id: StringName = _next_scenario_from(scenario_definition, campaign_definition)
		if next_id != &"":
			_unlock_scenario(next_id, changes)
			var next_definition: Dictionary = catalog.scenario(next_id) if catalog != null else {}
			var next_city: StringName = StringName(String(next_definition.get("city_id", "")))
			if next_city != &"":
				_unlock_city(next_city, changes)
	if result.mode == &"tutorial":
		profile.tutorial_state["completed"] = result.outcome == &"success"
		profile.tutorial_state["last_scenario_id"] = result.scenario_id
		profile.tutorial_state["last_result_id"] = result.result_id
	if result.campaign_id != &"":
		profile.campaign_progress[String(result.campaign_id)] = {
			"last_scenario_id": result.scenario_id,
			"last_result_id": result.result_id,
			"completed": result.outcome == &"success" and _next_scenario_from(
				scenario_definition, campaign_definition) == &"",
		}
	save_profile()
	profile_changed.emit(profile)
	progression_committed.emit(result.result_id, changes)
	return changes


func _record_success(result: ScenarioResultSnapshot, changes: Dictionary) -> void:
	profile.record_scenario_completion(result.scenario_id, result.score, result.medal)
	var scenario_key: String = String(result.scenario_id)
	changes["scenario_completed"] = result.scenario_id
	changes["best_score"] = int(profile.best_scores.get(scenario_key, 0))
	changes["medal"] = String(profile.medals.get(scenario_key, ""))


func _apply_success_outcome(scenario_definition: Dictionary, changes: Dictionary) -> void:
	var outcomes: Dictionary = scenario_definition.get("outcomes", {})
	var success: Dictionary = outcomes.get("success", {}) if outcomes is Dictionary else {}
	for value: Variant in success.get("unlock_cities", success.get("unlocked_cities", [])):
		_unlock_city(StringName(String(value)), changes)
	for value: Variant in success.get("unlock_scenarios", success.get("unlocked_scenarios", [])):
		_unlock_scenario(StringName(String(value)), changes)
	for value: Variant in success.get("unlock_content", success.get("unlocked_content", [])):
		var content_id: StringName = StringName(String(value))
		if content_id != &"" and not profile.unlocked_content.has(content_id):
			profile.unlock_content(content_id)
			(changes["unlocked_content"] as Array).append(content_id)
	_apply_reward_records(success.get("rewards", []), changes)


func _apply_campaign_chapter_rewards(scenario_id: StringName,
		campaign_definition: Dictionary, changes: Dictionary) -> void:
	for chapter_value: Variant in campaign_definition.get("chapters", []):
		if chapter_value is not Dictionary:
			continue
		var chapter: Dictionary = chapter_value
		var scenario_ids: Array = chapter.get("scenario_ids", [])
		if scenario_ids.is_empty():
			scenario_ids = [chapter.get("scenario_id", "")]
		if not scenario_ids.has(String(scenario_id)) and not scenario_ids.has(scenario_id):
			continue
		_apply_reward_records(chapter.get("persistent_rewards", []), changes)
		return


func _apply_reward_records(reward_records: Array, changes: Dictionary) -> void:
	for reward_value: Variant in reward_records:
		if reward_value is not Dictionary:
			continue
		var reward: Dictionary = reward_value
		var reward_type: StringName = StringName(String(reward.get("type", "")))
		var reward_id: StringName = StringName(String(reward.get("id", "")))
		match reward_type:
			&"unlock_city":
				_unlock_city(reward_id, changes)
			&"unlock_scenario":
				_unlock_scenario(reward_id, changes)
			&"profile_cash":
				var previous_cash: int = int(profile.preferences.get("profile_cash", 0))
				profile.preferences["profile_cash"] = previous_cash + int(reward.get("amount", 0))
				changes["profile_cash"] = profile.preferences["profile_cash"]
			&"profile_flag":
				profile.preferences[String(reward_id)] = true
				var profile_flags: Array = changes.get("profile_flags", [])
				if not profile_flags.has(reward_id):
					profile_flags.append(reward_id)
				changes["profile_flags"] = profile_flags
			&"complete_campaign":
				profile.campaign_progress[String(reward_id)] = {
					"completed": true,
					"last_scenario_id": changes.get("scenario_completed", &""),
				}
				changes["campaign_completed"] = reward_id
			&"unlock_system", &"unlock_mode", &"unlock_cosmetic", &"medal":
				var category: String = String(reward_type).trim_prefix("unlock_")
				_unlock_content(StringName("%s:%s" % [category, reward_id]), changes)


func _unlock_content(content_id: StringName, changes: Dictionary) -> void:
	if content_id == &"" or profile.unlocked_content.has(content_id):
		return
	profile.unlock_content(content_id)
	(changes["unlocked_content"] as Array).append(content_id)


func _next_scenario_from(scenario_definition: Dictionary,
		campaign_definition: Dictionary) -> StringName:
	var next_value: Variant = scenario_definition.get("next_scenario", {})
	if next_value is Dictionary:
		var next_data: Dictionary = next_value
		var explicit_id: StringName = StringName(String(next_data.get(
			"scenario_id", next_data.get("id", ""))))
		if explicit_id != &"":
			return explicit_id
	elif not String(next_value).is_empty():
		return StringName(String(next_value))
	if catalog != null and not campaign_definition.is_empty():
		return catalog.next_scenario_id(
			StringName(String(campaign_definition.get("id", ""))),
			StringName(String(scenario_definition.get("id", ""))))
	return &""


func _unlock_city(city_id: StringName, changes: Dictionary) -> void:
	if city_id == &"" or profile.unlocked_cities.has(city_id):
		return
	profile.unlock_city(city_id)
	(changes["unlocked_cities"] as Array).append(city_id)


func _unlock_scenario(scenario_id: StringName, changes: Dictionary) -> void:
	if scenario_id == &"" or profile.unlocked_scenarios.has(scenario_id):
		return
	profile.unlock_scenario(scenario_id)
	(changes["unlocked_scenarios"] as Array).append(scenario_id)


func _seed_default_unlocks() -> void:
	if profile == null or catalog == null:
		return
	profile.unlock_city(&"riverside")
	for campaign_id: StringName in catalog.campaigns:
		profile.unlock_campaign(campaign_id)
		var campaign_definition: Dictionary = catalog.campaign(campaign_id)
		var chapters: Array = campaign_definition.get("chapters", [])
		if not chapters.is_empty() and chapters[0] is Dictionary:
			var first_chapter: Dictionary = chapters[0]
			var scenario_ids: Array = first_chapter.get("scenario_ids", [])
			var scenario_id: StringName = StringName(String(
				scenario_ids[0] if not scenario_ids.is_empty() else first_chapter.get("scenario_id", "")))
			if scenario_id != &"":
				profile.unlock_scenario(scenario_id)
	for mode: StringName in [&"free_play", &"tutorial", &"challenge"]:
		for definition: Dictionary in catalog.scenarios_for_mode(mode):
			profile.unlock_scenario(StringName(String(definition.get("id", ""))))


static func _medal_rank(medal: StringName) -> int:
	match medal:
		&"gold":
			return 3
		&"silver":
			return 2
		&"bronze":
			return 1
	return 0
