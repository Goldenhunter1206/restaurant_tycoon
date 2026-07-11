class_name SaveSystem
extends RefCounted
## Static save/load for the tycoon layer. Company + restaurant + citizen
## wealth state; the city itself is deterministic and never saved.

const SAVE_PATH: String = "user://savegame.tres"


static func has_save() -> bool:
	return ResourceLoader.exists(SAVE_PATH)


static func save_game() -> bool:
	var save: SaveGame = SaveGame.new()
	save.day = GameClock.day
	save.game_hours = GameClock.game_hours
	save.cash = EconomyManager.cash
	save.loan = EconomyManager.loan
	save.reputation = EconomyManager.reputation
	save.history = EconomyManager.history.duplicate(true)
	for rest: RestaurantState in RestaurantManager.owned:
		save.restaurants.append(rest)
	for citizen_id: int in DemandManager.econ:
		save.citizen_wealth[citizen_id] = float(DemandManager.econ[citizen_id]["wealth"])
	var err: Error = ResourceSaver.save(save, SAVE_PATH)
	if err == OK:
		EconomyManager.post_message("good", "Game saved.")
	else:
		EconomyManager.post_message("alert", "Save failed (error %d)." % err)
	return err == OK


static func load_game() -> SaveGame:
	if not has_save():
		return null
	return load(SAVE_PATH) as SaveGame


static func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
