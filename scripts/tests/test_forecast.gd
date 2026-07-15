extends SceneTree
## Headless tests for ForecastService: EWMA smoothing, demand-multiplier
## projection, and warnings that react to menu enable and marketing spikes.
## Run: godot --headless --script res://scripts/tests/test_forecast.gd

var _failures: int = 0


func _initialize() -> void:
	_test_ewma()
	_test_projection()
	_test_menu_enable_adds_warning()
	_test_marketing_spike_moves_severity()
	_test_campaign_boost_targets_ingredient()
	if _failures == 0:
		print("PASS test_forecast: all scenarios OK")
		quit(0)
	else:
		print("FAIL test_forecast: %d failure(s)" % _failures)
		quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("  FAIL: %s" % label)


func _test_ewma() -> void:
	var svc: ForecastService = ForecastService.new()
	_check(absf(svc.ewma(10.0, 20.0, 0.5) - 15.0) < 0.001, "ewma midpoint at alpha 0.5")
	_check(absf(svc.ewma(10.0, 20.0, 0.0) - 10.0) < 0.001, "ewma alpha 0 keeps previous")
	_check(absf(svc.ewma(10.0, 20.0, 1.0) - 20.0) < 0.001, "ewma alpha 1 takes today")


func _test_projection() -> void:
	var svc: ForecastService = ForecastService.new()
	_check(absf(svc.projected_daily_use(10.0, 1.5) - 15.0) < 0.001, "demand mult scales use")
	_check(svc.days_of_cover(30.0, 10.0) == 3.0, "days of cover = available / use")
	_check(svc.days_of_cover(30.0, 0.0) == INF, "idle ingredient never runs out")


func _test_menu_enable_adds_warning() -> void:
	var svc: ForecastService = ForecastService.new()
	# A freshly-enabled ingredient with low stock and normal demand.
	var rows: Array[Dictionary] = [
		{"ingredient_id": &"mozzarella", "available": 100.0, "base_use": 10.0},
		{"ingredient_id": &"truffle_oil", "available": 3.0, "base_use": 4.0},
	]
	var warnings: Array[Dictionary] = svc.warnings(rows, 1.0, {})
	_check(warnings.size() == 1, "only the thin ingredient warns")
	_check(warnings[0]["ingredient_id"] == &"truffle_oil", "truffle_oil flagged (0.75 days)")
	_check(warnings[0]["severity"] == &"critical", "under 1 day is critical")


func _test_marketing_spike_moves_severity() -> void:
	var svc: ForecastService = ForecastService.new()
	var rows: Array[Dictionary] = [
		{"ingredient_id": &"mozzarella", "available": 18.0, "base_use": 10.0},
	]
	# Normal demand: 1.8 days -> warning (not critical).
	var calm: Array[Dictionary] = svc.warnings(rows, 1.0, {})
	_check(calm.size() == 1 and calm[0]["severity"] == &"warning", "calm demand = warning")
	# A citywide campaign lifts demand 60%: 18 / 16 = 1.1 days -> still warning,
	# and a stronger spike tips it critical.
	var spike: Array[Dictionary] = svc.warnings(rows, 2.0, {})
	_check(spike.size() == 1 and spike[0]["severity"] == &"critical", "demand spike tips to critical")
	_check(float(spike[0]["days"]) < float(calm[0]["days"]), "projected cover shrinks under demand")


func _test_campaign_boost_targets_ingredient() -> void:
	var svc: ForecastService = ForecastService.new()
	var rows: Array[Dictionary] = [
		{"ingredient_id": &"mozzarella", "available": 40.0, "base_use": 10.0},
		{"ingredient_id": &"pepperoni", "available": 40.0, "base_use": 10.0},
	]
	# Both hold 4 days normally -> no warnings. Promote pepperoni (x1.6):
	# 40 / 16 = 2.5 days, still >= WARN_DAYS, so bump base a touch via demand.
	var boosted: Dictionary = {&"pepperoni": 2.4}
	var warnings: Array[Dictionary] = svc.warnings(rows, 1.0, boosted)
	_check(warnings.size() == 1 and warnings[0]["ingredient_id"] == &"pepperoni",
		"only the promoted ingredient warns")
	_check(String(warnings[0]["reason"]).contains("campaign"), "warning cites campaign demand")
