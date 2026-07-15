extends TycoonScreen
## Marketing workspace: Active · Create · Placements · Results. The Create tab
## is a step wizard (Channel → Placement → Audience → Message → Budget) with a
## live reach-preview rail; everything routes through the same
## MarketingManager commands the rival AI uses.

const INK: Color = Color("#3A2010")
const INK_SOFT: Color = Color("#6E4326")
const INK_MUTED: Color = Color("#9A7245")
const CREAM: Color = Color("#FFF4DC")
const WOOD_RAIL: Color = Color("#A8692A")
const WOOD_EDGE: Color = Color("#6E3D18")
const GREEN_DONE: Color = Color("#6FB63A")
const RED_CURRENT: Color = Color("#EA4A2F")
const GOLD_DEEP: Color = Color("#B5810A")

const SEGMENT_ICONS: Dictionary = {
	&"teens": &"teen", &"students": &"student", &"workers": &"worker",
	&"families": &"family", &"seniors": &"senior",
}
const DISTRICT_NAMES: Dictionary = {
	"C": "City Center", "D": "Downtown", "N": "Neighborhood",
	"R": "Riverside", "P": "Park quarter", "I": "Industry",
}
const CLAIMS: Array = [
	[&"", "No claim"],
	[&"lowest_price", "Lowest prices"],
	[&"best_staff", "Best staff"],
	[&"highest_quality", "Highest quality"],
]
const RENT_DAYS: int = 14

var _tabs: TabContainer
var _active_list: VBoxContainer
var _placements_list: VBoxContainer
var _results_list: VBoxContainer
var _create_page: HBoxContainer
var _create_body: VBoxContainer
var _step_strip: HBoxContainer

# Preview rail widgets (updated live, never rebuilt).
var _reach: ReachPreview
var _cost_reach: Label
var _cost_duration: Label
var _cost_budget: Label
var _cost_fit: Label
var _back_btn: Button
var _next_btn: Button

# Create-wizard state.
var _step: int = 0
var _sel_channel: StringName = &"flyer"
var _sel_placements: Array[int] = []
var _sel_segments: Array[StringName] = []
var _message_text: String = ""
var _sel_claim: StringName = &""
var _sel_recipe: StringName = &""
var _sel_rival: StringName = &""
var _intensity: float = 1.0
var _duration: int = 7
var _command_serial: int = 0


func screen_title() -> String:
	return "Marketing"


func screen_icon() -> StringName:
	return &"megaphone"


func _build() -> void:
	custom_minimum_size = Vector2(960, 640)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_tabs)
	_active_list = _make_tab_list("Active")
	_create_page = HBoxContainer.new()
	_create_page.name = "Create"
	_create_page.add_theme_constant_override("separation", 14)
	_tabs.add_child(_create_page)
	_build_create_shell()
	_placements_list = _make_tab_list("Placements")
	_results_list = _make_tab_list("Results")
	BellaUi.style_tabs(_tabs)
	# Connect AFTER all tabs exist — tab_changed fires on the first add.
	_tabs.tab_changed.connect(func(_tab: int) -> void: refresh())
	MarketingManager.campaigns_changed.connect(refresh)
	MarketingManager.placements_changed.connect(refresh)
	MarketingManager.trends_changed.connect(refresh)


func refresh() -> void:
	if not is_inside_tree():
		return
	match _tabs.current_tab:
		0:
			_refresh_active()
		1:
			_refresh_preview()
		2:
			_refresh_placements()
		3:
			_refresh_results()


# --- Active tab ---------------------------------------------------------------


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


func _refresh_active() -> void:
	_clear(_active_list)
	var campaigns: Array[MarketingCampaign] = MarketingManager.campaigns_for(&"player")
	var slots: int = CapabilityRegistry.campaign_slots(&"player")
	_heading(_active_list, "Your campaigns (%d/%d slots)" % [campaigns.size(), slots])
	if campaigns.is_empty():
		_active_list.add_child(_empty_state())
		return
	for campaign: MarketingCampaign in campaigns:
		_active_list.add_child(_campaign_card(campaign))


## Design "No campaigns yet" empty state.
func _empty_state() -> Control:
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(0, 300)
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.sunk_box(16))
	card.custom_minimum_size = Vector2(340, 210)
	center.add_child(card)
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var icon: TextureRect = UiAssets.icon_rect(&"megaphone", 40)
	if icon != null:
		icon.modulate.a = 0.7
		var holder: CenterContainer = CenterContainer.new()
		holder.add_child(icon)
		box.add_child(holder)
	var title: Label = Label.new()
	title.text = "No campaigns yet"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", INK)
	box.add_child(title)
	var sub: Label = Label.new()
	sub.text = "Run your first campaign to bring in more guests."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", INK_MUTED)
	box.add_child(sub)
	var cta: Button = Button.new()
	cta.text = "Create campaign"
	cta.custom_minimum_size = Vector2(180, 40)
	BellaUi.green_button(cta)
	cta.pressed.connect(func() -> void: _tabs.current_tab = 1)
	var cta_holder: CenterContainer = CenterContainer.new()
	cta_holder.add_child(cta)
	box.add_child(cta_holder)
	return center


