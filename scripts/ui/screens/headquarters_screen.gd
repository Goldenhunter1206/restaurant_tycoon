extends TycoonScreen
## Company headquarters dashboard. The persistent frame lives in the scene;
## tab contents are rebuilt from authoritative manager state.

signal request_screen(screen_id: StringName)

const INK: Color = Color("#3a2010")
const INK_SOFT: Color = Color("#6e4326")
const MUTED: Color = Color("#9a7245")
const RED: Color = Color("#c7331c")
const GREEN: Color = Color("#4e8f27")

@onready var _company_title: Label = $Paper/Workspace/Root/Header/CompanyTitle
@onready var _tier_label: Label = $Paper/Workspace/Root/Header/TierPill/TierLabel
@onready var _upkeep_label: Label = $Paper/Workspace/Root/Header/UpkeepPill/UpkeepLabel
@onready var _close_button: Button = $Paper/Workspace/Root/Header/CloseButton
@onready var _tab_row: HBoxContainer = $Paper/Workspace/Root/TabScroll/TabRow
@onready var _body: VBoxContainer = $Paper/Workspace/Root/BodyPanel/BodyMargin/BodyScroll/Body
@onready var _status: Label = $Paper/Workspace/Root/Status
@onready var _confirm: ConfirmationDialog = $Confirm

var _active_tab: StringName = &"overview"
var _tab_buttons: Dictionary = {}
var _status_text: String = ""
var _pending_action: StringName
var _pending_department: StringName
var _refresh_elapsed: float = 0.0


func screen_title() -> String:
	return "Headquarters"


func screen_icon() -> StringName:
	return &"house"


func wants_spring_open() -> bool:
	return true


func setup(target_building_id: int) -> void:
	building_id = target_building_id
	_apply_responsive_size()
	var viewport: Viewport = get_viewport()
	if not viewport.size_changed.is_connected(_apply_responsive_size):
		viewport.size_changed.connect(_apply_responsive_size)
	add_theme_stylebox_override("panel", TycoonTheme.wood_frame_lg_box())
	$Paper.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		$Paper/Workspace.add_theme_constant_override(side, 18)
		$Paper/Workspace/Root/BodyPanel/BodyMargin.add_theme_constant_override(side, 14)
	$Paper/Workspace/Root/BodyPanel.add_theme_stylebox_override("panel", BellaUi.sunk_box(14))
	_style_badge($Paper/Workspace/Root/Header/TierPill, Color("#f2b72d"), Color("#b5810a"))
	_style_badge($Paper/Workspace/Root/Header/UpkeepPill, Color("#f6e4b0"), Color("#d3a847"))
	_close_button.custom_minimum_size = Vector2(48, 48)
	_close_button.pressed.connect(func() -> void: closed.emit())
	_tactile(_close_button)
	_confirm.confirmed.connect(_on_confirmed)
	_build_tabs()
	var manager: Node = _manager()
	if manager != null:
		manager.headquarters_changed.connect(_on_headquarters_changed)
		manager.project_started.connect(_on_project_event)
		manager.project_completed.connect(_on_project_event)
	refresh()
	set_process(true)


func _apply_responsive_size() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	custom_minimum_size = Vector2(
		minf(1220.0, maxf(760.0, viewport_size.x - 48.0)),
		minf(720.0, maxf(560.0, viewport_size.y - 48.0))
	)


func refresh() -> void:
	var company: CompanyState = CompanyManager.player
	if company == null:
		return
	var state: HeadquartersState = _state()
	var definition: HeadquartersTierDef = _manager().call("tier_def", state.tier) as HeadquartersTierDef
	_company_title.text = "%s Headquarters" % company.display_name
	_tier_label.text = "TIER %d  ·  %s" % [state.tier, definition.display_name]
	_upkeep_label.text = "$%d / DAY" % roundi(float(_manager().call("upkeep_for", company.id)))
	_status.text = _status_text
	_refresh_tabs(state)
	_render_active_tab(state)


func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed < 1.0:
		return
	_refresh_elapsed = 0.0
	var state: HeadquartersState = _state()
	if state != null and state.has_active_project():
		refresh()


