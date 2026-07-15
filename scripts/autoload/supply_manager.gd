extends Node
## Autoload: the supply chain. Owns ingredient stock (per restaurant, later
## per warehouse), the supplier catalog, purchase/transfer orders and the
## command layer shared by the player UI and rival AI. Lot math delegates to
## InventoryService; money always moves through CompanyState.transact with
## dedicated ledger categories so finance reports can reconcile the chain.
##
## Timing uses absolute game minutes (GameClock.total_minutes) so freshness
## and lead times are deterministic across time speeds.

signal inventory_changed(owner_kind: StringName, owner_id: int)
signal orders_changed
signal warehouses_changed
signal policies_changed

const ITEMS_DIR: String = "res://data/inventory_items"
const SUPPLIERS_DIR: String = "res://data/suppliers"

## Catalogs (id-keyed defs, loaded once).
var item_defs: Dictionary = {}
var supplier_defs: Dictionary = {}

## Live state (saved).
var purchase_orders: Array[PurchaseOrder] = []
var transfer_orders: Array[TransferOrder] = []
var warehouses: Array[WarehouseState] = []
var contracts: Array[SupplierContractState] = []
var disruptions: Array[SupplyDisruption] = []
var next_supply_id: int = 1

var _inv: InventoryService = InventoryService.new()
var _proc: ProcurementService = ProcurementService.new()
var _logi: LogisticsService = LogisticsService.new()
var _forecast: ForecastService = ForecastService.new()
## warehouse_id -> WarehouseMarker node (runtime visuals).
var _markers: Dictionary = {}
## Live cosmetic supply trucks (capped; deliveries settle on timers).
var _trucks: Array[Node] = []
const MAX_VISIBLE_TRUCKS: int = 4
var _initialized: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## "company_id/ingredient_id" -> day — one emergency-buy alert per day.
var _alerted: Dictionary = {}


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_load_defs()
	_rng.seed = hash("supply_%d" % GameSetup.world_seed)
	var save: SaveGame = CompanyManager.loaded_save
	if save != null:
		_restore(save)
	_seed_missing_inventories()
	# Warehouses from a save need capacity re-derived and world markers spawned.
	for wh: WarehouseState in warehouses:
		if wh.inventory != null:
			_apply_warehouse_capacity(wh)
	if not warehouses.is_empty():
		_refresh_markers.call_deferred()
	EconomyManager.daily_cost_providers.append(_charge_daily_supply)
	GameClock.hour_changed.connect(_on_hour)
	GameClock.day_changed.connect(_on_day)
	# Every cancel path must release its reservation. Both signals fire on
	# cancellation (dine-in/backlog vs delivery timeout); release is idempotent
	# so double notification is harmless.
	RestaurantManager.order_state_changed.connect(_on_order_state)
	DeliveryManager.delivery_state_changed.connect(_on_order_state)


# --- Order lifecycle (called by RestaurantManager) ---------------------------


## Reserve the order's bill of materials at accept time. Orders without a
## components snapshot (fixed legacy dishes) skip inventory entirely.
func reserve_for_order(rest: RestaurantState, order: FoodOrder) -> CommandResult:
	if order.components_snapshot.is_empty():
		return CommandResult.good({"legacy": true})
	var inv: InventoryState = inventory_for_restaurant(rest)
	# Swap short ingredients for an in-stock substitute where policy allows it,
	# before falling back to emergency buys.
	var needs: Array[Dictionary] = _apply_substitutions(inv, _needs_from(order))
	if _inv.reserve(inv, order.order_id, needs):
		return CommandResult.good()
	# Shortage: apply per-ingredient emergency behavior. Default keeps the
	# kitchen running via marked-up retail stock.
	var missing: Array[Dictionary] = _inv.missing_for(inv, needs)
	for gap: Dictionary in missing:
		var ing: StringName = gap["ingredient_id"]
		var policy: ReorderPolicy = inv.policy_for(ing)
		var behavior: StringName = policy.emergency_behavior if policy != null else &"emergency_buy"
		# disable/delay reject the order; substitute falls through to an
		# emergency buy here (its substitute was already out of stock).
		if behavior == &"disable" or behavior == &"delay":
			return CommandResult.fail(&"out_of_stock",
				"Out of %s." % _ingredient_name(ing))
		_emergency_buy(rest, inv, ing, float(gap["missing"]))
	if _inv.reserve(inv, order.order_id, needs):
		inventory_changed.emit(&"restaurant", rest.building_id)
		return CommandResult.good({"emergency": true})
	return CommandResult.fail(&"out_of_stock", "Ingredients unavailable.")