func _campaign_card(campaign: MarketingCampaign) -> Control:
	var def: MarketingChannelDef = MarketingManager.channel(campaign.channel_id)
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.tile_box())
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)
	var icon: TextureRect = UiAssets.icon_rect(def.icon if def != null else "megaphone", 26)
	if icon != null:
		top.add_child(icon)
	var name_label: Label = Label.new()
	name_label.text = _campaign_title(campaign)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var days: Label = Label.new()
	days.text = "%d day%s left" % [campaign.days_left, "" if campaign.days_left == 1 else "s"]
	days.add_theme_font_size_override("font_size", 12)
	days.add_theme_color_override("font_color", INK_SOFT)
	top.add_child(days)
	var stop: Button = Button.new()
	stop.text = "Stop"
	stop.pressed.connect(_stop_campaign.bind(campaign))
	top.add_child(stop)
	var pills: HBoxContainer = HBoxContainer.new()
	pills.add_theme_constant_override("separation", 6)
	box.add_child(pills)
	pills.add_child(BellaUi.pill(_audience_text(campaign), INK_SOFT, BellaUi.PAPER_SUNK, BellaUi.PAPER_EDGE))
	pills.add_child(BellaUi.pill("$%.0f/day" % campaign.cost_per_day, GOLD_DEEP, BellaUi.PAPER_SUNK, BellaUi.PAPER_EDGE))
	if campaign.claim != &"":
		var truthful: bool = campaign.credibility >= 0.99
		pills.add_child(BellaUi.pill(
			_claim_label(campaign.claim) + ("" if truthful else " — reads false!"),
			Color.WHITE if not truthful else INK_SOFT,
			RED_CURRENT if not truthful else BellaUi.PAPER_SUNK,
			BellaUi.RED_EDGE if not truthful else BellaUi.PAPER_EDGE))
	if campaign.promoted_recipe != &"":
		pills.add_child(BellaUi.pill("Promotes %s" % _recipe_label(campaign.promoted_recipe),
			INK_SOFT, BellaUi.PAPER_SUNK, BellaUi.PAPER_EDGE))
	var meter: HBoxContainer = HBoxContainer.new()
	meter.add_theme_constant_override("separation", 8)
	box.add_child(meter)
	var eff: Label = Label.new()
	eff.text = "Effect %d%%  ·  Fatigue %d%%  ·  Spend $%.0f" % [
		roundi(campaign.effectiveness * 100.0), roundi(campaign.fatigue * 100.0),
		campaign.total_spend]
	eff.add_theme_font_size_override("font_size", 12)
	eff.add_theme_color_override("font_color", INK_MUTED)
	meter.add_child(eff)
	return card


func _campaign_title(campaign: MarketingCampaign) -> String:
	var def: MarketingChannelDef = MarketingManager.channel(campaign.channel_id)
	var channel_name: String = def.display_name if def != null else String(campaign.channel_id)
	if not campaign.placement_ids.is_empty():
		var site: AdPlacement = MarketingManager.placement(campaign.placement_ids[0])
		if site != null:
			return "%s · %s" % [channel_name, DISTRICT_NAMES.get(site.district, site.district)]
	var rest: RestaurantState = RestaurantManager.by_building.get(campaign.building_id)
	if rest != null:
		return "%s · %s" % [channel_name, rest.restaurant_name]
	return "%s · citywide" % channel_name


func _audience_text(campaign: MarketingCampaign) -> String:
	var wanted: Array[StringName] = campaign.segments()
	if wanted.is_empty():
		return "Everyone"
	var names: Array[String] = []
	for segment: StringName in wanted:
		names.append(String(segment).capitalize())
	return ", ".join(names)


# --- Create tab -----------------------------------------------------------------


func _build_create_shell() -> void:
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	_create_page.add_child(left)
	_step_strip = HBoxContainer.new()
	_step_strip.add_theme_constant_override("separation", 6)
	left.add_child(_step_strip)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_create_body = VBoxContainer.new()
	_create_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_create_body)
	_create_page.add_child(_build_preview_rail())
	_rebuild_create()