func _build_tabs() -> void:
	var tabs: Array[Dictionary] = [
		{"id": &"overview", "text": "OVERVIEW"},
		{"id": &"departments", "text": "DEPARTMENTS"},
		{"id": &"upgrades", "text": "UPGRADES"},
		{"id": &"procurement", "text": "PROCUREMENT"},
		{"id": &"analytics", "text": "ANALYTICS"},
		{"id": &"managers", "text": "MANAGERS & POLICIES"},
		{"id": &"training", "text": "TRAINING",
			"lock": "Requires a Tier 2 headquarters and the Staff Training feature."},
		{"id": &"security", "text": "SECURITY",
			"lock": "Requires a Tier 2 headquarters and the Security feature."},
		{"id": &"government", "text": "GOVERNMENT RELATIONS"},
	]
	for tab: Dictionary in tabs:
		var button: Button = Button.new()
		button.text = String(tab["text"])
		button.custom_minimum_size = Vector2(0, 46)
		button.pressed.connect(_select_tab.bind(StringName(tab["id"])))
		button.set_meta("lock", String(tab.get("lock", "")))
		_tactile(button)
		_tab_row.add_child(button)
		_tab_buttons[StringName(tab["id"])] = button


func _refresh_tabs(state: HeadquartersState) -> void:
	for id_variant: Variant in _tab_buttons:
		var id: StringName = id_variant
		var button: Button = _tab_buttons[id]
		BellaUi.style_chip(button, id == _active_tab)
		var lock_message: String = String(button.get_meta("lock", ""))
		button.disabled = not lock_message.is_empty()
		button.tooltip_text = lock_message
		if id == &"procurement" and state.tier < 3:
			button.tooltip_text = "Procurement requires headquarters Tier 3."
		if id == &"analytics" and state.tier < 2:
			button.tooltip_text = "Analytics requires headquarters Tier 2."
		if id == &"government":
			var gov: Node = get_tree().root.get_node_or_null(^"GovernmentManager")
			var gov_on: bool = gov != null and bool(gov.call("enabled"))
			button.disabled = not gov_on
			button.tooltip_text = "Opens City Hall." if gov_on \
				else "The civic layer is disabled in this game."


func _select_tab(tab_id: StringName) -> void:
	if tab_id == &"managers":
		request_screen.emit(&"company.managers")
		return
	if tab_id == &"government":
		request_screen.emit(&"city_hall")
		return
	if _active_tab == tab_id:
		return
	_active_tab = tab_id
	refresh()
	_body.modulate.a = 0.0
	create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).tween_property(
		_body, "modulate:a", 1.0, 0.16)


func _render_active_tab(state: HeadquartersState) -> void:
	_clear_body()
	match _active_tab:
		&"departments":
			_render_departments(state)
		&"upgrades":
			_render_upgrades(state)
		&"procurement":
			_render_procurement(state)
		&"analytics":
			_render_analytics(state)
		_:
			_render_overview(state)


func _render_overview(state: HeadquartersState) -> void:
	if state.tier == 0:
		_render_founder_overview(state)
		return
	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	heading.add_child(_section_title("DEPARTMENTS"))
	var capacity: Label = _muted("CAPACITY  %d / %d" % [
		int(_manager().call("capacity_used", CompanyManager.player.id)),
		int(_manager().call("slots_for", CompanyManager.player.id))])
	capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	capacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(capacity)
	_body.add_child(heading)

	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_body.add_child(grid)
	for definition: DepartmentDef in _manager().call("department_defs"):
		_add_department_card(grid, state, definition, true)

	var project: UpgradeProjectState = state.active_project()
	if project != null:
		_add_project_panel(project)
	else:
		var action: VBoxContainer = _panel_stack(_body)
		action.add_child(_section_title("NEXT UNLOCK"))
		action.add_child(_body_text(String(_manager().call("next_unlock_text", CompanyManager.player.id))))
		if state.tier < 3:
			var next_tier: HeadquartersTierDef = _manager().call("tier_def", state.tier + 1) as HeadquartersTierDef
			var upgrade: Button = _action_button("UPGRADE TO %s  ·  $%s" % [
				next_tier.display_name.to_upper(), _money(next_tier.project_cost)])
			upgrade.pressed.connect(_start_tier_upgrade)
			action.add_child(upgrade)


