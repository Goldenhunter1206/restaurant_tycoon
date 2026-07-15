class_name InventoryService
extends RefCounted
## Pure lot math for InventoryState: FEFO reservations, consumption, spoilage.
## No money, no signals, no autoload access — SupplyManager owns those.
## Invariants: qty and reserved never go negative; reservations are keyed by
## order id and are idempotent to release. Reservations are runtime-only —
## they do not survive save/load (orders don't either), so restored
## inventories must pass through clear_runtime_reservations().

## order_id -> {"inv": InventoryState, "entries": [{"lot": StockLot, "qty": float}]}
var _reservations: Dictionary = {}


func has_reservation(order_id: int) -> bool:
	return _reservations.has(order_id)


func reservation_count() -> int:
	return _reservations.size()


## needs: [{ingredient_id, qty}] -> [{ingredient_id, missing}] (empty = all coverable).
func missing_for(inv: InventoryState, needs: Array[Dictionary]) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	var claimed: Dictionary = {}
	for need: Dictionary in needs:
		var ing: StringName = need.get("ingredient_id", &"")
		var qty: float = float(need.get("qty", 0.0))
		if ing == &"" or qty <= 0.0:
			continue
		var already: float = float(claimed.get(ing, 0.0))
		var short: float = already + qty - inv.available(ing)
		claimed[ing] = already + qty
		if short > 0.0001:
			missing.append({"ingredient_id": ing, "missing": short})
	return missing


## All-or-nothing FEFO reservation. Returns true only if every need was
## covered; on failure nothing is held.
func reserve(inv: InventoryState, order_id: int, needs: Array[Dictionary]) -> bool:
	if _reservations.has(order_id):
		return true
	if not missing_for(inv, needs).is_empty():
		return false
	var entries: Array[Dictionary] = []
	for need: Dictionary in needs:
		var ing: StringName = need.get("ingredient_id", &"")
		var remaining: float = float(need.get("qty", 0.0))
		if ing == &"" or remaining <= 0.0:
			continue
		for lot: StockLot in inv.lots_for(ing):
			if remaining <= 0.0001:
				break
			var take: float = minf(remaining, lot.available())
			if take <= 0.0:
				continue
			lot.reserved += take
			entries.append({"lot": lot, "qty": take})
			remaining -= take
	_reservations[order_id] = {"inv": inv, "entries": entries}
	return true


## Idempotent: releasing an unknown or already-consumed order is a no-op.
func release(order_id: int) -> void:
	var res: Dictionary = _reservations.get(order_id, {})
	if res.is_empty():
		return
	for entry: Dictionary in res["entries"]:
		var lot: StockLot = entry["lot"]
		lot.reserved = maxf(lot.reserved - float(entry["qty"]), 0.0)
	_reservations.erase(order_id)


## Consume a reservation. Mapped lots may have spoiled since reserve — the
## remainder re-resolves FEFO against live stock; anything still uncovered
## comes back as shortfall for the caller's emergency policy.
## Returns {cost, qty, quality_qty (Σ qty*quality), shortfall: [{ingredient_id, qty}]}.
func consume(inv: InventoryState, order_id: int) -> Dictionary:
	var result: Dictionary = {"cost": 0.0, "qty": 0.0, "quality_qty": 0.0, "shortfall": []}
	var res: Dictionary = _reservations.get(order_id, {})
	if res.is_empty():
		return result
	var pending: Dictionary = {}
	for entry: Dictionary in res["entries"]:
		var lot: StockLot = entry["lot"]
		var want: float = float(entry["qty"])
		lot.reserved = maxf(lot.reserved - want, 0.0)
		var take: float = minf(want, lot.qty)
		if take > 0.0:
			_drain(inv, lot, take, result)
		if want - take > 0.0001:
			var ing: StringName = lot.ingredient_id
			pending[ing] = float(pending.get(ing, 0.0)) + (want - take)
	_reservations.erase(order_id)
	for ing: StringName in pending.keys():
		var remainder: float = _take_fefo_into(inv, ing, pending[ing], result)
		if remainder > 0.0001:
			result["shortfall"].append({"ingredient_id": ing, "qty": remainder})
	_prune_empty(inv)
	return result


## Direct FEFO draw without a reservation (transfers, unreserved cooking,
## emergency paths). Returns same shape as consume().
func take_fefo(inv: InventoryState, ingredient_id: StringName, qty: float) -> Dictionary:
	var result: Dictionary = {"cost": 0.0, "qty": 0.0, "quality_qty": 0.0, "shortfall": []}
	var remainder: float = _take_fefo_into(inv, ingredient_id, qty, result)
	if remainder > 0.0001:
		result["shortfall"].append({"ingredient_id": ingredient_id, "qty": remainder})
	_prune_empty(inv)
	return result


func add_lot(inv: InventoryState, ingredient_id: StringName, qty: float, quality: float,
		unit_cost: float, supplier_id: StringName, acquired_minute: int,
		expiry_minute: int) -> StockLot:
	var lot: StockLot = StockLot.new()
	lot.ingredient_id = ingredient_id
	lot.qty = qty
	lot.quality = quality
	lot.unit_cost = unit_cost
	lot.supplier_id = supplier_id
	lot.acquired_minute = acquired_minute
	lot.expiry_minute = expiry_minute
	inv.lots.append(lot)
	inv.total_bought += qty
	return lot