## Right rail: LIVE REACH PREVIEW + cost card + Back/Next (design D4).
func _build_preview_rail() -> Control:
	var rail: PanelContainer = PanelContainer.new()
	var rail_style: StyleBoxFlat = StyleBoxFlat.new()
	rail_style.bg_color = WOOD_RAIL
	rail_style.border_color = WOOD_EDGE
	rail_style.set_border_width_all(3)
	rail_style.set_corner_radius_all(14)
	rail_style.set_content_margin_all(14.0)
	rail.add_theme_stylebox_override("panel", rail_style)
	rail.custom_minimum_size = Vector2(320, 0)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	rail.add_child(box)
	var eyebrow: Label = Label.new()
	eyebrow.text = "LIVE REACH PREVIEW"
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", CREAM)
	box.add_child(eyebrow)
	var map_frame: PanelContainer = PanelContainer.new()
	var map_style: StyleBoxFlat = StyleBoxFlat.new()
	map_style.bg_color = Color("#4A8535")
	map_style.border_color = WOOD_EDGE
	map_style.set_border_width_all(3)
	map_style.set_corner_radius_all(14)
	map_frame.add_theme_stylebox_override("panel", map_style)
	box.add_child(map_frame)
	_reach = ReachPreview.new()
	_reach.custom_minimum_size = Vector2(0, 150)
	map_frame.add_child(_reach)
	var cost_card: PanelContainer = PanelContainer.new()
	cost_card.add_theme_stylebox_override("panel", BellaUi.tile_box())
	box.add_child(cost_card)
	var cost_box: VBoxContainer = VBoxContainer.new()
	cost_box.add_theme_constant_override("separation", 6)
	cost_card.add_child(cost_box)
	_cost_reach = _cost_row(cost_box, "Est. reach")
	_cost_duration = _cost_row(cost_box, "Duration")
	_cost_fit = _cost_row(cost_box, "Message fit")
	_cost_budget = _cost_row(cost_box, "Budget")
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_back_btn = Button.new()
	_back_btn.text = "Back"
	_back_btn.custom_minimum_size = Vector2(80, 44)
	_back_btn.pressed.connect(func() -> void:
		_step = maxi(_step - 1, 0)
		_rebuild_create())
	buttons.add_child(_back_btn)
	_next_btn = Button.new()
	_next_btn.custom_minimum_size = Vector2(0, 44)
	_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	TycoonTheme.apply_orange(_next_btn)
	_next_btn.add_theme_color_override("font_color", Color.WHITE)
	_next_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	_next_btn.pressed.connect(_on_next)
	buttons.add_child(_next_btn)
	return rail


func _steps() -> Array[String]:
	var def: MarketingChannelDef = MarketingManager.channel(_sel_channel)
	var steps: Array[String] = ["Channel"]
	if def != null and def.needs_placement:
		steps.append("Placement")
	steps.append_array(["Audience", "Message", "Budget"])
	return steps


func _rebuild_create() -> void:
	_clear(_create_body)
	_rebuild_step_strip()
	var steps: Array[String] = _steps()
	_step = clampi(_step, 0, steps.size() - 1)
	match steps[_step]:
		"Channel":
			_build_channel_step()
		"Placement":
			_build_placement_step()
		"Audience":
			_build_audience_step()
		"Message":
			_build_message_step()
		"Budget":
			_build_budget_step()
	_refresh_preview()


func _rebuild_step_strip() -> void:
	_clear(_step_strip)
	var steps: Array[String] = _steps()
	for i: int in steps.size():
		if i > 0:
			var sep: Label = Label.new()
			sep.text = "›"
			sep.add_theme_color_override("font_color", INK_MUTED)
			_step_strip.add_child(sep)
		var dot: PanelContainer = PanelContainer.new()
		var dot_style: StyleBoxFlat = StyleBoxFlat.new()
		dot_style.set_corner_radius_all(999)
		dot_style.content_margin_left = 8.0
		dot_style.content_margin_right = 8.0
		dot_style.content_margin_top = 2.0
		dot_style.content_margin_bottom = 2.0
		if i < _step:
			dot_style.bg_color = GREEN_DONE
		elif i == _step:
			dot_style.bg_color = RED_CURRENT
		else:
			dot_style.bg_color = BellaUi.PAPER_SUNK
		dot.add_theme_stylebox_override("panel", dot_style)
		var dot_label: Label = Label.new()
		dot_label.text = ("✓ " + steps[i]) if i < _step else steps[i]
		dot_label.add_theme_font_size_override("font_size", 11)
		dot_label.add_theme_color_override("font_color",
			Color.WHITE if i <= _step else INK_MUTED)
		dot.add_child(dot_label)
		_step_strip.add_child(dot)


func _build_channel_step() -> void:
	_heading(_create_body, "Pick a channel")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_create_body.add_child(grid)
	for def: MarketingChannelDef in MarketingManager.channel_list():
		grid.add_child(_channel_card(def))


