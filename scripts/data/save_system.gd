class_name SaveSystem
extends RefCounted
## Static save/load for the tycoon layer. Companies (with their restaurants)
## + job market + citizen wealth; the city itself is deterministic and never
## saved. Pre-v4 single-company saves are NOT migrated: load_game() treats
## them as absent, and the Load screen offers deletion.

const SAVE_PATH: String = "user://savegame.tres"


static func has_save() -> bool:
	return ResourceLoader.exists(SAVE_PATH)


## &"none" (no file), &"ok" (loadable v4), or &"incompatible" (pre-v4/corrupt).
static func save_state() -> StringName:
	if not has_save():
		return &"none"
	return &"ok" if load_game() != null else &"incompatible"


static func save_game() -> bool:
	var save: SaveGame = SaveGame.new()
	save.day = GameClock.day
	save.game_hours = GameClock.game_hours
	CompanyManager.player.recipe_book = RecipeManager.export_book()
	for company: CompanyState in CompanyManager.companies:
		save.companies.append(company)
	for campaign: MarketingCampaign in MarketingManager.campaigns:
		save.active_campaigns.append(campaign)
	for cand: JobCandidate in RestaurantManager.job_market:
		save.job_market.append(cand)
	save.next_candidate_uid = RestaurantManager._next_candidate_uid
	for citizen_id: int in DemandManager.econ:
		save.citizen_wealth[citizen_id] = float(DemandManager.econ[citizen_id]["wealth"])
	save.world_seed = GameSetup.world_seed
	save.difficulty = GameSetup.difficulty
	var err: Error = ResourceSaver.save(save, SAVE_PATH)
	if err == OK:
		EconomyManager.post_message("good", "Game saved.")
	else:
		EconomyManager.post_message("alert", "Save failed (error %d)." % err)
	return err == OK


static func load_game() -> SaveGame:
	if not has_save():
		return null
	var save: SaveGame = load(SAVE_PATH) as SaveGame
	if save == null or save.companies.is_empty():
		# Pre-v4 (single-company) or corrupt — treated as absent; the file
		# stays on disk so the player can delete it from the Load screen.
		return null
	return save


static func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
