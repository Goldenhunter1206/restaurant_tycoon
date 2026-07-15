extends Node
## Owns the dish/staff catalogs and every company's restaurants, and advances
## the per-restaurant kitchen + dining-room simulation each game minute.
## Restaurant storage lives per company on CompanyState; by_building indexes
## every branch regardless of owner.
## Catalogs are directory-loaded: drop a .tres into data/dishes or
## data/staff_types and it is available without code changes.

signal restaurant_purchased(rest: RestaurantState)
signal restaurant_updated(building_id: int)
signal restaurant_closed(building_id: int)
signal order_state_changed(order: FoodOrder)
signal order_ready_for_delivery(order: FoodOrder)
signal job_market_changed

const DISH_DIR: String = "res://data/dishes"
const STAFF_TYPE_DIR: String = "res://data/staff_types"

## Editable-interior brain: furniture catalog, layout evaluation, validation.
var interior: InteriorLayoutService = null

var dishes: Dictionary = {}
var staff_types: Dictionary = {}
## The player's branches. Legacy alias kept for the many UI call sites; the
## actual storage is CompanyManager.player.restaurants.
var owned: Array[RestaurantState]:
	get:
		return CompanyManager.player.restaurants
## building_id -> RestaurantState for EVERY company's branches.
var by_building: Dictionary = {}
## Rolling pool of hireable applicants shared by all restaurants.
var job_market: Array[JobCandidate] = []

var _next_order_id: int = 1
var _next_staff_uid: int = 1
var _next_candidate_uid: int = 1
var _last_tick_minute: int = -1
var _initialized: bool = false


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_load_catalogs()
	interior = InteriorLayoutService.new()
	interior.load_catalog()
	RecipeManager.book_changed.connect(_sync_recipe_menu_entries)
	GameClock.minute_ticked.connect(_on_minute)
	GameClock.day_changed.connect(_on_day_changed)
	EconomyManager.daily_cost_providers.append(_charge_daily_costs)
	# CompanyManager (initialized just before us) already restored companies
	# from the save; we rebuild runtime restaurant state from them.
	var save: SaveGame = CompanyManager.loaded_save
	if save != null:
		_restore_from_save(save)
	else:
		_found_starting_restaurant()
	if job_market.is_empty():
		_refresh_job_market(GameClock.day)


func dish(dish_id: StringName) -> DishDef:
	return dishes.get(dish_id)


## Every company's branches — the sim and demand loops iterate this.
func all_restaurants() -> Array[RestaurantState]:
	var result: Array[RestaurantState] = []
	for rest: RestaurantState in by_building.values():
		result.append(rest)
	return result


## Reputation delta for the company that owns `rest`, tuning-clamped.
func add_company_reputation(rest: RestaurantState, delta: float) -> void:
	if rest == null:
		return
	var lo: float = float(EconomyManager.tuning_value("reputation.min", 1.0))
	var hi: float = float(EconomyManager.tuning_value("reputation.max", 5.0))
	rest.company().add_reputation(delta, lo, hi)


## Menu ids resolve to either a RecipeDef (custom/starter recipes) or a
## DishDef (fixed catalog items). One namespace, two backing types.
func resolve_item(dish_id: StringName) -> Dictionary:
	if RecipeManager.is_recipe(dish_id):
		var rec: RecipeDef = RecipeManager.recipe(dish_id)
		return {
			"kind": &"recipe",
			"display_name": rec.display_name,
			"category": rec.product_type,
			"prep_minutes": rec.cached_prep,
			"tiers": RecipeManager.tiers_for(dish_id),
			"suggested_price": RecipeManager.suggested_price_for(rec),
		}
	var def: DishDef = dishes.get(dish_id)
	if def == null:
		return {}
	return {
		"kind": &"dish",
		"display_name": def.display_name,
		"category": def.category,
		"prep_minutes": def.base_prep_minutes,
		"tiers": def.tiers,
		"suggested_price": def.suggested_price,
	}


func category_for(dish_id: StringName) -> StringName:
	var cat: StringName = RecipeManager.category_for(dish_id)
	if cat != &"":
		return cat
	var def: DishDef = dishes.get(dish_id)
	return def.category if def != null else &""


func quality_for(dish_id: StringName, tier_id: StringName) -> float:
	if RecipeManager.is_recipe(dish_id):
		var t: QualityTier = RecipeManager.tier_for(dish_id, tier_id)
		return t.quality_score if t != null else 0.5
	var def: DishDef = dishes.get(dish_id)
	if def != null:
		var t2: QualityTier = def.tier_by_id(tier_id)
		if t2 != null:
			return t2.quality_score
	return 0.5


func staff_type(type_id: StringName) -> StaffTypeDef:
	return staff_types.get(type_id)


# --- Ownership / purchase -------------------------------------------------


func price_for(building_id: int) -> float:
	var info: Dictionary = CityData.get_building(building_id)
	if info.is_empty():
		return 0.0
	var base: float = float(EconomyManager.tuning_value("purchase.base_price", 14000.0))
	var mults: Dictionary = EconomyManager.tuning_value("purchase.affluence_mult", {})
	var mult: float = float(mults.get(info.get("district", "N"), 1.0))
	var body: Node3D = get_node_or_null(info.get("node_path", NodePath()))
	var area: float = 120.0
	if body != null and body.has_meta("size"):
		var size: Vector3 = body.get_meta("size")
		area = size.x * size.z
	var size_factor: float = float(EconomyManager.tuning_value("purchase.size_factor", 0.004))
	return base * mult * (1.0 + size_factor * area)


func is_purchasable(building_id: int) -> bool:
	if by_building.has(building_id):
		return false
	var info: Dictionary = CityData.get_building(building_id)
	if info.is_empty():
		return false
	var btype: String = String(info.get("type", ""))
	var district: String = String(info.get("district", ""))
	if btype == "shop":
		return district in ["C", "D", "N", "R", "P"]
	# Downtown has no dedicated shop lots — ground-floor office conversions
	# are the (expensive) way into the D district.
	if btype == "office":
		return district == "D"
	return false


func purchasable_buildings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: int in CityData.buildings:
		if is_purchasable(id):
			var info: Dictionary = CityData.get_building(id).duplicate()
			info["price"] = price_for(id)
			result.append(info)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["price"]) < float(b["price"]))
	return result


func signing_fee_for(building_id: int) -> float:
	var frac: float = float(EconomyManager.tuning_value("purchase.signing_fee_fraction", 0.15))
	return price_for(building_id) * frac


func purchase(building_id: int, restaurant_name: String = "") -> bool:
	var result: CommandResult = purchase_location(&"player", building_id, restaurant_name)
	if not result.ok:
		if result.code == &"insufficient_cash":
			EconomyManager.post_message("alert", "Not enough cash to sign this lease ($%.0f)." % signing_fee_for(building_id))
		return false
	var rest: RestaurantState = result.payload
	var rents: Dictionary = EconomyManager.tuning_value("rent.daily_by_district", {})
	var rent: float = float(rents.get(rest.district, 120.0))
	EconomyManager.post_message("good", "Signed the lease on %s for $%.0f — rent is $%.0f/day." % [rest.restaurant_name, rest.purchase_price, rent])
	EconomyManager.post_message("info", "Hire cooks and waiters so %s can serve customers." % rest.restaurant_name)
	return true


## Pays the full property value; the location stops paying rent permanently.
func buyout(building_id: int) -> bool:
	var rest: RestaurantState = by_building.get(building_id)
	var result: CommandResult = buyout_location(&"player", building_id)
	if not result.ok:
		if result.code == &"insufficient_cash" and rest != null:
			EconomyManager.post_message("alert", "Not enough cash to buy %s outright ($%.0f)." % [rest.restaurant_name, rest.property_value])
		return false
	EconomyManager.post_message("good", "%s is now yours — no more rent!" % rest.restaurant_name)
	return true


# --- Company command layer (shared by the UI and the rival AI) --------------
# Every command validates ownership + funds against the acting company and
# returns a CommandResult, so AI and UI receive identical validation.


func purchase_location(company_id: StringName, building_id: int, restaurant_name: String = "") -> CommandResult:
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null:
		return CommandResult.fail(&"unknown_company", "No company '%s'." % company_id)
	if not is_purchasable(building_id):
		return CommandResult.fail(&"not_purchasable", "Building %d is not for sale." % building_id)
	var value: float = price_for(building_id)
	var fee: float = value * float(EconomyManager.tuning_value("purchase.signing_fee_fraction", 0.15))
	if not company.can_afford(fee):
		return CommandResult.fail(&"insufficient_cash", "Signing fee is $%.0f." % fee)
	company.transact(&"signing_fee", -fee)
	return CommandResult.good(_add_restaurant(building_id, restaurant_name, fee, value, company_id))


func buyout_location(company_id: StringName, building_id: int) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	var company: CompanyState = CompanyManager.company(company_id)
	if rest.owned_outright:
		return CommandResult.fail(&"already_owned", "%s is already owned outright." % rest.restaurant_name)
	if rest.property_value <= 0.0:
		rest.property_value = price_for(building_id)
	if not company.can_afford(rest.property_value):
		return CommandResult.fail(&"insufficient_cash", "Buyout costs $%.0f." % rest.property_value)
	company.transact(&"property_purchase", -rest.property_value)
	rest.owned_outright = true
	restaurant_updated.emit(building_id)
	return CommandResult.good(rest)


