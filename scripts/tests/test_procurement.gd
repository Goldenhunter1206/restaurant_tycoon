extends SceneTree
## Headless tests for ProcurementService: offers, seeded reliability rolls,
## min-order padding, outage handling, delivery tick and reorder dedupe.
## Run: godot --headless --script res://scripts/tests/test_procurement.gd
## The service is autoload-free: ingredient defs load straight from .tres and
## are injected via the lookup Callable, cash is a plain float.

var _failures: int = 0
var _ing_cache: Dictionary = {}


func _initialize() -> void:
	if _lookup(&"mozzarella") == null:
		printerr("FAIL: ingredient catalog unavailable")
		quit(1)
		return
	_test_offers()
	_test_reliability_rolls()
	_test_min_order()
	_test_outage()
	_test_tick_delivery_and_loss()
	_test_reorder_dedupe()
	if _failures == 0:
		print("PASS test_procurement: all scenarios OK")
		quit(0)
	else:
		print("FAIL test_procurement: %d failure(s)" % _failures)
		quit(1)


func _lookup(id: StringName) -> IngredientDef:
	if not _ing_cache.has(id):
		var path: String = "res://data/ingredients/%s.tres" % id
		_ing_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return _ing_cache[id]


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("  FAIL: %s" % label)


func _supplier(id: String) -> SupplierDef:
	return load("res://data/suppliers/%s.tres" % id)


func _defs() -> Dictionary:
	var out: Dictionary = {}
	for id: String in ["valuemart", "bella_fresh", "antonios_dairy", "metro_meats", "quickdrop", "global_sundries"]:
		var def: SupplierDef = _supplier(id)
		out[def.id] = def
	return out


func _lines(ing: StringName, qty: float) -> Array[Dictionary]:
	return [{"ingredient_id": ing, "qty": qty}]


func _test_offers() -> void:
	var svc: ProcurementService = ProcurementService.new()
	var none: Array[SupplyDisruption] = []
	var offers: Array[Dictionary] = svc.offers_for(_defs(), none, &"mozzarella", 0, _lookup)
	_check(offers.size() >= 3, "several suppliers carry mozzarella (got %d)" % offers.size())
	for i: int in range(offers.size() - 1):
		_check(float(offers[i]["unit_cost"]) <= float(offers[i + 1]["unit_cost"]), "offers sorted by price")
	var meat_offers: Array[Dictionary] = svc.offers_for(_defs(), none, &"beef_patty", 0, _lookup)
	for offer: Dictionary in meat_offers:
		_check(offer["supplier_id"] != &"bella_fresh", "produce supplier never offers meat")


func _test_reliability_rolls() -> void:
	var svc: ProcurementService = ProcurementService.new()
	var none: Array[SupplyDisruption] = []
	var supplier: SupplierDef = _supplier("valuemart")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var on_time: int = 0
	var delayed_or_lost: int = 0
	for i: int in range(200):
		var po: PurchaseOrder = svc.make_draft(i, &"player", supplier, &"restaurant", 1,
			_lines(&"mozzarella", 400.0), none, 0, false, _lookup)
		var result: CommandResult = svc.place(po, supplier, 100000.0, none, rng, 0)
		_check(result.ok, "placement succeeds with cash + healthy supplier")
		if po.eta_minute == supplier.lead_time_minutes and po.failure_reason == "":
			on_time += 1
		else:
			delayed_or_lost += 1
	_check(on_time > 150 and on_time < 200, "~90%% on-time (got %d/200)" % on_time)
	_check(delayed_or_lost > 0, "some orders are delayed or lost")
	var rng_a: RandomNumberGenerator = RandomNumberGenerator.new()
	var rng_b: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_a.seed = 7
	rng_b.seed = 7
	var etas_a: Array[int] = []
	var etas_b: Array[int] = []
	for i: int in range(30):
		var pa: PurchaseOrder = svc.make_draft(i, &"player", supplier, &"restaurant", 1,
			_lines(&"mozzarella", 400.0), none, 0, false, _lookup)
		svc.place(pa, supplier, 100000.0, none, rng_a, 0)
		etas_a.append(pa.eta_minute)
		var pb: PurchaseOrder = svc.make_draft(i, &"player", supplier, &"restaurant", 1,
			_lines(&"mozzarella", 400.0), none, 0, false, _lookup)
		svc.place(pb, supplier, 100000.0, none, rng_b, 0)
		etas_b.append(pb.eta_minute)
	_check(etas_a == etas_b, "seeded reliability is deterministic")


func _test_min_order() -> void:
	var svc: ProcurementService = ProcurementService.new()
	var none: Array[SupplyDisruption] = []
	var supplier: SupplierDef = _supplier("valuemart")  # min_order_value 150
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	var small: PurchaseOrder = svc.make_draft(1, &"player", supplier, &"restaurant", 1,
		_lines(&"mozzarella", 5.0), none, 0, false, _lookup)
	var rejected: CommandResult = svc.place(small, supplier, 10000.0, none, rng, 0)
	_check(not rejected.ok and rejected.code == &"min_order", "small order rejected by min_order")
	_check(small.status == &"draft", "rejected order stays a draft")
	var lines: Array = [{"ingredient_id": &"mozzarella", "qty": 5.0}]
	svc.pad_to_min_order(lines, supplier, _lookup)
	var typed: Array[Dictionary] = []
	for line: Dictionary in lines:
		typed.append(line)
	var padded: PurchaseOrder = svc.make_draft(2, &"player", supplier, &"restaurant", 1,
		typed, none, 0, false, _lookup)
	_check(padded.goods_cost() >= supplier.min_order_value - 0.01, "pad_to_min_order clears the minimum")


