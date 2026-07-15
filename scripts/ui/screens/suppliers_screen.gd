extends TycoonScreen
## Suppliers & Inventory workspace (design D6): Overview · Inventory ·
## Suppliers · Purchase Orders · Warehouses · Policies. Everything routes
## through SupplyManager commands — the same layer the rival AI uses.

const INK: Color = Color("#3A2010")
const INK_SOFT: Color = Color("#6E4326")
const INK_MUTED: Color = Color("#9A7245")
const GREEN_BAR: Color = Color("#6FB63A")
const GOLD_BAR: Color = Color("#F5C518")
const RED_BAR: Color = Color("#EA4A2F")
const RED_TINT: Color = Color(0.918, 0.29, 0.184, 0.10)
const GOLD_DEEP: Color = Color("#B5810A")
const GREEN_DEEP: Color = Color("#356615")

var _tabs: TabContainer
var _overview_list: VBoxContainer
var _inventory_list: VBoxContainer
var _suppliers_list: VBoxContainer
var _orders_list: VBoxContainer
var _warehouses_list: VBoxContainer
var _policies_list: VBoxContainer
var _risk_pill: PanelContainer
var _risk_label: Label
## Warehouses tab drill-in: -1 = list, else the warehouse being inspected.
var _view_warehouse_id: int = -1


func screen_title() -> String:
	return "Suppliers & Inventory"


func screen_icon() -> StringName:
	return &"basket"


func _build() -> void:
	custom_minimum_size = Vector2(1100, 660)
	_build_risk_pill()
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_tabs)
	_overview_list = _make_tab_list("Overview")
	_inventory_list = _make_tab_list("Inventory")
	_suppliers_list = _make_tab_list("Suppliers")
	_orders_list = _make_tab_list("Purchase Orders")
	_warehouses_list = _make_tab_list("Warehouses")
	_policies_list = _make_tab_list("Policies")
	BellaUi.style_tabs(_tabs)
	# Connect AFTER all tabs exist — tab_changed fires on the first add.
	_tabs.tab_changed.connect(func(_tab: int) -> void: refresh())
	SupplyManager.inventory_changed.connect(_on_inventory_changed)
	SupplyManager.orders_changed.connect(refresh)
	SupplyManager.policies_changed.connect(refresh)
	SupplyManager.warehouses_changed.connect(refresh)


func refresh() -> void:
	if not is_inside_tree():
		return
	_refresh_risk_pill()
	match _tabs.current_tab:
		0:
			_refresh_overview()
		1:
			_refresh_inventory()
		2:
			_refresh_suppliers()
		3:
			_refresh_orders()
		4:
			_refresh_warehouses()
		5:
			_refresh_policies()


func _on_inventory_changed(owner_kind: StringName, owner_id: int) -> void:
	if owner_kind == &"restaurant" and owner_id == building_id:
		refresh()


# --- Header risk pill -----------------------------------------------------


func _build_risk_pill() -> void:
	var header: HBoxContainer = _content.get_child(0)
	_risk_pill = BellaUi.pill("", Color("#97230F"), Color(0.918, 0.29, 0.184, 0.18), RED_BAR)
	_risk_label = _risk_pill.get_child(0)
	header.add_child(_risk_pill)
	header.move_child(_risk_pill, header.get_child_count() - 2)


func _refresh_risk_pill() -> void:
	var rest: RestaurantState = restaurant()
	if rest == null:
		_risk_pill.visible = false
		return
	var risks: Array[StringName] = SupplyManager.stockout_risks(rest)
	_risk_pill.visible = not risks.is_empty()
	if risks.size() == 1:
		_risk_label.text = "1 stockout risk"
	else:
		_risk_label.text = "%d stockout risks" % risks.size()


# --- Overview tab -----------------------------------------------------------


func _refresh_overview() -> void:
	_clear(_overview_list)
	var rest: RestaurantState = restaurant()
	if rest == null:
		return
	var inv: InventoryState = SupplyManager.inventory_for_restaurant(rest)
	# Stat tiles: stock value, cover, waste, ingredients tracked.
	var value: float = 0.0
	for lot: StockLot in inv.lots:
		value += lot.qty * lot.unit_cost
	var min_cover: float = INF
	var tracked: int = 0
	for ing: StringName in _menu_ingredients(rest):
		tracked += 1
		min_cover = minf(min_cover, SupplyManager.days_of_cover(rest, ing))
	var tiles: GridContainer = GridContainer.new()
	tiles.columns = 4
	tiles.add_theme_constant_override("h_separation", 8)
	_overview_list.add_child(tiles)
	_stat_tile(tiles, "Stock value", "$%s" % _thousands(int(value)), INK)
	var cover_text: String = "—" if tracked == 0 else (
		"%.1f d" % min_cover if min_cover < 99.0 else "99+ d")
	_stat_tile(tiles, "Days of cover", cover_text,
		RED_BAR if min_cover < 1.0 else (GOLD_DEEP if min_cover < 2.5 else GREEN_DEEP))
	_stat_tile(tiles, "Wasted (total)", "%.0f portions" % inv.total_wasted,
		RED_BAR if inv.total_wasted > 0.0 else INK)
	_stat_tile(tiles, "Ingredients", str(tracked), INK)
	# Active supplier disruptions (city-wide, affect everyone).
	var disruptions: Array[SupplyDisruption] = SupplyManager.active_disruptions()
	if not disruptions.is_empty():
		_heading(_overview_list, "Supplier alerts")
		for disruption: SupplyDisruption in disruptions:
			_overview_list.add_child(_disruption_row(disruption))
	# Forecast: demand- and campaign-aware days-of-cover warnings.
	_heading(_overview_list, "Forecast")
	var warnings: Array[Dictionary] = SupplyManager.forecast_warnings(rest)
	if warnings.is_empty():
		var ok_row: PanelContainer = PanelContainer.new()
		ok_row.add_theme_stylebox_override("panel", BellaUi.sunk_box())
		var ok_label: Label = Label.new()
		ok_label.text = "Stock levels look healthy for the days ahead."
		ok_label.add_theme_font_size_override("font_size", 13)
		ok_label.add_theme_color_override("font_color", GREEN_DEEP)
		ok_row.add_child(ok_label)
		_overview_list.add_child(ok_row)
	for warning: Dictionary in warnings:
		_overview_list.add_child(_forecast_row(rest, warning))