## Closes a branch: staff are let go, the building returns to the market. If
## the property was owned outright, a resale credit is paid out.
func close_branch(company_id: StringName, building_id: int) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	var company: CompanyState = CompanyManager.company(company_id)
	for i: int in range(rest.staff.size() - 1, -1, -1):
		var member: StaffMember = rest.staff[i]
		var def: StaffTypeDef = staff_types.get(member.type_id)
		if def != null and def.is_driver:
			DeliveryManager.on_driver_fired(rest, member)
		rest.staff.remove_at(i)
	for seat: Dictionary in rest.dining:
		_notify_citizen(seat["citizen"], "on_dine_rejected")
	for waiting: Dictionary in rest.dine_queue:
		_notify_citizen(waiting["citizen"], "on_dine_rejected")
	rest.dining.clear()
	rest.dine_queue.clear()
	for order: FoodOrder in rest.cook_backlog:
		order.state = FoodOrder.State.CANCELLED
		order_state_changed.emit(order)
	rest.cook_backlog.clear()
	for job: Dictionary in rest.cooking:
		var order: FoodOrder = job["order"]
		order.state = FoodOrder.State.CANCELLED
		order_state_changed.emit(order)
	rest.cooking.clear()
	if rest.owned_outright:
		var resale: float = rest.property_value * float(EconomyManager.tuning_value("purchase.resale_fraction", 0.7))
		company.transact(&"property_sale", resale)
	company.restaurants.erase(rest)
	by_building.erase(building_id)
	if is_inside_tree() and get_tree().current_scene != null:
		var marker: Node = get_tree().current_scene.get_node_or_null("RestaurantMarker_%d" % building_id)
		if marker != null:
			marker.queue_free()
	restaurant_closed.emit(building_id)
	return CommandResult.good(rest)


func hire(company_id: StringName, building_id: int, candidate_uid: int, shift_start: float, shift_hours: float = 8.0) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	for i: int in job_market.size():
		var cand: JobCandidate = job_market[i]
		if cand.uid != candidate_uid:
			continue
		var def: StaffTypeDef = staff_types.get(cand.type_id)
		if def == null:
			return CommandResult.fail(&"unknown_staff_type", "No staff type '%s'." % cand.type_id)
		job_market.remove_at(i)
		var member: StaffMember = _make_member(cand.type_id, cand.candidate_name, cand.attributes, cand.hourly_wage, shift_start, shift_hours)
		member.experience = cand.experience
		member.competencies = cand.competencies.duplicate(true)
		if member.competencies.is_empty():
			member.competencies = cand.attributes.duplicate(true)
		member.traits = cand.traits.duplicate()
		member.availability_by_weekday = cand.availability_by_weekday.duplicate(true)
		member.current_branch_building_id = building_id
		rest.staff.append(member)
		if def.is_driver:
			DeliveryManager.on_driver_hired(rest, member)
		restaurant_updated.emit(building_id)
		job_market_changed.emit()
		return CommandResult.good(member)
	return CommandResult.fail(&"candidate_gone", "Candidate %d is no longer available." % candidate_uid)


func fire_staff(company_id: StringName, building_id: int, uid: int) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	for i: int in rest.staff.size():
		var member: StaffMember = rest.staff[i]
		if member.uid == uid:
			rest.staff.remove_at(i)
			var def: StaffTypeDef = staff_types.get(member.type_id)
			if def != null and def.is_driver:
				DeliveryManager.on_driver_fired(rest, member)
			restaurant_updated.emit(building_id)
			return CommandResult.good(member)
	return CommandResult.fail(&"unknown_staff", "No staff member %d at this branch." % uid)


func set_shift_cmd(company_id: StringName, building_id: int, uid: int, start: float, hours: float) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	var lo: float = float(EconomyManager.tuning_value("staff.min_shift_hours", 2.0))
	var hi: float = float(EconomyManager.tuning_value("staff.max_shift_hours", 10.0))
	for member: StaffMember in rest.staff:
		if member.uid == uid:
			member.shift_start = wrapf(start, 0.0, 24.0)
			member.shift_hours = clampf(hours, lo, hi)
			restaurant_updated.emit(building_id)
			return CommandResult.good(member)
	return CommandResult.fail(&"unknown_staff", "No staff member %d at this branch." % uid)


func set_menu_entry_cmd(company_id: StringName, building_id: int, dish_id: StringName, price: float, tier: StringName, enabled: bool) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	for entry: MenuEntry in rest.menu:
		if entry.dish_id == dish_id:
			if enabled and not entry.enabled and not _has_free_menu_slot(rest):
				restaurant_updated.emit(building_id)
				return CommandResult.fail(&"no_slots", "All %d kitchen stations are in use." % rest.menu_slots)
			entry.price = maxf(0.5, price)
			entry.tier = tier
			entry.enabled = enabled
			restaurant_updated.emit(building_id)
			return CommandResult.good(entry)
	if enabled and not _has_free_menu_slot(rest):
		return CommandResult.fail(&"no_slots", "All %d kitchen stations are in use." % rest.menu_slots)
	var entry: MenuEntry = MenuEntry.new()
	entry.dish_id = dish_id
	entry.price = maxf(0.5, price)
	entry.tier = tier
	entry.enabled = enabled
	rest.menu.append(entry)
	restaurant_updated.emit(building_id)
	return CommandResult.good(entry)


func set_hours_cmd(company_id: StringName, building_id: int, new_open: float, new_close: float) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	rest.open_hour = wrapf(new_open, 0.0, 24.0)
	rest.close_hour = wrapf(new_close, 0.0, 24.0)
	restaurant_updated.emit(building_id)
	return CommandResult.good(rest)


func set_channels_cmd(company_id: StringName, building_id: int, dine_in: bool, delivery: bool) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	rest.dine_in_enabled = dine_in
	rest.delivery_enabled = delivery
	restaurant_updated.emit(building_id)
	return CommandResult.good(rest)


func set_delivery_cap_cmd(company_id: StringName, building_id: int, cap: int) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	rest.delivery_cap = clampi(cap, 0, 99)
	restaurant_updated.emit(building_id)
	return CommandResult.good(rest)


## Deprecated since editable interiors: menu capacity now derives from placed
## kitchen furniture (prep counters, shelves). Kept for AI compatibility.
func buy_menu_slot_cmd(_company_id: StringName, _building_id: int) -> CommandResult:
	return CommandResult.fail(&"deprecated", "Kitchen capacity now comes from prep counters and shelves placed in the interior.")


## Commits an edited interior draft: validates, charges/refunds the money
## delta, swaps the live layout and refreshes every derived capacity cache.
## The single mutation entry point for player editor AND AI templates.
func edit_interior_cmd(company_id: StringName, building_id: int, draft: InteriorLayoutState) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	if draft == null:
		return CommandResult.fail(&"no_layout", "Nothing to apply.")
	var company: CompanyState = CompanyManager.company(company_id)
	var ev: InteriorEvaluation = interior.evaluate(draft)
	if not ev.is_valid():
		var first: Dictionary = ev.blocking_issues()[0]
		return CommandResult.fail(&"invalid_layout", String(first.get("message", "The layout is invalid.")))
	var diff: Dictionary = interior.price_diff(rest.interior_layout, draft)
	var net: float = float(diff["net"])
	if net > 0.0 and not company.can_afford(net):
		return CommandResult.fail(&"insufficient_cash", "This layout needs $%.0f more." % net)
	if float(diff["buy"]) > 0.0:
		company.transact(&"furniture", -float(diff["buy"]))
		rest.today["expenses"] = float(rest.today.get("expenses", 0.0)) + float(diff["buy"])
	if float(diff["refund"]) > 0.0:
		company.transact(&"furniture_resale", float(diff["refund"]))
	draft.revision = rest.interior_layout.revision + 1 if rest.interior_layout != null else 1
	rest.interior_layout = draft
	interior.apply_to_restaurant(rest, ev)
	restaurant_updated.emit(building_id)
	return CommandResult.good(rest)


## Applies a designer template wholesale: everything not in the template is
## sold, the template's furniture is bought, plus a one-off design fee.
func apply_template_cmd(company_id: StringName, building_id: int, template_id: StringName) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	var template: InteriorTemplateDef = interior.template_for(template_id)
	if template == null:
		return CommandResult.fail(&"not_found", "Unknown interior set %s." % template_id)
	if template.prereq_cap != &"" and not CapabilityRegistry.has(company_id, template.prereq_cap):
		return CommandResult.fail(&"locked", CapabilityRegistry.explain(company_id, template.prereq_cap))
	var company: CompanyState = CompanyManager.company(company_id)
	var draft: InteriorLayoutState = template.build_layout()
	draft.expansion_level = rest.interior_layout.expansion_level
	draft.grid_rows = rest.interior_layout.grid_rows
	draft.grid_cols = rest.interior_layout.grid_cols
	var diff: Dictionary = interior.price_diff(rest.interior_layout, draft)
	if not company.can_afford(float(diff["net"]) + template.design_fee):
		return CommandResult.fail(&"insufficient_cash", "%s costs $%.0f all-in." % [template.display_name, float(diff["net"]) + template.design_fee])
	var result: CommandResult = edit_interior_cmd(company_id, building_id, draft)
	if result.ok and template.design_fee > 0.0:
		company.transact(&"furniture", -template.design_fee)
		rest.today["expenses"] = float(rest.today.get("expenses", 0.0)) + template.design_fee
	return result


