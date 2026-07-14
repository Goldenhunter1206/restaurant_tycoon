extends Node
## Player-company economy facade + global tuning knobs. The actual books live
## on CompanyManager.player (a CompanyState); the delegating properties below
## keep every legacy call site working. Rivals run their own CompanyState
## under the exact same rules — nothing in here grants the player special
## treatment beyond being the company this facade points at.

signal cash_changed(cash: float)
signal reputation_changed(reputation: float)
signal day_closed(summary: Dictionary)
signal bankrupt
signal message_posted(kind: String, text: String)
## Feed message attributed to a company (rival news) — carries the brand
## color so the feed can render a company-colored bead.
signal company_message_posted(brand: Color, kind: String, text: String)

const TUNING_PATH: String = "res://data/tuning.json"

var tuning: Dictionary = {}
## Callables invoked once per company on day rollover BEFORE that company's
## ledger closes, e.g. wages/rent. Signature: fn(company: CompanyState, day: int).
var daily_cost_providers: Array[Callable] = []

var company_name: String:
	get:
		var p: CompanyState = _p()
		return p.display_name if p != null else "Pizza Co."
	set(value):
		var p: CompanyState = _p()
		if p != null:
			p.display_name = value

var cash: float:
	get:
		var p: CompanyState = _p()
		return p.cash if p != null else 0.0
	set(value):
		var p: CompanyState = _p()
		if p != null:
			p.cash = value

var loan: float:
	get:
		var p: CompanyState = _p()
		return p.loan if p != null else 0.0
	set(value):
		var p: CompanyState = _p()
		if p != null:
			p.loan = value

var reputation: float:
	get:
		var p: CompanyState = _p()
		return p.reputation if p != null else 3.0
	set(value):
		var p: CompanyState = _p()
		if p != null:
			p.reputation = value

## Today's money movements: {category: amount}, income positive.
var ledger_today: Dictionary:
	get:
		var p: CompanyState = _p()
		return p.ledger_today if p != null else {}
	set(value):
		var p: CompanyState = _p()
		if p != null:
			p.ledger_today = value

## One summary dict per finished day.
var history: Array[Dictionary]:
	get:
		var p: CompanyState = _p()
		if p == null:
			var empty: Array[Dictionary] = []
			return empty
		return p.history
	set(value):
		var p: CompanyState = _p()
		if p != null:
			p.history = value

var _initialized: bool = false
var _bound: CompanyState = null


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_ensure_tuning()


## Points the facade (and its re-emitted signals) at the player company.
## Called by CompanyManager whenever the player instance is set or replaced.
func bind_player(company: CompanyState) -> void:
	if _bound == company:
		return
	if _bound != null:
		_bound.finances_changed.disconnect(_on_player_finances)
		_bound.reputation_shifted.disconnect(_on_player_reputation)
		_bound.message.disconnect(post_message)
		_bound.day_closed.disconnect(_on_player_day_closed)
		_bound.went_bankrupt.disconnect(_on_player_bankrupt)
	_bound = company
	company.finances_changed.connect(_on_player_finances)
	company.reputation_shifted.connect(_on_player_reputation)
	company.message.connect(post_message)
	company.day_closed.connect(_on_player_day_closed)
	company.went_bankrupt.connect(_on_player_bankrupt)


## Re-emits current player finances, e.g. after (re)configuring the company.
func announce_state() -> void:
	cash_changed.emit(cash)
	reputation_changed.emit(reputation)


## Read a tuning knob by dotted path, e.g. tuning_value("delivery.cancel_minutes", 60).
func tuning_value(path: String, fallback: Variant) -> Variant:
	if tuning.is_empty():
		_ensure_tuning()
	var node: Variant = tuning
	for key: String in path.split("."):
		if node is Dictionary and node.has(key):
			node = node[key]
		else:
			return fallback
	return node


func transact(category: StringName, amount: float) -> void:
	_p().transact(category, amount)


func can_afford(amount: float) -> bool:
	return _p().can_afford(amount)


func take_loan(amount: float) -> bool:
	return _p().take_loan(amount, float(tuning_value("loan.max", 50000.0)))


func repay_loan(amount: float) -> bool:
	return _p().repay_loan(amount)


func add_reputation(delta: float) -> void:
	var lo: float = float(tuning_value("reputation.min", 1.0))
	var hi: float = float(tuning_value("reputation.max", 5.0))
	_p().add_reputation(delta, lo, hi)


func post_message(kind: String, text: String) -> void:
	message_posted.emit(kind, text)


func post_company_message(brand: Color, kind: String, text: String) -> void:
	company_message_posted.emit(brand, kind, text)


## Next scheduled economy beats, soonest first: [{title, kind, day, when}].
## Purely informational for now; structured so a real event system can back it.
func upcoming_events(count: int = 3) -> Array[Dictionary]:
	var rules: Array[Dictionary] = [
		{"title": "Food Festival", "kind": "festival", "every": 42, "offset": 20},
		{"title": "Rent Review", "kind": "rent", "every": 42, "offset": 41},
		{"title": "Health Inspection", "kind": "inspection", "every": 28, "offset": 9},
	]
	var events: Array[Dictionary] = []
	var today: int = GameClock.day
	for rule: Dictionary in rules:
		var every: int = int(rule["every"])
		var offset: int = int(rule["offset"])
		var cycle_pos: int = (today - 1) % every
		var wait_days: int = (offset - cycle_pos + every) % every
		var event_day: int = today + wait_days
		events.append({
			"title": rule["title"],
			"kind": rule["kind"],
			"day": event_day,
			"when": GameClock.month_name_for(event_day),
		})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["day"]) < int(b["day"]))
	return events.slice(0, count)


func income_today() -> float:
	return _p().income_today()


func expenses_today() -> float:
	return _p().expenses_today()


func profit_today() -> float:
	return _p().profit_today()


## Per-category totals over the last `days` days; today counts as one day.
func category_totals(days: int) -> Dictionary:
	return _p().category_totals(days)


## Daily series of a summary key ("profit", "income", "expenses", "cash"),
## oldest first, over the last `days` closed days.
func series(key: String, days: int) -> Array[float]:
	return _p().series(key, days)


func _p() -> CompanyState:
	return CompanyManager.player


func _ensure_tuning() -> void:
	if tuning.is_empty():
		tuning = _load_json(TUNING_PATH)


func _on_player_finances() -> void:
	cash_changed.emit(cash)


func _on_player_reputation(value: float) -> void:
	reputation_changed.emit(value)


func _on_player_day_closed(summary: Dictionary) -> void:
	day_closed.emit(summary)
	post_message("info", "Day %d closed: profit $%.0f." % [int(summary["day"]), summary["profit"]])


func _on_player_bankrupt() -> void:
	bankrupt.emit()
	post_message("alert", "The company is bankrupt!")


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("EconomyManager: missing %s" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
