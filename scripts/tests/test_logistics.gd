extends SceneTree
## Headless tests for LogisticsService: route ETA math, transfer build (FEFO
## lot-identity preserved), delivery, bounce, capacity, and the settle tick.
## Run: godot --headless --script res://scripts/tests/test_logistics.gd
## Autoload-free — a tiny hand-built RoadGraph stands in for the city.

var _failures: int = 0


func _initialize() -> void:
	_test_route_eta()
	_test_unreachable()
	_test_transfer_preserves_lot_identity()
	_test_transfer_deliver_and_capacity()
	_test_bounce_returns_goods()
	_test_tick_settles_at_eta()
	if _failures == 0:
		print("PASS test_logistics: all scenarios OK")
		quit(0)
	else:
		print("FAIL test_logistics: %d failure(s)" % _failures)
		quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("  FAIL: %s" % label)


## A minimal 3-node lane graph: A(0,0,0) - B(90,0,0) - C(90,0,90).
func _mk_graph() -> RoadGraph:
	var g: RoadGraph = RoadGraph.new()
	g.lane_points = PackedVector3Array([Vector3(0, 0, 0), Vector3(90, 0, 0), Vector3(90, 0, 90)])
	g.lane_from = PackedInt32Array([0, 1, 1, 2])
	g.lane_to = PackedInt32Array([1, 0, 2, 1])
	g.lane_kind = PackedInt32Array([0, 0, 0, 0])
	g.lane_enters = PackedInt32Array([-1, -1, -1, -1])
	g.lane_enter_heading = PackedInt32Array([0, 0, 0, 0])
	# Minimal sidewalk graph so AStar reserve_space isn't handed 0 nodes.
	g.side_points = PackedVector3Array([Vector3(0, 0, 2), Vector3(90, 0, 2)])
	g.side_from = PackedInt32Array([0])
	g.side_to = PackedInt32Array([1])
	g.side_crossing = PackedInt32Array([0])
	g.side_cross_axis = PackedInt32Array([0])
	g.build_runtime()
	return g


func _mk_warehouse() -> WarehouseState:
	var wh: WarehouseState = WarehouseState.new()
	wh.id = 1
	wh.company_id = &"player"
	wh.world_pos = Vector3(0, 0, 0)
	wh.inventory = InventoryState.new()
	wh.inventory.owner_kind = &"warehouse"
	wh.inventory.owner_id = 1
	wh.inventory.capacity_by_class = {&"dry": 1000.0, &"chilled": 500.0, &"frozen": 500.0}
	return wh


func _test_route_eta() -> void:
	var svc: LogisticsService = LogisticsService.new()
	var g: RoadGraph = _mk_graph()
	# A -> C is 90 + 90 = 180 units at 9 u/min = 20 min drive, x1.2 buffer + 25 handling.
	var eta: float = svc.route_eta_minutes(g, Vector3(0, 0, 0), Vector3(90, 0, 90))
	var expected: float = LogisticsService.HANDLING_MINUTES + 180.0 / 9.0 * LogisticsService.DRIVE_BUFFER
	_check(absf(eta - expected) < 0.5, "ETA matches edge-length math (got %.1f, want %.1f)" % [eta, expected])
	_check(eta > 0.0, "reachable route returns positive ETA")


func _test_unreachable() -> void:
	var svc: LogisticsService = LogisticsService.new()
	_check(svc.route_eta_minutes(null, Vector3.ZERO, Vector3.ONE) < 0.0, "null graph -> unreachable")


func _test_transfer_preserves_lot_identity() -> void:
	var inv_svc: InventoryService = InventoryService.new()
	var logi: LogisticsService = LogisticsService.new()
	var wh: WarehouseState = _mk_warehouse()
	# Two lots, distinct expiry; FEFO should take the earlier one first.
	inv_svc.add_lot(wh.inventory, &"mozzarella", 10.0, 0.9, 1.2, &"antonios_dairy", 0, 5000)
	inv_svc.add_lot(wh.inventory, &"mozzarella", 10.0, 0.6, 0.8, &"valuemart", 0, 2000)
	var wants: Array[Dictionary] = [{"ingredient_id": &"mozzarella", "qty": 12.0}]
	var transfer: TransferOrder = logi.build_transfer(inv_svc, 5, &"player", wh, 42,
		wants, 30.0, 20.0, 100, false)
	_check(transfer != null, "transfer builds when stock exists")
	_check(absf(transfer.total_qty() - 12.0) < 0.01, "transfer carries requested qty")
	_check(absf(wh.inventory.available(&"mozzarella") - 8.0) < 0.01, "warehouse stock drawn down")
	# The earlier-expiry (valuemart, expiry 2000) lot must be fully consumed first.
	var carried_valuemart: float = 0.0
	var carried_antonios: float = 0.0
	for line: Dictionary in transfer.lines:
		if line["supplier_id"] == &"valuemart":
			carried_valuemart += float(line["qty"])
		elif line["supplier_id"] == &"antonios_dairy":
			carried_antonios += float(line["qty"])
	_check(absf(carried_valuemart - 10.0) < 0.01, "FEFO: earlier-expiry lot fully carried")
	_check(absf(carried_antonios - 2.0) < 0.01, "FEFO: later lot covers remainder")
	# Expiry survives the trip.
	for line: Dictionary in transfer.lines:
		if line["supplier_id"] == &"valuemart":
			_check(int(line["expiry_minute"]) == 2000, "lot expiry rides along in transfer")


