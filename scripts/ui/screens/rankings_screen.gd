extends TycoonScreen
## Rankings (design C5) + rival company profile (design E5, opened from a
## rival's row). Rival numbers come from RivalIntel only — known facts,
## stable estimates marked "~/estimated", and "?" for hidden information.

const INK: Color = Color("#3A2010")
const INK_SOFT: Color = Color("#6E4326")
const INK_MUTED: Color = Color("#9A7245")
const GOLD_EDGE: Color = Color("#B5810A")
const GREEN_DARK: Color = Color("#356615")
const RED_DARK: Color = Color("#C7331C")

signal request_screen(screen_id: StringName)

## Ranking tabs (C5). Company-metric tabs read AnalyticsManager.rankings();
## Restaurants/Recipes are the player's own leaderboards; Awards is a stub.
const RANK_TABS: Array = [
	{"id": &"companies", "label": "Companies", "ranking": &"value"},
	{"id": &"restaurants", "label": "Restaurants", "ranking": &""},
	{"id": &"recipes", "label": "Recipes", "ranking": &""},
	{"id": &"delivery", "label": "Delivery", "ranking": &"delivery"},
	{"id": &"awards", "label": "Awards", "ranking": &""},
	{"id": &"score", "label": "Score", "ranking": &"scenario"},
]

## Empty = company list; otherwise the rival profile being inspected.
var _view_company: StringName = &""
var _active_tab: StringName = &"companies"
var _body: VBoxContainer


func screen_title() -> String:
	return "Rankings"


func screen_icon() -> StringName:
	return &"trophy"


func _build() -> void:
	custom_minimum_size = Vector2(760, 540)
	_body = add_scroll_list()


func refresh() -> void:
	for child: Node in _body.get_children():
		child.queue_free()
	if _view_company != &"":
		var company: CompanyState = CompanyManager.company(_view_company)
		if company != null:
			_render_profile(company)
			return
		_view_company = &""
	_render_rankings()


# --- Companies leaderboard -----------------------------------------------------


func _render_rankings() -> void:
	var scope: Label = Label.new()
	scope.text = "City rankings · this week · updated daily"
	scope.add_theme_font_size_override("font_size", 12)
	scope.add_theme_color_override("font_color", INK_MUTED)
	_body.add_child(scope)
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_body.add_child(tabs)
	for tab: Dictionary in RANK_TABS:
		var chip: Button = BellaUi.chip(String(tab["label"]), StringName(tab["id"]) == _active_tab)
		chip.pressed.connect(_on_tab.bind(StringName(tab["id"])))
		tabs.add_child(chip)
	match _active_tab:
		&"restaurants":
			_render_restaurant_leaderboard()
		&"recipes":
			_render_recipe_leaderboard()
		&"awards":
			_render_awards()
		_:
			_render_company_ranking(_ranking_for_tab(_active_tab))


func _analytics() -> Node:
	return get_node_or_null("/root/AnalyticsManager")


func _on_tab(id: StringName) -> void:
	_active_tab = id
	refresh()


func _ranking_for_tab(tab: StringName) -> StringName:
	for entry: Dictionary in RANK_TABS:
		if StringName(entry["id"]) == tab:
			return StringName(entry["ranking"])
	return &"value"


func _render_company_ranking(ranking_id: StringName) -> void:
	var am: Node = _analytics()
	if am == null:
		var order: Array[CompanyState] = CompanyManager.current_rankings()
		for i: int in order.size():
			_body.add_child(_rank_row(order[i], i + 1))
		return
	var entries: Array = am.rankings(ranking_id)
	if entries.is_empty():
		_body.add_child(_muted_line("No ranked companies yet."))
		return
	_render_ranking_banner(am, ranking_id, entries)
	for entry: Dictionary in entries:
		_body.add_child(_ranking_row(entry))