## Pushes the front wall out, adding floor rows on the door side. Placements
## keep their coordinates because the grid origin sits at the kitchen corner.
func expand_interior_cmd(company_id: StringName, building_id: int) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	var layout: InteriorLayoutState = rest.interior_layout
	if layout.expansion_level >= 2:
		return CommandResult.fail(&"cap_reached", "The property cannot grow any further.")
	var company: CompanyState = CompanyManager.company(company_id)
	var cost: float = maxf(2000.0, rest.property_value * 0.25) * float(layout.expansion_level + 1)
	if not company.can_afford(cost):
		return CommandResult.fail(&"insufficient_cash", "Expanding costs $%.0f." % cost)
	company.transact(&"expansion", -cost)
	rest.today["expenses"] = float(rest.today.get("expenses", 0.0)) + cost
	layout.expansion_level += 1
	layout.grid_rows += InteriorLayoutState.EXPAND_STEP
	layout.revision += 1
	var ev: InteriorEvaluation = interior.evaluate(layout)
	interior.apply_to_restaurant(rest, ev)
	restaurant_updated.emit(building_id)
	return CommandResult.good(rest)


func set_repair_policy_cmd(company_id: StringName, building_id: int, policy: StringName, threshold: float) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	rest.repair_policy = policy
	rest.repair_threshold = clampf(threshold, 0.05, 0.95)
	restaurant_updated.emit(building_id)
	return CommandResult.good(rest)


## Player wrapper for the interior editor's Save button.
func edit_interior(building_id: int, draft: InteriorLayoutState) -> CommandResult:
	var result: CommandResult = edit_interior_cmd(&"player", building_id, draft)
	if result.ok:
		var rest: RestaurantState = result.payload
		EconomyManager.post_message("good", "%s: new interior layout applied — %d tables, %d stations." % [rest.restaurant_name, rest.table_count, rest.cook_station_cap])
	else:
		EconomyManager.post_message("alert", result.message)
	return result


## Resolves a branch and validates that `company_id` owns it.
func _owned_branch(company_id: StringName, building_id: int) -> CommandResult:
	var rest: RestaurantState = by_building.get(building_id)
	if rest == null:
		return CommandResult.fail(&"not_found", "No restaurant at building %d." % building_id)
	if rest.company_id != company_id:
		return CommandResult.fail(&"not_owner", "Building %d belongs to another company." % building_id)
	return CommandResult.good(rest)


# --- Order intake ----------------------------------------------------------


func make_order(building_id: int, citizen_id: int, dish_id: StringName, is_delivery: bool) -> FoodOrder:
	var rest: RestaurantState = by_building.get(building_id)
	if rest == null:
		return null
	var entry: MenuEntry = rest.menu_entry_for(dish_id)
	if entry == null:
		return null
	var order: FoodOrder = FoodOrder.new()
	order.order_id = _next_order_id
	_next_order_id += 1
	order.restaurant_id = building_id
	order.citizen_id = citizen_id
	order.dish_id = dish_id
	order.tier = entry.tier
	order.price = entry.price
	order.placed_minute = GameClock.total_minutes()
	order.is_delivery = is_delivery
	if RecipeManager.is_recipe(dish_id):
		# Snapshot the recipe so later edits never mutate this order.
		var rec: RecipeDef = RecipeManager.recipe(dish_id)
		var rtier: QualityTier = RecipeManager.tier_for(dish_id, entry.tier)
		order.recipe_id = rec.id
		order.recipe_version = rec.version
		order.product_category = rec.product_type
		for c: RecipeComponent in rec.components:
			order.components_snapshot.append({
				"ingredient_id": c.ingredient_id,
				"role": c.role,
				"qty": c.quantity,
			})
		order.ingredient_cost = rtier.ingredient_cost if rtier != null else rec.cached_cost
		order.prep_minutes = rec.cached_prep
	else:
		var def: DishDef = dishes.get(dish_id)
		if def == null:
			return null
		var tier: QualityTier = def.tier_by_id(entry.tier)
		order.product_category = def.category
		order.ingredient_cost = tier.ingredient_cost if tier != null else 2.0
		order.prep_minutes = def.base_prep_minutes
	return order


## Delivery intake. Returns false when the restaurant cannot take the order
## (closed, channel off, cap reached, no driver on shift).
func place_delivery_order(order: FoodOrder) -> bool:
	var rest: RestaurantState = by_building.get(order.restaurant_id)
	if rest == null or not rest.delivery_enabled:
		return false
	if not rest.is_open(GameClock.game_hours):
		return false
	if rest.active_deliveries >= rest.delivery_cap:
		return false
	if rest.staff_on_shift(&"driver", GameClock.game_hours) <= 0:
		return false
	if rest.staff_on_shift(&"cook", GameClock.game_hours) <= 0:
		return false
	# Reserve the bill of materials now; the shortage policy may reject the
	# order outright instead of letting the kitchen start something it can't cook.
	if not SupplyManager.reserve_for_order(rest, order).ok:
		rest.today["stockouts"] = int(rest.today.get("stockouts", 0)) + 1
		return false
	order.state = FoodOrder.State.QUEUED
	rest.cook_backlog.append(order)
	rest.active_deliveries += 1
	DeliveryManager.register_order(order)
	order_state_changed.emit(order)
	return true


## Dine-in intake, called when a citizen arrives at the door.
## Returns "seated", "queued" or "rejected".
func request_seat(citizen: Node, building_id: int, dish_id: StringName) -> String:
	var rest: RestaurantState = by_building.get(building_id)
	if rest == null or not rest.dine_in_enabled:
		return "rejected"
	if not rest.is_open(GameClock.game_hours):
		return "rejected"
	if rest.staff_on_shift(&"cook", GameClock.game_hours) <= 0:
		return "rejected"
	if rest.staff_on_shift(&"waiter", GameClock.game_hours) <= 0:
		return "rejected"
	if rest.menu_entry_for(dish_id) == null:
		return "rejected"
	if _try_seat(rest, citizen, dish_id):
		return "seated"
	rest.dine_queue.append({
		"citizen": citizen,
		"dish_id": dish_id,
		"arrived_minute": GameClock.total_minutes(),
	})
	return "queued"


# --- Staff -----------------------------------------------------------------


## Fabricates an average-ish employee outside the job market (starting staff).
func _hire_generated(rest: RestaurantState, type_id: StringName, shift_start: float, shift_hours: float = 8.0) -> StaffMember:
	var def: StaffTypeDef = staff_types.get(type_id)
	if rest == null or def == null:
		return null
	var member: StaffMember = _make_member(type_id, _random_person_name(), _roll_attributes(def), def.base_hourly_wage, shift_start, shift_hours)
	member.current_branch_building_id = rest.building_id
	rest.staff.append(member)
	if def.is_driver:
		DeliveryManager.on_driver_hired(rest, member)
	restaurant_updated.emit(rest.building_id)
	return member


func _make_member(type_id: StringName, member_name: String, attrs: Dictionary, wage: float, shift_start: float, shift_hours: float) -> StaffMember:
	var lo: float = float(EconomyManager.tuning_value("staff.min_shift_hours", 2.0))
	var hi: float = float(EconomyManager.tuning_value("staff.max_shift_hours", 10.0))
	var member: StaffMember = StaffMember.new()
	member.uid = _next_staff_uid
	_next_staff_uid += 1
	member.type_id = type_id
	member.staff_name = member_name
	member.attributes = attrs.duplicate()
	member.competencies = attrs.duplicate(true)
	member.hourly_wage = wage
	member.shift_start = wrapf(shift_start, 0.0, 24.0)
	member.shift_hours = clampf(shift_hours, lo, hi)
	return member


func _roll_attributes(def: StaffTypeDef, rng: RandomNumberGenerator = null) -> Dictionary:
	var attrs: Dictionary = {}
	if def == null:
		return attrs
	var roller: RandomNumberGenerator = rng
	if roller == null:
		roller = RandomNumberGenerator.new()
		roller.randomize()
	for key: StringName in def.attribute_keys:
		attrs[key] = clampf(roller.randfn(0.5, 0.2), 0.05, 0.95)
	return attrs


func set_shift(building_id: int, uid: int, start: float, hours: float) -> void:
	set_shift_cmd(&"player", building_id, uid, start, hours)


func fire(building_id: int, uid: int) -> bool:
	return fire_staff(&"player", building_id, uid).ok


# --- Job market --------------------------------------------------------------