## Replace a need with a substitute ingredient when the primary is short, the
## policy permits substitution, and the substitute is in stock.
func _apply_substitutions(inv: InventoryState, needs: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for need: Dictionary in needs:
		var ing: StringName = need["ingredient_id"]
		var qty: float = float(need["qty"])
		var policy: ReorderPolicy = inv.policy_for(ing)
		var swapped: bool = false
		if inv.available(ing) < qty and policy != null and policy.emergency_behavior == &"substitute":
			var item: InventoryItemDef = item_defs.get(ing)
			if item != null:
				for sub: StringName in item.substitutes:
					if inv.available(sub) >= qty:
						result.append({"ingredient_id": sub, "qty": qty})
						swapped = true
						break
		if not swapped:
			result.append(need)
	return result


## Consume reserved stock at cook start and charge actual lot cost.
## Payload: {"cost": float} — what the kitchen actually paid.
func consume_for_order(rest: RestaurantState, order: FoodOrder) -> CommandResult:
	var company: CompanyState = rest.company()
	if order.components_snapshot.is_empty():
		# Legacy dish: preserve the old direct ingredient charge.
		if company != null:
			company.transact(&"ingredients", -order.ingredient_cost)
		return CommandResult.good({"cost": order.ingredient_cost})
	var inv: InventoryState = inventory_for_restaurant(rest)
	var result: Dictionary
	if _inv.has_reservation(order.order_id):
		result = _inv.consume(inv, order.order_id)
	else:
		# Order predates the inventory system (e.g. right after load).
		result = {"cost": 0.0, "qty": 0.0, "quality_qty": 0.0, "shortfall": _needs_from(order)}
	var cost: float = float(result["cost"])
	for gap: Dictionary in result["shortfall"]:
		var ing: StringName = gap["ingredient_id"]
		var qty: float = float(gap["qty"])
		_emergency_buy(rest, inv, ing, qty)
		var extra: Dictionary = _inv.take_fefo(inv, ing, qty)
		cost += float(extra["cost"])
	if company != null and cost > 0.0:
		company.transact(&"ingredients", -cost)
	inventory_changed.emit(&"restaurant", rest.building_id)
	return CommandResult.good({"cost": cost})


## Idempotent — safe on every cancel path.
func release_for_order(order: FoodOrder) -> void:
	_inv.release(order.order_id)


func _on_order_state(order: FoodOrder) -> void:
	if order.state == FoodOrder.State.CANCELLED:
		_inv.release(order.order_id)


# --- Player/AI commands -------------------------------------------------------


## Sorted offers (cheapest first) for one ingredient — the comparison UI and
## the AI read the same rows.
func supplier_offers_cmd(_company_id: StringName, ingredient_id: StringName) -> CommandResult:
	var offers: Array[Dictionary] = _proc.offers_for(supplier_defs, disruptions,
		ingredient_id, GameClock.total_minutes(), RecipeManager.ingredient)
	if offers.is_empty():
		return CommandResult.fail(&"no_supplier", "No supplier carries that ingredient.")
	return CommandResult.good(offers)


## Create AND place a purchase order in one step.
## lines: [{ingredient_id, qty}].
func place_purchase_order_cmd(company_id: StringName, supplier_id: StringName,
		dest_kind: StringName, dest_id: int, lines: Array[Dictionary]) -> CommandResult:
	var check: CommandResult = _validate_dest(company_id, dest_kind, dest_id)
	if not check.ok:
		return check
	var supplier: SupplierDef = supplier_defs.get(supplier_id)
	if supplier == null:
		return CommandResult.fail(&"unknown_supplier", "No such supplier.")
	var po: PurchaseOrder = _proc.make_draft(next_supply_id, company_id, supplier,
		dest_kind, dest_id, lines, disruptions, GameClock.total_minutes(), false,
		RecipeManager.ingredient)
	next_supply_id += 1
	purchase_orders.append(po)
	var placed: CommandResult = _try_place(po)
	orders_changed.emit()
	return placed


## Place (or retry) an existing draft/failed order.
func place_draft_cmd(company_id: StringName, po_id: int) -> CommandResult:
	var po: PurchaseOrder = _find_po(company_id, po_id)
	if po == null:
		return CommandResult.fail(&"unknown_order", "No such purchase order.")
	if po.status != &"draft" and po.status != &"failed":
		return CommandResult.fail(&"not_draft", "That order is already on its way.")
	var placed: CommandResult = _try_place(po)
	orders_changed.emit()
	return placed


func cancel_purchase_order_cmd(company_id: StringName, po_id: int) -> CommandResult:
	var po: PurchaseOrder = _find_po(company_id, po_id)
	if po == null:
		return CommandResult.fail(&"unknown_order", "No such purchase order.")
	if po.status == &"delivered":
		return CommandResult.fail(&"already_delivered", "That order already arrived.")
	if po.status == &"draft" or po.status == &"failed" or po.status == &"cancelled":
		purchase_orders.erase(po)
	else:
		# Nothing was charged yet (goods+fee settle on delivery), so cancelling
		# an in-flight order simply forfeits the slot.
		po.status = &"cancelled"
	orders_changed.emit()
	return CommandResult.good()


## Set (creating if needed) an ingredient's reorder policy on a restaurant.
## fields keys (all optional): reorder_point, target_stock, preferred_supplier,
## min_quality, emergency_behavior, mode.
func set_reorder_policy_cmd(company_id: StringName, building_id: int,
		ingredient_id: StringName, fields: Dictionary) -> CommandResult:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null or rest.company_id != company_id:
		return CommandResult.fail(&"not_owner", "That branch isn't owned by the company.")
	var inv: InventoryState = inventory_for_restaurant(rest)
	var policy: ReorderPolicy = inv.policy_for(ingredient_id)
	if policy == null:
		policy = ReorderPolicy.new()
		policy.ingredient_id = ingredient_id
		inv.policies[ingredient_id] = policy
	if fields.has("reorder_point"):
		policy.reorder_point = maxf(0.0, float(fields["reorder_point"]))
	if fields.has("target_stock"):
		policy.target_stock = maxf(0.0, float(fields["target_stock"]))
	if fields.has("preferred_supplier"):
		policy.preferred_supplier = fields["preferred_supplier"]
	if fields.has("min_quality"):
		policy.min_quality = clampf(float(fields["min_quality"]), 0.0, 1.0)
	if fields.has("emergency_behavior"):
		policy.emergency_behavior = fields["emergency_behavior"]
	if fields.has("mode"):
		policy.mode = fields["mode"]
	policies_changed.emit()
	return CommandResult.good(policy)


func set_policy_mode_cmd(company_id: StringName, building_id: int,
		ingredient_id: StringName, mode: StringName) -> CommandResult:
	return set_reorder_policy_cmd(company_id, building_id, ingredient_id, {"mode": mode})


## The inventory-row "Reorder" button: tops the ingredient up to its policy
## target via a real purchase order from the policy's supplier.
func manual_restock_cmd(company_id: StringName, building_id: int,
		ingredient_id: StringName, qty: float) -> CommandResult:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null or rest.company_id != company_id:
		return CommandResult.fail(&"not_owner", "That branch isn't owned by the company.")
	if qty <= 0.0:
		return CommandResult.fail(&"bad_qty", "Nothing to order.")
	var inv: InventoryState = inventory_for_restaurant(rest)
	var policy: ReorderPolicy = inv.policy_for(ingredient_id)
	var supplier: SupplierDef = null
	if policy != null:
		supplier = supplier_defs.get(policy.preferred_supplier)
	if supplier == null:
		supplier = cheapest_supplier_for(ingredient_id)
	if supplier == null:
		return CommandResult.fail(&"no_supplier", "No supplier carries that ingredient.")
	var lines: Array[Dictionary] = [{"ingredient_id": ingredient_id, "qty": ceilf(qty)}]
	_proc.pad_to_min_order(lines, supplier, RecipeManager.ingredient)
	return place_purchase_order_cmd(company_id, supplier.id, &"restaurant",
		building_id, lines)


# --- Warehouse commands ---------------------------------------------------------


func warehouse_by_id(warehouse_id: int) -> WarehouseState:
	for wh: WarehouseState in warehouses:
		if wh.id == warehouse_id:
			return wh
	return null


func warehouses_of(company_id: StringName) -> Array[WarehouseState]:
	var found: Array[WarehouseState] = []
	for wh: WarehouseState in warehouses:
		if wh.company_id == company_id:
			found.append(wh)
	return found


## First company warehouse serving a restaurant, or null.
func warehouse_serving(building_id: int) -> WarehouseState:
	for wh: WarehouseState in warehouses:
		if wh.assigned_restaurant_ids.has(building_id):
			return wh
	return null


## Industrial buildings that can become warehouses (not yet taken).
func purchasable_warehouse_buildings() -> Array[Dictionary]:
	var taken: Dictionary = {}
	for wh: WarehouseState in warehouses:
		taken[wh.building_id] = true
	var found: Array[Dictionary] = []
	for id: int in CityData.buildings:
		var info: Dictionary = CityData.buildings[id]
		if String(info.get("type", "")) != "factory":
			continue
		if taken.has(id):
			continue
		found.append(info)
	return found


func warehouse_price() -> float:
	return EconomyManager.tuning_value("supply.warehouse_price", 8000.0)


func buy_warehouse_cmd(company_id: StringName, building_id: int) -> CommandResult:
	var why_locked: String = CapabilityRegistry.explain(company_id, &"supply.warehouses")
	if why_locked != "":
		return CommandResult.fail(&"locked", why_locked)
	var info: Dictionary = CityData.get_building(building_id)
	if info.is_empty() or String(info.get("type", "")) != "factory":
		return CommandResult.fail(&"bad_building", "Warehouses need an industrial building.")
	for wh: WarehouseState in warehouses:
		if wh.building_id == building_id:
			return CommandResult.fail(&"taken", "That building already is a warehouse.")
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null:
		return CommandResult.fail(&"unknown_company", "No such company.")
	var price: float = warehouse_price()
	if not company.can_afford(price):
		return CommandResult.fail(&"cant_afford", "The warehouse costs $%.0f." % price)
	company.transact(&"property_purchase", -price)
	var wh: WarehouseState = WarehouseState.new()
	wh.id = next_supply_id
	next_supply_id += 1
	wh.company_id = company_id
	wh.building_id = building_id
	wh.world_pos = info.get("position", Vector3.ZERO)
	wh.district = String(info.get("district", "I"))
	wh.display_name = "%s Warehouse" % company.display_name
	wh.purchase_price = price
	wh.purchased_day = GameClock.day
	wh.inventory = InventoryState.new()
	wh.inventory.owner_kind = &"warehouse"
	wh.inventory.owner_id = wh.id
	_apply_warehouse_capacity(wh)
	warehouses.append(wh)
	_refresh_markers()
	warehouses_changed.emit()
	if company.is_player:
		EconomyManager.post_message("good", "Warehouse opened in the industrial district.")
	return CommandResult.good(wh)


func upgrade_warehouse_cmd(company_id: StringName, warehouse_id: int) -> CommandResult:
	var wh: WarehouseState = warehouse_by_id(warehouse_id)
	if wh == null or wh.company_id != company_id:
		return CommandResult.fail(&"not_owner", "That warehouse isn't owned by the company.")
	if wh.expansion_level >= WarehouseState.MAX_LEVEL:
		return CommandResult.fail(&"max_level", "The warehouse is already fully expanded.")
	var company: CompanyState = CompanyManager.company(company_id)
	var cost: float = wh.upgrade_cost()
	if company == null or not company.can_afford(cost):
		return CommandResult.fail(&"cant_afford", "The expansion costs $%.0f." % cost)
	company.transact(&"expansion", -cost)
	wh.expansion_level += 1
	_apply_warehouse_capacity(wh)
	warehouses_changed.emit()
	return CommandResult.good(wh)


func assign_restaurant_cmd(company_id: StringName, warehouse_id: int,
		building_id: int, assign: bool) -> CommandResult:
	var wh: WarehouseState = warehouse_by_id(warehouse_id)
	if wh == null or wh.company_id != company_id:
		return CommandResult.fail(&"not_owner", "That warehouse isn't owned by the company.")
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null or rest.company_id != company_id:
		return CommandResult.fail(&"not_owner", "That branch isn't owned by the company.")
	if assign and not wh.assigned_restaurant_ids.has(building_id):
		# One warehouse per restaurant: unassign elsewhere first.
		for other: WarehouseState in warehouses:
			other.assigned_restaurant_ids.erase(building_id)
		wh.assigned_restaurant_ids.append(building_id)
	elif not assign:
		wh.assigned_restaurant_ids.erase(building_id)
	_sync_warehouse_policies(wh)
	warehouses_changed.emit()
	return CommandResult.good(wh)


## Manual (or automated) warehouse -> restaurant stock transfer.
## wants: [{ingredient_id, qty}].
func create_transfer_cmd(company_id: StringName, warehouse_id: int,
		building_id: int, wants: Array[Dictionary], auto_generated: bool = false) -> CommandResult:
	var wh: WarehouseState = warehouse_by_id(warehouse_id)
	if wh == null or wh.company_id != company_id:
		return CommandResult.fail(&"not_owner", "That warehouse isn't owned by the company.")
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null or rest.company_id != company_id:
		return CommandResult.fail(&"not_owner", "That branch isn't owned by the company.")
	var eta: float = route_eta(wh.world_pos, rest.door_pos)
	if eta < 0.0:
		return CommandResult.fail(&"unreachable", "No road route reaches that branch.")
	var cost: float = _logi.transfer_cost(eta,
		EconomyManager.tuning_value("supply.transfer_base_fee", 12.0),
		EconomyManager.tuning_value("supply.transfer_per_minute", 0.5))
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null or not company.can_afford(cost):
		return CommandResult.fail(&"cant_afford", "The transfer run costs $%.0f." % cost)
	var transfer: TransferOrder = _logi.build_transfer(_inv, next_supply_id, company_id,
		wh, building_id, wants, eta, cost, GameClock.total_minutes(), auto_generated)
	if transfer == null:
		return CommandResult.fail(&"no_stock", "The warehouse holds none of that stock.")
	next_supply_id += 1
	transfer_orders.append(transfer)
	company.transact(&"supply_delivery", -cost)
	inventory_changed.emit(&"warehouse", wh.id)
	# Cosmetic truck spawns off the command's hot path (GLB load can hitch,
	# and daily auto-reorders may fire several transfers at once).
	_maybe_spawn_truck.call_deferred(transfer, wh, rest)
	orders_changed.emit()
	return CommandResult.good(transfer)


## Door-to-door route ETA in game minutes (-1 = unreachable).
func route_eta(from_pos: Vector3, to_pos: Vector3) -> float:
	return _logi.route_eta_minutes(CityData.road_graph, from_pos, to_pos)


func transfers_of(company_id: StringName) -> Array[TransferOrder]:
	var found: Array[TransferOrder] = []
	for transfer: TransferOrder in transfer_orders:
		if transfer.company_id == company_id:
			found.append(transfer)
	found.sort_custom(func(a: TransferOrder, b: TransferOrder) -> bool:
		return a.created_minute > b.created_minute)
	return found


## In-transit transfer portions headed to a restaurant.
func transfer_inbound_qty(building_id: int, ingredient_id: StringName) -> float:
	var total: float = 0.0
	for transfer: TransferOrder in transfer_orders:
		if transfer.dest_restaurant_id != building_id or transfer.status != &"in_transit":
			continue
		for line: Dictionary in transfer.lines:
			if line.get("ingredient_id", &"") == ingredient_id:
				total += float(line.get("qty", 0.0))
	return total


# --- Queries ------------------------------------------------------------------


func inventory_for_restaurant(rest: RestaurantState) -> InventoryState:
	if rest.inventory == null:
		rest.inventory = _new_restaurant_inventory(rest)
		_seed_starter_stock(rest, rest.inventory)
	return rest.inventory


func item_def(ingredient_id: StringName) -> InventoryItemDef:
	return item_defs.get(ingredient_id)


func supplier(supplier_id: StringName) -> SupplierDef:
	return supplier_defs.get(supplier_id)


## Open + draft orders headed for one company, newest first.
func open_orders(company_id: StringName) -> Array[PurchaseOrder]:
	var found: Array[PurchaseOrder] = []
	for po: PurchaseOrder in purchase_orders:
		if po.company_id == company_id:
			found.append(po)
	found.sort_custom(func(a: PurchaseOrder, b: PurchaseOrder) -> bool:
		return a.created_minute > b.created_minute)
	return found


## Portions already ordered (open or drafted) toward an inventory.
func inbound_qty(inv: InventoryState, ingredient_id: StringName) -> float:
	var total: float = 0.0
	for po: PurchaseOrder in purchase_orders:
		if po.dest_kind != inv.owner_kind or po.dest_id != inv.owner_id:
			continue
		if po.is_open() or po.status == &"draft":
			total += po.qty_of(ingredient_id)
	return total


func cheapest_supplier_for(ingredient_id: StringName) -> SupplierDef:
	var ing_def: IngredientDef = RecipeManager.ingredient(ingredient_id)
	var category: StringName = ing_def.category if ing_def != null else &"veg"
	var best: SupplierDef = null
	for def: SupplierDef in supplier_defs.values():
		if not def.carries(ingredient_id, category):
			continue
		if best == null or def.price_mult < best.price_mult:
			best = def
	return best


## Supplier chosen along a cheap<->premium axis. style 0 = cheapest,
## 1 = highest quality; between, a weighted blend. Used by AI procurement.
func supplier_for_style(ingredient_id: StringName, style: float) -> SupplierDef:
	var ing_def: IngredientDef = RecipeManager.ingredient(ingredient_id)
	var category: StringName = ing_def.category if ing_def != null else &"veg"
	var best: SupplierDef = null
	var best_score: float = -INF
	for def: SupplierDef in supplier_defs.values():
		if not def.carries(ingredient_id, category):
			continue
		# Cheapness in [0,1] (price_mult ~0.85..1.5) blended with quality.
		var cheapness: float = clampf((1.6 - def.price_mult) / 0.75, 0.0, 1.0)
		var score: float = lerpf(cheapness, def.base_quality, clampf(style, 0.0, 1.0))
		score += def.reliability * 0.15
		if score > best_score:
			best_score = score
			best = def
	return best


## Smoothed daily use with a menu-based fallback before history exists.
func estimated_daily_use(rest: RestaurantState, ingredient_id: StringName) -> float:
	var inv: InventoryState = inventory_for_restaurant(rest)
	var smoothed: float = float(inv.daily_use.get(ingredient_id, 0.0))
	if smoothed > 0.01:
		return smoothed
	return _menu_daily_need(rest).get(ingredient_id, 0.0)


func days_of_cover(rest: RestaurantState, ingredient_id: StringName) -> float:
	var use: float = estimated_daily_use(rest, ingredient_id)
	if use <= 0.001:
		return INF
	return inventory_for_restaurant(rest).available(ingredient_id) / use


## Ingredients the menu needs that are under 1 day of cover.
func stockout_risks(rest: RestaurantState) -> Array[StringName]:
	var risks: Array[StringName] = []
	for ing: StringName in _menu_daily_need(rest).keys():
		if days_of_cover(rest, ing) < 1.0:
			risks.append(ing)
	return risks


## Extra demand from active marketing campaigns on a branch (1.0 = normal).
func demand_multiplier(rest: RestaurantState) -> float:
	var mult: float = 1.0
	for campaign: MarketingCampaign in MarketingManager.campaigns_for(rest.company_id):
		if campaign.days_left <= 0:
			continue
		if campaign.building_id == rest.building_id or campaign.building_id < 0:
			mult += campaign.utility_bonus * campaign.intensity * 0.6
	return mult


## Per-ingredient extra multiplier for campaign-promoted recipes/ingredients.
func _campaign_boosts(rest: RestaurantState) -> Dictionary:
	var boosts: Dictionary = {}
	for campaign: MarketingCampaign in MarketingManager.campaigns_for(rest.company_id):
		if campaign.days_left <= 0:
			continue
		if campaign.building_id != rest.building_id and campaign.building_id >= 0:
			continue
		if campaign.promoted_ingredient != &"":
			boosts[campaign.promoted_ingredient] = 1.6
		if campaign.promoted_recipe != &"":
			var recipe: RecipeDef = RecipeManager.recipe(campaign.promoted_recipe)
			if recipe != null:
				for component: RecipeComponent in recipe.components:
					boosts[component.ingredient_id] = maxf(float(boosts.get(component.ingredient_id, 1.0)), 1.4)
	return boosts


## Forecast warnings for the Overview feed: [{ingredient_id, severity, days,
## reason}], worst-first, demand- and campaign-aware.
func forecast_warnings(rest: RestaurantState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for ing: StringName in _menu_daily_need(rest).keys():
		rows.append({
			"ingredient_id": ing,
			"available": inventory_for_restaurant(rest).available(ing),
			"base_use": estimated_daily_use(rest, ing),
		})
	return _forecast.warnings(rows, demand_multiplier(rest), _campaign_boosts(rest))


# --- Disruptions & contracts ----------------------------------------------------


func active_disruptions() -> Array[SupplyDisruption]:
	var now: int = GameClock.total_minutes()
	var out: Array[SupplyDisruption] = []
	for disruption: SupplyDisruption in disruptions:
		if disruption.active(now):
			out.append(disruption)
	return out


## Sign a supplier contract: a standing discount in exchange for commitment.
func sign_contract_cmd(company_id: StringName, supplier_id: StringName) -> CommandResult:
	var supplier: SupplierDef = supplier_defs.get(supplier_id)
	if supplier == null:
		return CommandResult.fail(&"unknown_supplier", "No such supplier.")
	var contract: SupplierContractState = _contract_for(company_id, supplier_id)
	if contract.signed:
		return CommandResult.fail(&"already_signed", "You already have a contract with %s." % supplier.display_name)
	contract.signed = true
	contract.signed_day = GameClock.day
	contract.discount_mult = EconomyManager.tuning_value("supply.contract_discount", 0.92)
	orders_changed.emit()
	return CommandResult.good(contract)


func contract_with(company_id: StringName, supplier_id: StringName) -> SupplierContractState:
	for contract: SupplierContractState in contracts:
		if contract.company_id == company_id and contract.supplier_id == supplier_id:
			return contract
	return null


## Seeded daily disruption roll from each supplier's disruption_profile.
func _roll_disruptions() -> void:
	var now: int = GameClock.total_minutes()
	for supplier: SupplierDef in supplier_defs.values():
		if _has_active_disruption(supplier.id):
			continue
		for kind: StringName in supplier.disruption_profile.keys():
			var chance: float = float(supplier.disruption_profile[kind])
			if _rng.randf() >= chance:
				continue
			var disruption: SupplyDisruption = SupplyDisruption.new()
			disruption.supplier_id = supplier.id
			disruption.kind = kind
			var days: int = _rng.randi_range(1, 3)
			disruption.start_minute = now
			disruption.end_minute = now + days * 1440
			disruption.severity = _disruption_severity(kind)
			disruptions.append(disruption)
			for company: CompanyState in CompanyManager.companies:
				if company.is_player:
					EconomyManager.post_message("alert", "%s: %s for ~%d day(s)." %
						[supplier.display_name, _disruption_label(kind), days])
			break


func _disruption_severity(kind: StringName) -> float:
	match kind:
		&"price_spike":
			return _rng.randf_range(1.3, 1.8)
		&"delay":
			return _rng.randf_range(1.5, 2.5)
	return 1.0


func _disruption_label(kind: StringName) -> String:
	match kind:
		&"outage":
			return "supply outage"
		&"price_spike":
			return "prices spiking"
		&"delay":
			return "shipping delays"
	return "disruption"


func _has_active_disruption(supplier_id: StringName) -> bool:
	var now: int = GameClock.total_minutes()
	for disruption: SupplyDisruption in disruptions:
		if disruption.supplier_id == supplier_id and disruption.active(now):
			return true
	return false


func _prune_expired_disruptions() -> void:
	var now: int = GameClock.total_minutes()
	var keep: Array[SupplyDisruption] = []
	for disruption: SupplyDisruption in disruptions:
		if disruption.end_minute > now:
			keep.append(disruption)
	disruptions = keep


# --- Save ---------------------------------------------------------------------


func write_save(save: SaveGame) -> void:
	save.warehouses = warehouses.duplicate()
	save.purchase_orders = purchase_orders.duplicate()
	save.transfer_orders = transfer_orders.duplicate()
	save.supplier_contracts = contracts.duplicate()
	save.supply_disruptions = disruptions.duplicate()
	save.supply_next_id = next_supply_id


func _restore(save: SaveGame) -> void:
	for wh: WarehouseState in save.warehouses:
		warehouses.append(wh)
	for po: PurchaseOrder in save.purchase_orders:
		purchase_orders.append(po)
	for to: TransferOrder in save.transfer_orders:
		transfer_orders.append(to)
	for contract: SupplierContractState in save.supplier_contracts:
		contracts.append(contract)
	for disruption: SupplyDisruption in save.supply_disruptions:
		disruptions.append(disruption)
	next_supply_id = maxi(save.supply_next_id, 1)
	# In-flight order reservations died with the previous session.
	for company: CompanyState in CompanyManager.companies:
		for rest: RestaurantState in company.restaurants:
			if rest.inventory != null:
				_inv.clear_runtime_reservations(rest.inventory)
	for wh: WarehouseState in warehouses:
		if wh.inventory != null:
			_inv.clear_runtime_reservations(wh.inventory)


# --- Internals ----------------------------------------------------------------


func _load_defs() -> void:
	item_defs.clear()
	supplier_defs.clear()
	_load_dir(ITEMS_DIR, item_defs)
	_load_dir(SUPPLIERS_DIR, supplier_defs)


func _load_dir(dir_path: String, into: Dictionary) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_warning("SupplyManager: catalog missing at %s" % dir_path)
		return
	dir.list_dir_begin()
	var file: String = dir.get_next()
	while file != "":
		if file.ends_with(".tres") or file.ends_with(".res"):
			var def: Resource = load("%s/%s" % [dir_path, file])
			if def != null and def.get("id") != null and def.id != &"":
				into[def.id] = def
		file = dir.get_next()
	dir.list_dir_end()


func _seed_missing_inventories() -> void:
	for company: CompanyState in CompanyManager.companies:
		for rest: RestaurantState in company.restaurants:
			inventory_for_restaurant(rest)


func _new_restaurant_inventory(rest: RestaurantState) -> InventoryState:
	var inv: InventoryState = InventoryState.new()
	inv.owner_kind = &"restaurant"
	inv.owner_id = rest.building_id
	inv.capacity_by_class = {
		&"dry": EconomyManager.tuning_value("supply.restaurant_capacity.dry", 600.0),
		&"chilled": EconomyManager.tuning_value("supply.restaurant_capacity.chilled", 400.0),
		&"frozen": EconomyManager.tuning_value("supply.restaurant_capacity.frozen", 300.0),
	}
	return inv


## New restaurants (and legacy saves) start with a few days of stock so the
## kitchen never opens to empty shelves — the migration grace the feature
## plan requires.
func _seed_starter_stock(rest: RestaurantState, inv: InventoryState) -> void:
	var days: float = EconomyManager.tuning_value("supply.starter_days", 4.0)
	var now: int = GameClock.total_minutes()
	for ing: StringName in _menu_daily_need(rest).keys():
		var daily: float = _menu_daily_need(rest)[ing]
		var item: InventoryItemDef = item_defs.get(ing)
		var ing_def: IngredientDef = RecipeManager.ingredient(ing)
		if item == null or ing_def == null or daily <= 0.0:
			continue
		var qty: float = ceilf(daily * days)
		_inv.add_lot(inv, ing, qty, 0.5, ing_def.unit_cost, &"starter",
			now, item.expiry_for(now))
		if not inv.policies.has(ing):
			inv.policies[ing] = _default_policy(ing, daily)


func _default_policy(ingredient_id: StringName, daily_use: float) -> ReorderPolicy:
	var policy: ReorderPolicy = ReorderPolicy.new()
	policy.ingredient_id = ingredient_id
	policy.reorder_point = ceilf(daily_use * EconomyManager.tuning_value("supply.reorder_days", 1.5))
	policy.target_stock = ceilf(daily_use * EconomyManager.tuning_value("supply.target_days", 4.0))
	policy.mode = &"automatic"
	policy.emergency_behavior = &"emergency_buy"
	return policy


## ingredient_id -> estimated portions/day from the enabled recipe menu.
func _menu_daily_need(rest: RestaurantState) -> Dictionary:
	var per_dish: float = EconomyManager.tuning_value("supply.portions_per_dish_day", 14.0)
	var needs: Dictionary = {}
	for entry: MenuEntry in rest.enabled_menu():
		var recipe: RecipeDef = RecipeManager.recipe(entry.dish_id)
		if recipe == null:
			continue
		for component: RecipeComponent in recipe.components:
			needs[component.ingredient_id] = \
				float(needs.get(component.ingredient_id, 0.0)) + component.quantity * per_dish
	return needs


func _needs_from(order: FoodOrder) -> Array[Dictionary]:
	var needs: Array[Dictionary] = []
	for component: Dictionary in order.components_snapshot:
		needs.append({
			"ingredient_id": component.get("ingredient_id", &""),
			"qty": float(component.get("qty", 0.0)),
		})
	return needs


## Instantly source qty of an ingredient at retail markup. Charged the moment
## the stock appears (category &"emergency_buy"), so the later consume charge
## through &"ingredients" only covers what recipes actually used.
func _emergency_buy(rest: RestaurantState, inv: InventoryState,
		ingredient_id: StringName, qty: float) -> void:
	var ing_def: IngredientDef = RecipeManager.ingredient(ingredient_id)
	var item: InventoryItemDef = item_defs.get(ingredient_id)
	if ing_def == null or item == null or qty <= 0.0:
		return
	var mult: float = EconomyManager.tuning_value("supply.emergency_mult", 2.0)
	var buffer: float = EconomyManager.tuning_value("supply.emergency_buffer", 1.2)
	var buy_qty: float = ceilf(qty * buffer)
	var unit_cost: float = ing_def.unit_cost * mult
	var now: int = GameClock.total_minutes()
	_inv.add_lot(inv, ingredient_id, buy_qty, 0.4, unit_cost, &"retail",
		now, item.expiry_for(now))
	var company: CompanyState = rest.company()
	if company != null:
		company.transact(&"emergency_buy", -unit_cost * buy_qty)
		_post_emergency_alert(company, rest, ingredient_id)


func _post_emergency_alert(company: CompanyState, rest: RestaurantState,
		ingredient_id: StringName) -> void:
	if not company.is_player:
		return
	var key: String = "%s/%s" % [rest.building_id, ingredient_id]
	if int(_alerted.get(key, -1)) == GameClock.day:
		return
	_alerted[key] = GameClock.day
	EconomyManager.post_message("alert", "%s ran out of %s — emergency stock bought at retail prices." %
		[rest.restaurant_name, _ingredient_name(ingredient_id)])


func _ingredient_name(ingredient_id: StringName) -> String:
	var ing_def: IngredientDef = RecipeManager.ingredient(ingredient_id)
	return ing_def.display_name if ing_def != null else String(ingredient_id)


func _validate_dest(company_id: StringName, dest_kind: StringName, dest_id: int) -> CommandResult:
	if dest_kind == &"restaurant":
		var rest: RestaurantState = RestaurantManager.by_building.get(dest_id)
		if rest == null or rest.company_id != company_id:
			return CommandResult.fail(&"not_owner", "That branch isn't owned by the company.")
		return CommandResult.good()
	if dest_kind == &"warehouse":
		var wh: WarehouseState = warehouse_by_id(dest_id)
		if wh == null or wh.company_id != company_id:
			return CommandResult.fail(&"not_owner", "That warehouse isn't owned by the company.")
		return CommandResult.good()
	return CommandResult.fail(&"bad_dest", "Unknown destination.")


func _find_po(company_id: StringName, po_id: int) -> PurchaseOrder:
	for po: PurchaseOrder in purchase_orders:
		if po.id == po_id and po.company_id == company_id:
			return po
	return null


func _try_place(po: PurchaseOrder) -> CommandResult:
	var supplier: SupplierDef = supplier_defs.get(po.supplier_id)
	var company: CompanyState = CompanyManager.company(po.company_id)
	if supplier == null or company == null:
		return CommandResult.fail(&"unknown_supplier", "No such supplier.")
	return _proc.place(po, supplier, company.cash, disruptions, _rng, GameClock.total_minutes())


func _dest_inventory(po: PurchaseOrder) -> InventoryState:
	if po.dest_kind == &"restaurant":
		var rest: RestaurantState = RestaurantManager.by_building.get(po.dest_id)
		if rest != null:
			return inventory_for_restaurant(rest)
	if po.dest_kind == &"warehouse":
		var wh: WarehouseState = warehouse_by_id(po.dest_id)
		if wh != null:
			return wh.inventory
	return null


func _contract_for(company_id: StringName, supplier_id: StringName) -> SupplierContractState:
	for contract: SupplierContractState in contracts:
		if contract.company_id == company_id and contract.supplier_id == supplier_id:
			return contract
	var fresh: SupplierContractState = SupplierContractState.new()
	fresh.company_id = company_id
	fresh.supplier_id = supplier_id
	contracts.append(fresh)
	return fresh


func _deliver_po(po: PurchaseOrder) -> void:
	var inv: InventoryState = _dest_inventory(po)
	var company: CompanyState = CompanyManager.company(po.company_id)
	var now: int = GameClock.total_minutes()
	if inv == null or company == null:
		po.status = &"failed"
		po.failure_reason = "Destination no longer exists."
		return
	for line: Dictionary in po.lines:
		var ing: StringName = line.get("ingredient_id", &"")
		var item: InventoryItemDef = item_defs.get(ing)
		if item == null:
			continue
		_inv.add_lot(inv, ing, float(line["qty"]), float(line["quality"]),
			float(line["unit_cost"]), po.supplier_id, now, item.expiry_for(now))
	company.transact(&"stock_purchase", -po.goods_cost())
	company.transact(&"supply_delivery", -po.fee)
	var contract: SupplierContractState = _contract_for(po.company_id, po.supplier_id)
	contract.deliveries_total += 1
	if now <= po.eta_minute + 60:
		contract.deliveries_on_time += 1
	else:
		contract.deliveries_late += 1
	inventory_changed.emit(inv.owner_kind, inv.owner_id)
	if company.is_player:
		var supplier: SupplierDef = supplier_defs.get(po.supplier_id)
		var supplier_name: String = supplier.display_name if supplier != null else "Supplier"
		EconomyManager.post_message("good", "Shipment from %s arrived — $%s of stock." %
			[supplier_name, str(int(po.goods_cost()))])


## Daily reorder pass for one restaurant — groups needs per supplier and
## respects each ingredient's policy mode.
## Pull stock from a serving warehouse into a restaurant via transfer, up to
## the restaurant's policy target and whatever the warehouse actually holds.
func _fulfill_from_warehouse(rest: RestaurantState, inv: InventoryState,
		warehouse: WarehouseState, company: CompanyState) -> void:
	var wants: Array[Dictionary] = []
	for ing: StringName in inv.policies.keys():
		var policy: ReorderPolicy = inv.policies[ing]
		if policy == null or policy.target_stock <= 0.0:
			continue
		var projected: float = inv.available(ing) + transfer_inbound_qty(rest.building_id, ing)
		if projected >= policy.reorder_point:
			continue
		var take: float = minf(policy.target_stock - projected, warehouse.inventory.available(ing))
		if take >= 1.0:
			wants.append({"ingredient_id": ing, "qty": ceilf(take)})
	if not wants.is_empty():
		create_transfer_cmd(company.id, warehouse.id, rest.building_id, wants, true)


## A warehouse restocks itself from suppliers (always automatic — the player
## tunes the served restaurants' policies, and the warehouse mirrors them).
func _run_warehouse_reorder(wh: WarehouseState) -> void:
	var company: CompanyState = CompanyManager.company(wh.company_id)
	if company == null or wh.inventory.policies.is_empty():
		return
	var zero_use: Callable = func(_r: Variant, _i: StringName) -> float: return 0.0
	var groups: Dictionary = _proc.reorder_needs(wh.inventory, null, purchase_orders,
		supplier_defs, zero_use, RecipeManager.ingredient)
	for supplier_id: StringName in groups.keys():
		var supplier: SupplierDef = supplier_defs.get(supplier_id)
		if supplier == null:
			continue
		var lines: Array[Dictionary] = groups[supplier_id]
		_proc.pad_to_min_order(lines, supplier, RecipeManager.ingredient)
		var po: PurchaseOrder = _proc.make_draft(next_supply_id, wh.company_id,
			supplier, &"warehouse", wh.id, lines, disruptions,
			GameClock.total_minutes(), true, RecipeManager.ingredient)
		next_supply_id += 1
		purchase_orders.append(po)
		_try_place(po)
	if not groups.is_empty():
		orders_changed.emit()


func _run_reorder(rest: RestaurantState) -> void:
	var inv: InventoryState = inventory_for_restaurant(rest)
	var company: CompanyState = CompanyManager.company(rest.company_id)
	if company == null:
		return
	# Restaurants served by a warehouse pull stock from it via transfer; the
	# warehouse handles supplier procurement, so no direct restaurant POs.
	var warehouse: WarehouseState = warehouse_serving(rest.building_id)
	if warehouse != null:
		_fulfill_from_warehouse(rest, inv, warehouse, company)
		return
	var groups: Dictionary = _proc.reorder_needs(inv, rest, purchase_orders,
		supplier_defs, estimated_daily_use, RecipeManager.ingredient)
	for supplier_id: StringName in groups.keys():
		var supplier: SupplierDef = supplier_defs.get(supplier_id)
		if supplier == null:
			continue
		# Split the supplier group by policy mode — automatic lines place now,
		# approve/recommend lines wait as drafts for the player.
		var auto_lines: Array[Dictionary] = []
		var draft_lines: Array[Dictionary] = []
		for line: Dictionary in groups[supplier_id]:
			var policy: ReorderPolicy = inv.policy_for(line["ingredient_id"])
			var mode: StringName = policy.mode if policy != null else &"automatic"
			if mode == &"automatic":
				auto_lines.append(line)
			else:
				draft_lines.append(line)
		if not auto_lines.is_empty():
			_proc.pad_to_min_order(auto_lines, supplier, RecipeManager.ingredient)
			var po: PurchaseOrder = _proc.make_draft(next_supply_id, rest.company_id,
				supplier, &"restaurant", rest.building_id, auto_lines, disruptions,
				GameClock.total_minutes(), true, RecipeManager.ingredient)
			next_supply_id += 1
			purchase_orders.append(po)
			var placed: CommandResult = _try_place(po)
			if placed.ok and company.is_player:
				EconomyManager.post_message("info", "Restock ordered: %d item(s) from %s." %
					[auto_lines.size(), supplier.display_name])
		if not draft_lines.is_empty():
			_proc.pad_to_min_order(draft_lines, supplier, RecipeManager.ingredient)
			var draft: PurchaseOrder = _proc.make_draft(next_supply_id, rest.company_id,
				supplier, &"restaurant", rest.building_id, draft_lines, disruptions,
				GameClock.total_minutes(), true, RecipeManager.ingredient)
			next_supply_id += 1
			purchase_orders.append(draft)
			if company.is_player:
				EconomyManager.post_message("info", "Restock suggestion ready: %d item(s) from %s — review purchase orders." %
					[draft_lines.size(), supplier.display_name])
	orders_changed.emit()


func _prune_settled_orders() -> void:
	var cutoff: int = GameClock.total_minutes() - 7 * 1440
	var keep: Array[PurchaseOrder] = []
	for po: PurchaseOrder in purchase_orders:
		var settled: bool = po.status == &"delivered" or po.status == &"cancelled"
		if settled and po.created_minute < cutoff:
			continue
		keep.append(po)
	purchase_orders = keep
	var keep_transfers: Array[TransferOrder] = []
	for transfer: TransferOrder in transfer_orders:
		var done: bool = transfer.status == &"delivered" or transfer.status == &"cancelled"
		if done and transfer.created_minute < cutoff:
			continue
		keep_transfers.append(transfer)
	transfer_orders = keep_transfers


func _apply_warehouse_capacity(wh: WarehouseState) -> void:
	wh.inventory.capacity_by_class = {
		&"dry": wh.capacity_for(&"dry"),
		&"chilled": wh.capacity_for(&"chilled"),
		&"frozen": wh.capacity_for(&"frozen"),
	}


## Warehouse stocking targets follow the branches it serves: hold twice the
## sum of their targets so one warehouse run can top everyone up.
func _sync_warehouse_policies(wh: WarehouseState) -> void:
	var totals: Dictionary = {}
	var points: Dictionary = {}
	for building_id: int in wh.assigned_restaurant_ids:
		var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
		if rest == null:
			continue
		var inv: InventoryState = inventory_for_restaurant(rest)
		for ing: StringName in inv.policies:
			var policy: ReorderPolicy = inv.policies[ing]
			totals[ing] = float(totals.get(ing, 0.0)) + policy.target_stock
			points[ing] = float(points.get(ing, 0.0)) + policy.reorder_point
	var mult: float = EconomyManager.tuning_value("supply.warehouse_stock_mult", 2.0)
	for ing: StringName in totals.keys():
		var wh_policy: ReorderPolicy = wh.inventory.policy_for(ing)
		if wh_policy == null:
			wh_policy = ReorderPolicy.new()
			wh_policy.ingredient_id = ing
			wh_policy.mode = &"automatic"
			wh.inventory.policies[ing] = wh_policy
		wh_policy.target_stock = ceilf(float(totals[ing]) * mult)
		wh_policy.reorder_point = ceilf(float(points[ing]) * mult * 0.75)


## Cosmetic truck for a transfer when the cap allows and a route exists.
func _maybe_spawn_truck(transfer: TransferOrder, wh: WarehouseState,
		rest: RestaurantState) -> void:
	for i: int in range(_trucks.size() - 1, -1, -1):
		if not is_instance_valid(_trucks[i]):
			_trucks.remove_at(i)
	if _trucks.size() >= MAX_VISIBLE_TRUCKS:
		return
	var graph: RoadGraph = CityData.road_graph
	if graph == null:
		return
	var start_node: int = graph.nearest_lane_node(wh.world_pos)
	if start_node < 0:
		return
	var truck: Node3D = TrafficManager.spawn_ambient_car(graph.lane_points[start_node])
	if truck == null:
		return
	truck.set("kind", "supply")
	truck.set_model(TrafficManager.model_path_for("supply"))
	truck.set("owner_desc", "%s — supply run" % wh.display_name)
	var path: PackedInt32Array = TrafficManager.request_route(truck, wh.world_pos, rest.door_pos)
	if path.is_empty():
		truck.queue_free()
		TrafficManager.vehicles.erase(truck)
		return
	var shipment: SupplyShipment = SupplyShipment.new()
	shipment.transfer_id = transfer.id
	shipment.on_finished = func(_pos: Vector3) -> void: _free_truck(truck)
	truck.set_meta("supply_shipment", shipment)
	truck.start_trip(path, shipment)
	transfer.vehicle_visible = true
	_trucks.append(truck)


func _free_truck(truck: Node3D) -> void:
	_trucks.erase(truck)
	if is_instance_valid(truck):
		TrafficManager.vehicles.erase(truck)
		truck.queue_free()


func _refresh_markers() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var live: Dictionary = {}
	for wh: WarehouseState in warehouses:
		live[wh.id] = true
		if _markers.has(wh.id) and is_instance_valid(_markers[wh.id]):
			continue
		var marker: WarehouseMarker = WarehouseMarker.new()
		marker.name = "WarehouseMarker_%d" % wh.id
		scene.add_child(marker)
		marker.setup(wh)
		_markers[wh.id] = marker
	for id: int in _markers.keys():
		if not live.has(id):
			if is_instance_valid(_markers[id]):
				_markers[id].queue_free()
			_markers.erase(id)


func _on_hour(_day: int, _hour: int) -> void:
	var now: int = GameClock.total_minutes()
	# Settle purchase orders whose ETA passed.
	for event: Dictionary in _proc.tick(purchase_orders, now):
		var po: PurchaseOrder = event["po"]
		if event["kind"] == &"delivered":
			_deliver_po(po)
		else:
			var contract: SupplierContractState = _contract_for(po.company_id, po.supplier_id)
			contract.deliveries_total += 1
			contract.deliveries_failed += 1
			var company: CompanyState = CompanyManager.company(po.company_id)
			if company != null and company.is_player:
				EconomyManager.post_message("alert", "A shipment was lost — %s. The order is kept for retry." % po.failure_reason)
		orders_changed.emit()
	# Settle warehouse -> restaurant transfers.
	var transfer_events: Array[Dictionary] = _logi.tick(_inv, transfer_orders, now,
		func(building_id: int) -> InventoryState:
			var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
			return inventory_for_restaurant(rest) if rest != null else null,
		func(warehouse_id: int) -> InventoryState:
			var wh: WarehouseState = warehouse_by_id(warehouse_id)
			return wh.inventory if wh != null else null)
	for event: Dictionary in transfer_events:
		var transfer: TransferOrder = event["transfer"]
		var company: CompanyState = CompanyManager.company(transfer.company_id)
		if event["kind"] == &"delivered":
			inventory_changed.emit(&"restaurant", transfer.dest_restaurant_id)
			if company != null and company.is_player:
				EconomyManager.post_message("good", "Warehouse van delivered %.0f portions." % transfer.total_qty())
		else:
			if company != null and company.is_player:
				EconomyManager.post_message("alert", "A stock transfer bounced — goods returned to the warehouse.")
		orders_changed.emit()
	for company: CompanyState in CompanyManager.companies:
		var waste_cost: float = 0.0
		var waste_qty: float = 0.0
		for rest: RestaurantState in company.restaurants:
			if rest.inventory == null:
				continue
			var spoiled: Dictionary = _inv.spoil_tick(rest.inventory, now)
			if float(spoiled["wasted_qty"]) > 0.0:
				waste_cost += float(spoiled["wasted_cost"])
				waste_qty += float(spoiled["wasted_qty"])
				inventory_changed.emit(&"restaurant", rest.building_id)
		if waste_cost > 0.0:
			company.transact(&"stock_waste", -waste_cost)
			if company.is_player:
				EconomyManager.post_message("alert",
					"%.0f portions spoiled — $%.0f written off." % [waste_qty, waste_cost])


func _on_day(_day: int) -> void:
	# Roll today's consumption into the EWMA the forecasts read.
	_roll_disruptions()
	_prune_expired_disruptions()
	var alpha: float = EconomyManager.tuning_value("supply.ewma_alpha", 0.3)
	for company: CompanyState in CompanyManager.companies:
		# Warehouses restock from suppliers first so their shelves are as full
		# as possible before assigned restaurants pull from them.
		for wh: WarehouseState in warehouses:
			if wh.company_id == company.id:
				_run_warehouse_reorder(wh)
		for rest: RestaurantState in company.restaurants:
			var inv: InventoryState = rest.inventory
			if inv == null:
				continue
			var ids: Dictionary = {}
			for ing: StringName in inv.consumed_today.keys():
				ids[ing] = true
			for ing: StringName in inv.daily_use.keys():
				ids[ing] = true
			for ing: StringName in ids.keys():
				var today: float = float(inv.consumed_today.get(ing, 0.0))
				var prev: float = float(inv.daily_use.get(ing, today))
				inv.daily_use[ing] = _forecast.ewma(prev, today, alpha)
			inv.consumed_today = {}
			_run_reorder(rest)
	_prune_settled_orders()


## EconomyManager daily cost provider — runs once per company per day close.
## Warehouses carry a daily operating cost (rent + utilities + crew).
func _charge_daily_supply(company: CompanyState, _day: int) -> void:
	var upkeep: float = 0.0
	for wh: WarehouseState in warehouses:
		if wh.company_id == company.id:
			upkeep += wh.daily_cost()
	if upkeep > 0.0:
		company.transact(&"warehouse_rent", -upkeep)