func _channel_card(def: MarketingChannelDef) -> Control:
	var locked_why: String = CapabilityRegistry.explain(&"player", def.required_capability)
	var selected: bool = _sel_channel == def.id
	var card: Button = Button.new()
	card.custom_minimum_size = Vector2(280, 92)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.disabled = locked_why != ""
	var style: StyleBoxFlat = BellaUi.tile_box(
		Color("#F47B10") if selected else BellaUi.PAPER_EDGE, 3 if selected else 2)
	if locked_why != "":
		style.bg_color = BellaUi.PAPER_SUNK
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		card.add_theme_stylebox_override(state, style)
	card.pressed.connect(func() -> void:
		_sel_channel = def.id
		_sel_placements.clear()
		_step += 1
		_rebuild_create())
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	var icon: TextureRect = UiAssets.icon_rect(def.icon, 32)
	if icon != null:
		if locked_why != "":
			icon.modulate.a = 0.45
		row.add_child(icon)
	var text_box: VBoxContainer = VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_box)
	var title: Label = Label.new()
	title.text = def.display_name
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", INK if locked_why == "" else INK_MUTED)
	text_box.add_child(title)
	var sub: Label = Label.new()
	sub.text = locked_why if locked_why != "" else "%s · $%.0f/day%s" % [
		"Citywide" if def.scope == &"citywide" else "Local",
		def.cost_per_day,
		(" · $%.0f setup" % def.setup_cost) if def.setup_cost > 0.0 else ""]
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", INK_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(sub)
	return card


func _build_placement_step() -> void:
	_heading(_create_body, "Pick a billboard site")
	var hint: Label = Label.new()
	hint.text = "Rented sites bill $/day separately; the campaign advertises around the sign. Check the minimap's Marketing layer to scout locations."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", INK_SOFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_create_body.add_child(hint)
	for site: AdPlacement in MarketingManager.placements:
		var mine: bool = site.owner_company == &"player"
		if not site.vacant() and not mine:
			continue
		var row: PanelContainer = PanelContainer.new()
		var chosen: bool = _sel_placements.has(site.id)
		row.add_theme_stylebox_override("panel", BellaUi.tile_box(
			Color("#F47B10") if chosen else BellaUi.PAPER_EDGE, 3 if chosen else 2))
		_create_body.add_child(row)
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		row.add_child(line)
		var info: Label = Label.new()
		info.text = "Site %d · %s · rent $%.0f/day%s" % [site.id,
			DISTRICT_NAMES.get(site.district, site.district), site.rent_per_day,
			(" · rented, %d days left" % site.days_left) if mine else ""]
		info.add_theme_font_size_override("font_size", 13)
		info.add_theme_color_override("font_color", INK)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(info)
		var pick: Button = Button.new()
		pick.text = "Chosen" if chosen else "Choose"
		pick.disabled = chosen
		var site_id: int = site.id
		pick.pressed.connect(func() -> void:
			_sel_placements = [site_id]
			_step += 1
			_rebuild_create())
		line.add_child(pick)


func _build_audience_step() -> void:
	_heading(_create_body, "Who should see it?")
	var share: Dictionary = _segment_share()
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_create_body.add_child(grid)
	for segment: StringName in RecipeManager.SEGMENTS:
		grid.add_child(_segment_card(segment, float(share.get(segment, 0.0))))
	var hint: Label = Label.new()
	hint.text = "No selection targets everyone (broad but weaker fit)."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", INK_MUTED)
	_create_body.add_child(hint)


func _segment_card(segment: StringName, share: float) -> Control:
	var selected: bool = _sel_segments.has(segment)
	var card: Button = Button.new()
	card.custom_minimum_size = Vector2(280, 64)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = BellaUi.tile_box(
		Color("#F47B10") if selected else BellaUi.PAPER_EDGE, 3 if selected else 2)
	if not selected:
		style.bg_color = BellaUi.PAPER_SUNK
	for state: String in ["normal", "hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(state, style)
	card.pressed.connect(func() -> void:
		if _sel_segments.has(segment):
			_sel_segments.erase(segment)
		else:
			_sel_segments.append(segment)
		_rebuild_create())
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	var icon: TextureRect = UiAssets.icon_rect(SEGMENT_ICONS.get(segment, &"people"), 32)
	if icon != null:
		row.add_child(icon)
	var text_box: VBoxContainer = VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_box)
	var title: Label = Label.new()
	title.text = String(segment).capitalize()
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", INK)
	text_box.add_child(title)
	var sub: Label = Label.new()
	sub.text = "%d%% of your traffic" % roundi(share * 100.0)
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", INK_MUTED)
	text_box.add_child(sub)
	var check: Label = Label.new()
	check.text = "✓" if selected else ""
	check.custom_minimum_size = Vector2(24, 0)
	check.add_theme_font_size_override("font_size", 18)
	check.add_theme_color_override("font_color", Color("#F47B10"))
	row.add_child(check)
	return card