func _disruption_row(disruption: SupplyDisruption) -> Control:
	var card: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = BellaUi.tile_box(GOLD_DEEP, 3)
	box.bg_color = Color(0.96, 0.77, 0.09, 0.14)
	card.add_theme_stylebox_override("panel", box)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	card.add_child(row)
	var bell: TextureRect = UiAssets.icon_rect(&"bell", 20)
	if bell != null:
		row.add_child(bell)
	var supplier: SupplierDef = SupplyManager.supplier(disruption.supplier_id)
	var label: Label = Label.new()
	var kind_text: String = {
		&"outage": "is offline", &"price_spike": "prices are spiking",
		&"delay": "is running late",
	}.get(disruption.kind, "is disrupted")
	label.text = "%s %s" % [supplier.display_name if supplier != null else "A supplier", kind_text]
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", BellaUi.WOOD_EDGE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var ends: int = disruption.end_minute - GameClock.total_minutes()
	var ends_label: Label = Label.new()
	ends_label.text = "~%.0fd left" % maxf(float(ends) / 1440.0, 0.0)
	ends_label.add_theme_font_size_override("font_size", 11)
	ends_label.add_theme_color_override("font_color", INK_MUTED)
	row.add_child(ends_label)
	return card


func _forecast_row(rest: RestaurantState, warning: Dictionary) -> Control:
	var critical: bool = warning["severity"] == &"critical"
	var card: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = BellaUi.tile_box(RED_BAR if critical else GOLD_DEEP, 3 if critical else 2)
	card.add_theme_stylebox_override("panel", box)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	card.add_child(row)
	row.add_child(_swatch(warning["ingredient_id"]))
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_label: Label = Label.new()
	name_label.text = _ingredient_name(warning["ingredient_id"])
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", INK)
	text.add_child(name_label)
	var reason: Label = Label.new()
	reason.text = warning["reason"]
	reason.add_theme_font_size_override("font_size", 11)
	reason.add_theme_color_override("font_color", RED_BAR if critical else GOLD_DEEP)
	text.add_child(reason)
	var qty: float = _restock_qty(rest, warning["ingredient_id"])
	var reorder: Button = Button.new()
	reorder.text = "Reorder · $%.0f" % _restock_cost(warning["ingredient_id"], qty)
	reorder.add_theme_font_size_override("font_size", 12)
	TycoonTheme.apply_orange(reorder)
	reorder.pressed.connect(func() -> void: _do_restock(warning["ingredient_id"]))
	row.add_child(reorder)
	return card


# --- Inventory tab ------------------------------------------------------------


func _refresh_inventory() -> void:
	_clear(_inventory_list)
	var rest: RestaurantState = restaurant()
	if rest == null:
		return
	var inv: InventoryState = SupplyManager.inventory_for_restaurant(rest)
	var ids: Dictionary = {}
	for ing: StringName in _menu_ingredients(rest):
		ids[ing] = true
	for ing: StringName in inv.ingredient_ids():
		ids[ing] = true
	if ids.is_empty():
		_inventory_list.add_child(_empty_state(&"basket", "No stock yet",
			"Enable a recipe on the menu and starter stock arrives with it."))
		return
	_inventory_list.add_child(_table_header())
	var sorted_ids: Array = ids.keys()
	sorted_ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return SupplyManager.days_of_cover(rest, a) < SupplyManager.days_of_cover(rest, b))
	for ing: StringName in sorted_ids:
		_inventory_list.add_child(_inventory_row(rest, ing))


func _table_header() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for spec: Array in [["INGREDIENT", 2.0], ["QTY", 0.8], ["FRESHNESS", 1.4], ["DAYS LEFT", 0.8], ["ACTION", 1.0]]:
		var label: Label = Label.new()
		label.text = spec[0]
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", INK_MUTED)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = spec[1]
		row.add_child(label)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_child(row)
	return margin


