class_name CompanyState
extends Resource
## One competing restaurant company: identity, finances, reputation, owned
## branches. Every money movement flows through transact() so the ledger stays
## honest. The player and every AI rival share this exact state and rules.

signal finances_changed
signal reputation_shifted(value: float)
signal message(kind: String, text: String)
signal day_closed(summary: Dictionary)
signal went_bankrupt

@export var id: StringName = &"player"
@export var display_name: String = "Pizza Co."
@export var brand_color: Color = Color("#EA4A2F")
@export var is_player: bool = false
@export var cash: float = 0.0
@export var loan: float = 0.0
@export var reputation: float = 3.0
## Today's money movements: {category: amount}, income positive.
@export var ledger_today: Dictionary = {}
## One summary dict per finished day.
@export var history: Array[Dictionary] = []
@export var is_bankrupt: bool = false
@export var restaurants: Array[RestaurantState] = []
## One company-wide headquarters; null only while migrating pre-v6 saves.
@export var headquarters: HeadquartersState
## Only the player carries a mutable book; rivals cook from the shared
## starter catalog until per-company books land.
@export var recipe_book: RecipeBookState = null
@export var profile: CompetitorProfile = null
## Compact public log of recent moves for news/intel: [{day, kind, text}].
@export var recent_moves: Array[Dictionary] = []


func transact(category: StringName, amount: float) -> void:
	cash += amount
	ledger_today[category] = float(ledger_today.get(category, 0.0)) + amount
	finances_changed.emit()


func can_afford(amount: float) -> bool:
	return cash >= amount


func take_loan(amount: float, loan_max: float) -> bool:
	if loan + amount > loan_max:
		return false
	loan += amount
	transact(&"loan", amount)
	message.emit("info", "Took a loan of $%.0f." % amount)
	return true


func repay_loan(amount: float) -> bool:
	var pay: float = minf(amount, loan)
	if pay <= 0.0 or not can_afford(pay):
		return false
	loan -= pay
	transact(&"loan_repayment", -pay)
	return true


func add_reputation(delta: float, lo: float, hi: float) -> void:
	var next: float = clampf(reputation + delta, lo, hi)
	if not is_equal_approx(next, reputation):
		reputation = next
		reputation_shifted.emit(reputation)


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


## Loan interest, daily summary, ledger reset, bankruptcy check. Daily cost
## providers run BEFORE this — CompanyManager owns the day loop.
func close_day(day: int, daily_interest: float, bankrupt_floor: float) -> Dictionary:
	if loan > 0.0:
		transact(&"loan_interest", -loan * daily_interest)
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
	ledger_today = {}
	if cash < bankrupt_floor:
		is_bankrupt = true
		went_bankrupt.emit()
	return summary


## Appends to the public move log, trimming to the newest 30 entries.
func log_move(day: int, kind: String, text: String) -> void:
	recent_moves.append({"day": day, "kind": kind, "text": text})
	while recent_moves.size() > 30:
		recent_moves.remove_at(0)