func _render_founder_overview(state: HeadquartersState) -> void:
	_body.add_child(_section_title("ESTABLISH YOUR COMPANY HEADQUARTERS"))
	_body.add_child(_body_text(
		"Claim an eligible office to unlock one specialization slot. Your restaurants keep every existing chain unlock; headquarters adds strategic capacity."))
	var project: UpgradeProjectState = state.active_project()
	if project != null:
		_add_project_panel(project)
		return
	var offices: Array = _manager().call("eligible_buildings", CompanyManager.player.id)
	if offices.is_empty():
		var empty: VBoxContainer = _panel_stack(_body)
		empty.add_child(_body_text("No eligible office is currently available."))
		return
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_body.add_child(grid)
	for info_variant: Variant in offices.slice(0, 8):
		var info: Dictionary = info_variant
		var stack: VBoxContainer = _panel_stack(grid)
		stack.add_child(_section_title("OFFICE  #%d" % int(info.get("id", -1))))
		stack.add_child(_muted("%s DISTRICT  ·  AVAILABLE" % String(info.get("district", "CITY"))))
		stack.add_child(_body_text("$6,000 capital  ·  2 days  ·  $80/day"))
		var acquire: Button = _action_button("BUILD HEADQUARTERS")
		acquire.pressed.connect(_start_acquisition.bind(int(info.get("id", -1))))
		stack.add_child(acquire)


func _render_departments(state: HeadquartersState) -> void:
	_body.add_child(_section_title("DEPARTMENT SPECIALIZATION"))
	_body.add_child(_body_text(
		"Each completed level consumes one slot. Higher levels compete directly with a broader organization."))
	var capacity: Label = _muted("USED %d OF %d SLOTS" % [
		int(_manager().call("capacity_used", CompanyManager.player.id)),
		int(_manager().call("slots_for", CompanyManager.player.id))])
	_body.add_child(capacity)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_body.add_child(grid)
	for definition: DepartmentDef in _manager().call("department_defs"):
		_add_department_card(grid, state, definition, false)


func _add_department_card(parent: Container, state: HeadquartersState,
		definition: DepartmentDef, compact: bool) -> void:
	var stack: VBoxContainer = _panel_stack(parent)
	var level: int = state.department_level(definition.id)
	var title: String = "%s  ·  LEVEL %d" % [definition.display_name.to_upper(), level]
	stack.add_child(_section_title(title))
	stack.add_child(_body_text(definition.description))
	stack.add_child(_muted(_department_effect(definition.id, level)))
	if compact:
		return
	var next_level: int = level + 1
	if next_level <= definition.max_level():
		stack.add_child(_muted("NEXT  $%s  ·  %d DAYS  ·  $%d/DAY TOTAL" % [
			_money(definition.cost_for(next_level)),
			ceili(float(definition.minutes_for(next_level)) / 1440.0),
			roundi(definition.upkeep_for(next_level))]))
		var build: Button = _action_button("BUILD" if level == 0 else "UPGRADE TO LEVEL %d" % next_level)
		var required_tier: int = definition.required_tier_for(next_level)
		if state.tier < required_tier:
			_lock_button(build, "%s Level %d requires headquarters Tier %d." % [
				definition.display_name, next_level, required_tier])
		elif state.has_active_project():
			_lock_button(build, "Only one headquarters construction project can run at a time.")
		elif int(_manager().call("capacity_used", CompanyManager.player.id, false)) + 1 > int(
				_manager().call("slots_for", CompanyManager.player.id)):
			_lock_button(build, "No department capacity remains at this headquarters tier.")
		build.pressed.connect(_start_department.bind(definition.id))
		stack.add_child(build)
	else:
		var complete: Label = _muted("MAXIMUM LEVEL")
		complete.add_theme_color_override("font_color", GREEN)
		stack.add_child(complete)
	if level > 0:
		var remove: Button = _secondary_button("DECOMMISSION  ·  REFUND 20%")
		remove.pressed.connect(_ask_decommission.bind(definition.id, definition.display_name))
		stack.add_child(remove)