func _render_ranking_banner(am: Node, ranking_id: StringName, entries: Array) -> void:
	var player_entry: Dictionary = {}
	for entry: Dictionary in entries:
		if bool(entry.get("is_player", false)):
			player_entry = entry
			break
	if player_entry.is_empty():
		return
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BellaUi.sunk_box())
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)
	var rank: int = int(player_entry.get("rank", 0))
	var unit: int = int(player_entry.get("unit", 0))
	var head: Label = Label.new()
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", INK)
	if rank == 1:
		head.text = "You lead the city — hold your position."
	else:
		var target: Dictionary = am.next_target(ranking_id, CompanyManager.player.id)
		if not target.is_empty() and not bool(target.get("leader", false)):
			head.text = "You're #%d — pass %s to climb (gap %s)." % [rank, String(target.get("target_name", "")), _fmt_score(absf(float(target.get("gap", 0.0))), unit, false)]
		else:
			head.text = "You're #%d." % rank
	vbox.add_child(head)
	var leader: Dictionary = entries[0]
	var leader_line: Label = Label.new()
	leader_line.text = "Leader: %s — %s" % [String(leader.get("display_name", "")), String(leader.get("strength", ""))]
	leader_line.add_theme_font_size_override("font_size", 12)
	leader_line.add_theme_color_override("font_color", INK_MUTED)
	leader_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(leader_line)
	_body.add_child(panel)


func _ranking_row(entry: Dictionary) -> PanelContainer:
	var row: PanelContainer = PanelContainer.new()
	var rank: int = int(entry.get("rank", 0))
	var is_player: bool = bool(entry.get("is_player", false))
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.set_corner_radius_all(14)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	if rank == 1:
		box.bg_color = Color("#FFF3CE")
		box.set_border_width_all(3)
		box.border_color = GOLD_EDGE
	else:
		box.bg_color = Color("#FBEFC9")
		box.set_border_width_all(2)
		box.border_color = Color("#EAD59B")
	row.add_theme_stylebox_override("panel", box)
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	row.add_child(line)
	var rank_label: Label = Label.new()
	rank_label.text = str(rank)
	rank_label.custom_minimum_size = Vector2(34, 0)
	rank_label.add_theme_font_size_override("font_size", 26)
	rank_label.add_theme_color_override("font_color", INK)
	line.add_child(rank_label)
	var movement: int = int(entry.get("movement", 0))
	var move_label: Label = Label.new()
	if movement > 0:
		move_label.text = "▲%d" % movement
		move_label.add_theme_color_override("font_color", GREEN_DARK)
	elif movement < 0:
		move_label.text = "▼%d" % -movement
		move_label.add_theme_color_override("font_color", RED_DARK)
	else:
		move_label.text = "—"
		move_label.add_theme_color_override("font_color", INK_MUTED)
	move_label.custom_minimum_size = Vector2(38, 0)
	move_label.add_theme_font_size_override("font_size", 15)
	line.add_child(move_label)
	line.add_child(_swatch(entry.get("brand_color", Color.WHITE), 34))
	var name_block: VBoxContainer = VBoxContainer.new()
	name_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_block.add_theme_constant_override("separation", 0)
	line.add_child(name_block)
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_block.add_child(name_row)
	var name_label: Label = Label.new()
	name_label.text = String(entry.get("display_name", ""))
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", INK)
	name_row.add_child(name_label)
	if is_player:
		name_row.add_child(BellaUi.pill("YOU", Color.WHITE, Color("#6FB63A"), Color("#4E8F27")))
	var strength: Label = Label.new()
	strength.text = String(entry.get("strength", "")) + ("  ·  estimated" if bool(entry.get("estimated", false)) else "")
	strength.add_theme_font_size_override("font_size", 12)
	strength.add_theme_color_override("font_color", INK_MUTED)
	name_block.add_child(strength)
	var score_label: Label = Label.new()
	score_label.text = _fmt_score(float(entry.get("score", 0.0)), int(entry.get("unit", 0)), bool(entry.get("estimated", false)))
	score_label.add_theme_font_size_override("font_size", 18)
	score_label.add_theme_color_override("font_color", INK if is_player else INK_SOFT)
	line.add_child(score_label)
	if not is_player:
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.tooltip_text = "View company profile"
		var company_id: StringName = StringName(entry.get("company_id", &""))
		row.gui_input.connect(func(event: InputEvent) -> void:
			var click: InputEventMouseButton = event as InputEventMouseButton
			if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				_view_company = company_id
				refresh())
	return row


func _fmt_score(score: float, unit: int, estimated: bool) -> String:
	var s: String
	match unit:
		MetricDef.Unit.MONEY:
			s = MetricDef.money_compact(score)
		MetricDef.Unit.PERCENT:
			s = "%d%%" % roundi(score * 100.0)
		MetricDef.Unit.RATING:
			s = "%.1f" % score
		MetricDef.Unit.COUNT:
			s = MetricDef.thousands(roundi(score))
		_:
			s = _fmt_thousands(score)
	return ("~" + s) if estimated else s


