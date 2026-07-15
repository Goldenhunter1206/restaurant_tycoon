class_name ProcurementService
extends RefCounted
## Supplier offers, purchase-order lifecycle and the reorder-policy engine.
## Owns no state and touches no autoloads — SupplyManager passes collections,
## an ingredient-lookup Callable (id -> IngredientDef) and cash in, so the
## service stays pure and headless-testable. RNG is seeded by the manager.
##
## PO lifecycle: draft -> placed -> confirmed -> in_transit -> delivered,
## with failed (kept + retriable) and cancelled. Money: goods + fee are
## charged on DELIVERY (cash stays free until the truck arrives; affordability
## is checked at placement so companies can't overcommit).

## Reliability roll outcomes.
const OUTCOME_ON_TIME: int = 0
const OUTCOME_DELAYED: int = 1
const OUTCOME_LOST: int = 2


## One offer row for the comparison UI / AI. Returns [] for unknown items.
func offers_for(supplier_defs: Dictionary, disruptions: Array[SupplyDisruption],
		ingredient_id: StringName, now_minute: int, lookup: Callable) -> Array[Dictionary]:
	var ing_def: IngredientDef = lookup.call(ingredient_id)
	if ing_def == null:
		return []
	var offers: Array[Dictionary] = []
	for def: SupplierDef in supplier_defs.values():
		if not def.carries(ingredient_id, ing_def.category):
			continue
		var spike: float = _price_spike(disruptions, def.id, now_minute)
		var offline: bool = _has_disruption(disruptions, def.id, &"outage", now_minute)
		offers.append({
			"supplier_id": def.id,
			"unit_cost": ing_def.unit_cost * def.price_mult * spike,
			"quality": def.base_quality,
			"reliability": def.reliability,
			"lead_minutes": _lead_minutes(disruptions, def, now_minute),
			"fee": def.delivery_fee,
			"min_order_value": def.min_order_value,
			"offline": offline,
		})
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["unit_cost"]) < float(b["unit_cost"]))
	return offers


## Build a draft PO (not yet placed; drafts persist and show in the UI).
func make_draft(next_id: int, company_id: StringName, supplier: SupplierDef,
		dest_kind: StringName, dest_id: int, lines: Array[Dictionary],
		disruptions: Array[SupplyDisruption], now_minute: int,
		auto_generated: bool, lookup: Callable) -> PurchaseOrder:
	var po: PurchaseOrder = PurchaseOrder.new()
	po.id = next_id
	po.company_id = company_id
	po.supplier_id = supplier.id
	po.dest_kind = dest_kind
	po.dest_id = dest_id
	po.status = &"draft"
	po.created_minute = now_minute
	po.fee = supplier.delivery_fee
	po.auto_generated = auto_generated
	var spike: float = _price_spike(disruptions, supplier.id, now_minute)
	for line: Dictionary in lines:
		var ing_def: IngredientDef = lookup.call(line.get("ingredient_id", &""))
		if ing_def == null:
			continue
		po.lines.append({
			"ingredient_id": line["ingredient_id"],
			"qty": float(line["qty"]),
			"unit_cost": ing_def.unit_cost * supplier.price_mult * spike,
			"quality": supplier.base_quality,
		})
	return po


## Place a draft: validates supplier state and affordability, rolls
## reliability, sets status + eta. Returns a CommandResult; on failure the
## draft is KEPT (design: "your order details were kept").
func place(po: PurchaseOrder, supplier: SupplierDef, cash_available: float,
		disruptions: Array[SupplyDisruption], rng: RandomNumberGenerator,
		now_minute: int) -> CommandResult:
	if po.lines.is_empty():
		return CommandResult.fail(&"empty", "Nothing on this order.")
	if _has_disruption(disruptions, supplier.id, &"outage", now_minute):
		po.status = &"failed"
		po.failure_reason = "Supplier is offline right now."
		return CommandResult.fail(&"supplier_offline",
			"%s is offline. Your order details were kept." % supplier.display_name)
	if supplier.min_order_value > 0.0 and po.goods_cost() < supplier.min_order_value:
		return CommandResult.fail(&"min_order",
			"%s needs at least $%.0f of goods per order." % [supplier.display_name, supplier.min_order_value])
	if cash_available < po.total_cost():
		return CommandResult.fail(&"cant_afford",
			"Order totals $%.0f — not enough cash." % po.total_cost())
	var lead: int = _lead_minutes(disruptions, supplier, now_minute)
	po.status = &"confirmed"
	po.created_minute = now_minute
	po.failure_reason = ""
	match _roll(supplier.reliability, rng):
		OUTCOME_ON_TIME:
			po.eta_minute = now_minute + lead
		OUTCOME_DELAYED:
			po.eta_minute = now_minute + int(float(lead) * rng.randf_range(1.4, 2.2))
		OUTCOME_LOST:
			# Confirmed now, fails at the promised ETA — the player finds out
			# when the truck never shows.
			po.eta_minute = now_minute + lead
			po.failure_reason = "__lost__"
	return CommandResult.good(po)


