extends TycoonScreen
## Reports home (handoff screen D7): pinned KPIs, period/interval controls, a
## chart shell with clickable event annotations, and a report-families sidebar.
## Reads finalized buckets from AnalyticsManager — it never scrapes live managers
## to reconstruct history. Company / Restaurants / Recipes ship here; Workforce /
## Marketing / Supply / Competition families are appended in the extended pass.

const GOOD: Color = Color("#2e7d32")
const BAD: Color = Color("#c0392b")
const MUTED: Color = Color("#8a7150")

const PERIODS: Array = [[7, "7d"], [14, "14d"], [30, "30d"], [42, "Quarter"]]

var _period_days: int = 7
var _interval: StringName = &"day"
var _active_family: StringName = &"company"

var _kpi_grid: GridContainer
var _chart: ReportChart
var _chart_title: Label
var _detail: VBoxContainer
var _interval_btn: Button
var _period_buttons: Array[Button] = []
var _family_buttons: Dictionary = {}

# Scope of the chart currently drawn, for the click-to-drill handler.
var _chart_kind: StringName = &"company"
var _chart_id: String = "player"
var _chart_labels: Array = []


func screen_title() -> String:
	return "Reports"


func screen_icon() -> StringName:
	return &"chart_bars"


## Family list — extended by the later "shipped families" pass.
func _family_defs() -> Array:
	return [
		{"id": &"company", "label": "Company", "icon": &"bank"},
		{"id": &"restaurants", "label": "Restaurants", "icon": &"store"},
		{"id": &"recipes", "label": "Recipes", "icon": &"pizza"},
		{"id": &"workforce", "label": "Workforce", "icon": &"chef_hat"},
		{"id": &"marketing", "label": "Marketing", "icon": &"megaphone"},
		{"id": &"supply", "label": "Supply", "icon": &"basket"},
		{"id": &"competition", "label": "Competition", "icon": &"trophy"},
		{"id": &"more", "label": "Awards · Crime · Gov", "icon": &"bell"},
	]


func _analytics() -> Node:
	return get_node_or_null("/root/AnalyticsManager")


# --- Build -------------------------------------------------------------------


func _build() -> void:
	GameSetup.observe_action(&"daily_report_opened")
	custom_minimum_size = Vector2(940, 640)

	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	_content.add_child(controls)
	var period_label: Label = Label.new()
	period_label.text = "Period"
	period_label.add_theme_font_size_override("font_size", 12)
	period_label.add_theme_color_override("font_color", MUTED)
	controls.add_child(period_label)
	for p: Array in PERIODS:
		var chip: Button = BellaUi.chip(String(p[1]), int(p[0]) == _period_days)
		chip.pressed.connect(_on_period.bind(int(p[0])))
		_period_buttons.append(chip)
		controls.add_child(chip)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)
	_interval_btn = BellaUi.chip("Daily", false)
	_interval_btn.pressed.connect(_on_toggle_interval)
	controls.add_child(_interval_btn)

	var main: HBoxContainer = HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(main)

	var left: VBoxContainer = VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(left)

	_kpi_grid = GridContainer.new()
	_kpi_grid.columns = 4
	_kpi_grid.add_theme_constant_override("h_separation", 8)
	_kpi_grid.add_theme_constant_override("v_separation", 8)
	left.add_child(_kpi_grid)

	var chart_card: PanelContainer = PanelContainer.new()
	chart_card.add_theme_stylebox_override("panel", BellaUi.tile_box())
	chart_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(chart_card)
	var chart_box: VBoxContainer = VBoxContainer.new()
	chart_box.add_theme_constant_override("separation", 6)
	chart_card.add_child(chart_box)
	_chart_title = Label.new()
	_chart_title.add_theme_font_size_override("font_size", 15)
	_chart_title.add_theme_color_override("font_color", BellaUi.INK)
	chart_box.add_child(_chart_title)
	_chart = ReportChart.new()
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chart.bar_clicked.connect(_on_bar_clicked)
	chart_box.add_child(_chart)

	var detail_scroll: ScrollContainer = ScrollContainer.new()
	detail_scroll.custom_minimum_size = Vector2(0, 190)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	detail_scroll.add_child(_detail)
	left.add_child(detail_scroll)

	var side: VBoxContainer = VBoxContainer.new()
	side.custom_minimum_size = Vector2(200, 0)
	side.add_theme_constant_override("separation", 6)
	main.add_child(side)
	var fam_hdr: Label = Label.new()
	fam_hdr.text = "Report families"
	fam_hdr.add_theme_font_size_override("font_size", 12)
	fam_hdr.add_theme_color_override("font_color", MUTED)
	side.add_child(fam_hdr)
	for fam: Dictionary in _family_defs():
		var btn: Button = _family_button(fam)
		_family_buttons[fam["id"]] = btn
		side.add_child(btn)