func _render_upgrades(state: HeadquartersState) -> void:
	_body.add_child(_section_title("HEADQUARTERS TIER ROADMAP"))
	for tier: int in range(1, 4):
		var definition: HeadquartersTierDef = _manager().call("tier_def", tier) as HeadquartersTierDef
		var stack: VBoxContainer = _panel_stack(_body)
		var status: String = "CURRENT" if tier == state.tier else ("COMPLETE" if tier < state.tier else "LOCKED")
		stack.add_child(_section_title("TIER %d  ·  %s  ·  %s" % [tier, definition.display_name.to_upper(), status]))
		stack.add_child(_body_text("%d restaurants  ·  $%s  ·  %d days  ·  %d slots  ·  $%d/day" % [
			definition.min_restaurants, _money(definition.project_cost),
			ceili(float(definition.project_minutes) / 1440.0), definition.department_slots,
			roundi(definition.base_upkeep)]))
	if state.active_project() != null:
		_add_project_panel(state.active_project())
	elif state.tier > 0 and state.tier < 3:
		var upgrade: Button = _action_button("START NEXT TIER UPGRADE")
		upgrade.pressed.connect(_start_tier_upgrade)
		_body.add_child(upgrade)
	if state.tier > 0:
		var sale: Button = _secondary_button("SELL HEADQUARTERS  ·  REFUND 35%")
		if state.has_active_project():
			_lock_button(sale, "Cancel the active project before selling headquarters.")
		sale.pressed.connect(_ask_sale)
		_body.add_child(sale)


func _render_procurement(state: HeadquartersState) -> void:
	_body.add_child(_section_title("PROCUREMENT CAPACITY"))
	var stack: VBoxContainer = _panel_stack(_body)
	var owned: int = 0
	for warehouse: WarehouseState in SupplyManager.warehouses:
		if warehouse.company_id == CompanyManager.player.id:
			owned += 1
	var limit: int = int(_manager().call("warehouse_limit", CompanyManager.player.id))
	stack.add_child(_section_title("%d OF %d WAREHOUSES" % [owned, limit]))
	stack.add_child(_body_text(
		"Your existing basic allowance remains active. Procurement L1 raises the numeric limit by 1; L2 raises it by 2. Existing legacy warehouses keep operating if over limit."))
	stack.add_child(_muted(_department_effect(&"procurement", state.department_level(&"procurement"))))
	var open_supply: Button = _action_button("OPEN SUPPLIERS & WAREHOUSES")
	open_supply.pressed.connect(func() -> void: request_screen.emit(&"suppliers"))
	stack.add_child(open_supply)


func _render_analytics(state: HeadquartersState) -> void:
	_body.add_child(_section_title("COMPANY ANALYTICS"))
	var stack: VBoxContainer = _panel_stack(_body)
	var depth: int = int(_manager().call("analytics_depth", CompanyManager.player.id))
	stack.add_child(_section_title("REPORT DEPTH  %d" % depth))
	stack.add_child(_body_text("Treasury  $%s  ·  HQ upkeep  $%d/day  ·  Portfolio  %d restaurants" % [
		_money(CompanyManager.player.cash),
		roundi(float(_manager().call("upkeep_for", CompanyManager.player.id))),
		CompanyManager.player.restaurants.size()]))
	stack.add_child(_body_text(
		"Build Analytics L1 to model rival treasury in $5,000 bands. Level 2 verifies the exact figure in Rankings."
		if depth == 0 else ("Rival treasury is modeled in $5,000 bands; Level 2 verifies it."
		if depth == 1 else "Rival treasury is verified in Rankings.")))
	var rankings: Button = _action_button("OPEN RANKINGS INTELLIGENCE")
	rankings.pressed.connect(func() -> void: request_screen.emit(&"rankings"))
	stack.add_child(rankings)


func _add_project_panel(project: UpgradeProjectState) -> void:
	var stack: VBoxContainer = _panel_stack(_body)
	stack.add_child(_section_title("ACTIVE PROJECT  ·  %s" % String(_manager().call("project_label", project)).to_upper()))
	var progress: float = project.progress_at(GameClock.total_minutes())
	var bar: ProgressBar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 32)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = progress * 100.0
	bar.show_percentage = true
	stack.add_child(bar)
	var remaining_days: float = float(project.remaining_minutes(GameClock.total_minutes())) / 1440.0
	var refund: float = project.paid_amount * (1.0 - progress) * 0.5
	stack.add_child(_muted("%.1f days remaining  ·  cancel refund $%s" % [remaining_days, _money(refund)]))
	var cancel: Button = _secondary_button("CANCEL PROJECT")
	cancel.pressed.connect(_cancel_project.bind(project.id))
	stack.add_child(cancel)