func _inventory_row(rest: RestaurantState, ing: StringName) -> Control:
	var inv: InventoryState = SupplyManager.inventory_for_restaurant(rest)
	var cover: float = SupplyManager.days_of_cover(rest, ing)
	var available: float = inv.available(ing)
	var at_risk: bool = cover < 1.0
	var low: bool = cover < 2.5
	var card: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = BellaUi.tile_box(RED_BAR if at_risk else BellaUi.PAPER_EDGE, 3 if at_risk else 2)
	if at_risk:
		box.bg_color = Color(0.984, 0.937, 0.788).lerp(Color(RED_TINT.r, RED_TINT.g, RED_TINT.b), RED_TINT.a)
	card.add_theme_stylebox_override("panel", box)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	# Ingredient swatch + name.
	var name_box: HBoxContainer = HBoxContainer.new()
	name_box.add_theme_constant_override("separation", 8)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.size_flags_stretch_ratio = 2.0
	name_box.add_child(_swatch(ing))
	var name_label: Label = Label.new()
	name_label.text = _ingredient_name(ing)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", INK)
	name_box.add_child(name_label)
	row.add_child(name_box)
	# Quantity (reserved shown when present).
	var qty_label: Label = Label.new()
	var reserved: float = inv.reserved_qty(ing)
	qty_label.text = "%.0f" % available if reserved <= 0.0 else "%.0f (+%.0f held)" % [available, reserved]
	qty_label.add_theme_font_size_override("font_size", 13)
	qty_label.add_theme_color_override("font_color", RED_BAR if at_risk else INK_SOFT)
	qty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qty_label.size_flags_stretch_ratio = 0.8
	row.add_child(qty_label)
	# Freshness meter (quantity-weighted).
	var fresh: float = _avg_freshness(inv, ing)
	var meter_wrap: VBoxContainer = VBoxContainer.new()
	meter_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	meter_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter_wrap.size_flags_stretch_ratio = 1.4
	meter_wrap.add_child(_meter(fresh))
	row.add_child(meter_wrap)
	# Days left until first expiry.
	var days_label: Label = Label.new()
	var next_expiry: int = inv.next_expiry(ing)
	if next_expiry <= 0 or available <= 0.0:
		days_label.text = "—"
		days_label.add_theme_color_override("font_color", INK_MUTED)
	else:
		var minutes_left: int = next_expiry - GameClock.total_minutes()
		var days_left: float = float(minutes_left) / 1440.0
		days_label.text = "<1 day" if days_left < 1.0 else "%.0f days" % days_left
		days_label.add_theme_color_override("font_color",
			RED_BAR if days_left < 1.0 else (GOLD_DEEP if days_left < 2.5 else GREEN_DEEP))
	days_label.add_theme_font_size_override("font_size", 13)
	days_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	days_label.size_flags_stretch_ratio = 0.8
	row.add_child(days_label)
	# Action.
	var action_wrap: HBoxContainer = HBoxContainer.new()
	action_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_wrap.size_flags_stretch_ratio = 1.0
	if at_risk or low:
		var qty: float = _restock_qty(rest, ing)
		var cost: float = _restock_cost(ing, qty)
		var reorder: Button = Button.new()
		reorder.text = "Reorder · $%.0f" % cost
		reorder.add_theme_font_size_override("font_size", 12)
		TycoonTheme.apply_orange(reorder)
		reorder.pressed.connect(func() -> void: _do_restock(ing))
		action_wrap.add_child(reorder)
	else:
		var ok_label: Label = Label.new()
		ok_label.text = "OK"
		ok_label.add_theme_font_size_override("font_size", 12)
		ok_label.add_theme_color_override("font_color", INK_MUTED)
		action_wrap.add_child(ok_label)
	row.add_child(action_wrap)
	return card


func _do_restock(ing: StringName) -> void:
	var rest: RestaurantState = restaurant()
	if rest == null:
		return
	var qty: float = _restock_qty(rest, ing)
	var result: CommandResult = SupplyManager.manual_restock_cmd(&"player", building_id, ing, qty)
	if not result.ok:
		EconomyManager.post_message("alert", result.message)
	refresh()


func _restock_qty(rest: RestaurantState, ing: StringName) -> float:
	var inv: InventoryState = SupplyManager.inventory_for_restaurant(rest)
	var policy: ReorderPolicy = inv.policy_for(ing)
	var target: float = policy.target_stock if policy != null else \
		ceilf(SupplyManager.estimated_daily_use(rest, ing) * 4.0)
	return maxf(target - inv.available(ing), ceilf(SupplyManager.estimated_daily_use(rest, ing)))


func _restock_cost(ing: StringName, qty: float) -> float:
	var ing_def: IngredientDef = RecipeManager.ingredient(ing)
	if ing_def == null:
		return 0.0
	var supplier: SupplierDef = SupplyManager.cheapest_supplier_for(ing)
	var mult: float = supplier.price_mult if supplier != null else 1.0
	var fee: float = supplier.delivery_fee if supplier != null else 20.0
	return ing_def.unit_cost * mult * qty + fee


# --- Suppliers tab -------------------------------------------------------------


func _refresh_suppliers() -> void:
	_clear(_suppliers_list)
	_heading(_suppliers_list, "City suppliers — compare price, quality and reliability")
	var defs: Array = SupplyManager.supplier_defs.values()
	defs.sort_custom(func(a: SupplierDef, b: SupplierDef) -> bool:
		return a.price_mult < b.price_mult)
	for def: SupplierDef in defs:
		_suppliers_list.add_child(_supplier_card(def))