func _family_button(fam: Dictionary) -> Button:
	var btn: Button = Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = "  " + String(fam["label"])
	UiAssets.icon_button(btn, StringName(fam["icon"]), 20)
	btn.pressed.connect(_on_family.bind(StringName(fam["id"])))
	_style_family_button(btn, StringName(fam["id"]) == _active_family)
	return btn


func _style_family_button(btn: Button, active: bool) -> void:
	var style: StyleBoxFlat = BellaUi.tile_box(BellaUi.RED_EDGE if active else BellaUi.PAPER_EDGE, 2)
	if active:
		style.bg_color = BellaUi.RED_ACTIVE
	for state: String in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, style)
	btn.add_theme_color_override("font_color", Color.WHITE if active else BellaUi.INK)
	btn.add_theme_color_override("font_hover_color", Color.WHITE if active else BellaUi.INK)


# --- Interaction -------------------------------------------------------------


func _on_period(days: int) -> void:
	_period_days = days
	refresh()


func _on_toggle_interval() -> void:
	_interval = &"week" if _interval == &"day" else &"day"
	refresh()


func _on_family(id: StringName) -> void:
	_active_family = id
	refresh()


func _on_bar_clicked(index: int) -> void:
	if index < 0 or index >= _chart_labels.size():
		return
	_render_events_for(int(_chart_labels[index]))


# --- Refresh -----------------------------------------------------------------


func refresh() -> void:
	if _chart == null:
		return
	for i: int in _period_buttons.size():
		BellaUi.style_chip(_period_buttons[i], int(PERIODS[i][0]) == _period_days)
	BellaUi.style_chip(_interval_btn, _interval == &"week")
	_interval_btn.text = "Weekly" if _interval == &"week" else "Daily"
	for fam: Dictionary in _family_defs():
		if _family_buttons.has(fam["id"]):
			_style_family_button(_family_buttons[fam["id"]], StringName(fam["id"]) == _active_family)
	var am: Node = _analytics()
	if am == null or not am.has_history():
		_clear(_kpi_grid)
		_clear(_detail)
		_chart.clear()
		_chart_title.text = "Reports"
		var note: Label = Label.new()
		note.text = "Reports populate at the first midnight — play a day to see trends."
		note.add_theme_color_override("font_color", MUTED)
		_detail.add_child(note)
		return
	_refresh_kpis(am)
	_refresh_chart(am)
	match _active_family:
		&"restaurants":
			_render_restaurants(am)
		&"recipes":
			_render_recipes(am)
		&"workforce":
			_render_workforce()
		&"marketing":
			_render_marketing()
		&"supply":
			_render_supply()
		&"competition":
			_render_competition()
		&"more":
			_render_more()
		_:
			_render_company(am)


