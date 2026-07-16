class_name SaveSystem
extends RefCounted
## Static v7 save/load for companies, supply, workforce, and management.

const SAVE_PATH: String = "user://savegame.tres"


static func has_save() -> bool:
	return ResourceLoader.exists(SAVE_PATH)


## &"none", &"ok", or &"incompatible".
static func save_state() -> StringName:
	if not has_save():
		return &"none"
	return &"ok" if load_game() != null else &"incompatible"


static func save_game() -> bool:
	var save := SaveGame.new()
	save.day = GameClock.day
	save.game_hours = GameClock.game_hours
	CompanyManager.player.recipe_book = RecipeManager.export_book()
	for company: CompanyState in CompanyManager.companies:
		save.companies.append(company)
	MarketingManager.write_save(save)
	SupplyManager.write_save(save)
	CapabilityRegistry.write_save(save)
	_write_service_save("/root/StaffManager", save)
	_write_service_save("/root/BranchCommandRouter", save)
	_write_service_save("/root/ManagementManager", save)
	_write_service_save("/root/AnalyticsManager", save)
	_write_service_save("/root/AwardsManager", save)
	for candidate: JobCandidate in RestaurantManager.job_market:
		save.job_market.append(candidate)
	save.next_candidate_uid = RestaurantManager._next_candidate_uid
	for citizen_id: int in DemandManager.econ:
		save.citizen_wealth[citizen_id] = float(DemandManager.econ[citizen_id]["wealth"])
	save.world_seed = GameSetup.world_seed
	save.difficulty = GameSetup.difficulty
	var error := ResourceSaver.save(save, SAVE_PATH)
	if error == OK:
		EconomyManager.post_message("good", "Game saved.")
	else:
		EconomyManager.post_message("alert", "Save failed (error %d)." % error)
	return error == OK


static func load_game() -> SaveGame:
	if not has_save():
		return null
	var save := load(SAVE_PATH) as SaveGame
	if save == null or save.companies.is_empty():
		return null
	if save.save_version < 7:
		_migrate_v7(save)
	if save.save_version < 8:
		_migrate_v8(save)
	if save.save_version < 9:
		_migrate_v9(save)
	if save.save_version < 10:
		_migrate_v10(save)
	return save


static func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


static func _write_service_save(node_path: String, save: SaveGame) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var service := tree.root.get_node_or_null(node_path)
	if service != null and service.has_method("write_save"):
		service.call("write_save", save)


## v10: mark the awards section present. Rating states are seeded by
## AwardsManager._ensure_rating_states() from each branch's legacy star_rating
## (one code path also covers fresh games, new branches, and pre-v10 saves
## re-written by a v10 build where awards_schema_version stays 0).
static func _migrate_v10(save: SaveGame) -> void:
	save.awards_schema_version = 1
	save.save_version = 10


## v9: seed analytics buckets from the unbounded CompanyState.history so loaded
## games show company trends immediately. Restaurant buckets and weekly/quarterly
## rollups accrue forward from the next day close.
static func _migrate_v9(save: SaveGame) -> void:
	var daily: Array[Dictionary] = []
	for company: CompanyState in save.companies:
		for summary: Dictionary in company.history:
			var stamp: int = int(summary.get("day", 0))
			var ledger: Dictionary = summary.get("ledger", {})
			daily.append({
				"grain": &"day", "period": stamp, "scope_kind": &"company",
				"scope_id": String(company.id), "day": stamp, "company_id": String(company.id),
				"metrics": {
					"revenue": float(summary.get("income", 0.0)),
					"expenses": -float(summary.get("expenses", 0.0)),
					"profit": float(summary.get("profit", 0.0)),
					"cash": float(summary.get("cash", 0.0)),
					"restaurant_count": float(company.restaurants.size()),
				},
				"ledger": (ledger as Dictionary).duplicate(),
			})
	save.analytics_daily = daily
	save.analytics_schema_version = 1
	save.save_version = 9


static func _migrate_v7(save: SaveGame) -> void:
	for company: CompanyState in save.companies:
		for rest: RestaurantState in company.restaurants:
			for member: StaffMember in rest.staff:
				member.schema_version = 2
				member.current_branch_building_id = rest.building_id
				if member.competencies.is_empty():
					member.competencies = member.attributes.duplicate(true)
	var lifetime := 4
	for candidate: JobCandidate in save.job_market:
		candidate.schema_version = 2
		if candidate.competencies.is_empty():
			candidate.competencies = candidate.attributes.duplicate(true)
		if candidate.expires_day <= candidate.posted_day:
			candidate.expires_day = candidate.posted_day + lifetime
	save.save_version = 7


static func _migrate_v8(save: SaveGame) -> void:
	var renames: Dictionary = {&"quality": &"consistency", &"management": &"judgment", &"reliability": &"driving"}
	for company: CompanyState in save.companies:
		for rest: RestaurantState in company.restaurants:
			for member: StaffMember in rest.staff:
				member.schema_version = 3
				_rename_competency_keys(member.competencies, renames)
				_rename_competency_keys(member.attributes, renames)
				if member.desired_wage <= 0.0:
					member.desired_wage = member.hourly_wage
				var tenure: int = maxi(0, save.day - member.contract_start_day)
				member.loyalty = clampf(0.4 + float(tenure) / 365.0 * 0.3 + (member.satisfaction - 0.5) * 0.4, 0.0, 1.0)
				if member.home_building_id < 0:
					member.home_building_id = member.current_branch_building_id
	for candidate: JobCandidate in save.job_market:
		candidate.schema_version = 3
		_rename_competency_keys(candidate.competencies, renames)
		_rename_competency_keys(candidate.attributes, renames)
		candidate.interview_state = &"unseen"
	save.workforce_schema_version = 2
	save.save_version = 8


static func _rename_competency_keys(dict: Dictionary, renames: Dictionary) -> void:
	for old_key: StringName in renames:
		if not dict.has(old_key):
			continue
		var new_key: StringName = renames[old_key]
		dict[new_key] = maxf(float(dict.get(new_key, 0.0)), float(dict[old_key]))
		dict.erase(old_key)