func _supplier_card(def: SupplierDef) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.tile_box())
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	card.add_child(body)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 9)
	body.add_child(top)
	var icon: TextureRect = UiAssets.icon_rect(StringName(def.icon), 30)
	if icon != null:
		top.add_child(icon)
	var names: VBoxContainer = VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	var name_label: Label = Label.new()
	name_label.text = def.display_name
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", INK)
	names.add_child(name_label)
	var blurb: Label = Label.new()
	blurb.text = def.blurb
	blurb.add_theme_font_size_override("font_size", 11)
	blurb.add_theme_color_override("font_color", INK_MUTED)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(blurb)
	top.add_child(TycoonTheme.star_row(def.reliability * 5.0, 14))
	# Stat strip.
	var stats: HBoxContainer = HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	body.add_child(stats)
	var lead_days: float = float(def.lead_time_minutes) / 1440.0
	var lead_text: String = "%.0f h" % (float(def.lead_time_minutes) / 60.0) if lead_days < 1.0 else "%.0f d" % lead_days
	_mini_stat(stats, "Price", "×%.2f" % def.price_mult,
		GREEN_DEEP if def.price_mult < 1.0 else (INK if def.price_mult < 1.25 else RED_BAR))
	_mini_stat(stats, "Quality", "%d/100" % int(def.base_quality * 100.0),
		GREEN_DEEP if def.base_quality >= 0.75 else INK)
	_mini_stat(stats, "Reliability", "%d%%" % int(def.reliability * 100.0),
		GREEN_DEEP if def.reliability >= 0.9 else (INK if def.reliability >= 0.8 else RED_BAR))
	_mini_stat(stats, "Lead time", lead_text, INK)
	_mini_stat(stats, "Delivery fee", "$%.0f" % def.delivery_fee, INK)
	_mini_stat(stats, "Min order", "$%.0f" % def.min_order_value if def.min_order_value > 0.0 else "None", INK)
	_mini_stat(stats, "Carries", "%d items" % _coverage_count(def), INK)
	# Contract row: sign for a standing discount, or show the active badge.
	var contract: SupplierContractState = SupplyManager.contract_with(&"player", def.id)
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	body.add_child(footer)
	if SupplyManager._has_active_disruption(def.id):
		footer.add_child(BellaUi.pill("DISRUPTED", Color("#97230F"),
			Color(0.918, 0.29, 0.184, 0.14), RED_BAR))
	if contract != null and contract.signed:
		footer.add_child(BellaUi.pill("CONTRACT · %d%% OFF" % int((1.0 - contract.discount_mult) * 100.0),
			GREEN_DEEP, Color(0.44, 0.71, 0.23, 0.16), BellaUi.GREEN_EDGE))
		var history: Label = Label.new()
		history.text = "  %d deliveries · %d%% on time" % [contract.deliveries_total, int(contract.on_time_rate() * 100.0)]
		history.add_theme_font_size_override("font_size", 11)
		history.add_theme_color_override("font_color", INK_MUTED)
		footer.add_child(history)
	else:
		var spacer: Control = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(spacer)
		var sign: Button = Button.new()
		sign.text = "Sign contract"
		sign.add_theme_font_size_override("font_size", 12)
		sign.pressed.connect(func() -> void:
			var result: CommandResult = SupplyManager.sign_contract_cmd(&"player", def.id)
			if not result.ok:
				EconomyManager.post_message("alert", result.message)
			else:
				EconomyManager.post_message("good", "Signed a supply contract with %s." % def.display_name)
			refresh())
		footer.add_child(sign)
	return card


func _coverage_count(def: SupplierDef) -> int:
	var count: int = 0
	for ing_id: StringName in SupplyManager.item_defs.keys():
		var ing_def: IngredientDef = RecipeManager.ingredient(ing_id)
		var category: StringName = ing_def.category if ing_def != null else &"veg"
		if def.carries(ing_id, category):
			count += 1
	return count


# --- Purchase Orders tab --------------------------------------------------------


func _refresh_orders() -> void:
	_clear(_orders_list)
	var orders: Array[PurchaseOrder] = SupplyManager.open_orders(&"player")
	if orders.is_empty():
		_orders_list.add_child(_empty_state(&"receipt", "No purchase orders yet",
			"Hit Reorder on a low ingredient, or let automatic restocking draft orders overnight."))
		return
	_heading(_orders_list, "Purchase orders — newest first")
	for po: PurchaseOrder in orders:
		_orders_list.add_child(_po_card(po))


func _po_card(po: PurchaseOrder) -> Control:
	var failed: bool = po.status == &"failed"
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		BellaUi.tile_box(RED_BAR if failed else BellaUi.PAPER_EDGE, 3 if failed else 2))
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	card.add_child(body)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 9)
	body.add_child(top)
	top.add_child(_status_pill(po.status))
	var supplier: SupplierDef = SupplyManager.supplier(po.supplier_id)
	var name_label: Label = Label.new()
	name_label.text = supplier.display_name if supplier != null else String(po.supplier_id)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", INK)
	top.add_child(name_label)
	var dest_label: Label = Label.new()
	var rest: RestaurantState = RestaurantManager.by_building.get(po.dest_id)
	dest_label.text = "→ %s" % (rest.restaurant_name if rest != null else "?")
	dest_label.add_theme_font_size_override("font_size", 12)
	dest_label.add_theme_color_override("font_color", INK_MUTED)
	dest_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(dest_label)
	var total_label: Label = Label.new()
	total_label.text = "$%s" % _thousands(int(po.total_cost()))
	total_label.add_theme_font_size_override("font_size", 15)
	total_label.add_theme_color_override("font_color", INK)
	top.add_child(total_label)
	# Lines + timing.
	var detail: HBoxContainer = HBoxContainer.new()
	detail.add_theme_constant_override("separation", 9)
	body.add_child(detail)
	var lines_label: Label = Label.new()
	var parts: Array[String] = []
	for line: Dictionary in po.lines:
		parts.append("%s ×%.0f" % [_ingredient_name(line["ingredient_id"]), float(line["qty"])])
	lines_label.text = " · ".join(parts)
	lines_label.add_theme_font_size_override("font_size", 12)
	lines_label.add_theme_color_override("font_color", INK_SOFT)
	lines_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_child(lines_label)
	var when_label: Label = Label.new()
	when_label.text = _po_timing(po)
	when_label.add_theme_font_size_override("font_size", 12)
	when_label.add_theme_color_override("font_color", RED_BAR if failed else INK_MUTED)
	detail.add_child(when_label)
	# Actions.
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 7)
	actions.alignment = BoxContainer.ALIGNMENT_END
	if po.status == &"draft" or failed:
		var place: Button = Button.new()
		place.text = "Try again · $%s" % _thousands(int(po.total_cost())) if failed else \
			"Place order · $%s" % _thousands(int(po.total_cost()))
		place.add_theme_font_size_override("font_size", 12)
		TycoonTheme.apply_orange(place)
		place.pressed.connect(func() -> void:
			var result: CommandResult = SupplyManager.place_draft_cmd(&"player", po.id)
			if not result.ok:
				EconomyManager.post_message("alert", result.message)
			refresh())
		actions.add_child(place)
	if po.status != &"delivered" and po.status != &"cancelled":
		var cancel: Button = Button.new()
		cancel.text = "Cancel"
		cancel.add_theme_font_size_override("font_size", 12)
		cancel.pressed.connect(func() -> void:
			SupplyManager.cancel_purchase_order_cmd(&"player", po.id)
			refresh())
		actions.add_child(cancel)
	if actions.get_child_count() > 0:
		body.add_child(actions)
	if failed and po.failure_reason != "":
		var reason: Label = Label.new()
		reason.text = "%s Your order details were kept." % po.failure_reason
		reason.add_theme_font_size_override("font_size", 11)
		reason.add_theme_color_override("font_color", RED_BAR)
		body.add_child(reason)
	return card