func _department_effect(department_id: StringName, level: int) -> String:
	match department_id:
		&"operations":
			return "Portfolio alert and detail depth %d" % level
		&"marketing":
			return "Campaign capacity +%d%s" % [
				int(CapabilityRegistry.capacity(CompanyManager.player.id, &"marketing.campaign_slots")),
				"  ·  billboard enabled" if level >= 2 else ""]
		&"analytics":
			return "HQ and Rankings report depth %d" % level
		&"procurement":
			return "Warehouse capacity +%d above the basic allowance" % int(
				CapabilityRegistry.capacity(CompanyManager.player.id, &"procurement.warehouse_count"))
	return "No active grants"


func _start_acquisition(office_id: int) -> void:
	_apply_result(_manager().call("start_acquisition_cmd", CompanyManager.player.id, office_id) as CommandResult)


func _start_tier_upgrade() -> void:
	_apply_result(_manager().call("start_tier_upgrade_cmd", CompanyManager.player.id) as CommandResult)


func _start_department(department_id: StringName) -> void:
	_apply_result(_manager().call("start_department_project_cmd",
		CompanyManager.player.id, department_id) as CommandResult)


func _cancel_project(project_id: int) -> void:
	_apply_result(_manager().call("cancel_project_cmd", CompanyManager.player.id, project_id) as CommandResult)


func _ask_decommission(department_id: StringName, display_name: String) -> void:
	_pending_action = &"decommission"
	_pending_department = department_id
	_confirm.title = "Decommission %s?" % display_name
	_confirm.dialog_text = "This is immediate. All department capability grants are removed and 20% of completed capital is refunded."
	_confirm.popup_centered(Vector2i(560, 220))


func _ask_sale() -> void:
	_pending_action = &"sale"
	_pending_department = &""
	_confirm.title = "Sell headquarters?"
	_confirm.dialog_text = "All departments and headquarters grants are removed. The office is released and 35% of completed HQ capital is refunded."
	_confirm.popup_centered(Vector2i(560, 220))


func _on_confirmed() -> void:
	if _pending_action == &"decommission":
		_apply_result(_manager().call("decommission_department_cmd",
			CompanyManager.player.id, _pending_department) as CommandResult)
	elif _pending_action == &"sale":
		_apply_result(_manager().call("sell_headquarters_cmd", CompanyManager.player.id) as CommandResult)
	_pending_action = &""
	_pending_department = &""


func _apply_result(result: CommandResult) -> void:
	if result == null:
		_status_text = "Headquarters command was unavailable."
	elif result.ok:
		_status_text = "Headquarters updated."
	else:
		# Command messages are deliberately shown unchanged.
		_status_text = result.message
	refresh()


func _on_headquarters_changed(company_id: StringName) -> void:
	if CompanyManager.player != null and company_id == CompanyManager.player.id:
		refresh()


func _on_project_event(company_id: StringName, _project: UpgradeProjectState) -> void:
	_on_headquarters_changed(company_id)


func _state() -> HeadquartersState:
	return _manager().call("state_for", CompanyManager.player.id) as HeadquartersState


func _manager() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("HeadquartersManager")


func _clear_body() -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


func _panel_stack(parent: Container) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", BellaUi.tile_box(Color("#d3a847"), 2))
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 7)
	margin.add_child(stack)
	parent.add_child(panel)
	return stack


func _section_title(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", INK)
	return label


func _body_text(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", INK_SOFT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _muted(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _action_button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	BellaUi.green_button(button)
	_tactile(button)
	return button


func _secondary_button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 46)
	BellaUi.style_chip(button, false)
	_tactile(button)
	return button


func _lock_button(button: Button, message: String) -> void:
	button.disabled = true
	button.tooltip_text = message


func _tactile(button: Button) -> void:
	button.button_down.connect(func() -> void:
		button.pivot_offset = button.size * 0.5
		button.scale = Vector2(0.97, 0.97))
	button.button_up.connect(func() -> void:
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(
			button, "scale", Vector2.ONE, 0.09))


func _style_badge(panel: PanelContainer, fill: Color, edge: Color) -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(18)
	box.set_border_width_all(2)
	box.border_color = edge
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", box)


func _money(value: float) -> String:
	var raw: String = "%.0f" % maxf(0.0, value)
	var out: String = ""
	var count: int = 0
	for i: int in range(raw.length() - 1, -1, -1):
		out = raw[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
