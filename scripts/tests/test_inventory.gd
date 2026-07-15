extends SceneTree
## Headless property tests for InventoryService / InventoryState / StockLot.
## Run: godot --headless --script res://scripts/tests/test_inventory.gd
## Pure lot math only — no autoload access, so it runs in bare script mode.

var _failures: int = 0


func _initialize() -> void:
	_test_fefo_ordering()
	_test_reserve_all_or_nothing()
	_test_consume_exactly_once()
	_test_release_idempotent()
	_test_spoilage_and_reresolve()
	_test_capacity_and_availability_never_negative()
	_test_random_walk_invariants()
	_test_save_round_trip()
	if _failures == 0:
		print("PASS test_inventory: all scenarios OK")
		quit(0)
	else:
		print("FAIL test_inventory: %d failure(s)" % _failures)
		quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("  FAIL: %s" % label)


func _mk_inv() -> InventoryState:
	var inv: InventoryState = InventoryState.new()
	inv.owner_kind = &"restaurant"
	inv.owner_id = 1
	return inv


func _test_fefo_ordering() -> void:
	var svc: InventoryService = InventoryService.new()
	var inv: InventoryState = _mk_inv()
	svc.add_lot(inv, &"mozzarella", 10.0, 0.5, 1.0, &"a", 0, 5000)
	svc.add_lot(inv, &"mozzarella", 10.0, 0.9, 2.0, &"b", 0, 1000)
	svc.add_lot(inv, &"mozzarella", 10.0, 0.7, 3.0, &"c", 0, 3000)
	var result: Dictionary = svc.take_fefo(inv, &"mozzarella", 12.0)
	# First-expiring lot (b, expiry 1000, cost 2.0) drains first, then c.
	_check(absf(float(result["cost"]) - (10.0 * 2.0 + 2.0 * 3.0)) < 0.01, "FEFO consumes earliest expiry first")
	_check(absf(inv.on_hand(&"mozzarella") - 18.0) < 0.01, "on_hand after take")
	_check(result["shortfall"].is_empty(), "no shortfall when stock suffices")


func _test_reserve_all_or_nothing() -> void:
	var svc: InventoryService = InventoryService.new()
	var inv: InventoryState = _mk_inv()
	svc.add_lot(inv, &"tomato", 5.0, 0.5, 1.0, &"a", 0, 5000)
	svc.add_lot(inv, &"basil", 1.0, 0.5, 1.0, &"a", 0, 5000)
	var needs: Array[Dictionary] = [
		{"ingredient_id": &"tomato", "qty": 3.0},
		{"ingredient_id": &"basil", "qty": 2.0},
	]
	_check(not svc.reserve(inv, 1, needs), "reserve fails when one ingredient is short")
	_check(inv.reserved_qty(&"tomato") == 0.0, "failed reserve holds nothing (tomato)")
	_check(inv.reserved_qty(&"basil") == 0.0, "failed reserve holds nothing (basil)")
	var ok_needs: Array[Dictionary] = [
		{"ingredient_id": &"tomato", "qty": 3.0},
		{"ingredient_id": &"basil", "qty": 1.0},
	]
	_check(svc.reserve(inv, 1, ok_needs), "reserve succeeds when covered")
	_check(absf(inv.available(&"tomato") - 2.0) < 0.01, "available excludes reserved")
	# Same needs twice: double demand must respect the earlier claim.
	var double_needs: Array[Dictionary] = [{"ingredient_id": &"tomato", "qty": 2.5}]
	_check(not svc.reserve(inv, 2, double_needs), "second reserve sees remaining availability only")


func _test_consume_exactly_once() -> void:
	var svc: InventoryService = InventoryService.new()
	var inv: InventoryState = _mk_inv()
	svc.add_lot(inv, &"pepperoni", 4.0, 0.6, 1.5, &"a", 0, 5000)
	var needs: Array[Dictionary] = [{"ingredient_id": &"pepperoni", "qty": 2.0}]
	svc.reserve(inv, 7, needs)
	var result: Dictionary = svc.consume(inv, 7)
	_check(absf(float(result["cost"]) - 3.0) < 0.01, "consume cost = qty * unit_cost")
	_check(absf(inv.on_hand(&"pepperoni") - 2.0) < 0.01, "stock reduced once")
	_check(absf(inv.total_consumed - 2.0) < 0.01, "audit total_consumed")
	var again: Dictionary = svc.consume(inv, 7)
	_check(float(again["qty"]) == 0.0 and again["shortfall"].is_empty(), "second consume is a no-op")
	_check(absf(inv.on_hand(&"pepperoni") - 2.0) < 0.01, "no double consumption")


func _test_release_idempotent() -> void:
	var svc: InventoryService = InventoryService.new()
	var inv: InventoryState = _mk_inv()
	svc.add_lot(inv, &"flourish", 4.0, 0.6, 1.0, &"a", 0, 5000)
	var needs: Array[Dictionary] = [{"ingredient_id": &"flourish", "qty": 3.0}]
	svc.reserve(inv, 9, needs)
	_check(absf(inv.reserved_qty(&"flourish") - 3.0) < 0.01, "reserved after reserve")
	svc.release(9)
	_check(inv.reserved_qty(&"flourish") == 0.0, "release frees reservation")
	svc.release(9)
	svc.release(12345)
	_check(inv.reserved_qty(&"flourish") == 0.0, "release is idempotent / unknown ids safe")