## Hourly tick: settle POs whose ETA passed. Returns events for the manager
## to act on: [{po, kind: &"delivered"|&"failed", result?}].
func tick(purchase_orders: Array[PurchaseOrder], now_minute: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for po: PurchaseOrder in purchase_orders:
		if po.status != &"confirmed" and po.status != &"in_transit":
			continue
		if po.status == &"confirmed" and now_minute >= po.eta_minute - 120:
			po.status = &"in_transit"
		if now_minute < po.eta_minute:
			continue
		if po.failure_reason == "__lost__":
			po.status = &"failed"
			po.failure_reason = "The shipment never arrived."
			events.append({"po": po, "kind": &"failed"})
		else:
			po.status = &"delivered"
			events.append({"po": po, "kind": &"delivered"})
	return events


## Reorder engine for one inventory. Checks every policy against
## available + inbound and returns the per-supplier line groups that need
## ordering: {supplier_id: [{ingredient_id, qty}]}. `inbound` includes open
## POs AND existing drafts so the engine never duplicates its own work.
func reorder_needs(inv: InventoryState, rest: Variant,
		purchase_orders: Array[PurchaseOrder], supplier_defs: Dictionary,
		fallback_use: Callable, lookup: Callable,
		extra_inbound: Callable = Callable()) -> Dictionary:
	var groups: Dictionary = {}
	for ing: StringName in inv.policies.keys():
		var policy: ReorderPolicy = inv.policies[ing]
		if policy == null or policy.target_stock <= 0.0:
			continue
		var projected: float = inv.available(ing) + _pending_qty(purchase_orders, inv, ing)
		if extra_inbound.is_valid():
			projected += float(extra_inbound.call(inv, ing))
		var point: float = policy.reorder_point
		if point <= 0.0:
			point = ceilf(float(fallback_use.call(rest, ing)) * 1.5)
		if projected >= point:
			continue
		var qty: float = maxf(policy.target_stock - projected, 1.0)
		var supplier: SupplierDef = _supplier_for_policy(policy, ing, supplier_defs, lookup)
		if supplier == null:
			continue
		var lines: Array = groups.get(supplier.id, [])
		lines.append({"ingredient_id": ing, "qty": ceilf(qty)})
		groups[supplier.id] = lines
	return groups


## Bump the largest line so the group clears the supplier's minimum order.
func pad_to_min_order(lines: Array, supplier: SupplierDef, lookup: Callable) -> void:
	if supplier.min_order_value <= 0.0:
		return
	var goods: float = 0.0
	var largest: Dictionary = {}
	var largest_cost: float = 0.0
	for line: Dictionary in lines:
		var ing_def: IngredientDef = lookup.call(line["ingredient_id"])
		if ing_def == null:
			continue
		var unit: float = ing_def.unit_cost * supplier.price_mult
		var cost: float = unit * float(line["qty"])
		goods += cost
		if cost >= largest_cost:
			largest_cost = cost
			largest = line
	if goods >= supplier.min_order_value or largest.is_empty():
		return
	var ing_def: IngredientDef = lookup.call(largest["ingredient_id"])
	if ing_def == null:
		return
	var unit: float = ing_def.unit_cost * supplier.price_mult
	if unit <= 0.0:
		return
	largest["qty"] = float(largest["qty"]) + ceilf((supplier.min_order_value - goods) / unit)


func _pending_qty(purchase_orders: Array[PurchaseOrder], inv: InventoryState,
		ingredient_id: StringName) -> float:
	var total: float = 0.0
	for po: PurchaseOrder in purchase_orders:
		if po.dest_kind != inv.owner_kind or po.dest_id != inv.owner_id:
			continue
		if po.is_open() or po.status == &"draft":
			total += po.qty_of(ingredient_id)
	return total


func _supplier_for_policy(policy: ReorderPolicy, ingredient_id: StringName,
		supplier_defs: Dictionary, lookup: Callable) -> SupplierDef:
	var preferred: SupplierDef = supplier_defs.get(policy.preferred_supplier)
	var ing_def: IngredientDef = lookup.call(ingredient_id)
	var category: StringName = ing_def.category if ing_def != null else &"veg"
	if preferred != null and preferred.carries(ingredient_id, category):
		return preferred
	var best: SupplierDef = null
	for def: SupplierDef in supplier_defs.values():
		if not def.carries(ingredient_id, category):
			continue
		if policy.min_quality > 0.0 and def.base_quality < policy.min_quality:
			continue
		if best == null or def.price_mult < best.price_mult:
			best = def
	return best


func _roll(reliability: float, rng: RandomNumberGenerator) -> int:
	var r: float = rng.randf()
	if r < reliability:
		return OUTCOME_ON_TIME
	# Most misses are delays; a sliver of orders vanish outright.
	if r < reliability + (1.0 - reliability) * 0.8:
		return OUTCOME_DELAYED
	return OUTCOME_LOST


func _lead_minutes(disruptions: Array[SupplyDisruption], supplier: SupplierDef,
		now_minute: int) -> int:
	var lead: float = float(supplier.lead_time_minutes)
	for disruption: SupplyDisruption in disruptions:
		if disruption.supplier_id == supplier.id and disruption.kind == &"delay" \
				and disruption.active(now_minute):
			lead *= maxf(disruption.severity, 1.0)
	return int(lead)


func _price_spike(disruptions: Array[SupplyDisruption], supplier_id: StringName,
		now_minute: int) -> float:
	for disruption: SupplyDisruption in disruptions:
		if disruption.supplier_id == supplier_id and disruption.kind == &"price_spike" \
				and disruption.active(now_minute):
			return maxf(disruption.severity, 1.0)
	return 1.0


func _has_disruption(disruptions: Array[SupplyDisruption], supplier_id: StringName,
		kind: StringName, now_minute: int) -> bool:
	for disruption: SupplyDisruption in disruptions:
		if disruption.supplier_id == supplier_id and disruption.kind == kind \
				and disruption.active(now_minute):
			return true
	return false