func _build_message_step() -> void:
	_heading(_create_body, "What does it say?")
	var msg_label: Label = _field_label("Message")
	_create_body.add_child(msg_label)
	var message: LineEdit = LineEdit.new()
	message.text = _message_text
	message.placeholder_text = "Family night — kids eat free!"
	message.custom_minimum_size = Vector2(0, 40)
	message.text_changed.connect(func(value: String) -> void: _message_text = value)
	_create_body.add_child(message)
	_create_body.add_child(_field_label("Claim (checked against reality — false claims backfire)"))
	var claim_row: HBoxContainer = HBoxContainer.new()
	claim_row.add_theme_constant_override("separation", 6)
	_create_body.add_child(claim_row)
	for option: Array in CLAIMS:
		var claim_id: StringName = option[0]
		var chip: Button = BellaUi.chip(option[1], _sel_claim == claim_id)
		chip.pressed.connect(func() -> void:
			_sel_claim = claim_id
			_rebuild_create())
		claim_row.add_child(chip)
	if _sel_claim != &"":
		var truthful: bool = MarketingManager.claim_check(&"player", _sel_claim)
		var verdict: Label = Label.new()
		verdict.text = "✓ True today — full credibility." if truthful \
			else "✗ Not true today — low credibility, risk of fines."
		verdict.add_theme_font_size_override("font_size", 12)
		verdict.add_theme_color_override("font_color",
			Color("#4E8F27") if truthful else RED_CURRENT)
		_create_body.add_child(verdict)
	_create_body.add_child(_field_label("Promote a recipe (optional — enough buzz starts a city trend)"))
	var recipes: OptionButton = OptionButton.new()
	recipes.add_item("None", 0)
	recipes.set_item_metadata(0, &"")
	var idx: int = 1
	for rec: RecipeDef in RecipeManager.live_recipes():
		recipes.add_item(rec.display_name if "display_name" in rec else String(rec.id), idx)
		recipes.set_item_metadata(idx, rec.id)
		if rec.id == _sel_recipe:
			recipes.selected = idx
		idx += 1
	recipes.item_selected.connect(func(item: int) -> void:
		_sel_recipe = recipes.get_item_metadata(item)
		_refresh_preview())
	_create_body.add_child(recipes)
	var rivals: Array[CompanyState] = CompanyManager.rivals()
	if _sel_claim != &"" and not rivals.is_empty():
		_create_body.add_child(_field_label("Compare against (narrows the claim to one rival — and provokes them)"))
		var rival_pick: OptionButton = OptionButton.new()
		rival_pick.add_item("The whole market", 0)
		rival_pick.set_item_metadata(0, &"")
		var rival_idx: int = 1
		for rival: CompanyState in rivals:
			rival_pick.add_item(rival.display_name, rival_idx)
			rival_pick.set_item_metadata(rival_idx, rival.id)
			if rival.id == _sel_rival:
				rival_pick.selected = rival_idx
			rival_idx += 1
		rival_pick.item_selected.connect(func(item: int) -> void:
			_sel_rival = rival_pick.get_item_metadata(item)
			_refresh_preview())
		_create_body.add_child(rival_pick)


func _build_budget_step() -> void:
	var def: MarketingChannelDef = MarketingManager.channel(_sel_channel)
	if def == null:
		return
	_heading(_create_body, "Budget & duration")
	var intensity_label: Label = _field_label("Intensity ×%.1f — $%.0f/day" % [_intensity, def.cost_per_day * _intensity])
	_create_body.add_child(intensity_label)
	var intensity: HSlider = HSlider.new()
	intensity.min_value = 0.5
	intensity.max_value = 2.0
	intensity.step = 0.25
	intensity.value = _intensity
	intensity.custom_minimum_size = Vector2(280, 24)
	# Update in place — a rebuild would break the drag grab.
	intensity.value_changed.connect(func(value: float) -> void:
		_intensity = value
		intensity_label.text = "Intensity ×%.1f — $%.0f/day" % [_intensity, def.cost_per_day * _intensity]
		_refresh_preview())
	_create_body.add_child(intensity)
	var duration_label: Label = _field_label("Duration — %d days" % _duration)
	_create_body.add_child(duration_label)
	var duration: HSlider = HSlider.new()
	duration.min_value = def.min_days
	duration.max_value = def.max_days
	duration.step = 1
	duration.value = clampi(_duration, def.min_days, def.max_days)
	duration.custom_minimum_size = Vector2(280, 24)
	duration.value_changed.connect(func(value: float) -> void:
		_duration = int(value)
		duration_label.text = "Duration — %d days" % _duration
		_refresh_preview())
	_create_body.add_child(duration)
	# Review summary.
	var summary: PanelContainer = PanelContainer.new()
	summary.add_theme_stylebox_override("panel", BellaUi.sunk_box())
	_create_body.add_child(summary)
	var lines: VBoxContainer = VBoxContainer.new()
	summary.add_child(lines)
	# Totals live in the preview rail, which tracks the sliders; these lines
	# recap the fixed choices only.
	var draft: MarketingCampaign = _draft()
	for text: String in [
		"Channel: %s" % def.display_name,
		"Audience: %s" % _audience_text(draft),
		"Message: %s" % (_message_text if _message_text != "" else "—"),
		"Claim: %s" % _claim_label(_sel_claim),
		"Estimates carry roughly ±20%% uncertainty.",
	]:
		var line: Label = Label.new()
		line.text = text
		line.add_theme_font_size_override("font_size", 12)
		line.add_theme_color_override("font_color", INK_SOFT)
		lines.add_child(line)