func _test_spoilage_and_reresolve() -> void:
	var svc: InventoryService = InventoryService.new()
	var inv: InventoryState = _mk_inv()
	svc.add_lot(inv, &"basil", 3.0, 0.9, 2.0, &"a", 0, 100)
	svc.add_lot(inv, &"basil", 5.0, 0.5, 1.0, &"b", 0, 9000)
	var needs: Array[Dictionary] = [{"ingredient_id": &"basil", "qty": 3.0}]
	svc.reserve(inv, 11, needs)  # lands on the earlier-expiring lot
	var spoiled: Dictionary = svc.spoil_tick(inv, 500)
	_check(absf(float(spoiled["wasted_qty"]) - 3.0) < 0.01, "expired lot spoils even while reserved")
	_check(absf(inv.total_wasted - 3.0) < 0.01, "audit total_wasted")
	var result: Dictionary = svc.consume(inv, 11)
	_check(absf(float(result["qty"]) - 3.0) < 0.01, "consume re-resolves onto surviving lots")
	_check(result["shortfall"].is_empty(), "no shortfall while other lots cover")
	_check(absf(inv.on_hand(&"basil") - 2.0) < 0.01, "post re-resolve on_hand")
	# Now exhaust and verify shortfall reporting.
	svc.add_lot(inv, &"basil", 1.0, 0.5, 1.0, &"c", 0, 200)
	var needs2: Array[Dictionary] = [{"ingredient_id": &"basil", "qty": 3.0}]
	svc.reserve(inv, 12, needs2)
	svc.spoil_tick(inv, 9500)  # everything left expires
	var starved: Dictionary = svc.consume(inv, 12)
	_check(not starved["shortfall"].is_empty(), "shortfall reported when nothing survives")


func _test_capacity_and_availability_never_negative() -> void:
	var svc: InventoryService = InventoryService.new()
	var inv: InventoryState = _mk_inv()
	svc.add_lot(inv, &"corn", 2.0, 0.5, 1.0, &"a", 0, 5000)
	var result: Dictionary = svc.take_fefo(inv, &"corn", 10.0)
	_check(absf(float(result["qty"]) - 2.0) < 0.01, "take_fefo caps at stock")
	_check(inv.on_hand(&"corn") >= 0.0, "on_hand never negative")
	var short: Array = result["shortfall"]
	_check(short.size() == 1 and absf(float(short[0]["qty"]) - 8.0) < 0.01, "shortfall reports remainder")


func _test_random_walk_invariants() -> void:
	var svc: InventoryService = InventoryService.new()
	var inv: InventoryState = _mk_inv()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1337
	var ingredients: Array[StringName] = [&"a", &"b", &"c"]
	var live_orders: Array[int] = []
	var order_seq: int = 100
	var now: int = 0
	for step: int in range(600):
		now += rng.randi_range(0, 40)
		match rng.randi_range(0, 4):
			0:
				var ing: StringName = ingredients[rng.randi_range(0, 2)]
				svc.add_lot(inv, ing, rng.randf_range(1.0, 8.0), 0.5,
					rng.randf_range(0.5, 3.0), &"s", now, now + rng.randi_range(50, 2000))
			1:
				var needs: Array[Dictionary] = [{
					"ingredient_id": ingredients[rng.randi_range(0, 2)],
					"qty": rng.randf_range(0.5, 5.0),
				}]
				order_seq += 1
				if svc.reserve(inv, order_seq, needs):
					live_orders.append(order_seq)
			2:
				if not live_orders.is_empty():
					var order_id: int = live_orders.pop_at(rng.randi_range(0, live_orders.size() - 1))
					svc.consume(inv, order_id)
			3:
				if not live_orders.is_empty():
					var order_id: int = live_orders.pop_at(rng.randi_range(0, live_orders.size() - 1))
					svc.release(order_id)
			4:
				svc.spoil_tick(inv, now)
		for lot: StockLot in inv.lots:
			if lot.qty < -0.001 or lot.reserved < -0.001:
				_check(false, "negative lot value at step %d" % step)
				return
	# Settle: everything still reserved must match the map exactly.
	_check(svc.reserved_matches_map(inv), "reservation map matches lot.reserved after random walk")
	for order_id: int in live_orders:
		svc.release(order_id)
	var held: float = 0.0
	for lot: StockLot in inv.lots:
		held += lot.reserved
	_check(held < 0.01, "all reservations released cleanly")


func _test_save_round_trip() -> void:
	var svc: InventoryService = InventoryService.new()
	var inv: InventoryState = _mk_inv()
	svc.add_lot(inv, &"mozzarella", 7.5, 0.8, 1.25, &"antonios_dairy", 100, 10180)
	var policy: ReorderPolicy = ReorderPolicy.new()
	policy.ingredient_id = &"mozzarella"
	policy.reorder_point = 5.0
	policy.target_stock = 12.0
	inv.policies[&"mozzarella"] = policy
	inv.consumed_today[&"mozzarella"] = 3.0
	var path: String = "user://test_inventory_roundtrip.tres"
	var err: Error = ResourceSaver.save(inv, path)
	_check(err == OK, "inventory saves")
	var loaded: InventoryState = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded != null, "inventory loads")
	if loaded != null:
		_check(loaded.lots.size() == 1, "lots survive round trip")
		if loaded.lots.size() == 1:
			var lot: StockLot = loaded.lots[0]
			_check(absf(lot.qty - 7.5) < 0.001 and lot.expiry_minute == 10180
				and lot.supplier_id == &"antonios_dairy", "lot fields survive")
		var loaded_policy: ReorderPolicy = loaded.policy_for(&"mozzarella")
		_check(loaded_policy != null and absf(loaded_policy.target_stock - 12.0) < 0.001,
			"policies survive round trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