func _status_pill(status: StringName) -> Control:
	match status:
		&"draft":
			return BellaUi.pill("DRAFT", INK_SOFT, BellaUi.PAPER_SUNK, BellaUi.PAPER_EDGE)
		&"confirmed":
			return BellaUi.pill("CONFIRMED", GOLD_DEEP, Color(0.96, 0.77, 0.09, 0.16), BellaUi.GOLD_EDGE)
		&"in_transit":
			return BellaUi.pill("ON THE WAY", GOLD_DEEP, Color(0.96, 0.77, 0.09, 0.16), BellaUi.GOLD_EDGE)
		&"delivered":
			return BellaUi.pill("DELIVERED", GREEN_DEEP, Color(0.44, 0.71, 0.23, 0.16), BellaUi.GREEN_EDGE)
		&"failed":
			return BellaUi.pill("FAILED", Color("#97230F"), Color(0.918, 0.29, 0.184, 0.14), RED_BAR)
		&"cancelled":
			return BellaUi.pill("CANCELLED", INK_MUTED, BellaUi.PAPER_SUNK, BellaUi.PAPER_EDGE)
	return BellaUi.pill(String(status).to_upper(), INK_SOFT, BellaUi.PAPER_SUNK, BellaUi.PAPER_EDGE)


func _po_timing(po: PurchaseOrder) -> String:
	var now: int = GameClock.total_minutes()
	match po.status:
		&"confirmed", &"in_transit":
			var minutes: int = po.eta_minute - now
			if minutes <= 0:
				return "Arriving now"
			if minutes < 1440:
				return "ETA %dh %02dm" % [minutes / 60, minutes % 60]
			return "ETA %.1f days" % (float(minutes) / 1440.0)
		&"delivered":
			return "Arrived"
		&"draft":
			return "Not placed yet"
		&"cancelled":
			return "Cancelled"
	return ""


# --- Warehouses tab --------------------------------------------------------------


func _refresh_warehouses() -> void:
	_clear(_warehouses_list)
	var locked_hint: String = CapabilityRegistry.explain(&"player", &"supply.warehouses")
	if locked_hint != "":
		_view_warehouse_id = -1
		_warehouses_list.add_child(_locked_state("Warehouses locked", locked_hint))
		return
	if _view_warehouse_id >= 0 and SupplyManager.warehouse_by_id(_view_warehouse_id) != null:
		_render_warehouse_detail(SupplyManager.warehouse_by_id(_view_warehouse_id))
		return
	_view_warehouse_id = -1
	var owned: Array[WarehouseState] = SupplyManager.warehouses_of(&"player")
	if owned.is_empty():
		_heading(_warehouses_list, "Central storage")
		var intro: Label = Label.new()
		intro.text = "Buy an industrial building to stock ingredients in bulk and van them out to your branches."
		intro.add_theme_font_size_override("font_size", 12)
		intro.add_theme_color_override("font_color", INK_MUTED)
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_warehouses_list.add_child(intro)
	else:
		_heading(_warehouses_list, "Your warehouses")
		for wh: WarehouseState in owned:
			_warehouses_list.add_child(_warehouse_card(wh))
	# Buy section.
	var available: Array[Dictionary] = SupplyManager.purchasable_warehouse_buildings()
	if not available.is_empty():
		_heading(_warehouses_list, "Available industrial buildings")
		var price: float = SupplyManager.warehouse_price()
		var shown: int = mini(available.size(), 6)
		for i: int in range(shown):
			_warehouses_list.add_child(_buy_warehouse_row(available[i], price))
		if available.size() > shown:
			var more: Label = Label.new()
			more.text = "+ %d more industrial buildings on the map." % (available.size() - shown)
			more.add_theme_font_size_override("font_size", 11)
			more.add_theme_color_override("font_color", INK_MUTED)
			_warehouses_list.add_child(more)


func _warehouse_card(wh: WarehouseState) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.tile_box())
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var icon: TextureRect = UiAssets.icon_rect(&"truck", 28)
	if icon != null:
		row.add_child(icon)
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label: Label = Label.new()
	name_label.text = "%s · Level %d" % [wh.display_name, wh.expansion_level]
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", INK)
	info.add_child(name_label)
	var sub: Label = Label.new()
	sub.text = "%d branches served · %.0f%% full" % [wh.assigned_restaurant_ids.size(), _capacity_pct(wh)]
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", INK_MUTED)
	info.add_child(sub)
	var manage: Button = Button.new()
	manage.text = "Manage"
	manage.add_theme_font_size_override("font_size", 12)
	manage.pressed.connect(func() -> void:
		_view_warehouse_id = wh.id
		refresh())
	row.add_child(manage)
	return card


