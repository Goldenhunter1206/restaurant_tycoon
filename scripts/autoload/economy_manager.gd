extends Node
## Company finances: cash, loan, reputation, daily ledger. Pure bookkeeping —
## every money movement flows through transact() so the ledger stays honest.
## Other systems register daily-cost providers instead of being hardcoded here.

signal cash_changed(cash: float)
signal reputation_changed(reputation: float)
signal day_closed(summary: Dictionary)
signal bankrupt
signal message_posted(kind: String, text: String)

const TUNING_PATH: String = "res://data/tuning.json"

var tuning: Dictionary = {}
var company_name: String = "Pizza Co."
var cash: float = 0.0
var loan: float = 0.0
var reputation: float = 3.0
## Today's money movements: {category: amount}, income positive.
var ledger_today: Dictionary = {}
## One summary dict per finished day.
var history: Array[Dictionary] = []
## Callables invoked on day rollover BEFORE the ledger closes, e.g. wages/rent.
var daily_cost_providers: Array[Callable] = []

var _initialized: bool = false


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	tuning = _load_json(TUNING_PATH)
	company_name = String(tuning_value("company.name", "Pizza Co."))
	cash = float(tuning_value("company.starting_cash", 20000.0))
	reputation = float(tuning_value("reputation.start", 3.0))
	GameClock.day_changed.connect(_on_day_changed)
	cash_changed.emit(cash)


## Read a tuning knob by dotted path, e.g. tuning_value("delivery.cancel_minutes", 60).
func tuning_value(path: String, fallback: Variant) -> Variant:
	var node: Variant = tuning
	for key: String in path.split("."):
		if node is Dictionary and node.has(key):
			node = node[key]
		else:
			return fallback
	return node


func transact(category: StringName, amount: float) -> void:
	cash += amount
	ledger_today[category] = float(ledger_today.get(category, 0.0)) + amount
	cash_changed.emit(cash)


func can_afford(amount: float) -> bool:
	return cash >= amount


func take_loan(amount: float) -> bool:
	var loan_max: float = float(tuning_value("loan.max", 50000.0))
	if loan + amount > loan_max:
		return false
	loan += amount
	transact(&"loan", amount)
	post_message("info", "Took a loan of $%.0f." % amount)
	return true


func repay_loan(amount: float) -> bool:
	var pay: float = minf(amount, loan)
	if pay <= 0.0 or not can_afford(pay):
		return false
	loan -= pay
	transact(&"loan_repayment", -pay)
	return true


func add_reputation(delta: float) -> void:
	var lo: float = float(tuning_value("reputation.min", 1.0))
	var hi: float = float(tuning_value("reputation.max", 5.0))
	var next: float = clampf(reputation + delta, lo, hi)
	if not is_equal_approx(next, reputation):
		reputation = next
		reputation_changed.emit(reputation)


func post_message(kind: String, text: String) -> void:
	message_posted.emit(kind, text)


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
	var total: float = 0.0
	for amount: float in ledger_today.values():
		if amount > 0.0:
			total += amount
	return total


func expenses_today() -> float:
	var total: float = 0.0
	for amount: float in ledger_today.values():
		if amount < 0.0:
			total += amount
	return total


func profit_today() -> float:
	return income_today() + expenses_today()


## Per-category totals over the last `days` days; today counts as one day.
func category_totals(days: int) -> Dictionary:
	var totals: Dictionary = {}
	for category: StringName in ledger_today:
		totals[category] = float(totals.get(category, 0.0)) + float(ledger_today[category])
	var extra: int = maxi(0, days - 1)
	for i: int in range(history.size() - 1, maxi(-1, history.size() - 1 - extra), -1):
		var ledger: Dictionary = history[i].get("ledger", {})
		for category: StringName in ledger:
			totals[category] = float(totals.get(category, 0.0)) + float(ledger[category])
	return totals


## Daily series of a summary key ("profit", "income", "expenses", "cash"),
## oldest first, over the last `days` closed days.
func series(key: String, days: int) -> Array[float]:
	var result: Array[float] = []
	for i: int in range(maxi(0, history.size() - days), history.size()):
		result.append(float(history[i].get(key, 0.0)))
	return result


func _on_day_changed(day: int) -> void:
	for provider: Callable in daily_cost_providers:
		if provider.is_valid():
			provider.call(day)
	if loan > 0.0:
		var interest: float = loan * float(tuning_value("loan.daily_interest", 0.002))
		transact(&"loan_interest", -interest)
	var summary: Dictionary = {
		"day": day - 1,
		"income": income_today(),
		"expenses": expenses_today(),
		"profit": profit_today(),
		"cash": cash,
		"ledger": ledger_today.duplicate(),
	}
	history.append(summary)
	day_closed.emit(summary)
	post_message("info", "Day %d closed: profit $%.0f." % [day - 1, summary["profit"]])
	ledger_today = {}
	if cash < -float(tuning_value("loan.max", 50000.0)):
		bankrupt.emit()
		post_message("alert", "The company is bankrupt!")


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("EconomyManager: missing %s" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
