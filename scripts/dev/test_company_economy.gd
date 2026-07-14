extends SceneTree
## Dev-only headless test for CompanyState bookkeeping — the shared economy
## core every company (player and AI rival) runs on.
## Run: godot --headless --path . --script res://scripts/dev/test_company_economy.gd
## Exits 0 when every assertion passes, 1 otherwise.

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_test_transact()
	_test_loans()
	_test_reputation()
	_test_close_day()
	_test_bankruptcy()
	_test_history_queries()
	_test_move_log()
	_test_command_result()
	print("---")
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s" % label)


func _company(cash: float = 1000.0) -> CompanyState:
	var company: CompanyState = CompanyState.new()
	company.id = &"test"
	company.cash = cash
	return company


func _test_transact() -> void:
	print("transact:")
	var company: CompanyState = _company()
	company.transact(&"sales", 250.0)
	company.transact(&"wages", -100.0)
	company.transact(&"sales", 50.0)
	_check(company.cash == 1200.0, "cash tracks all movements")
	_check(float(company.ledger_today[&"sales"]) == 300.0, "ledger accumulates per category")
	_check(company.income_today() == 300.0, "income_today sums positives")
	_check(company.expenses_today() == -100.0, "expenses_today sums negatives")
	_check(company.profit_today() == 200.0, "profit is income + expenses")
	_check(company.can_afford(1200.0) and not company.can_afford(1200.5), "can_afford boundary")


func _test_loans() -> void:
	print("loans:")
	var company: CompanyState = _company()
	_check(company.take_loan(4000.0, 5000.0), "loan under cap accepted")
	_check(company.cash == 5000.0 and company.loan == 4000.0, "loan credits cash + records debt")
	_check(not company.take_loan(2000.0, 5000.0), "loan over cap rejected")
	_check(company.repay_loan(1000.0), "repay accepted")
	_check(company.loan == 3000.0 and company.cash == 4000.0, "repay reduces both")
	company.cash = 0.0
	_check(not company.repay_loan(500.0), "repay without cash rejected")


func _test_reputation() -> void:
	print("reputation:")
	var company: CompanyState = _company()
	company.reputation = 4.9
	company.add_reputation(0.5, 1.0, 5.0)
	_check(company.reputation == 5.0, "reputation clamps at max")
	company.add_reputation(-10.0, 1.0, 5.0)
	_check(company.reputation == 1.0, "reputation clamps at min")


func _test_close_day() -> void:
	print("close_day:")
	var company: CompanyState = _company(2000.0)
	company.loan = 1000.0
	company.transact(&"sales", 500.0)
	var summary: Dictionary = company.close_day(3, 0.01, -50000.0)
	_check(int(summary["day"]) == 2, "summary is for the finished day")
	_check(is_equal_approx(float(summary["income"]), 500.0), "summary income")
	_check(is_equal_approx(float(company.ledger_today.size()), 0.0), "ledger resets after close")
	_check(company.history.size() == 1, "history appended")
	_check(is_equal_approx(company.cash, 2490.0), "loan interest charged (1%)")
	_check(not company.is_bankrupt, "solvent company not bankrupt")


func _test_bankruptcy() -> void:
	print("bankruptcy:")
	var company: CompanyState = _company(100.0)
	var fired: Array = []
	company.went_bankrupt.connect(func() -> void: fired.append(true))
	company.transact(&"disaster", -60000.0)
	company.close_day(2, 0.0, -50000.0)
	_check(company.is_bankrupt, "cash below floor flags bankruptcy")
	_check(fired.size() == 1, "went_bankrupt emitted")


func _test_history_queries() -> void:
	print("history queries:")
	var company: CompanyState = _company()
	for day: int in range(2, 6):
		company.transact(&"sales", 100.0 * day)
		company.transact(&"rent", -40.0)
		company.close_day(day, 0.0, -50000.0)
	# "3 days" = today's (empty, post-close) ledger + the last two closed days.
	var totals: Dictionary = company.category_totals(3)
	_check(is_equal_approx(float(totals[&"rent"]), -80.0), "category_totals spans requested days")
	var profits: Array[float] = company.series("profit", 2)
	_check(profits.size() == 2 and is_equal_approx(profits[1], 460.0), "series returns oldest-first window")


func _test_move_log() -> void:
	print("move log:")
	var company: CompanyState = _company()
	for i: int in 40:
		company.log_move(i, "news", "move %d" % i)
	_check(company.recent_moves.size() == 30, "recent_moves trimmed to 30")
	_check(String(company.recent_moves[-1]["text"]) == "move 39", "newest move kept")


func _test_command_result() -> void:
	print("command result:")
	var ok_result: CommandResult = CommandResult.good("payload")
	_check(ok_result.ok and String(ok_result.payload) == "payload", "good() carries payload")
	var fail_result: CommandResult = CommandResult.fail(&"nope", "reason")
	_check(not fail_result.ok and fail_result.code == &"nope" and fail_result.message == "reason", "fail() carries code + message")