func _on_next() -> void:
	var steps: Array[String] = _steps()
	if _step < steps.size() - 1:
		if steps[_step] == "Placement" and _sel_placements.is_empty():
			EconomyManager.post_message("alert", "Choose a billboard site first.")
			return
		_step += 1
		_rebuild_create()
		return
	_launch()


func _launch() -> void:
	var draft: MarketingCampaign = _draft()
	var def: MarketingChannelDef = MarketingManager.channel(_sel_channel)
	# Billboards: rent the chosen vacant site first, through the same command.
	if def != null and def.needs_placement:
		for site_id: int in draft.placement_ids:
			var site: AdPlacement = MarketingManager.placement(site_id)
			if site != null and site.vacant():
				var rent: CommandResult = MarketingManager.rent_placement(&"player", site_id, maxi(_duration, RENT_DAYS))
				if not rent.ok:
					EconomyManager.post_message("alert", rent.message)
					return
	var preview: Dictionary = MarketingManager.preview(draft)
	var result: CommandResult = _run_marketing_command(&"marketing.start_local", draft,
		float(preview.get("total_cost", 0.0)))
	if result.ok:
		EconomyManager.post_message("good", "Campaign launched: %s." % _campaign_title(draft))
		_step = 0
		_sel_placements = []
		_message_text = ""
		_rebuild_create()
		_tabs.current_tab = 0
	else:
		EconomyManager.post_message("alert", result.message)


func _stop_campaign(campaign: MarketingCampaign) -> void:
	var result := _run_marketing_command(&"marketing.stop_local", campaign, 0.0)
	if result.ok:
		refresh()


func _run_marketing_command(command_id: StringName, campaign: MarketingCampaign,
		exact_cost: float) -> CommandResult:
	var router := get_node_or_null("/root/BranchCommandRouter")
	if router == null or CompanyManager.player == null:
		return CommandResult.fail(&"router_unavailable", "The branch command router is unavailable.")
	_command_serial += 1
	var result := router.call("execute", command_id, {
		"building_id": campaign.building_id,
		"campaign": campaign,
		"exact_cost": exact_cost,
	}, {
		"kind": &"player",
		"id": "marketing_workspace",
		"company_id": CompanyManager.player.id,
	}, "ui:marketing:%s:%d:%d:%d" % [command_id, campaign.building_id,
		GameClock.total_minutes(), _command_serial]) as CommandResult
	return result if result != null else CommandResult.fail(
		&"command_unavailable", "The marketing command was unavailable.")


func _draft() -> MarketingCampaign:
	var campaign: MarketingCampaign = MarketingCampaign.new()
	campaign.company_id = &"player"
	campaign.channel_id = _sel_channel
	var def: MarketingChannelDef = MarketingManager.channel(_sel_channel)
	if def != null and def.needs_placement:
		campaign.building_id = -1
		campaign.placement_ids = _sel_placements.duplicate()
	elif def != null and def.scope == &"citywide":
		campaign.building_id = -1
	else:
		campaign.building_id = building_id
	campaign.target_segments = _sel_segments.duplicate()
	campaign.brand_image = _message_text
	campaign.claim = _sel_claim
	campaign.promoted_recipe = _sel_recipe
	campaign.rival_target = _sel_rival
	campaign.intensity = _intensity
	campaign.days_left = _duration
	if def != null:
		campaign.radius = def.base_radius
	return campaign


## Light refresh: preview rail + CTA only (keeps focus while typing).
func _refresh_preview() -> void:
	if _reach == null:
		return
	var draft: MarketingCampaign = _draft()
	var def: MarketingChannelDef = MarketingManager.channel(_sel_channel)
	var pv: Dictionary = MarketingManager.preview(draft)
	var centers: Array[Vector3] = MarketingManager._campaign_centers(draft)
	_reach.show_reach(centers, draft.radius, def != null and def.reach_shape == &"city")
	_cost_reach.text = "~%s people" % _thousands(int(pv.get("people", 0)))
	_cost_duration.text = "%d days" % int(pv.get("days", _duration))
	_cost_fit.text = "%d%%" % roundi(float(pv.get("fit", 0.0)) * 100.0)
	_cost_budget.text = "$%s" % _thousands(int(pv.get("total_cost", 0.0)))
	var steps: Array[String] = _steps()
	_back_btn.disabled = _step == 0
	if _step < steps.size() - 1:
		_next_btn.text = "Next: %s" % steps[_step + 1]
		_next_btn.disabled = false
	else:
		var total: float = float(pv.get("total_cost", 0.0))
		_next_btn.text = "Launch · $%s" % _thousands(int(total))
		_next_btn.disabled = not EconomyManager.can_afford(
			(def.setup_cost if def != null else 0.0) + float(pv.get("daily_cost", 0.0)))