func _refresh_kpis(am: Node) -> void:
	_clear(_kpi_grid)
	var revenue: float = am.sum_window(&"company", "player", &"revenue", _period_days)
	var profit: float = am.sum_window(&"company", "player", &"profit", _period_days)
	var orders: float = _company_orders(am, _period_days)
	var reputation: float = am.latest(&"company", "player", &"reputation", 0.0)
	var prev_rev: float = _prev_window(am, &"company", "player", &"revenue", _period_days)
	var prev_profit: float = _prev_window(am, &"company", "player", &"profit", _period_days)
	_add_kpi("Revenue", MetricDef.money(revenue), _pct_delta(revenue, prev_rev))
	_add_kpi("Profit", MetricDef.money(profit), _pct_delta(profit, prev_profit))
	_add_kpi("Orders", MetricDef.thousands(roundi(orders)), "")
	_add_kpi("Reputation", "%.1f" % reputation, "")


func _refresh_chart(am: Node) -> void:
	var metric: StringName = &"revenue"
	var kind: StringName = &"company"
	var scope_id: String = "player"
	var title: String = "Revenue"
	match _active_family:
		&"restaurants":
			var first: int = _first_branch()
			if first >= 0:
				kind = &"restaurant"
				scope_id = str(first)
				metric = &"sales"
				title = "%s — Sales" % _branch_name(first)
		&"recipes":
			metric = &"profit"
			title = "Company profit"
	_chart_kind = kind
	_chart_id = scope_id
	var spec: ReportQuery = ReportQuery.new(metric, kind, scope_id, _period_days, _interval)
	var result: Dictionary = am.query(spec)
	_chart_labels = result.get("labels", [])
	var series: Array = result.get("series", [])
	var primary: Array = series[0] if not series.is_empty() else []
	_chart.set_series(primary, _chart_labels)
	_chart.set_annotations(_build_annotations(am, kind, scope_id, _chart_labels))
	var unit: String = "weekly" if _interval == &"week" else "daily"
	_chart_title.text = "%s — %s, last %d days" % [title, unit, _period_days]


func _build_annotations(am: Node, kind: StringName, scope_id: String, labels: Array) -> Array:
	var annos: Array = []
	for i: int in labels.size():
		var day: int = int(labels[i])
		var evs: Array = am.events_for_day(kind, scope_id, day)
		if not evs.is_empty():
			annos.append({"index": i, "label": _short_event(evs[0]), "tone": &"bad"})
	return annos


# --- Family views ------------------------------------------------------------


func _render_company(am: Node) -> void:
	_clear(_detail)
	var dash: Dictionary = am.company_dashboard(&"player")
	var metrics: Dictionary = dash.get("metrics", {})
	_detail.add_child(_section("Balance & position"))
	var tiles: HBoxContainer = HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	_detail.add_child(tiles)
	_mini_tile(tiles, "Cash", MetricDef.money(float(metrics.get("cash", 0.0))))
	_mini_tile(tiles, "Loan", MetricDef.money(float(metrics.get("loan", 0.0))))
	_mini_tile(tiles, "Inventory", MetricDef.money(float(metrics.get("inventory_value", 0.0))))
	_mini_tile(tiles, "Market share", "%d%%" % roundi(float(metrics.get("market_share", 0.0)) * 100.0))
	_detail.add_child(_section("What changed"))
	var day: int = int(dash.get("day", 0))
	var events: Array = am.events_in_range(&"player", day - _period_days, day)
	if events.is_empty():
		_hint("No notable events in this period — steady trading.")
	else:
		events.reverse()
		var shown: int = 0
		for ev: Dictionary in events:
			_event_row(ev)
			shown += 1
			if shown >= 8:
				break