func _test_outage() -> void:
	var svc: ProcurementService = ProcurementService.new()
	var supplier: SupplierDef = _supplier("quickdrop")
	var outage: SupplyDisruption = SupplyDisruption.new()
	outage.supplier_id = supplier.id
	outage.kind = &"outage"
	outage.start_minute = 0
	outage.end_minute = 1000
	var disruptions: Array[SupplyDisruption] = [outage]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	var po: PurchaseOrder = svc.make_draft(1, &"player", supplier, &"restaurant", 1,
		_lines(&"mozzarella", 10.0), disruptions, 100, false, _lookup)
	var result: CommandResult = svc.place(po, supplier, 10000.0, disruptions, rng, 100)
	_check(not result.ok and result.code == &"supplier_offline", "outage blocks placement")
	_check(po.status == &"failed", "order kept as failed for retry")
	var retry: CommandResult = svc.place(po, supplier, 10000.0, disruptions, rng, 2000)
	_check(retry.ok, "retry succeeds after outage ends")


func _test_tick_delivery_and_loss() -> void:
	var svc: ProcurementService = ProcurementService.new()
	var none: Array[SupplyDisruption] = []
	var supplier: SupplierDef = _supplier("quickdrop")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	var po: PurchaseOrder = svc.make_draft(1, &"player", supplier, &"restaurant", 1,
		_lines(&"mozzarella", 10.0), none, 0, false, _lookup)
	svc.place(po, supplier, 10000.0, none, rng, 0)
	var pos: Array[PurchaseOrder] = [po]
	var early: Array[Dictionary] = svc.tick(pos, po.eta_minute - 200)
	_check(early.is_empty(), "nothing settles before ETA")
	var events: Array[Dictionary] = svc.tick(pos, po.eta_minute + 1)
	_check(events.size() == 1, "one settle event at ETA")
	if events.size() == 1:
		var expected: StringName = &"failed" if po.failure_reason != "" else &"delivered"
		_check(events[0]["kind"] == expected, "event kind matches roll outcome")
	var lost: PurchaseOrder = PurchaseOrder.new()
	lost.id = 2
	lost.company_id = &"player"
	lost.supplier_id = supplier.id
	lost.status = &"confirmed"
	lost.eta_minute = 500
	lost.failure_reason = "__lost__"
	lost.lines = [{"ingredient_id": &"mozzarella", "qty": 10.0, "unit_cost": 1.0, "quality": 0.5}]
	var lost_arr: Array[PurchaseOrder] = [lost]
	var lost_events: Array[Dictionary] = svc.tick(lost_arr, 501)
	_check(lost_events.size() == 1 and lost_events[0]["kind"] == &"failed", "lost order fails at ETA")
	_check(lost.status == &"failed" and lost.failure_reason != "__lost__", "loss reason humanized")


func _test_reorder_dedupe() -> void:
	var svc: ProcurementService = ProcurementService.new()
	var inv: InventoryState = InventoryState.new()
	inv.owner_kind = &"restaurant"
	inv.owner_id = 1
	var policy: ReorderPolicy = ReorderPolicy.new()
	policy.ingredient_id = &"mozzarella"
	policy.reorder_point = 20.0
	policy.target_stock = 50.0
	inv.policies[&"mozzarella"] = policy
	var fallback: Callable = func(_rest: Variant, _ing: StringName) -> float: return 10.0
	var empty_orders: Array[PurchaseOrder] = []
	var needs: Dictionary = svc.reorder_needs(inv, null, empty_orders, _defs(), fallback, _lookup)
	_check(needs.size() == 1, "low stock triggers one supplier group")
	var group_lines: Array = needs.values()[0] if needs.size() == 1 else []
	_check(group_lines.size() == 1 and absf(float(group_lines[0]["qty"]) - 50.0) < 0.01,
		"orders up to target when empty")
	var open_po: PurchaseOrder = PurchaseOrder.new()
	open_po.dest_kind = &"restaurant"
	open_po.dest_id = 1
	open_po.status = &"confirmed"
	open_po.lines = [{"ingredient_id": &"mozzarella", "qty": 60.0, "unit_cost": 1.0, "quality": 0.5}]
	var with_open: Array[PurchaseOrder] = [open_po]
	var needs_after: Dictionary = svc.reorder_needs(inv, null, with_open, _defs(), fallback, _lookup)
	_check(needs_after.is_empty(), "inbound stock suppresses duplicate orders")
	open_po.status = &"draft"
	var needs_draft: Dictionary = svc.reorder_needs(inv, null, with_open, _defs(), fallback, _lookup)
	_check(needs_draft.is_empty(), "existing drafts suppress duplicate suggestions")