## City labor-market climate, nudged by Phase 4 events. 0 = neutral.
var labor_market_supply_shift: float = 0.0
var labor_market_wage_shift: float = 0.0


func candidates_for(type_id: StringName) -> Array[JobCandidate]:
	var result: Array[JobCandidate] = []
	for cand: JobCandidate in job_market:
		if cand.type_id == type_id:
			result.append(cand)
	return result


func hire_candidate(building_id: int, candidate_uid: int, shift_start: float, shift_hours: float = 8.0) -> StaffMember:
	return hire(&"player", building_id, candidate_uid, shift_start, shift_hours).payload


## Ages the pool each day: stale/leaving candidates drop out, fresh ones apply.
func _refresh_job_market(day: int) -> void:
	var lifetime: int = int(EconomyManager.tuning_value("hiring.candidate_lifetime_days", 4))
	var leave_chance: float = float(EconomyManager.tuning_value("hiring.daily_leave_chance", 0.2))
	var rng: RandomNumberGenerator = WorkforceRng.make(&"market", day, [])
	for i: int in range(job_market.size() - 1, -1, -1):
		var cand: JobCandidate = job_market[i]
		if day - cand.posted_day >= lifetime or rng.randf() < leave_chance:
			job_market.remove_at(i)
	var lo: int = int(EconomyManager.tuning_value("hiring.market_min", 3))
	var hi: int = int(EconomyManager.tuning_value("hiring.market_max", 5))
	var supply_bonus: int = _market_supply_bonus()
	for type_id: StringName in staff_types:
		var have: int = candidates_for(type_id).size()
		var target: int = maxi(1, rng.randi_range(lo, hi) + supply_bonus)
		while have < target:
			var cand_rng: RandomNumberGenerator = WorkforceRng.make(&"market", day, [type_id, _next_candidate_uid])
			job_market.append(_generate_candidate(type_id, cand_rng))
			have += 1
	job_market_changed.emit()


func _market_supply_bonus() -> int:
	var player: CompanyState = CompanyManager.player
	var reputation: float = player.reputation if player != null else 3.0
	# A stronger reputation and a healthy wage climate attract more applicants.
	var bonus: float = clampf((reputation - 3.0) * 0.5, -1.0, 2.0) + labor_market_supply_shift
	return int(round(bonus))


func _generate_candidate(type_id: StringName, rng: RandomNumberGenerator = null) -> JobCandidate:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var def: StaffTypeDef = staff_types.get(type_id)
	var cand: JobCandidate = JobCandidate.new()
	cand.uid = _next_candidate_uid
	_next_candidate_uid += 1
	cand.type_id = type_id
	cand.candidate_name = _random_person_name(rng)
	cand.attributes = _roll_attributes(def, rng)
	cand.hourly_wage = _asking_wage(def, cand.attributes, rng)
	cand.posted_day = GameClock.day
	cand.expires_day = GameClock.day + int(EconomyManager.tuning_value("hiring.candidate_lifetime_days", 4))
	cand.competencies = cand.attributes.duplicate(true)
	cand.experience = _average_attributes(cand.attributes) * 120.0
	cand.manager_eligible = type_id == &"manager"
	# Imperfect info: the roster shows only noised bands until an interview.
	cand.interview_state = &"unseen"
	cand.revealed_competencies = _noised_competencies(cand.competencies, rng)
	for weekday: int in 7:
		cand.availability_by_weekday[weekday] = true
	return cand


