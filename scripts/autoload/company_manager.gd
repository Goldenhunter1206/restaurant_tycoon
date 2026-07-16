extends Node
## Registry of all competing companies (player + AI rivals) and owner of the
## daily economy close for every company. EconomyManager stays the
## player-facing facade; rivals get their own CompanyState under the exact
## same rules. AI planners attach in start_ai() once restaurants exist.

signal company_registered(company: CompanyState)
signal rival_bankrupt(company: CompanyState)

const PROFILE_DIR: String = "res://data/competitors"

var companies: Array[CompanyState] = []
var by_id: Dictionary = {}
var player: CompanyState
## Rival profiles by id, loaded from PROFILE_DIR.
var profiles: Dictionary = {}

## The save loaded at boot, if any. RestaurantManager reads this to rebuild
## runtime restaurant state after companies are restored.
var loaded_save: SaveGame = null

var _initialized: bool = false
# AiCompany brains. Untyped + load()-based on purpose: a hard class
# reference from an autoload script to AiCompany (whose compile resolves
# autoload identifiers) breaks cold headless boots.
var _ai: Array = []
## Public-score rank per company id, snapshotted daily for ▲▼ movement.
var _ranks_yesterday: Dictionary = {}
var _ranks_today: Dictionary = {}


func _ready() -> void:
	_ensure_player()


## The player company exists from process start so the EconomyManager facade
## never dereferences null. Also called from initialize() because headless
## --script runs never fire autoload _ready.
func _ensure_player() -> void:
	if player != null:
		return
	var starter := CompanyState.new()
	starter.id = &"player"
	starter.is_player = true
	register(starter)
	player = starter
	EconomyManager.bind_player(starter)


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_ensure_player()
	load_profiles()
	# Connected BEFORE RestaurantManager.initialize() runs so the daily cost
	# providers still fire before restaurant history rolls over.
	GameClock.day_changed.connect(_on_day_changed)
	# Load only when explicitly requested (Load screen) or when booting
	# straight into Main without the frontend (dev flow). A configured New
	# Game must NOT resurrect the previous save.
	var want_save: bool = GameSetup.from_save or not GameSetup.configured
	loaded_save = SaveSystem.load_game() if want_save else null
	if loaded_save != null:
		_restore_companies(loaded_save)
	else:
		if GameSetup.configured:
			seed(GameSetup.world_seed)
		_configure_player()
		_spawn_rivals()


func register(company: CompanyState) -> void:
	companies.append(company)
	by_id[company.id] = company
	if not company.is_player:
		# Rival "news" messages surface in the player's feed; internal chatter
		# (loan confirmations etc.) stays private — that's hidden information.
		company.message.connect(func(kind: String, text: String) -> void:
			if kind == "news":
				EconomyManager.post_company_message(company.brand_color, "info", text))
	company_registered.emit(company)


func company(company_id: StringName) -> CompanyState:
	return by_id.get(company_id)


func rivals() -> Array[CompanyState]:
	var result: Array[CompanyState] = []
	for entry: CompanyState in companies:
		if not entry.is_player:
			result.append(entry)
	return result


## Attaches AI planners to rival companies. Called by the City scene after
## every manager is initialized, so restaurants and demand exist.
func start_ai() -> void:
	if not _ai.is_empty():
		return
	var brain_script: GDScript = load("res://scripts/ai/ai_company.gd")
	for rival: CompanyState in rivals():
		if rival.profile == null or rival.is_bankrupt:
			continue
		var brain: RefCounted = brain_script.new()
		brain.setup(rival, GameSetup.world_seed)
		_ai.append(brain)
	if _ai.is_empty():
		return
	GameClock.minute_ticked.connect(_on_ai_minute)
	GameClock.hour_changed.connect(_on_ai_hour)
	# Connected after every manager's day handler, so strategic planning sees
	# freshly closed books.
	GameClock.day_changed.connect(_on_ai_day)
	# Encroachment: every brain hears about every new opening (its own included
	# — brains ignore those) and may defend nearby branches.
	RestaurantManager.restaurant_purchased.connect(_on_restaurant_opened)


## The planner for a rival company (debug/intel; null for the player).
func ai_for(company_id: StringName) -> RefCounted:
	for brain: RefCounted in _ai:
		if brain.company.id == company_id:
			return brain
	return null


func _on_ai_minute(_day: int, _hour: int, _minute: int) -> void:
	for brain: RefCounted in _ai:
		brain.on_minute()


func _on_ai_hour(day: int, hour: int) -> void:
	for brain: RefCounted in _ai:
		brain.on_hour(day, hour)