func _render_restaurants(am: Node) -> void:
	_clear(_detail)
	_detail.add_child(_section("Branch comparison — last %d days" % _period_days))
	_detail.add_child(_branch_header())
	for rest: RestaurantState in RestaurantManager.owned:
		var bid: int = rest.building_id
		var sales: float = am.sum_window(&"restaurant", str(bid), &"sales", _period_days)
		var profit: float = am.sum_window(&"restaurant", str(bid), &"branch_profit", _period_days)
		var guests: float = am.sum_window(&"restaurant", str(bid), &"guests", _period_days)
		var lost: float = am.sum_window(&"restaurant", str(bid), &"lost_demand", _period_days)
		var rating: float = am.latest(&"restaurant", str(bid), &"rating", rest.star_rating)
		var row: PanelContainer = make_row()
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		row.add_child(box)
		_cell(box, rest.restaurant_name, 150, HORIZONTAL_ALIGNMENT_LEFT, BellaUi.INK)
		_cell(box, MetricDef.money(sales), 90, HORIZONTAL_ALIGNMENT_RIGHT, GOOD)
		_cell(box, "%s%s" % ["+" if profit >= 0.0 else "−", MetricDef.money(absf(profit)).lstrip("−")], 90, HORIZONTAL_ALIGNMENT_RIGHT, GOOD if profit >= 0.0 else BAD)
		_cell(box, MetricDef.thousands(roundi(guests)), 70, HORIZONTAL_ALIGNMENT_RIGHT, BellaUi.INK)
		_cell(box, MetricDef.thousands(roundi(lost)), 80, HORIZONTAL_ALIGNMENT_RIGHT, BAD if lost > 0.0 else MUTED)
		_cell(box, "★ %.1f" % rating, 60, HORIZONTAL_ALIGNMENT_RIGHT, Color("#B5810A"))
		_detail.add_child(row)