func _buy_warehouse_row(info: Dictionary, price: float) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.sunk_box())
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var label: Label = Label.new()
	label.text = "Industrial building #%d · %s district" % [int(info.get("id", 0)), String(info.get("district", "I"))]
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var buy: Button = Button.new()
	buy.text = "Buy · $%s" % _thousands(int(price))
	buy.add_theme_font_size_override("font_size", 12)
	TycoonTheme.apply_orange(buy)
	var building_id: int = int(info.get("id", 0))
	buy.pressed.connect(func() -> void:
		var result: CommandResult = SupplyManager.buy_warehouse_cmd(&"player", building_id)
		if not result.ok:
			EconomyManager.post_message("alert", result.message)
		elif result.payload is WarehouseState:
			_view_warehouse_id = (result.payload as WarehouseState).id
		refresh())
	row.add_child(buy)
	return card


func _render_warehouse_detail(wh: WarehouseState) -> void:
	# Back to list.
	var back: Button = Button.new()
	back.text = "‹ All warehouses"
	back.add_theme_font_size_override("font_size", 12)
	back.pressed.connect(func() -> void:
		_view_warehouse_id = -1
		refresh())
	_warehouses_list.add_child(back)
	var title: Label = Label.new()
	title.text = "%s · Level %d" % [wh.display_name, wh.expansion_level]
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", INK)
	_warehouses_list.add_child(title)
	# Capacity + inbound cards.
	var cards: HBoxContainer = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	_warehouses_list.add_child(cards)
	cards.add_child(_capacity_card(wh))
	cards.add_child(_inbound_card(wh))
	# Upgrade.
	if wh.expansion_level < WarehouseState.MAX_LEVEL:
		var upgrade: Button = Button.new()
		upgrade.text = "Expand to Level %d · $%s" % [wh.expansion_level + 1, _thousands(int(wh.upgrade_cost()))]
		upgrade.add_theme_font_size_override("font_size", 12)
		TycoonTheme.apply_orange(upgrade)
		upgrade.pressed.connect(func() -> void:
			var result: CommandResult = SupplyManager.upgrade_warehouse_cmd(&"player", wh.id)
			if not result.ok:
				EconomyManager.post_message("alert", result.message)
			refresh())
		_warehouses_list.add_child(upgrade)
	# Assigned + assignable branches.
	_heading(_warehouses_list, "Branches served")
	for rest: RestaurantState in _player_restaurants():
		_warehouses_list.add_child(_assign_row(wh, rest))
	# Inventory summary.
	_heading(_warehouses_list, "Warehouse stock")
	var ids: Array[StringName] = wh.inventory.ingredient_ids()
	if ids.is_empty():
		var empty: Label = Label.new()
		empty.text = "Empty — the warehouse restocks from suppliers overnight once it serves a branch."
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", INK_MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_warehouses_list.add_child(empty)
	else:
		ids.sort()
		for ing: StringName in ids:
			_warehouses_list.add_child(_wh_stock_row(wh, ing))


func _capacity_card(wh: WarehouseState) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.tile_box())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = box_with_title("CAPACITY USED")
	card.add_child(box)
	var pct: float = _capacity_pct(wh)
	box.add_child(_capacity_meter(pct / 100.0))
	var detail: Label = Label.new()
	detail.text = "%.0f%% of %s units" % [pct, _thousands(int(wh.total_capacity()))]
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", INK_MUTED)
	box.add_child(detail)
	return card


func _inbound_card(wh: WarehouseState) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.tile_box())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = box_with_title("INBOUND")
	card.add_child(box)
	var count: int = 0
	var next_eta: int = -1
	for po: PurchaseOrder in SupplyManager.open_orders(&"player"):
		if po.dest_kind == &"warehouse" and po.dest_id == wh.id and po.is_open():
			count += 1
			var eta: int = po.eta_minute - GameClock.total_minutes()
			if next_eta < 0 or eta < next_eta:
				next_eta = eta
	var count_label: Label = Label.new()
	count_label.text = "%d shipments" % count
	count_label.add_theme_font_size_override("font_size", 18)
	count_label.add_theme_color_override("font_color", INK)
	box.add_child(count_label)
	var eta_label: Label = Label.new()
	eta_label.text = "Next in %dh %02dm" % [next_eta / 60, next_eta % 60] if next_eta > 0 else "Nothing inbound"
	eta_label.add_theme_font_size_override("font_size", 12)
	eta_label.add_theme_color_override("font_color", GREEN_DEEP if next_eta > 0 else INK_MUTED)
	box.add_child(eta_label)
	return card


func _assign_row(wh: WarehouseState, rest: RestaurantState) -> Control:
	var assigned: bool = wh.assigned_restaurant_ids.has(rest.building_id)
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.sunk_box())
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	card.add_child(row)
	var store: TextureRect = UiAssets.icon_rect(&"store", 22)
	if store != null:
		row.add_child(store)
	var name_label: Label = Label.new()
	name_label.text = rest.restaurant_name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	# Route-time chip.
	var eta: float = SupplyManager.route_eta(wh.world_pos, rest.door_pos)
	var route_label: Label = Label.new()
	if eta < 0.0:
		route_label.text = "no route"
		route_label.add_theme_color_override("font_color", RED_BAR)
	else:
		route_label.text = "%d min route" % int(eta)
		route_label.add_theme_color_override("font_color", GREEN_DEEP if eta < 20.0 else GOLD_DEEP)
	route_label.add_theme_font_size_override("font_size", 12)
	row.add_child(route_label)
	if assigned:
		var send: Button = Button.new()
		send.text = "Send stock"
		send.add_theme_font_size_override("font_size", 11)
		send.pressed.connect(func() -> void: _send_stock(wh, rest))
		row.add_child(send)
	var toggle: Button = BellaUi.chip("Assigned" if assigned else "Assign", assigned)
	toggle.pressed.connect(func() -> void:
		SupplyManager.assign_restaurant_cmd(&"player", wh.id, rest.building_id, not assigned)
		refresh())
	row.add_child(toggle)
	return card