func _render_restaurant_leaderboard() -> void:
	var am: Node = _analytics()
	_body.add_child(_muted_line("Your branches ranked by this week's sales."))
	var rows: Array = []
	for rest: RestaurantState in RestaurantManager.owned:
		var sales: float = am.sum_window(&"restaurant", str(rest.building_id), &"sales", 7) if am != null else 0.0
		rows.append({"rest": rest, "sales": sales})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["sales"]) > float(b["sales"]))
	if rows.is_empty():
		_body.add_child(_muted_line("No branches yet — open one to compete."))
		return
	for i: int in rows.size():
		var rest: RestaurantState = rows[i]["rest"]
		_body.add_child(_simple_rank_row(i + 1, rest.restaurant_name, "$%s" % _fmt_thousands(float(rows[i]["sales"])), rest.star_rating))


func _render_recipe_leaderboard() -> void:
	_body.add_child(_muted_line("Your recipes ranked by units sold. Rival recipe sales stay private."))
	var agg: Dictionary = {}
	for rest: RestaurantState in RestaurantManager.owned:
		for key: String in rest.recipe_sales:
			var src: Dictionary = rest.recipe_sales[key]
			var row: Dictionary = agg.get(key, {"units": 0.0, "revenue": 0.0})
			row["units"] = float(row["units"]) + float(src.get("units", 0))
			row["revenue"] = float(row["revenue"]) + float(src.get("revenue", 0.0))
			agg[key] = row
	if agg.is_empty():
		_body.add_child(_muted_line("No recipe sales recorded yet."))
		return
	var keys: Array = agg.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float(agg[a]["units"]) > float(agg[b]["units"]))
	for i: int in keys.size():
		var key: String = keys[i]
		_body.add_child(_simple_rank_row(i + 1, key.get_slice("@", 0).capitalize(), "%d sold" % int(agg[key]["units"]), -1.0))


func _render_awards() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BellaUi.sunk_box())
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	var title: Label = Label.new()
	title.text = "Awards & competitions"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", INK)
	vbox.add_child(title)
	var body: Label = Label.new()
	body.text = "City awards and recipe cups arrive with the Competitions update. Your company rankings above already feed the scenario score."
	body.add_theme_font_size_override("font_size", 12)
	body.add_theme_color_override("font_color", INK_MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)
	_body.add_child(panel)


func _simple_rank_row(rank: int, name_text: String, value_text: String, rating: float) -> PanelContainer:
	var row: PanelContainer = make_row()
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	row.add_child(line)
	var rank_label: Label = Label.new()
	rank_label.text = str(rank)
	rank_label.custom_minimum_size = Vector2(30, 0)
	rank_label.add_theme_font_size_override("font_size", 20)
	rank_label.add_theme_color_override("font_color", INK)
	line.add_child(rank_label)
	var name_label: Label = Label.new()
	name_label.text = name_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", INK)
	line.add_child(name_label)
	if rating >= 0.0:
		line.add_child(TycoonTheme.star_row(rating, 13))
	var value_label: Label = Label.new()
	value_label.text = value_text
	value_label.add_theme_font_size_override("font_size", 15)
	value_label.add_theme_color_override("font_color", INK_SOFT)
	line.add_child(value_label)
	return row