# --- Placements tab ---------------------------------------------------------------


func _refresh_placements() -> void:
	_clear(_placements_list)
	_heading(_placements_list, "Billboard sites")
	var why_locked: String = CapabilityRegistry.explain(&"player", &"marketing.billboards")
	if why_locked != "":
		var lock: Label = Label.new()
		lock.text = why_locked
		lock.add_theme_font_size_override("font_size", 13)
		lock.add_theme_color_override("font_color", INK_SOFT)
		_placements_list.add_child(lock)
	for site: AdPlacement in MarketingManager.placements:
		_placements_list.add_child(_placement_row(site, why_locked == ""))


func _placement_row(site: AdPlacement, unlocked: bool) -> Control:
	var row: PanelContainer = PanelContainer.new()
	row.add_theme_stylebox_override("panel", BellaUi.tile_box())
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	row.add_child(line)
	var info: Label = Label.new()
	info.text = "Site %d · %s · $%.0f/day" % [site.id,
		DISTRICT_NAMES.get(site.district, site.district), site.rent_per_day]
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", INK)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(info)
	if site.vacant():
		line.add_child(BellaUi.pill("Vacant", INK_SOFT, BellaUi.PAPER_SUNK, BellaUi.PAPER_EDGE))
		var rent: Button = Button.new()
		rent.text = "Rent %d days · $%.0f/day" % [RENT_DAYS, site.rent_per_day]
		rent.disabled = not unlocked
		var site_id: int = site.id
		rent.pressed.connect(func() -> void:
			var result: CommandResult = MarketingManager.rent_placement(&"player", site_id, RENT_DAYS)
			if not result.ok:
				EconomyManager.post_message("alert", result.message))
		line.add_child(rent)
	elif site.owner_company == &"player":
		line.add_child(BellaUi.pill("Yours · %d days" % site.days_left, Color.WHITE,
			BellaUi.GREEN, BellaUi.GREEN_EDGE))
		var release: Button = Button.new()
		release.text = "Release"
		var site_id: int = site.id
		release.pressed.connect(func() -> void: MarketingManager.release_placement(site_id))
		line.add_child(release)
	else:
		var company: CompanyState = CompanyManager.company(site.owner_company)
		line.add_child(BellaUi.pill(
			company.display_name if company != null else "Rival", Color.WHITE,
			company.brand_color if company != null else BellaUi.RED_ACTIVE, WOOD_EDGE))
	return row


# --- Results tab -------------------------------------------------------------------


func _refresh_results() -> void:
	_clear(_results_list)
	_heading(_results_list, "Results (last-touch estimates)")
	var voice: float = MarketingManager.share_of_voice(&"player")
	var awareness_avg: float = MarketingManager.awareness.company_average(&"player")
	var chips: HBoxContainer = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	_results_list.add_child(chips)
	chips.add_child(BellaUi.pill("Share of voice %d%%" % roundi(voice * 100.0),
		INK_SOFT, BellaUi.PAPER_SUNK, BellaUi.PAPER_EDGE))
	chips.add_child(BellaUi.pill("Avg awareness %d%%" % roundi(awareness_avg * 100.0),
		INK_SOFT, BellaUi.PAPER_SUNK, BellaUi.PAPER_EDGE))
	for trend: CityTrend in MarketingManager.city_trends:
		chips.add_child(BellaUi.pill("Trending: %s (%dd)" % [trend.display_name, trend.days_left],
			Color.WHITE, BellaUi.RED_ACTIVE, BellaUi.RED_EDGE))
	var awareness_map: Dictionary = MarketingManager.awareness.district_averages(&"player")
	if not awareness_map.is_empty():
		_heading(_results_list, "Awareness by district")
		for district: String in awareness_map:
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			_results_list.add_child(row)
			var name_label: Label = Label.new()
			name_label.text = DISTRICT_NAMES.get(district, district)
			name_label.custom_minimum_size = Vector2(120, 0)
			name_label.add_theme_font_size_override("font_size", 12)
			name_label.add_theme_color_override("font_color", INK_SOFT)
			row.add_child(name_label)
			var bar: ProgressBar = ProgressBar.new()
			bar.max_value = 1.0
			bar.value = float(awareness_map[district])
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 14)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(bar)
			var pct: Label = Label.new()
			pct.text = "%d%%" % roundi(float(awareness_map[district]) * 100.0)
			pct.add_theme_font_size_override("font_size", 12)
			pct.add_theme_color_override("font_color", INK_MUTED)
			row.add_child(pct)
	_heading(_results_list, "Campaign attribution")
	var campaigns: Array[MarketingCampaign] = MarketingManager.campaigns_for(&"player")
	if campaigns.is_empty():
		var none: Label = Label.new()
		none.text = "No active campaigns to report on."
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", INK_MUTED)
		_results_list.add_child(none)
	for campaign: MarketingCampaign in campaigns:
		_results_list.add_child(_result_card(campaign))