func _send_stock(wh: WarehouseState, rest: RestaurantState) -> void:
	var inv: InventoryState = SupplyManager.inventory_for_restaurant(rest)
	var wants: Array[Dictionary] = []
	for ing: StringName in inv.policies.keys():
		var policy: ReorderPolicy = inv.policies[ing]
		if policy == null:
			continue
		var take: float = minf(policy.target_stock - inv.available(ing), wh.inventory.available(ing))
		if take >= 1.0:
			wants.append({"ingredient_id": ing, "qty": ceilf(take)})
	if wants.is_empty():
		EconomyManager.post_message("info", "%s is already stocked, or the warehouse has nothing it needs." % rest.restaurant_name)
		return
	var result: CommandResult = SupplyManager.create_transfer_cmd(&"player", wh.id, rest.building_id, wants)
	if not result.ok:
		EconomyManager.post_message("alert", result.message)
	refresh()


func _wh_stock_row(wh: WarehouseState, ing: StringName) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.sunk_box())
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	card.add_child(row)
	row.add_child(_swatch(ing))
	var name_label: Label = Label.new()
	name_label.text = _ingredient_name(ing)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var qty: Label = Label.new()
	qty.text = "%.0f" % wh.inventory.available(ing)
	qty.add_theme_font_size_override("font_size", 13)
	qty.add_theme_color_override("font_color", INK_SOFT)
	row.add_child(qty)
	return card


func _capacity_pct(wh: WarehouseState) -> float:
	var used: float = 0.0
	for storage_class: StringName in [&"dry", &"chilled", &"frozen"]:
		used += wh.inventory.used_volume(storage_class, _class_of, _volume_of)
	var cap: float = wh.total_capacity()
	return clampf(used / cap * 100.0, 0.0, 100.0) if cap > 0.0 else 0.0


func _class_of(ing: StringName) -> StringName:
	var item: InventoryItemDef = SupplyManager.item_def(ing)
	return item.storage_class if item != null else &"dry"


func _volume_of(ing: StringName) -> float:
	var item: InventoryItemDef = SupplyManager.item_def(ing)
	return item.unit_volume if item != null else 1.0


func _player_restaurants() -> Array[RestaurantState]:
	var company: CompanyState = CompanyManager.player
	return company.restaurants if company != null else [] as Array[RestaurantState]


func box_with_title(title: String) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var title_label: Label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 10)
	title_label.add_theme_color_override("font_color", INK_MUTED)
	box.add_child(title_label)
	return box


# --- Policies tab -----------------------------------------------------------------


func _refresh_policies() -> void:
	_clear(_policies_list)
	var rest: RestaurantState = restaurant()
	if rest == null:
		return
	_heading(_policies_list, "Restocking rules per ingredient")
	var inv: InventoryState = SupplyManager.inventory_for_restaurant(rest)
	var ids: Array = _menu_ingredients(rest)
	if ids.is_empty():
		_policies_list.add_child(_empty_state(&"gear", "Nothing to restock",
			"Enable recipes on the menu first."))
		return
	for ing: StringName in ids:
		_policies_list.add_child(_policy_row(rest, inv, ing))


func _policy_row(rest: RestaurantState, inv: InventoryState, ing: StringName) -> Control:
	var policy: ReorderPolicy = inv.policy_for(ing)
	if policy == null:
		policy = SupplyManager._default_policy(ing, SupplyManager.estimated_daily_use(rest, ing))
		inv.policies[ing] = policy
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.tile_box())
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	row.add_child(_swatch(ing))
	var name_label: Label = Label.new()
	name_label.text = _ingredient_name(ing)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var reorder_label: Label = Label.new()
	reorder_label.text = "Reorder at"
	reorder_label.add_theme_font_size_override("font_size", 11)
	reorder_label.add_theme_color_override("font_color", INK_MUTED)
	row.add_child(reorder_label)
	row.add_child(_level_spin(policy.reorder_point, func(value: float) -> void:
		policy.reorder_point = value))
	var target_label: Label = Label.new()
	target_label.text = "top up to"
	target_label.add_theme_font_size_override("font_size", 11)
	target_label.add_theme_color_override("font_color", INK_MUTED)
	row.add_child(target_label)
	row.add_child(_level_spin(policy.target_stock, func(value: float) -> void:
		policy.target_stock = value))
	row.add_child(_supplier_picker(policy))
	for mode_spec: Array in [[&"recommend", "Recommend"], [&"approve", "Approve"], [&"automatic", "Automatic"]]:
		var mode: StringName = mode_spec[0]
		var chip: Button = BellaUi.chip(mode_spec[1], policy.mode == mode)
		chip.pressed.connect(func() -> void:
			SupplyManager.set_policy_mode_cmd(&"player", building_id, ing, mode)
			refresh())
		row.add_child(chip)
	return card


func _level_spin(initial: float, on_change: Callable) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = 0
	spin.max_value = 999
	spin.step = 1
	spin.value = initial
	spin.custom_minimum_size = Vector2(72, 0)
	spin.value_changed.connect(func(value: float) -> void: on_change.call(value))
	return spin