func _rank_row(company: CompanyState, rank: int) -> PanelContainer:
	var row: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.set_corner_radius_all(14)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	if rank == 1:
		box.bg_color = Color("#FFF3CE")
		box.set_border_width_all(3)
		box.border_color = GOLD_EDGE
	else:
		box.bg_color = Color("#FBEFC9")
		box.set_border_width_all(2)
		box.border_color = Color("#EAD59B")
	row.add_theme_stylebox_override("panel", box)
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	row.add_child(line)

	var rank_label: Label = Label.new()
	rank_label.text = str(rank)
	rank_label.custom_minimum_size = Vector2(34, 0)
	rank_label.add_theme_font_size_override("font_size", 26)
	rank_label.add_theme_color_override("font_color", INK)
	line.add_child(rank_label)

	var movement: int = CompanyManager.rank_movement(company.id)
	var move_label: Label = Label.new()
	if movement > 0:
		move_label.text = "▲%d" % movement
		move_label.add_theme_color_override("font_color", GREEN_DARK)
	elif movement < 0:
		move_label.text = "▼%d" % -movement
		move_label.add_theme_color_override("font_color", RED_DARK)
	else:
		move_label.text = "—"
		move_label.add_theme_color_override("font_color", INK_MUTED)
	move_label.custom_minimum_size = Vector2(38, 0)
	move_label.add_theme_font_size_override("font_size", 15)
	line.add_child(move_label)

	line.add_child(_swatch(company.brand_color, 34))

	var name_block: VBoxContainer = VBoxContainer.new()
	name_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_block.add_theme_constant_override("separation", 0)
	line.add_child(name_block)
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_block.add_child(name_row)
	var name_label: Label = Label.new()
	name_label.text = company.display_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", INK)
	name_row.add_child(name_label)
	if company.is_player:
		name_row.add_child(BellaUi.pill("YOU", Color.WHITE, Color("#6FB63A"), Color("#4E8F27")))
	if company.is_bankrupt:
		name_row.add_child(BellaUi.pill("BANKRUPT", Color.WHITE, Color("#EA4A2F"), Color("#97230F")))
	var strength: Label = Label.new()
	var tagline: String = company.profile.tagline if company.profile != null else "Strength: your empire"
	strength.text = tagline + ("" if company.is_player else "  ·  score estimated")
	strength.add_theme_font_size_override("font_size", 12)
	strength.add_theme_color_override("font_color", INK_MUTED)
	name_block.add_child(strength)

	var score_label: Label = Label.new()
	var score: float = RivalIntel.score(company, company.is_player)
	score_label.text = ("%s" if company.is_player else "~%s") % _fmt_thousands(score)
	score_label.add_theme_font_size_override("font_size", 18)
	score_label.add_theme_color_override("font_color", INK if company.is_player else INK_SOFT)
	line.add_child(score_label)

	if not company.is_player:
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.tooltip_text = "View company profile"
		var company_id: StringName = company.id
		row.gui_input.connect(func(event: InputEvent) -> void:
			var click: InputEventMouseButton = event as InputEventMouseButton
			if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				_view_company = company_id
				refresh())
	return row


# --- Rival profile (E5) ---------------------------------------------------------


func _render_profile(company: CompanyState) -> void:
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_body.add_child(header)
	var back: Button = Button.new()
	back.text = "‹ Rankings"
	back.pressed.connect(func() -> void:
		_view_company = &""
		refresh())
	header.add_child(back)
	header.add_child(_swatch(company.brand_color, 30))
	var name_label: Label = Label.new()
	name_label.text = company.display_name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var depth: int = _analytics_depth()
	var intel_label: String = "Intel: public only" if depth == 0 else ("Intel: modeled" if depth == 1 else "Intel: verified")
	header.add_child(BellaUi.pill(intel_label, INK_SOFT, Color("#F6E4B0"), Color("#EAD59B")))
	var compare: Button = Button.new()
	compare.text = "Compare report"
	compare.focus_mode = Control.FOCUS_NONE
	compare.pressed.connect(func() -> void: request_screen.emit(&"reports"))
	header.add_child(compare)

	if company.profile != null:
		var tagline: Label = Label.new()
		tagline.text = company.profile.tagline
		tagline.add_theme_font_size_override("font_size", 13)
		tagline.add_theme_color_override("font_color", INK_MUTED)
		_body.add_child(tagline)

	add_profile_section("Head to head — known vs estimated")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	_body.add_child(grid)
	var player: CompanyState = CompanyManager.player
	_head_to_head(grid, "Branches", str(player.restaurants.size()),
		"%d (known)" % RivalIntel.branch_count(company))
	_head_to_head(grid, "Avg rating", "%.1f" % RivalIntel.avg_rating(player),
		"%.1f (public)" % RivalIntel.avg_rating(company))
	_head_to_head(grid, "Weekly revenue", "$%s" % _fmt_thousands(RivalIntel.score(player, true) - float(player.restaurants.size()) * 1000.0 - player.reputation * 2000.0),
		"~$%s (estimated)" % _fmt_thousands(RivalIntel.estimated_revenue(company)))
	_head_to_head(grid, "Avg menu price", "$%.2f" % RivalIntel.avg_menu_price(player),
		"$%.2f (posted)" % RivalIntel.avg_menu_price(company))
	_head_to_head(grid, "Treasury", "$%.0f" % player.cash, _intel_treasury(company))
	_head_to_head(grid, "Ad campaigns", str(RivalIntel.spotted_campaigns(player)),
		"%d (spotted)" % RivalIntel.spotted_campaigns(company))
	_head_to_head(grid, "Share of voice", "%d%%" % roundi(RivalIntel.share_of_voice(player, true) * 100.0),
		"~%d%% (estimated)" % roundi(RivalIntel.share_of_voice(company, false) * 100.0))

	var note: PanelContainer = PanelContainer.new()
	var note_box: StyleBoxFlat = StyleBoxFlat.new()
	note_box.bg_color = Color("#F6E4B0")
	note_box.set_corner_radius_all(10)
	note_box.content_margin_left = 10.0
	note_box.content_margin_right = 10.0
	note_box.content_margin_top = 6.0
	note_box.content_margin_bottom = 6.0
	note.add_theme_stylebox_override("panel", note_box)
	var note_label: Label = Label.new()
	note_label.text = "Build Analytics at HQ to model rival treasury." if depth == 0 else ("Analytics L1 models treasury in $5,000 bands; upgrade to L2 for verified figures." if depth == 1 else "Analytics L2 verifies rival treasury; recipes and staffing remain private.")
	note_label.add_theme_font_size_override("font_size", 12)
	note_label.add_theme_color_override("font_color", INK_MUTED)
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_child(note_label)
	_body.add_child(note)

	add_profile_section("Known branches")
	if company.restaurants.is_empty():
		_body.add_child(_muted_line("No branches yet." if not company.is_bankrupt else "All branches closed."))
	for rest: RestaurantState in company.restaurants:
		var branch: HBoxContainer = HBoxContainer.new()
		branch.add_theme_constant_override("separation", 8)
		var branch_name: Label = Label.new()
		branch_name.text = rest.restaurant_name
		branch_name.add_theme_font_size_override("font_size", 14)
		branch_name.add_theme_color_override("font_color", INK)
		branch_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		branch.add_child(branch_name)
		branch.add_child(TycoonTheme.star_row(rest.star_rating, 14))
		_body.add_child(branch)

	add_profile_section("Recent moves")
	if company.recent_moves.is_empty():
		_body.add_child(_muted_line("Nothing observed yet."))
	var moves: Array[Dictionary] = company.recent_moves.duplicate()
	moves.reverse()
	for move: Dictionary in moves.slice(0, 8):
		_body.add_child(_muted_line("Day %d — %s" % [int(move.get("day", 0)), String(move.get("text", ""))]))