func _render_recipes(am: Node) -> void:
	_clear(_detail)
	_detail.add_child(_section("Recipe performance (lifetime, owned branches)"))
	var agg: Dictionary = {}  # recipe key -> {units, revenue, cost}
	for rest: RestaurantState in RestaurantManager.owned:
		for key: String in rest.recipe_sales:
			var src: Dictionary = rest.recipe_sales[key]
			var row: Dictionary = agg.get(key, {"units": 0.0, "revenue": 0.0, "cost": 0.0})
			row["units"] = float(row["units"]) + float(src.get("units", 0))
			row["revenue"] = float(row["revenue"]) + float(src.get("revenue", 0.0))
			row["cost"] = float(row["cost"]) + float(src.get("cost", 0.0))
			agg[key] = row
	if agg.is_empty():
		_hint("No recipe sales recorded yet.")
		return
	var keys: Array = agg.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float(agg[a]["units"]) > float(agg[b]["units"]))
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_cell(header, "Recipe", 170, HORIZONTAL_ALIGNMENT_LEFT, MUTED)
	_cell(header, "Units", 70, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
	_cell(header, "Revenue", 100, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
	_cell(header, "Margin", 90, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
	_detail.add_child(header)
	for key: String in keys:
		var row_data: Dictionary = agg[key]
		var revenue: float = float(row_data["revenue"])
		var cost: float = float(row_data["cost"])
		var margin: float = (revenue - cost) / revenue if revenue > 0.0 else 0.0
		var row: PanelContainer = make_row()
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		row.add_child(box)
		_cell(box, key.get_slice("@", 0).capitalize(), 170, HORIZONTAL_ALIGNMENT_LEFT, BellaUi.INK)
		_cell(box, MetricDef.thousands(int(row_data["units"])), 70, HORIZONTAL_ALIGNMENT_RIGHT, BellaUi.INK)
		_cell(box, MetricDef.money(revenue), 100, HORIZONTAL_ALIGNMENT_RIGHT, GOOD)
		_cell(box, "%d%%" % roundi(margin * 100.0), 90, HORIZONTAL_ALIGNMENT_RIGHT, Color("#B5810A"))
		_detail.add_child(row)


func _render_events_for(day: int) -> void:
	_clear(_detail)
	var back: Button = Button.new()
	back.text = "← Back to %s" % _active_family.capitalize()
	back.focus_mode = Control.FOCUS_NONE
	BellaUi.style_chip(back, false)
	back.pressed.connect(refresh)
	_detail.add_child(back)
	_detail.add_child(_section("Events on Day %d" % day))
	var am: Node = _analytics()
	var evs: Array = am.events_for_day(_chart_kind, _chart_id, day) if am != null else []
	if evs.is_empty():
		_hint("No recorded events on this day.")
		return
	for ev: Dictionary in evs:
		_event_row(ev)


# --- Extended families (shipped source systems) ------------------------------


func _player_id() -> StringName:
	return CompanyManager.player.id if CompanyManager.player != null else &"player"


func _render_workforce() -> void:
	_clear(_detail)
	var staff: Node = get_node_or_null("/root/StaffManager")
	if staff == null or not staff.has_method("workforce_analytics"):
		_hint("Workforce analytics unlock with your first hires.")
		return
	var wa: Dictionary = staff.call("workforce_analytics", _player_id())
	_detail.add_child(_section("Workforce — company"))
	var tiles: HBoxContainer = HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	_detail.add_child(tiles)
	_mini_tile(tiles, "Headcount", MetricDef.thousands(int(wa.get("headcount", 0))))
	_mini_tile(tiles, "Payroll/day", MetricDef.money(float(wa.get("payroll_daily", 0.0))))
	_mini_tile(tiles, "Motivation", "%d%%" % roundi(float(wa.get("avg_motivation", 0.0)) * 100.0))
	_mini_tile(tiles, "Turnover 14d", MetricDef.thousands(int(wa.get("turnover_14d", 0))))
	var tiles2: HBoxContainer = HBoxContainer.new()
	tiles2.add_theme_constant_override("separation", 8)
	_detail.add_child(tiles2)
	_mini_tile(tiles2, "Absences 14d", MetricDef.thousands(int(wa.get("absences_14d", 0))))
	_mini_tile(tiles2, "Training active", MetricDef.thousands(int(wa.get("training_active", 0))))
	_mini_tile(tiles2, "Satisfaction", "%d%%" % roundi(float(wa.get("avg_satisfaction", 0.0)) * 100.0))
	_mini_tile(tiles2, "Readiness", "%d%%" % roundi(float(wa.get("avg_readiness", 0.0)) * 100.0))
	var by_role: Dictionary = wa.get("by_role", {})
	if not by_role.is_empty():
		_detail.add_child(_section("By role"))
		for role: Variant in by_role:
			var row: PanelContainer = make_row()
			var box: HBoxContainer = HBoxContainer.new()
			box.add_theme_constant_override("separation", 8)
			row.add_child(box)
			_cell(box, String(role).capitalize(), 200, HORIZONTAL_ALIGNMENT_LEFT, BellaUi.INK)
			_cell(box, MetricDef.thousands(int(by_role[role])), 80, HORIZONTAL_ALIGNMENT_RIGHT, BellaUi.INK)
			_detail.add_child(row)
	if int(wa.get("report_depth", 0)) < 1:
		_hint("Build the HQ Analytics department for deeper workforce breakdowns.")


func _render_marketing() -> void:
	_clear(_detail)
	if not MarketingManager.has_method("campaigns_for"):
		_hint("Marketing analytics unavailable.")
		return
	var campaigns: Array = MarketingManager.campaigns_for(_player_id())
	var sov: float = MarketingManager.share_of_voice(_player_id()) if MarketingManager.has_method("share_of_voice") else 0.0
	var total_spend: float = 0.0
	var total_attr: float = 0.0
	for c: Variant in campaigns:
		total_spend += float(c.get("total_spend") if c.get("total_spend") != null else 0.0)
		total_attr += float(c.get("attributed_revenue") if c.get("attributed_revenue") != null else 0.0)
	_detail.add_child(_section("Marketing"))
	var tiles: HBoxContainer = HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	_detail.add_child(tiles)
	_mini_tile(tiles, "Active campaigns", MetricDef.thousands(campaigns.size()))
	_mini_tile(tiles, "Share of voice", "%d%%" % roundi(sov * 100.0))
	_mini_tile(tiles, "Spend", MetricDef.money(total_spend))
	_mini_tile(tiles, "Attributed rev", MetricDef.money(total_attr))
	if campaigns.is_empty():
		_hint("No active campaigns. Launch one from Marketing.")
		return
	_detail.add_child(_section("Active campaigns"))
	for c: Variant in campaigns:
		var row: PanelContainer = make_row()
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		row.add_child(box)
		var channel: String = String(c.get("channel_id") if c.get("channel_id") != null else "Campaign")
		_cell(box, channel.capitalize(), 150, HORIZONTAL_ALIGNMENT_LEFT, BellaUi.INK)
		_cell(box, MetricDef.money(float(c.get("total_spend") if c.get("total_spend") != null else 0.0)), 90, HORIZONTAL_ALIGNMENT_RIGHT, BAD)
		_cell(box, MetricDef.money(float(c.get("attributed_revenue") if c.get("attributed_revenue") != null else 0.0)), 100, HORIZONTAL_ALIGNMENT_RIGHT, GOOD)
		_cell(box, "%d%% eff" % roundi(float(c.get("effectiveness") if c.get("effectiveness") != null else 0.0) * 100.0), 80, HORIZONTAL_ALIGNMENT_RIGHT, Color("#B5810A"))
		_detail.add_child(row)


func _render_supply() -> void:
	_clear(_detail)
	if not SupplyManager.has_method("stockout_risks"):
		_hint("Supply analytics unavailable.")
		return
	_detail.add_child(_section("Supply health by branch"))
	for rest: RestaurantState in RestaurantManager.owned:
		var risks: Array = SupplyManager.stockout_risks(rest)
		var warnings: Array = SupplyManager.forecast_warnings(rest) if SupplyManager.has_method("forecast_warnings") else []
		var row: PanelContainer = make_row()
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		row.add_child(box)
		_cell(box, rest.restaurant_name, 160, HORIZONTAL_ALIGNMENT_LEFT, BellaUi.INK)
		var risk_color: Color = BAD if risks.size() > 0 else GOOD
		_cell(box, "%d stockout risk%s" % [risks.size(), "" if risks.size() == 1 else "s"], 130, HORIZONTAL_ALIGNMENT_RIGHT, risk_color)
		var warn_text: String = "OK"
		if warnings.size() > 0 and warnings[0] is Dictionary:
			warn_text = String((warnings[0] as Dictionary).get("reason", "%d warnings" % warnings.size()))
		elif warnings.size() > 0:
			warn_text = "%d warnings" % warnings.size()
		_cell(box, warn_text, 190, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
		_detail.add_child(row)


func _render_competition() -> void:
	_clear(_detail)
	_detail.add_child(_section("Known rivals — estimates where noted"))
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_cell(header, "Company", 150, HORIZONTAL_ALIGNMENT_LEFT, MUTED)
	_cell(header, "Branches", 80, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
	_cell(header, "Rating", 60, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
	_cell(header, "Est. rev", 100, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
	_cell(header, "SoV", 60, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
	_detail.add_child(header)
	var rivals: Array = CompanyManager.rivals()
	var shown: int = 0
	for rival: Variant in rivals:
		if bool(rival.is_bankrupt):
			continue
		var row: PanelContainer = make_row()
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		row.add_child(box)
		_cell(box, String(rival.display_name), 150, HORIZONTAL_ALIGNMENT_LEFT, BellaUi.INK)
		_cell(box, str(RivalIntel.branch_count(rival)), 80, HORIZONTAL_ALIGNMENT_RIGHT, BellaUi.INK)
		_cell(box, "%.1f" % RivalIntel.avg_rating(rival), 60, HORIZONTAL_ALIGNMENT_RIGHT, Color("#B5810A"))
		_cell(box, "~" + MetricDef.money_compact(RivalIntel.estimated_revenue(rival, 7)), 100, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
		_cell(box, "~%d%%" % roundi(RivalIntel.share_of_voice(rival, false) * 100.0), 60, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
		_detail.add_child(row)
		shown += 1
	if shown == 0:
		_hint("No rivals in this city.")
	else:
		_hint("Rival treasury, recipes and staffing stay private until you have an intel source.")


func _render_more() -> void:
	_clear(_detail)
	_detail.add_child(_section("Awards & prestige"))
	_render_awards_summary()
	_detail.add_child(_section("Planned report families"))
	_locked_card("Crime & Security", "Incident, sabotage and recovery reports arrive with the Crime & Sabotage update.")
	_locked_card("Government", "Permits, inspections and taxes arrive with the Government update.")


func _render_awards_summary() -> void:
	var awards: Node = get_tree().root.get_node_or_null(^"AwardsManager")
	if awards == null:
		_locked_card("Awards", "City awards & recipe competitions arrive with the Competitions update.")
		return
	var player_id: StringName = CompanyManager.player.id
	var tiles: HBoxContainer = HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	_detail.add_child(tiles)
	_mini_tile(tiles, "Trophies", "%d" % int(awards.trophies_for(player_id)))
	_mini_tile(tiles, "Live contests", "%d" % (awards.active_competitions() as Array).size())
	var best: float = 0.0
	for rest: RestaurantState in RestaurantManager.owned:
		best = maxf(best, rest.star_rating)
	_mini_tile(tiles, "Best branch", "%.1f stars" % best)
	var results: Array = awards.award_results
	var shown: int = 0
	for i: int in range(results.size() - 1, -1, -1):
		if shown >= 4:
			break
		shown += 1
		var result: AwardResult = results[i]
		var row: Label = Label.new()
		row.text = "%s — %s (%s)" % [result.display_name, result.winner_name, result.period_label]
		row.add_theme_font_size_override("font_size", 12)
		row.add_theme_color_override("font_color", BellaUi.INK_SOFT)
		_detail.add_child(row)
	if shown == 0:
		_hint("No awards decided yet — the first ceremony lands at the quarter close.")


func _locked_card(title: String, body: String) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BellaUi.sunk_box())
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	vbox.add_child(head)
	var t: Label = Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 14)
	t.add_theme_color_override("font_color", BellaUi.INK)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(BellaUi.pill("PLANNED", BellaUi.INK_SOFT, BellaUi.PAPER_SUNK, BellaUi.PAPER_EDGE))
	var b: Label = Label.new()
	b.text = body
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", MUTED)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(b)
	_detail.add_child(panel)


# --- Small widgets -----------------------------------------------------------


func _add_kpi(title: String, value_text: String, delta_text: String) -> void:
	var tile: PanelContainer = PanelContainer.new()
	tile.add_theme_stylebox_override("panel", TycoonTheme.chip_box())
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	tile.add_child(box)
	var t: Label = Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 11)
	t.add_theme_color_override("font_color", MUTED)
	box.add_child(t)
	var v: Label = Label.new()
	v.text = value_text
	v.add_theme_font_size_override("font_size", 20)
	v.add_theme_color_override("font_color", BellaUi.INK)
	box.add_child(v)
	if not delta_text.is_empty():
		var d: Label = Label.new()
		d.text = delta_text
		d.add_theme_font_size_override("font_size", 11)
		d.add_theme_color_override("font_color", GOOD if delta_text.begins_with("▲") else BAD)
		box.add_child(d)
	_kpi_grid.add_child(tile)


func _mini_tile(parent: Control, title: String, value_text: String) -> void:
	var tile: PanelContainer = PanelContainer.new()
	tile.add_theme_stylebox_override("panel", BellaUi.sunk_box())
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	tile.add_child(box)
	var t: Label = Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 10)
	t.add_theme_color_override("font_color", MUTED)
	box.add_child(t)
	var v: Label = Label.new()
	v.text = value_text
	v.add_theme_font_size_override("font_size", 15)
	v.add_theme_color_override("font_color", BellaUi.INK)
	box.add_child(v)
	parent.add_child(tile)


func _event_row(ev: Dictionary) -> void:
	var row: PanelContainer = make_row()
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	row.add_child(box)
	var icon: TextureRect = UiAssets.icon_rect(BusinessEvent.icon_for(StringName(ev.get("type", &"receipt"))), 20)
	if icon != null:
		box.add_child(icon)
	var title: Label = Label.new()
	title.text = BusinessEvent.describe(ev)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", BellaUi.INK)
	box.add_child(title)
	var day_label: Label = Label.new()
	day_label.text = "Day %d" % int(ev.get("day", 0))
	day_label.add_theme_font_size_override("font_size", 11)
	day_label.add_theme_color_override("font_color", MUTED)
	box.add_child(day_label)
	var amount: float = float(ev.get("amount", 0.0))
	if not is_zero_approx(amount):
		var amt: Label = Label.new()
		amt.text = "%s%s" % ["+" if amount >= 0.0 else "−", MetricDef.money(absf(amount)).lstrip("−")]
		amt.custom_minimum_size = Vector2(80, 0)
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amt.add_theme_color_override("font_color", GOOD if amount >= 0.0 else BAD)
		box.add_child(amt)
	_detail.add_child(row)


func _branch_header() -> HBoxContainer:
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_cell(header, "Branch", 150, HORIZONTAL_ALIGNMENT_LEFT, MUTED)
	_cell(header, "Sales", 90, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
	_cell(header, "Profit", 90, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
	_cell(header, "Guests", 70, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
	_cell(header, "Lost", 80, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
	_cell(header, "Rating", 60, HORIZONTAL_ALIGNMENT_RIGHT, MUTED)
	return header


func _cell(parent: Control, text: String, width: int, align: int, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = align
	if align == HORIZONTAL_ALIGNMENT_LEFT:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _section(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#8a5a2b"))
	return label


func _hint(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", MUTED)
	_detail.add_child(label)


# --- Helpers -----------------------------------------------------------------


func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		child.queue_free()


func _pct_delta(current: float, previous: float) -> String:
	if is_zero_approx(previous):
		return ""
	var pct: float = (current - previous) / absf(previous) * 100.0
	return "%s %d%%" % ["▲" if pct >= 0.0 else "▼", roundi(absf(pct))]


func _prev_window(am: Node, kind: StringName, scope_id: String, metric: StringName, days: int) -> float:
	var series: Array = am.metric_series(metric, kind, scope_id, days * 2, &"day")
	var count: int = maxi(0, series.size() - days)
	var total: float = 0.0
	for i: int in count:
		total += float(series[i])
	return total


func _company_orders(am: Node, days: int) -> float:
	var total: float = 0.0
	for rest: RestaurantState in RestaurantManager.owned:
		total += am.sum_window(&"restaurant", str(rest.building_id), &"orders", days)
	return total


func _first_branch() -> int:
	for rest: RestaurantState in RestaurantManager.owned:
		return rest.building_id
	return -1


func _branch_name(building_id: int) -> String:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	return rest.restaurant_name if rest != null else "Branch"


func _short_event(ev: Dictionary) -> String:
	match StringName(ev.get("type", &"")):
		BusinessEvent.PRICE_CHANGE: return "Price"
		BusinessEvent.SHORTAGE: return "Short"
		BusinessEvent.STAFF_LOST: return "Staff"
		BusinessEvent.EXPANSION: return "Expand"
		BusinessEvent.RANK_CHANGE: return "Rank"
		BusinessEvent.CAMPAIGN_STARTED: return "Ad"
		_: return "Event"