func _result_card(campaign: MarketingCampaign) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.tile_box())
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var title: Label = Label.new()
	title.text = _campaign_title(campaign)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", INK)
	box.add_child(title)
	var cpa: String = "—"
	if campaign.attributed_visits > 0:
		cpa = "$%.0f" % (campaign.total_spend / campaign.attributed_visits)
	var stats: Label = Label.new()
	stats.text = "~%d visits · ~$%.0f revenue · est. cost/visit %s · spend $%.0f" % [
		campaign.attributed_visits, campaign.attributed_revenue, cpa, campaign.total_spend]
	stats.add_theme_font_size_override("font_size", 12)
	stats.add_theme_color_override("font_color", INK_SOFT)
	box.add_child(stats)
	if not campaign.segment_visits.is_empty():
		var parts: Array[String] = []
		for segment: StringName in campaign.segment_visits:
			parts.append("%s %d" % [String(segment).capitalize(), int(campaign.segment_visits[segment])])
		var seg_label: Label = Label.new()
		seg_label.text = "Segments: " + " · ".join(parts)
		seg_label.add_theme_font_size_override("font_size", 11)
		seg_label.add_theme_color_override("font_color", INK_MUTED)
		box.add_child(seg_label)
	var breakdown: Dictionary = MarketingManager.contribution_breakdown(campaign)
	var detail: Label = Label.new()
	detail.text = "Effect %d%% (novelty %d%% · fatigue %d%% · credibility %d%%)" % [
		roundi(campaign.effectiveness * 100.0),
		roundi(float(breakdown.get("novelty", 1.0)) * 100.0),
		roundi(campaign.fatigue * 100.0),
		roundi(campaign.credibility * 100.0)]
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", INK_MUTED)
	detail.tooltip_text = "awareness gain = reach × frequency × fit × credibility × spend efficiency × novelty − fatigue"
	box.add_child(detail)
	if campaign.claim != &"" and campaign.credibility < 0.85:
		var warn: Label = Label.new()
		warn.text = "⚠ Your \"%s\" claim reads false — credibility is hurting results and risks a fine." % _claim_label(campaign.claim)
		warn.add_theme_font_size_override("font_size", 12)
		warn.add_theme_color_override("font_color", RED_CURRENT)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(warn)
	return card


# --- Shared helpers -----------------------------------------------------------------


func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		child.queue_free()


func _heading(parent: Node, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("#8a5a2b"))
	parent.add_child(label)


func _field_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", INK_MUTED)
	return label


func _cost_row(parent: Node, key: String) -> Label:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	var key_label: Label = Label.new()
	key_label.text = key
	key_label.add_theme_font_size_override("font_size", 13)
	key_label.add_theme_color_override("font_color", INK_SOFT)
	key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key_label)
	var value: Label = Label.new()
	value.add_theme_font_size_override("font_size", 13)
	value.add_theme_color_override("font_color", GOLD_DEEP)
	row.add_child(value)
	return value


func _segment_share() -> Dictionary:
	var rest: RestaurantState = restaurant()
	if rest != null:
		return DemandManager.customer_profile(rest.building_id)
	var counts: Dictionary = {}
	var total: int = 0
	for data: Dictionary in PopulationManager.citizens_data:
		var segment: StringName = DemandManager.demographic_of(int(data.get("id", -1)))
		counts[segment] = int(counts.get(segment, 0)) + 1
		total += 1
	var result: Dictionary = {}
	for segment: StringName in counts:
		result[segment] = float(counts[segment]) / total if total > 0 else 0.0
	return result


func _claim_label(claim: StringName) -> String:
	for option: Array in CLAIMS:
		if option[0] == claim:
			return option[1]
	return "No claim"


func _recipe_label(recipe_id: StringName) -> String:
	var rec: RecipeDef = RecipeManager.recipe(recipe_id)
	if rec != null and "display_name" in rec:
		return rec.display_name
	return String(recipe_id).capitalize()


func _thousands(value: int) -> String:
	var text: String = str(absi(value))
	var out: String = ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3, 3) + out
		text = text.substr(0, text.length() - 3)
	return ("-" if value < 0 else "") + text + out