func add_profile_section(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("#8a5a2b"))
	_body.add_child(label)


func _head_to_head(grid: GridContainer, metric: String, yours: String, theirs: String) -> void:
	var you_label: Label = Label.new()
	you_label.text = yours
	you_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	you_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	you_label.add_theme_font_size_override("font_size", 14)
	you_label.add_theme_color_override("font_color", INK)
	grid.add_child(you_label)
	var metric_label: Label = Label.new()
	metric_label.text = metric.to_upper()
	metric_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	metric_label.custom_minimum_size = Vector2(120, 0)
	metric_label.add_theme_font_size_override("font_size", 11)
	metric_label.add_theme_color_override("font_color", INK_MUTED)
	grid.add_child(metric_label)
	var them_label: Label = Label.new()
	them_label.text = theirs
	them_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	them_label.add_theme_font_size_override("font_size", 14)
	them_label.add_theme_color_override("font_color", INK_SOFT)
	grid.add_child(them_label)


func _muted_line(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", INK_MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _swatch(color: Color, size_px: int) -> PanelContainer:
	var swatch: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(8)
	box.set_border_width_all(2)
	box.border_color = Color("#6E3D18")
	swatch.add_theme_stylebox_override("panel", box)
	swatch.custom_minimum_size = Vector2(size_px, size_px)
	return swatch


func _analytics_depth() -> int:
	if CompanyManager.player == null:
		return 0
	return CapabilityRegistry.level(CompanyManager.player.id, &"analytics.report_depth")


func _intel_treasury(company: CompanyState) -> String:
	var depth: int = _analytics_depth()
	if depth >= 2:
		return "$%s (verified)" % _fmt_thousands(company.cash)
	if depth == 1:
		return "~$%s (modeled)" % _fmt_thousands(snappedf(company.cash, 5000.0))
	return "?  unknown"


func _fmt_thousands(value: float) -> String:
	var raw: String = "%.0f" % maxf(0.0, value)
	var out: String = ""
	var count: int = 0
	for i: int in range(raw.length() - 1, -1, -1):
		out = raw[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