## Drop expired lots. Reserved portions spoil too — consume() re-resolves.
## Returns {wasted_qty, wasted_cost, by_ingredient: {id: qty}}.
func spoil_tick(inv: InventoryState, now_minute: int) -> Dictionary:
	var wasted_qty: float = 0.0
	var wasted_cost: float = 0.0
	var by_ingredient: Dictionary = {}
	var keep: Array[StockLot] = []
	for lot: StockLot in inv.lots:
		if lot.is_expired(now_minute) and lot.qty > 0.0:
			wasted_qty += lot.qty
			wasted_cost += lot.qty * lot.unit_cost
			by_ingredient[lot.ingredient_id] = float(by_ingredient.get(lot.ingredient_id, 0.0)) + lot.qty
			# Zero the detached lot: reservations may still point at it, and
			# consume() must find nothing to drain so it re-resolves FEFO.
			lot.qty = 0.0
			lot.reserved = 0.0
		elif lot.qty > 0.0:
			keep.append(lot)
	if wasted_qty > 0.0:
		inv.lots = keep
		inv.total_wasted += wasted_qty
	return {"wasted_qty": wasted_qty, "wasted_cost": wasted_cost, "by_ingredient": by_ingredient}


## FEFO draw that PRESERVES lot identity (for warehouse -> restaurant
## transfers, where quality/cost/expiry must ride along). Only unreserved
## stock moves. Returns [{ingredient_id, qty, quality, unit_cost,
## expiry_minute, acquired_minute, supplier_id}].
func extract_lots(inv: InventoryState, ingredient_id: StringName, qty: float) -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	var remaining: float = qty
	for lot: StockLot in inv.lots_for(ingredient_id):
		if remaining <= 0.0001:
			break
		var take: float = minf(remaining, lot.available())
		if take <= 0.0:
			continue
		lot.qty -= take
		remaining -= take
		taken.append({
			"ingredient_id": lot.ingredient_id,
			"qty": take,
			"quality": lot.quality,
			"unit_cost": lot.unit_cost,
			"expiry_minute": lot.expiry_minute,
			"acquired_minute": lot.acquired_minute,
			"supplier_id": lot.supplier_id,
		})
	_prune_empty(inv)
	return taken


## Insert a transferred lot snapshot, keeping its original timestamps.
func insert_lot_snapshot(inv: InventoryState, snapshot: Dictionary) -> void:
	var lot: StockLot = StockLot.new()
	lot.ingredient_id = snapshot.get("ingredient_id", &"")
	lot.qty = float(snapshot.get("qty", 0.0))
	lot.quality = float(snapshot.get("quality", 0.5))
	lot.unit_cost = float(snapshot.get("unit_cost", 0.0))
	lot.expiry_minute = int(snapshot.get("expiry_minute", 0))
	lot.acquired_minute = int(snapshot.get("acquired_minute", 0))
	lot.supplier_id = snapshot.get("supplier_id", &"")
	inv.lots.append(lot)


## Zero all lot reservations (after load: in-flight orders are gone).
func clear_runtime_reservations(inv: InventoryState) -> void:
	for lot: StockLot in inv.lots:
		lot.reserved = 0.0


## Debug/test invariant. Per live lot 0 <= reserved <= qty, and the total
## held can never exceed the mapped claims (spoilage may void part of a
## claim, so held < mapped is legal; held > mapped is a leak).
func reserved_matches_map(inv: InventoryState) -> bool:
	var mapped: float = 0.0
	for res: Dictionary in _reservations.values():
		if res["inv"] == inv:
			for entry: Dictionary in res["entries"]:
				mapped += float(entry["qty"])
	var held: float = 0.0
	for lot: StockLot in inv.lots:
		if lot.reserved < -0.001 or lot.reserved > lot.qty + 0.001:
			return false
		held += lot.reserved
	return held <= mapped + 0.01


func _take_fefo_into(inv: InventoryState, ingredient_id: StringName, qty: float,
		result: Dictionary) -> float:
	var remaining: float = qty
	for lot: StockLot in inv.lots_for(ingredient_id):
		if remaining <= 0.0001:
			break
		var take: float = minf(remaining, lot.available())
		if take <= 0.0:
			continue
		_drain(inv, lot, take, result)
		remaining -= take
	return remaining


func _drain(inv: InventoryState, lot: StockLot, take: float, result: Dictionary) -> void:
	lot.qty -= take
	result["cost"] = float(result["cost"]) + take * lot.unit_cost
	result["qty"] = float(result["qty"]) + take
	result["quality_qty"] = float(result["quality_qty"]) + take * lot.quality
	inv.total_consumed += take
	inv.consumed_today[lot.ingredient_id] = \
		float(inv.consumed_today.get(lot.ingredient_id, 0.0)) + take


func _prune_empty(inv: InventoryState) -> void:
	var keep: Array[StockLot] = []
	for lot: StockLot in inv.lots:
		if lot.qty > 0.0001 or lot.reserved > 0.0001:
			keep.append(lot)
	if keep.size() != inv.lots.size():
		inv.lots = keep