func _supplier_picker(policy: ReorderPolicy) -> OptionButton:
	var picker: OptionButton = OptionButton.new()
	picker.add_theme_font_size_override("font_size", 11)
	picker.add_item("Cheapest supplier")
	picker.set_item_metadata(0, &"")
	var ing_def: IngredientDef = RecipeManager.ingredient(policy.ingredient_id)
	var category: StringName = ing_def.category if ing_def != null else &"veg"
	var index: int = 1
	for def: SupplierDef in SupplyManager.supplier_defs.values():
		if not def.carries(policy.ingredient_id, category):
			continue
		picker.add_item(def.display_name)
		picker.set_item_metadata(index, def.id)
		if def.id == policy.preferred_supplier:
			picker.select(index)
		index += 1
	picker.item_selected.connect(func(selected: int) -> void:
		policy.preferred_supplier = picker.get_item_metadata(selected))
	return picker


# --- Shared helpers ----------------------------------------------------------------


func _make_tab_list(tab_name: String) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	_tabs.add_child(scroll)
	return list


func _menu_ingredients(rest: RestaurantState) -> Array:
	var ids: Array = SupplyManager._menu_daily_need(rest).keys()
	ids.sort()
	return ids


func _avg_freshness(inv: InventoryState, ing: StringName) -> float:
	var now: int = GameClock.total_minutes()
	var qty_sum: float = 0.0
	var weighted: float = 0.0
	for lot: StockLot in inv.lots:
		if lot.ingredient_id == ing and lot.qty > 0.0:
			qty_sum += lot.qty
			weighted += lot.qty * lot.freshness(now)
	return weighted / qty_sum if qty_sum > 0.0 else 0.0


func _meter(fraction: float) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.max_value = 1.0
	bar.value = clampf(fraction, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = BellaUi.PAPER_SUNK
	bg.border_color = BellaUi.PAPER_EDGE
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bg)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = GREEN_BAR if fraction > 0.55 else (GOLD_BAR if fraction > 0.25 else RED_BAR)
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


## Capacity meter: fuller = warmer (gold, then red near the ceiling).
func _capacity_meter(fraction: float) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.max_value = 1.0
	bar.value = clampf(fraction, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = BellaUi.PAPER_SUNK
	bg.border_color = BellaUi.PAPER_EDGE
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(7)
	bar.add_theme_stylebox_override("background", bg)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = RED_BAR if fraction > 0.9 else (Color("#F99A1C") if fraction > 0.6 else GREEN_BAR)
	fill.set_corner_radius_all(7)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _swatch(ing: StringName) -> Control:
	var swatch: Panel = Panel.new()
	swatch.custom_minimum_size = Vector2(20, 20)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	var ing_def: IngredientDef = RecipeManager.ingredient(ing)
	style.bg_color = ing_def.swatch_color if ing_def != null else Color(0.7, 0.6, 0.5)
	style.border_color = INK_SOFT
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	swatch.add_theme_stylebox_override("panel", style)
	return swatch


func _stat_tile(parent: Node, title: String, value: String, value_color: Color) -> void:
	var tile: PanelContainer = PanelContainer.new()
	tile.add_theme_stylebox_override("panel", BellaUi.sunk_box())
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(box)
	var title_label: Label = Label.new()
	title_label.text = title.to_upper()
	title_label.add_theme_font_size_override("font_size", 10)
	title_label.add_theme_color_override("font_color", INK_MUTED)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	var value_label: Label = Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", value_color)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(value_label)
	parent.add_child(tile)


func _mini_stat(parent: Node, title: String, value: String, value_color: Color) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_label: Label = Label.new()
	title_label.text = title.to_upper()
	title_label.add_theme_font_size_override("font_size", 9)
	title_label.add_theme_color_override("font_color", INK_MUTED)
	box.add_child(title_label)
	var value_label: Label = Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 13)
	value_label.add_theme_color_override("font_color", value_color)
	box.add_child(value_label)
	parent.add_child(box)


func _empty_state(icon_name: StringName, title: String, hint: String) -> Control:
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(0, 280)
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.sunk_box(16))
	card.custom_minimum_size = Vector2(360, 180)
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var icon: TextureRect = UiAssets.icon_rect(icon_name, 40)
	if icon != null:
		icon.self_modulate = Color(1, 1, 1, 0.7)
		var icon_center: CenterContainer = CenterContainer.new()
		icon_center.add_child(icon)
		box.add_child(icon_center)
	var title_label: Label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", INK)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	var hint_label: Label = Label.new()
	hint_label.text = hint
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", INK_MUTED)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size = Vector2(320, 0)
	box.add_child(hint_label)
	center.add_child(card)
	return center


## Design "Locked" state: dashed-feel sunk panel + trophy + capability hint.
func _locked_state(title: String, hint: String) -> Control:
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(0, 280)
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = BellaUi.sunk_box(16)
	style.border_color = BellaUi.WOOD_MID
	style.set_border_width_all(3)
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(360, 180)
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var icon: TextureRect = UiAssets.icon_rect(&"trophy", 40)
	if icon != null:
		icon.self_modulate = Color(1, 1, 1, 0.7)
		var icon_center: CenterContainer = CenterContainer.new()
		icon_center.add_child(icon)
		box.add_child(icon_center)
	var title_label: Label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", INK_MUTED)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	var hint_label: Label = Label.new()
	hint_label.text = hint
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", BellaUi.WOOD_EDGE)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size = Vector2(320, 0)
	box.add_child(hint_label)
	center.add_child(card)
	return center


func _heading(parent: Node, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", INK_SOFT)
	parent.add_child(label)


func _ingredient_name(ing: StringName) -> String:
	var ing_def: IngredientDef = RecipeManager.ingredient(ing)
	return ing_def.display_name if ing_def != null else String(ing)


func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		child.queue_free()


func _thousands(value: int) -> String:
	var text: String = str(absi(value))
	var out: String = ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3, 3) + out
		text = text.substr(0, text.length() - 3)
	out = text + out
	return ("-" + out) if value < 0 else out