func _test_transfer_deliver_and_capacity() -> void:
	var inv_svc: InventoryService = InventoryService.new()
	var logi: LogisticsService = LogisticsService.new()
	var wh: WarehouseState = _mk_warehouse()
	inv_svc.add_lot(wh.inventory, &"basil", 20.0, 0.8, 0.5, &"bella_fresh", 0, 3000)
	var dest: InventoryState = InventoryState.new()
	dest.owner_kind = &"restaurant"
	dest.owner_id = 42
	var wants: Array[Dictionary] = [{"ingredient_id": &"basil", "qty": 8.0}]
	var transfer: TransferOrder = logi.build_transfer(inv_svc, 6, &"player", wh, 42,
		wants, 30.0, 20.0, 100, false)
	logi.deliver_transfer(inv_svc, transfer, dest)
	_check(absf(dest.on_hand(&"basil") - 8.0) < 0.01, "delivered stock lands in destination")
	_check(transfer.status == &"delivered", "transfer marked delivered")
	_check(dest.lots[0].expiry_minute == 3000, "delivered lot keeps original expiry")
	# free_capacity respects the class ceiling.
	var class_of: Callable = func(_i: StringName) -> StringName: return &"chilled"
	var volume_of: Callable = func(_i: StringName) -> float: return 1.0
	dest.capacity_by_class = {&"chilled": 10.0}
	var free: float = logi.free_capacity(dest, &"chilled", class_of, volume_of)
	_check(absf(free - 2.0) < 0.01, "free_capacity = ceiling - used")


func _test_bounce_returns_goods() -> void:
	var inv_svc: InventoryService = InventoryService.new()
	var logi: LogisticsService = LogisticsService.new()
	var wh: WarehouseState = _mk_warehouse()
	inv_svc.add_lot(wh.inventory, &"tomato", 15.0, 0.7, 0.4, &"valuemart", 0, 4000)
	var wants: Array[Dictionary] = [{"ingredient_id": &"tomato", "qty": 6.0}]
	var transfer: TransferOrder = logi.build_transfer(inv_svc, 7, &"player", wh, 99,
		wants, 30.0, 20.0, 100, false)
	_check(absf(wh.inventory.available(&"tomato") - 9.0) < 0.01, "stock left warehouse")
	logi.bounce_transfer(inv_svc, transfer, wh.inventory)
	_check(absf(wh.inventory.available(&"tomato") - 15.0) < 0.01, "bounced goods return to warehouse")
	_check(transfer.status == &"cancelled", "bounced transfer cancelled")


func _test_tick_settles_at_eta() -> void:
	var inv_svc: InventoryService = InventoryService.new()
	var logi: LogisticsService = LogisticsService.new()
	var wh: WarehouseState = _mk_warehouse()
	inv_svc.add_lot(wh.inventory, &"flour", 30.0, 0.9, 0.3, &"valuemart", 0, 90000)
	var dest: InventoryState = InventoryState.new()
	dest.owner_kind = &"restaurant"
	dest.owner_id = 42
	var wants: Array[Dictionary] = [{"ingredient_id": &"flour", "qty": 10.0}]
	var transfer: TransferOrder = logi.build_transfer(inv_svc, 8, &"player", wh, 42,
		wants, 30.0, 20.0, 100, false)
	var transfers: Array[TransferOrder] = [transfer]
	var dest_lookup: Callable = func(building_id: int) -> InventoryState:
		return dest if building_id == 42 else null
	var wh_lookup: Callable = func(warehouse_id: int) -> InventoryState:
		return wh.inventory if warehouse_id == 1 else null
	var early: Array[Dictionary] = logi.tick(inv_svc, transfers, transfer.eta_minute - 5, dest_lookup, wh_lookup)
	_check(early.is_empty(), "nothing settles before ETA")
	var events: Array[Dictionary] = logi.tick(inv_svc, transfers, transfer.eta_minute + 1, dest_lookup, wh_lookup)
	_check(events.size() == 1 and events[0]["kind"] == &"delivered", "settles delivered at ETA")
	_check(absf(dest.on_hand(&"flour") - 10.0) < 0.01, "stock delivered on tick")
	# A transfer to a vanished destination bounces back to the warehouse.
	var gone: TransferOrder = logi.build_transfer(inv_svc, 9, &"player", wh, 777,
		[{"ingredient_id": &"flour", "qty": 5.0}], 30.0, 20.0, 200, false)
	var gone_events: Array[Dictionary] = logi.tick(inv_svc, [gone] as Array[TransferOrder],
		gone.eta_minute + 1, dest_lookup, wh_lookup)
	_check(gone_events.size() == 1 and gone_events[0]["kind"] == &"bounced", "vanished dest -> bounce")
	# Started 30, transfer 8 took 10 (delivered), transfer 9 took 5 then bounced back.
	_check(absf(wh.inventory.available(&"flour") - 20.0) < 0.01, "bounced goods restored to warehouse")