func _noised_competencies(source: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var noised: Dictionary = {}
	for key: Variant in source:
		noised[key] = clampf(float(source[key]) + rng.randf_range(-0.2, 0.2), 0.0, 1.0)
	return noised


func _average_attributes(attributes: Dictionary) -> float:
	if attributes.is_empty():
		return 0.5
	var total: float = 0.0
	for value: Variant in attributes.values():
		total += float(value)
	return total / float(attributes.size())


## Better attributes -> higher asking wage (~0.6x to ~1.4x of the role base).
func _asking_wage(def: StaffTypeDef, attrs: Dictionary, rng: RandomNumberGenerator = null) -> float:
	var base_frac: float = float(EconomyManager.tuning_value("hiring.wage_base_frac", 0.6))
	var span: float = float(EconomyManager.tuning_value("hiring.wage_attr_span", 0.8))
	var noise: float = float(EconomyManager.tuning_value("hiring.wage_noise", 0.06))
	var avg: float = 0.5
	if not attrs.is_empty():
		var total: float = 0.0
		for value: Variant in attrs.values():
			total += float(value)
		avg = total / float(attrs.size())
	var base: float = def.base_hourly_wage if def != null else 8.0
	var noise_mult: float = rng.randf_range(1.0 - noise, 1.0 + noise) if rng != null else randf_range(1.0 - noise, 1.0 + noise)
	var wage: float = base * (base_frac + span * avg) * noise_mult * (1.0 + labor_market_wage_shift)
	return snappedf(wage, 0.25)


# --- Settings mutators (UI entry points) ------------------------------------


func set_menu_entry(building_id: int, dish_id: StringName, price: float, tier: StringName, enabled: bool) -> void:
	var result: CommandResult = set_menu_entry_cmd(&"player", building_id, dish_id, price, tier, enabled)
	if result.code == &"no_slots":
		var rest: RestaurantState = by_building.get(building_id)
		EconomyManager.post_message("alert",
			"All %d kitchen stations at %s are in use — buy a station or take a dish off the menu."
			% [rest.menu_slots, rest.restaurant_name])
		# Preserve legacy behavior: a brand-new entry is still added, disabled.
		if rest.menu_entry_for(dish_id) == null:
			set_menu_entry_cmd(&"player", building_id, dish_id, price, tier, false)


## Every live recipe needs a (disabled) menu row in every restaurant so the
## player can enable freshly saved recipes. Runs on each book change.
func _sync_recipe_menu_entries() -> void:
	for rest: RestaurantState in owned:
		var changed: bool = false
		for rec: RecipeDef in RecipeManager.live_recipes():
			var found: bool = false
			for entry: MenuEntry in rest.menu:
				if entry.dish_id == rec.id:
					found = true
					break
			if not found:
				var rentry: MenuEntry = MenuEntry.new()
				rentry.dish_id = rec.id
				rentry.tier = &"med"
				rentry.price = RecipeManager.suggested_price_for(rec)
				rentry.enabled = false
				rest.menu.append(rentry)
				changed = true
		if changed:
			restaurant_updated.emit(rest.building_id)


func _has_free_menu_slot(rest: RestaurantState) -> bool:
	return rest.enabled_dish_count() < rest.menu_slots


## Price of the next kitchen station: escalates per station already added.
func menu_slot_price(rest: RestaurantState) -> float:
	var base: float = float(EconomyManager.tuning_value("menu.slot_base_price", 2500.0))
	var growth: float = float(EconomyManager.tuning_value("menu.slot_price_growth", 1.6))
	var base_slots: int = int(EconomyManager.tuning_value("menu.base_slots", 4))
	return base * pow(growth, float(maxi(0, rest.menu_slots - base_slots)))


func buy_menu_slot(building_id: int) -> bool:
	var rest: RestaurantState = by_building.get(building_id)
	if rest == null:
		return false
	var result: CommandResult = buy_menu_slot_cmd(&"player", building_id)
	if not result.ok:
		if result.code == &"cap_reached":
			EconomyManager.post_message("info", "The kitchen at %s has no room for more stations." % rest.restaurant_name)
		elif result.code == &"insufficient_cash":
			EconomyManager.post_message("alert", "Not enough cash for a new kitchen station ($%.0f)." % menu_slot_price(rest))
		return false
	EconomyManager.post_message("good", "%s installed a kitchen station — %d dish slots now." % [rest.restaurant_name, rest.menu_slots])
	return true


## Daily mise-en-place cost of one enabled dish at a given quality tier.
func dish_upkeep(def: DishDef, tier_id: StringName) -> float:
	var base: float = float(EconomyManager.tuning_value("menu.daily_upkeep_per_dish", 8.0))
	var factor: float = float(EconomyManager.tuning_value("menu.upkeep_ingredient_factor", 1.5))
	var cost: float = 2.0
	if def != null:
		var tier: QualityTier = def.tier_by_id(tier_id)
		if tier != null:
			cost = tier.ingredient_cost
	return base + cost * factor


func menu_upkeep_for(rest: RestaurantState) -> float:
	var total: float = 0.0
	for entry: MenuEntry in rest.menu:
		if entry.enabled:
			total += upkeep_for_id(entry.dish_id, entry.tier)
	return total


## Daily upkeep for any menu id — recipe or fixed dish.
func upkeep_for_id(dish_id: StringName, tier_id: StringName) -> float:
	if not RecipeManager.is_recipe(dish_id):
		return dish_upkeep(dishes.get(dish_id), tier_id)
	# Recipe dishes draw real inventory now — carrying cost and spoilage are
	# charged by SupplyManager, so daily upkeep keeps only the prep-labor share.
	return float(EconomyManager.tuning_value("menu.daily_upkeep_per_dish", 8.0))


func set_hours(building_id: int, open_hour: float, close_hour: float) -> void:
	set_hours_cmd(&"player", building_id, open_hour, close_hour)


func set_channels(building_id: int, dine_in: bool, delivery: bool) -> void:
	set_channels_cmd(&"player", building_id, dine_in, delivery)


func set_delivery_cap(building_id: int, cap: int) -> void:
	set_delivery_cap_cmd(&"player", building_id, cap)


# --- Per-minute simulation ---------------------------------------------------


func _on_minute(_day: int, hour: int, _minute: int) -> void:
	var now: int = GameClock.total_minutes()
	if _last_tick_minute < 0:
		_last_tick_minute = now
		return
	var dm: int = now - _last_tick_minute
	if dm <= 0:
		return
	_last_tick_minute = now
	for rest: RestaurantState in all_restaurants():
		_tick_restaurant(rest, now, dm, hour)
		restaurant_updated.emit(rest.building_id)


func _tick_restaurant(rest: RestaurantState, now: int, dm: int, _hour: int) -> void:
	var hourf: float = GameClock.game_hours
	# Waiters accumulate fractional serving capacity while on shift; a better
	# service attribute means more guests seated per hour.
	var waiter_span: float = float(EconomyManager.tuning_value("staff.effects.waiter_span", 0.6))
	var waiters: int = 0
	var serve_per_hour: float = 0.0
	for member: StaffMember in rest.staff:
		if not member.on_shift(hourf) or member.is_absent(GameClock.day):
			continue
		var wdef: StaffTypeDef = staff_types.get(member.type_id)
		if wdef == null or wdef.waiter_customers_per_hour <= 0.0:
			continue
		waiters += 1
		serve_per_hour += wdef.waiter_customers_per_hour * (1.0 + (member.competency(&"service") - 0.5) * waiter_span)
	if waiters > 0:
		var cap: float = maxf(2.0, float(waiters) * 2.0)
		# Layout flow: long walks and crowded aisles slow every serve.
		rest.waiter_credits = minf(rest.waiter_credits + serve_per_hour / 60.0 * float(dm) * rest.interior_throughput_mod, cap)
	# Kitchen: assign each live cook slot so the UI can show who owns every dish.
	var cook_slots: Array[Dictionary] = _cook_slot_descriptors(rest, hourf)
	while rest.cooking.size() < cook_slots.size() and not rest.cook_backlog.is_empty():
		var order: FoodOrder = rest.cook_backlog.pop_front()
		if order.state == FoodOrder.State.CANCELLED:
			continue
		var slot: Dictionary = cook_slots[rest.cooking.size()]
		order.state = FoodOrder.State.COOKING
		order.cook_consistency = float(slot.get("consistency", 0.5))
		# Consume reserved stock lots; the actual lot cost (not the recipe's
		# cached estimate) is what lands on the ledger.
		var consume_result: CommandResult = SupplyManager.consume_for_order(rest, order)
		var ingredient_charge: float = order.ingredient_cost
		if consume_result.ok and consume_result.payload is Dictionary:
			ingredient_charge = float(consume_result.payload.get("cost", order.ingredient_cost))
		rest.today["expenses"] = float(rest.today.get("expenses", 0.0)) + ingredient_charge
		rest.cooking.append({
			"order": order,
			"minutes_left": order.prep_minutes,
			"cook_uid": slot["cook_uid"],
			"cook_name": slot["cook_name"],
			"slot_index": slot["slot_index"],
		})
		order_state_changed.emit(order)
	var active: int = mini(cook_slots.size(), rest.cooking.size())
	for i: int in range(rest.cooking.size() - 1, -1, -1):
		var job: Dictionary = rest.cooking[i]
		var order: FoodOrder = job["order"]
		if order.state == FoodOrder.State.CANCELLED:
			rest.cooking.remove_at(i)
			continue
		if i >= active:
			job["cook_uid"] = -1
			job["cook_name"] = "Waiting for a cook"
			job["slot_index"] = -1
			continue
		var active_slot: Dictionary = cook_slots[i]
		job["cook_uid"] = active_slot["cook_uid"]
		job["cook_name"] = active_slot["cook_name"]
		job["slot_index"] = active_slot["slot_index"]
		order.cook_consistency = float(active_slot.get("consistency", 0.5))
		job["minutes_left"] = float(job["minutes_left"]) - float(dm) * float(active_slot.get("speed_mult", 1.0))
		if float(job["minutes_left"]) <= 0.0:
			rest.cooking.remove_at(i)
			_on_cooked(rest, order)
	_tick_dining(rest, now)
	_tick_dine_queue(rest, now)


func _on_cooked(rest: RestaurantState, order: FoodOrder) -> void:
	if order.is_delivery:
		order.state = FoodOrder.State.READY
		order_state_changed.emit(order)
		order_ready_for_delivery.emit(order)
		return
	# Dine-in: the matching seated guest starts eating.
	var eat_minutes: float = float(EconomyManager.tuning_value("dinein.eat_minutes", 45.0))
	for seat: Dictionary in rest.dining:
		if seat["order"] == order:
			seat["done_minute"] = GameClock.total_minutes() + int(eat_minutes)
			order.state = FoodOrder.State.SERVED
			order_state_changed.emit(order)
			return
	# Guest already left — the food is wasted.
	order.state = FoodOrder.State.CANCELLED
	order_state_changed.emit(order)


func _tick_dining(rest: RestaurantState, now: int) -> void:
	var food_wait_max: int = int(EconomyManager.tuning_value("dinein.food_wait_minutes", 60))
	for i: int in range(rest.dining.size() - 1, -1, -1):
		var seat: Dictionary = rest.dining[i]
		var order: FoodOrder = seat["order"]
		var done_minute: int = int(seat["done_minute"])
		if done_minute > 0 and now >= done_minute:
			rest.dining.remove_at(i)
			rest.tables_occupied = maxi(0, rest.tables_occupied - 1)
			_complete_dine_in(rest, seat["citizen"], order)
		elif done_minute < 0 and now - order.placed_minute > food_wait_max:
			# Kitchen never delivered — the guest storms out.
			rest.dining.remove_at(i)
			rest.tables_occupied = maxi(0, rest.tables_occupied - 1)
			order.state = FoodOrder.State.CANCELLED
			rest.today["queue_leaves"] = int(rest.today.get("queue_leaves", 0)) + 1
			add_company_reputation(rest, float(EconomyManager.tuning_value("reputation.per_queue_leave", -0.04)))
			_notify_citizen(seat["citizen"], "on_dine_rejected")
			order_state_changed.emit(order)


func _tick_dine_queue(rest: RestaurantState, now: int) -> void:
	# Comfortable interiors buy patience: up to +40% wait tolerance at max
	# comfort, less when the room is in poor shape.
	var patience_mod: float = 1.0 + clampf(rest.interior_comfort, 0.0, 5.0) * 0.08
	var leave_after: int = int(float(EconomyManager.tuning_value("dinein.queue_leave_minutes", 25)) * patience_mod)
	for i: int in range(rest.dine_queue.size() - 1, -1, -1):
		var waiting: Dictionary = rest.dine_queue[i]
		var citizen: Node = waiting["citizen"]
		if not is_instance_valid(citizen):
			rest.dine_queue.remove_at(i)
			continue
		if _try_seat(rest, citizen, waiting["dish_id"]):
			rest.dine_queue.remove_at(i)
			continue
		if now - int(waiting["arrived_minute"]) > leave_after:
			rest.dine_queue.remove_at(i)
			rest.today["queue_leaves"] = int(rest.today.get("queue_leaves", 0)) + 1
			add_company_reputation(rest, float(EconomyManager.tuning_value("reputation.per_queue_leave", -0.04)))
			_notify_citizen(citizen, "on_dine_rejected")


func _try_seat(rest: RestaurantState, citizen: Node, dish_id: StringName) -> bool:
	if rest.tables_occupied >= rest.table_count or rest.waiter_credits < 1.0:
		return false
	var citizen_id: int = -1
	var data: Variant = citizen.get("data")
	if data is Dictionary:
		citizen_id = int((data as Dictionary).get("id", -1))
	var order: FoodOrder = make_order(rest.building_id, citizen_id, dish_id, false)
	if order == null:
		return false
	if not SupplyManager.reserve_for_order(rest, order).ok:
		rest.today["stockouts"] = int(rest.today.get("stockouts", 0)) + 1
		return false
	rest.tables_occupied += 1
	rest.waiter_credits -= 1.0
	order.state = FoodOrder.State.QUEUED
	rest.cook_backlog.append(order)
	rest.dining.append({"citizen": citizen, "order": order, "done_minute": -1})
	rest.today["guests"] = int(rest.today.get("guests", 0)) + 1
	_notify_citizen(citizen, "on_seated")
	order_state_changed.emit(order)
	return true


func _complete_dine_in(rest: RestaurantState, citizen: Node, order: FoodOrder) -> void:
	rest.company().transact(&"dine_in_sales", order.price)
	rest.record_sale(order.price)
	record_category_sale(rest, order.dish_id)
	record_recipe_sale(rest, order)
	MarketingManager.attribute_sale(rest.building_id, order.citizen_id, order.price)
	DemandManager.charge_citizen(order.citizen_id, order.price)
	award_service_reputation(order)
	_award_charm_reputation(rest)
	order.state = FoodOrder.State.SERVED
	_notify_citizen(citizen, "on_meal_done")


## Shared reputation payout for a successfully served/delivered order,
## credited to the company that owns the restaurant.
func award_service_reputation(order: FoodOrder) -> void:
	var rest: RestaurantState = by_building.get(order.restaurant_id)
	if rest == null:
		return
	var base: float = float(EconomyManager.tuning_value("reputation.per_served", 0.01))
	var quality: float = quality_for(order.dish_id, order.tier)
	var bonus: float = (quality - 0.5) * float(EconomyManager.tuning_value("reputation.quality_bonus_scale", 0.02))
	bonus += (order.cook_consistency - 0.5) * float(EconomyManager.tuning_value("staff.effects.consistency_rep_scale", 0.02))
	add_company_reputation(rest, base + bonus)


## Charming waiters on shift leave a small extra impression on dine-in guests.
func _award_charm_reputation(rest: RestaurantState) -> void:
	var hourf: float = GameClock.game_hours
	var total: float = 0.0
	var count: int = 0
	for member: StaffMember in rest.staff:
		if not member.on_shift(hourf) or member.is_absent(GameClock.day):
			continue
		var def: StaffTypeDef = staff_types.get(member.type_id)
		if def == null or def.waiter_customers_per_hour <= 0.0:
			continue
		total += member.competency(&"charm") * member.operational_effect(&"service")
		count += 1
	if count == 0:
		return
	var scale: float = float(EconomyManager.tuning_value("staff.effects.charm_rep_scale", 0.015))
	add_company_reputation(rest, (total / float(count) - 0.5) * scale)


## Track which cuisine categories sell (customer-profile UI).
func record_category_sale(rest: RestaurantState, dish_id: StringName) -> void:
	var cat: StringName = category_for(dish_id)
	if cat == &"":
		return
	var by_cat: Dictionary = rest.today.get("by_category", {})
	by_cat[cat] = int(by_cat.get(cat, 0)) + 1
	rest.today["by_category"] = by_cat


## Per-recipe sales stats for the Performance tab (recipe orders only).
func record_recipe_sale(rest: RestaurantState, order: FoodOrder) -> void:
	if order.recipe_id == &"":
		return
	rest.record_recipe_sale(order.recipe_id, order.recipe_version, order.price,
		order.ingredient_cost, DemandManager.demographic_of(order.citizen_id))


func _cook_slot_descriptors(rest: RestaurantState, hourf: float) -> Array[Dictionary]:
	var prep_span: float = float(EconomyManager.tuning_value("staff.effects.prep_span", 0.5))
	var slots: Array[Dictionary] = []
	for member: StaffMember in rest.staff:
		if not member.on_shift(hourf) or member.is_absent(GameClock.day):
			continue
		var def: StaffTypeDef = staff_types.get(member.type_id)
		if def == null or def.cook_slots <= 0:
			continue
		for slot_index: int in def.cook_slots:
			slots.append({
				"cook_uid": member.uid,
				"cook_name": member.staff_name,
				"slot_index": slot_index,
				"speed_mult": (1.0 + (member.competency(&"speed") - 0.5) * prep_span) * member.operational_effect(&"speed"),
				"consistency": clampf(member.competency(&"consistency") * member.operational_effect(&"consistency"), 0.0, 1.0),
			})
	# Physical kitchen stations (ovens) cap concurrent cooking: a cook with
	# two slots still needs two ovens to use them.
	if slots.size() > rest.cook_station_cap:
		slots.resize(rest.cook_station_cap)
	return slots


func operations_snapshot(building_id: int) -> Dictionary:
	var rest: RestaurantState = by_building.get(building_id)
	if rest == null:
		return {}
	var now: int = GameClock.total_minutes()
	var hourf: float = GameClock.game_hours
	var cooking_rows: Array[Dictionary] = []
	for job: Dictionary in rest.cooking:
		var order: FoodOrder = job.get("order")
		if order == null:
			continue
		cooking_rows.append({
			"order_id": order.order_id,
			"dish": String(order.dish_id).replace("_", " ").capitalize(),
			"cook_name": String(job.get("cook_name", "Waiting for a cook")),
			"minutes_left": maxf(0.0, float(job.get("minutes_left", 0.0))),
			"delivery": order.is_delivery,
		})
	var queue_rows: Array[Dictionary] = []
	var oldest_queue_wait: int = 0
	for waiting: Dictionary in rest.dine_queue:
		var citizen: Node = waiting.get("citizen")
		var waited: int = maxi(0, now - int(waiting.get("arrived_minute", now)))
		oldest_queue_wait = maxi(oldest_queue_wait, waited)
		var citizen_data: Variant = citizen.get("data") if is_instance_valid(citizen) else {}
		queue_rows.append({
			"name": citizen_data.get("name", "Citizen") if citizen_data is Dictionary else "Citizen",
			"dish": String(waiting.get("dish_id", &"")).replace("_", " ").capitalize(),
			"wait_minutes": waited,
		})
	var oldest_kitchen_wait: int = 0
	for queued_order: FoodOrder in rest.cook_backlog:
		oldest_kitchen_wait = maxi(oldest_kitchen_wait, now - queued_order.placed_minute)
	var ready_count: int = 0
	var oldest_ready_wait: int = 0
	for ready_order: FoodOrder in DeliveryManager.ready_queue:
		if ready_order.restaurant_id != building_id:
			continue
		ready_count += 1
		oldest_ready_wait = maxi(oldest_ready_wait, now - ready_order.placed_minute)
	var driver_rows: Array[Dictionary] = []
	var idle_drivers: int = 0
	for driver_slot: Dictionary in DeliveryManager.rosters.get(building_id, []):
		var member: StaffMember = driver_slot.get("member")
		var driver: Node = driver_slot.get("node")
		if member == null:
			continue
		var idle: bool = is_instance_valid(driver) and driver.has_method("is_idle") and driver.is_idle()
		if idle and member.on_shift(hourf):
			idle_drivers += 1
		driver_rows.append({
			"name": member.staff_name,
			"on_shift": member.on_shift(hourf),
			"idle": idle,
			"status": String(driver.get("goal_desc")) if is_instance_valid(driver) else "unavailable",
		})
	var snapshot: Dictionary = {
		"building_id": building_id,
		"restaurant_name": rest.restaurant_name,
		"open": rest.is_open(hourf),
		"tables_occupied": rest.tables_occupied,
		"table_count": rest.table_count,
		"dine_queue": queue_rows,
		"oldest_queue_wait": oldest_queue_wait,
		"cook_backlog": rest.cook_backlog.size(),
		"oldest_kitchen_wait": oldest_kitchen_wait,
		"cooking": cooking_rows,
		"cook_slots": _cook_slot_descriptors(rest, hourf).size(),
		"cook_station_cap": rest.cook_station_cap,
		"interior_revision": rest.interior_layout.revision if rest.interior_layout != null else 0,
		"cooks_on_shift": rest.staff_on_shift(&"cook", hourf),
		"waiters_on_shift": rest.staff_on_shift(&"waiter", hourf),
		"drivers_on_shift": rest.staff_on_shift(&"driver", hourf),
		"drivers": driver_rows,
		"idle_drivers": idle_drivers,
		"ready_deliveries": ready_count,
		"oldest_ready_wait": oldest_ready_wait,
		"active_deliveries": rest.active_deliveries,
		"delivery_cap": rest.delivery_cap,
		"inbound_citizens": DemandManager.restaurant_intents_for(building_id),
	}
	snapshot["bottleneck"] = _bottleneck_for(rest, snapshot)
	return snapshot


func _bottleneck_for(rest: RestaurantState, snapshot: Dictionary) -> Dictionary:
	var queue_limit: int = int(EconomyManager.tuning_value("dinein.queue_leave_minutes", 25))
	var food_limit: int = int(EconomyManager.tuning_value("dinein.food_wait_minutes", 60))
	var delivery_limit: int = int(EconomyManager.tuning_value("delivery.cancel_minutes", 75))
	if not bool(snapshot["open"]):
		return {"severity": "info", "title": "Closed for now", "evidence": "Service resumes at %.0f:00." % rest.open_hour, "action": "Review opening hours", "screen": &"deliveries"}
	if int(snapshot["cooks_on_shift"]) <= 0:
		return {"severity": "critical", "title": "No cook on shift", "evidence": "Orders cannot enter the kitchen.", "action": "Schedule or hire a cook", "screen": &"staff"}
	if rest.dine_in_enabled and int(snapshot["waiters_on_shift"]) <= 0:
		return {"severity": "critical", "title": "No waiter on shift", "evidence": "Guests cannot be seated or served.", "action": "Schedule or hire a waiter", "screen": &"staff"}
	var stockout_risks: Array[StringName] = SupplyManager.stockout_risks(rest)
	if not stockout_risks.is_empty():
		var inv: InventoryState = SupplyManager.inventory_for_restaurant(rest)
		var worst: StringName = stockout_risks[0]
		var empty_now: bool = false
		for risk: StringName in stockout_risks:
			if inv.available(risk) <= 0.0:
				worst = risk
				empty_now = true
				break
		var ing_def: IngredientDef = RecipeManager.ingredient(worst)
		var worst_name: String = ing_def.display_name if ing_def != null else String(worst)
		var evidence: String = "%s is out of stock." % worst_name if empty_now else \
			"%s holds under a day of stock." % worst_name
		if stockout_risks.size() > 1:
			evidence += " %d ingredients at risk." % stockout_risks.size()
		return {"severity": "critical" if empty_now else "warning", "title": "Ingredients running out", "evidence": evidence, "action": "Order stock", "screen": &"suppliers"}
	if int(snapshot["oldest_queue_wait"]) >= int(float(queue_limit) * 0.75):
		return {"severity": "critical", "title": "Guests may leave", "evidence": "Oldest table wait: %d of %d min." % [snapshot["oldest_queue_wait"], queue_limit], "action": "Add waiter coverage or another location", "screen": &"staff"}
	if int(snapshot["oldest_kitchen_wait"]) >= int(float(food_limit) * 0.75):
		return {"severity": "critical", "title": "Kitchen is falling behind", "evidence": "Oldest food order: %d of %d min." % [snapshot["oldest_kitchen_wait"], food_limit], "action": "Add cook coverage", "screen": &"staff"}
	if int(snapshot["ready_deliveries"]) > 0 and int(snapshot["idle_drivers"]) <= 0:
		var severity: String = "critical" if int(snapshot["oldest_ready_wait"]) >= int(float(delivery_limit) * 0.75) else "warning"
		return {"severity": severity, "title": "Food is waiting for a driver", "evidence": "%d ready; oldest order is %d min." % [snapshot["ready_deliveries"], snapshot["oldest_ready_wait"]], "action": "Add driver coverage", "screen": &"staff"}
	if int(snapshot["cook_backlog"]) > 0 and int(snapshot["cooking"].size()) >= maxi(1, int(snapshot["cook_slots"])):
		return {"severity": "warning", "title": "Kitchen at capacity", "evidence": "%d orders queued behind %d active dishes." % [snapshot["cook_backlog"], snapshot["cooking"].size()], "action": "Schedule another cook", "screen": &"staff"}
	if int(snapshot["dine_queue"].size()) > 0 and int(snapshot["tables_occupied"]) >= int(snapshot["table_count"]):
		return {"severity": "warning", "title": "Every table is occupied", "evidence": "%d guests are waiting." % snapshot["dine_queue"].size(), "action": "Open another location", "screen": &"build"}
	if rest.delivery_enabled and int(snapshot["active_deliveries"]) >= int(snapshot["delivery_cap"]):
		return {"severity": "warning", "title": "Delivery cap reached", "evidence": "%d of %d deliveries active." % [snapshot["active_deliveries"], snapshot["delivery_cap"]], "action": "Review delivery capacity", "screen": &"deliveries"}
	return {"severity": "good", "title": "Flow is healthy", "evidence": "No service bottleneck detected.", "action": "", "screen": &""}


# --- Daily rollover ----------------------------------------------------------


func _on_day_changed(day: int) -> void:
	for rest: RestaurantState in all_restaurants():
		rest.sales_history.append(float(rest.today.get("sales", 0.0)))
		if rest.sales_history.size() > 14:
			rest.sales_history.remove_at(0)
		rest.expense_history.append(float(rest.today.get("expenses", 0.0)))
		if rest.expense_history.size() > 14:
			rest.expense_history.remove_at(0)
		_decay_interior(rest)
		rest.reset_today()
		restaurant_updated.emit(rest.building_id)
	_refresh_job_market(day)


## Nightly wear pass: yesterday's traffic grinds down furniture and dirties
## the room; the closed hours (and sinks) claw cleanliness back. Derived
## caches refresh afterwards so appeal reflects the new condition.
func _decay_interior(rest: RestaurantState) -> void:
	var layout: InteriorLayoutState = rest.interior_layout
	if layout == null or interior == null:
		return
	var guests: float = float(rest.today.get("guests", 0))
	var orders: float = float(rest.today.get("orders", 0))
	var seats: float = maxf(1.0, float(rest.table_count))
	var stations: float = maxf(1.0, float(rest.cook_station_cap))
	var clean_bonus: float = 0.35  # Overnight scrub-down.
	var dirt: float = clampf((guests + orders) * 0.004, 0.0, 0.5)
	for item: PlacedFurnitureState in layout.placed:
		var def: FurnitureDef = interior.def_for(item.def_id)
		if def == null:
			continue
		if def.cleanliness_impact > 0.0:
			clean_bonus += def.cleanliness_impact * 0.1
	for item: PlacedFurnitureState in layout.placed:
		var def: FurnitureDef = interior.def_for(item.def_id)
		if def == null or not item.enabled:
			continue
		var uses: float = 0.0
		if def.is_table or def.seats > 0:
			uses = guests / seats
		elif def.cook_slots > 0:
			uses = orders / stations
		elif def.pickup_slots > 0 or def.throughput > 0.0:
			uses = orders / maxf(1.0, stations)
		if uses > 0.0:
			item.durability = clampf(item.durability - def.wear_per_use * uses, 5.0, def.durability_max)
		item.cleanliness = clampf(item.cleanliness - dirt + clean_bonus - maxf(0.0, -def.cleanliness_impact) * 0.05, 0.05, 1.0)
	# Manager policy: auto-repair anything below the owner's threshold.
	if rest.repair_policy == &"auto":
		var worn: Array[int] = []
		for item: PlacedFurnitureState in layout.placed:
			if item.condition() < rest.repair_threshold:
				worn.append(item.instance_id)
		if not worn.is_empty():
			var repair: CommandResult = CommandResult.fail(&"router_unavailable", "Command router is unavailable.")
			var command_router: Node = get_node_or_null("/root/BranchCommandRouter")
			if command_router != null:
				repair = command_router.call(
					"execute",
					&"furniture.repair",
					{"building_id": rest.building_id, "instance_ids": worn},
					{"kind": &"manager", "id": "legacy_repair_policy", "company_id": rest.company_id},
					"legacy-repair:%s:%d:%d" % [rest.company_id, rest.building_id, GameClock.day]) as CommandResult
			if repair.ok:
				EconomyManager.post_message("info", "%s: manager repaired %d worn items ($%.0f)." % [rest.restaurant_name, int(repair.payload["count"]), float(repair.payload["cost"])])
	var ev: InteriorEvaluation = interior.evaluate(layout)
	interior.apply_to_restaurant(rest, ev)


## Repairs (and cleans) the given placed items back to factory condition.
func repair_furniture_cmd(company_id: StringName, building_id: int, instance_ids: Array[int]) -> CommandResult:
	var check: CommandResult = _owned_branch(company_id, building_id)
	if not check.ok:
		return check
	var rest: RestaurantState = check.payload
	var company: CompanyState = CompanyManager.company(company_id)
	var cost: float = 0.0
	var targets: Array[PlacedFurnitureState] = []
	for id: int in instance_ids:
		var item: PlacedFurnitureState = rest.interior_layout.find(id)
		if item == null:
			continue
		var def: FurnitureDef = interior.def_for(item.def_id)
		if def == null:
			continue
		var damage: float = 1.0 - item.durability / def.durability_max
		if damage > 0.01 or item.cleanliness < 0.95:
			cost += def.price * 0.3 * damage + 5.0
			targets.append(item)
	if targets.is_empty():
		return CommandResult.fail(&"nothing_to_repair", "Everything is already in good shape.")
	if not company.can_afford(cost):
		return CommandResult.fail(&"insufficient_cash", "Repairs cost $%.0f." % cost)
	company.transact(&"maintenance", -cost)
	rest.today["expenses"] = float(rest.today.get("expenses", 0.0)) + cost
	for item: PlacedFurnitureState in targets:
		var def: FurnitureDef = interior.def_for(item.def_id)
		item.durability = def.durability_max
		item.cleanliness = 1.0
	var ev: InteriorEvaluation = interior.evaluate(rest.interior_layout)
	interior.apply_to_restaurant(rest, ev)
	restaurant_updated.emit(building_id)
	return CommandResult.good({"cost": cost, "count": targets.size()})


## Registered with EconomyManager.daily_cost_providers; CompanyManager calls
## it once per company on day rollover.
func _charge_daily_costs(company: CompanyState, _day: int) -> void:
	var rents: Dictionary = EconomyManager.tuning_value("rent.daily_by_district", {})
	for rest: RestaurantState in company.restaurants:
		var wages: float = 0.0
		for member: StaffMember in rest.staff:
			wages += member.daily_pay()
		if wages > 0.0:
			company.transact(&"wages", -wages)
		var rent: float = 0.0
		if not rest.owned_outright:
			rent = float(rents.get(rest.district, 120.0))
			company.transact(&"rent", -rent)
		# Mise en place: every enabled dish costs daily prep + stocked
		# ingredients, so an unsold dish is a real loss on the ledger.
		var upkeep: float = menu_upkeep_for(rest)
		if upkeep > 0.0:
			company.transact(&"menu_upkeep", -upkeep)
		# Interior running costs: per-item maintenance plus the music service.
		var interior_cost: float = 0.0
		if rest.interior_layout != null and interior != null:
			for item: PlacedFurnitureState in rest.interior_layout.placed:
				var fdef: FurnitureDef = interior.def_for(item.def_id)
				if fdef != null and item.enabled:
					interior_cost += fdef.maintenance_cost
			var music: InteriorFinishDef = interior.finish_for(rest.interior_layout.music)
			if music != null:
				interior_cost += music.daily_cost
		if interior_cost > 0.0:
			company.transact(&"maintenance", -interior_cost)
		rest.today["expenses"] = float(rest.today.get("expenses", 0.0)) + wages + rent + upkeep + interior_cost


# --- Setup -------------------------------------------------------------------


func _load_catalogs() -> void:
	for res: Resource in _load_dir(DISH_DIR):
		if res is DishDef:
			dishes[res.id] = res
	for res: Resource in _load_dir(STAFF_TYPE_DIR):
		if res is StaffTypeDef:
			staff_types[res.id] = res
	print("RestaurantManager: %d dishes, %d staff types" % [dishes.size(), staff_types.size()])


func _load_dir(dir_path: String) -> Array[Resource]:
	var result: Array[Resource] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_warning("RestaurantManager: missing catalog dir %s" % dir_path)
		return result
	for file: String in dir.get_files():
		if file.ends_with(".tres") or file.ends_with(".res"):
			var res: Resource = load(dir_path.path_join(file))
			if res != null:
				result.append(res)
	return result


func _restore_from_save(save: SaveGame) -> void:
	for company: CompanyState in CompanyManager.companies:
		for rest: RestaurantState in company.restaurants.duplicate():
			var info: Dictionary = CityData.get_building(rest.building_id)
			if info.is_empty():
				push_warning("Save references missing building %d; skipping" % rest.building_id)
				company.restaurants.erase(rest)
				continue
			rest.door_pos = info.get("door_pos", Vector3.ZERO)
			rest.curb_pos = info.get("position", Vector3.ZERO)
			rest.reset_today()
			_ensure_interior(rest)
			by_building[rest.building_id] = rest
			_spawn_marker(rest)
			for member: StaffMember in rest.staff:
				_next_staff_uid = maxi(_next_staff_uid, member.uid + 1)
				var def: StaffTypeDef = staff_types.get(member.type_id)
				if def != null and def.is_driver:
					DeliveryManager.on_driver_hired(rest, member)
			restaurant_purchased.emit(rest)
	job_market = save.job_market.duplicate()
	for cand: JobCandidate in job_market:
		_next_candidate_uid = maxi(_next_candidate_uid, cand.uid + 1)
	_next_candidate_uid = maxi(_next_candidate_uid, save.next_candidate_uid)
	DemandManager.pending_wealth = save.citizen_wealth.duplicate()
	# The recipe book was loaded before our book_changed hookup — backfill
	# menu rows for any recipes the save's branches have never seen.
	_sync_recipe_menu_entries()
	EconomyManager.post_message("good", "Save loaded — welcome back, boss!")


func _found_starting_restaurant() -> void:
	var best_id: int = -1
	var best_score: float = INF
	var center: Vector3 = _city_center()
	for id: int in CityData.buildings:
		var info: Dictionary = CityData.get_building(id)
		if String(info.get("type", "")) != "shop":
			continue
		if String(info.get("district", "")) not in ["N", "C"]:
			continue
		var dist: float = Vector3(info.get("position", Vector3.ZERO)).distance_to(center)
		if dist < best_score:
			best_score = dist
			best_id = id
	if best_id < 0:
		push_warning("RestaurantManager: no shop building found for the starting restaurant")
		return
	var rest: RestaurantState = _add_restaurant(best_id, "%s — Home Base" % EconomyManager.company_name, 0.0, price_for(best_id))
	# The first location opens staffed for lunch AND the dinner rush
	# (evening leisure is when most citizens dine out).
	_hire_generated(rest, &"cook", 10.0)
	_hire_generated(rest, &"waiter", 10.0)
	_hire_generated(rest, &"cook", 14.0)
	_hire_generated(rest, &"waiter", 14.0)
	EconomyManager.post_message("good", "Welcome! %s opened its first restaurant." % EconomyManager.company_name)


func _add_restaurant(building_id: int, restaurant_name: String, fee: float, value: float, company_id: StringName = &"player") -> RestaurantState:
	var company: CompanyState = CompanyManager.company(company_id)
	var info: Dictionary = CityData.get_building(building_id)
	var rest: RestaurantState = RestaurantState.new()
	rest.building_id = building_id
	rest.company_id = company_id
	rest.district = String(info.get("district", "N"))
	rest.restaurant_name = restaurant_name if restaurant_name != "" else "Restaurant %d" % building_id
	rest.purchase_price = fee
	rest.property_value = value
	rest.door_pos = info.get("door_pos", Vector3.ZERO)
	rest.curb_pos = info.get("position", Vector3.ZERO)
	rest.table_count = _table_count_for(info)
	rest.star_rating = company.reputation
	rest.menu_slots = int(EconomyManager.tuning_value("menu.base_slots", 4))
	rest.reset_today()
	var enabled_count: int = 0
	# Rivals cook from the shared starter catalog; only the player's branches
	# see the player's custom recipe book.
	var recipe_pool: Array[RecipeDef] = RecipeManager.live_recipes() if company.is_player else RecipeManager.rival_recipe_pool()
	for rec: RecipeDef in recipe_pool:
		var rentry: MenuEntry = MenuEntry.new()
		rentry.dish_id = rec.id
		rentry.tier = &"med"
		rentry.price = RecipeManager.suggested_price_for(rec)
		rentry.enabled = RecipeManager.book.base_menu_ids.has(rec.id) and enabled_count < rest.menu_slots
		if rentry.enabled:
			enabled_count += 1
		rest.menu.append(rentry)
	for dish_id: StringName in dishes:
		var def: DishDef = dishes[dish_id]
		var entry: MenuEntry = MenuEntry.new()
		entry.dish_id = dish_id
		entry.tier = &"med"
		entry.price = def.suggested_price
		entry.enabled = def.category == &"pizza" and enabled_count < rest.menu_slots
		if entry.enabled:
			enabled_count += 1
		rest.menu.append(entry)
	company.restaurants.append(rest)
	_ensure_interior(rest)
	by_building[building_id] = rest
	_spawn_marker(rest)
	restaurant_purchased.emit(rest)
	return rest


## Guarantees a furniture layout exists (legacy saves have none) and refreshes
## the capacity/appeal caches derived from it.
func _ensure_interior(rest: RestaurantState) -> void:
	if rest.interior_layout == null:
		rest.interior_layout = interior.default_layout_for(rest)
	else:
		# Content updates may retire furniture defs: scrap orphans for cash.
		var fixed: Dictionary = interior.reconcile_catalog(rest.interior_layout)
		if int(fixed["removed"]) > 0:
			rest.company().transact(&"furniture_resale", float(fixed["refund"]))
			push_warning("%s: %d discontinued furniture items scrapped for $%.0f" % [rest.restaurant_name, fixed["removed"], fixed["refund"]])
	var ev: InteriorEvaluation = interior.evaluate(rest.interior_layout)
	interior.apply_to_restaurant(rest, ev)


func _spawn_marker(rest: RestaurantState) -> void:
	if not is_inside_tree():
		return  # Headless harness — no world to decorate.
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var marker: RestaurantMarker = RestaurantMarker.new()
	marker.name = "RestaurantMarker_%d" % rest.building_id
	scene_root.add_child(marker)
	marker.setup(rest)


func _table_count_for(info: Dictionary) -> int:
	var body: Node3D = get_node_or_null(info.get("node_path", NodePath()))
	var area: float = 120.0
	if body != null and body.has_meta("size"):
		var size: Vector3 = body.get_meta("size")
		area = size.x * size.z
	var per_table: float = float(EconomyManager.tuning_value("purchase.table_area_per_table", 14.0))
	var lo: int = int(EconomyManager.tuning_value("purchase.min_tables", 4))
	var hi: int = int(EconomyManager.tuning_value("purchase.max_tables", 24))
	return clampi(int(area / per_table), lo, hi)


func _city_center() -> Vector3:
	var total: Vector3 = Vector3.ZERO
	var count: int = 0
	for id: int in CityData.buildings:
		total += Vector3(CityData.get_building(id).get("position", Vector3.ZERO))
		count += 1
	return total / float(maxi(count, 1))


func _random_person_name(rng: RandomNumberGenerator = null) -> String:
	var first: Array = PopulationManager.FIRST_NAMES
	var last: Array = PopulationManager.LAST_NAMES
	if rng == null:
		return "%s %s" % [first.pick_random(), last.pick_random()]
	return "%s %s" % [first[rng.randi() % first.size()], last[rng.randi() % last.size()]]


func _notify_citizen(citizen: Node, method: String) -> void:
	if is_instance_valid(citizen) and citizen.has_method(method):
		citizen.call(method)