func _on_restaurant_opened(rest: RestaurantState) -> void:
	for brain: RefCounted in _ai:
		brain.on_competitor_opened(rest)


func _on_ai_day(day: int) -> void:
	for i: int in range(_ai.size() - 1, -1, -1):
		if _ai[i].company.is_bankrupt:
			_ai.remove_at(i)
			continue
		_ai[i].on_day(day)


func _configure_player() -> void:
	if not GameSetup.player_name.is_empty():
		player.display_name = GameSetup.player_name
	else:
		player.display_name = String(EconomyManager.tuning_value("company.name", "Pizza Co."))
	player.brand_color = GameSetup.player_color
	player.cash = GameSetup.starting_cash(
		float(EconomyManager.tuning_value("company.starting_cash", 20000.0)))
	player.reputation = GameSetup.starting_reputation(
		float(EconomyManager.tuning_value("reputation.start", 3.0)))
	EconomyManager.announce_state()


func _restore_companies(save: SaveGame) -> void:
	GameClock.day = save.day
	GameClock.game_hours = save.game_hours
	GameSetup.world_seed = save.world_seed
	GameSetup.difficulty = save.difficulty
	companies.clear()
	by_id.clear()
	for entry: CompanyState in save.companies:
		register(entry)
		if entry.is_player:
			player = entry
	EconomyManager.bind_player(player)
	RecipeManager.load_book(player.recipe_book)
	EconomyManager.announce_state()


func _spawn_rivals() -> void:
	for rival_id: StringName in GameSetup.selected_rivals:
		var prof: CompetitorProfile = profiles.get(rival_id)
		if prof == null:
			push_warning("CompanyManager: unknown rival profile %s" % rival_id)
			continue
		var rival := CompanyState.new()
		rival.id = rival_id
		rival.display_name = prof.display_name
		rival.brand_color = prof.brand_color
		var scenario_setup: Dictionary = GameSetup.rival_setup(rival_id)
		rival.cash = float(scenario_setup.get("starting_cash", prof.starting_cash))
		rival.reputation = float(scenario_setup.get(
			"starting_reputation", EconomyManager.tuning_value("reputation.start", 3.0)))
		rival.profile = prof
		register(rival)


## Idempotent; also called by the New Game Wizard before initialize().
func load_profiles() -> void:
	if not profiles.is_empty():
		return
	var dir: DirAccess = DirAccess.open(PROFILE_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		if file.ends_with(".tres") or file.ends_with(".res"):
			var res: Resource = load(PROFILE_DIR.path_join(file))
			if res is CompetitorProfile:
				profiles[res.id] = res


func _on_day_changed(day: int) -> void:
	var interest: float = float(EconomyManager.tuning_value("loan.daily_interest", 0.002))
	var floor_cash: float = -float(EconomyManager.tuning_value("loan.max", 50000.0))
	for entry: CompanyState in companies:
		for provider: Callable in EconomyManager.daily_cost_providers:
			if provider.is_valid():
				provider.call(entry, day)
		var was_bankrupt: bool = entry.is_bankrupt
		entry.close_day(day, interest, floor_cash)
		if entry.is_bankrupt and not was_bankrupt and not entry.is_player:
			_liquidate(entry)
			rival_bankrupt.emit(entry)
	_snapshot_ranks()


## Companies sorted by public score, best first (exact for the player,
## estimate-based for rivals — same data the Rankings screen shows).
func current_rankings() -> Array[CompanyState]:
	var sorted: Array[CompanyState] = companies.duplicate()
	sorted.sort_custom(func(a: CompanyState, b: CompanyState) -> bool:
		return RivalIntel.score(a, a.is_player) > RivalIntel.score(b, b.is_player))
	return sorted


## Rank delta vs yesterday: positive = climbed, 0 = held or unknown.
func rank_movement(company_id: StringName) -> int:
	if not _ranks_yesterday.has(company_id) or not _ranks_today.has(company_id):
		return 0
	return int(_ranks_yesterday[company_id]) - int(_ranks_today[company_id])


func _snapshot_ranks() -> void:
	_ranks_yesterday = _ranks_today.duplicate()
	var order: Array[CompanyState] = current_rankings()
	_ranks_today = {}
	for i: int in order.size():
		_ranks_today[order[i].id] = i + 1


## A bankrupt rival closes every branch; buildings return to the market.
func _liquidate(entry: CompanyState) -> void:
	for rest: RestaurantState in entry.restaurants.duplicate():
		RestaurantManager.close_branch(entry.id, rest.building_id)
	EconomyManager.post_message("info", "%s has gone bankrupt — its restaurants closed for good." % entry.display_name)
	entry.log_move(GameClock.day, "news", "%s went bankrupt." % entry.display_name)
