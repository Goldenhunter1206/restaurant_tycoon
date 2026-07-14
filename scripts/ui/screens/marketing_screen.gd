extends TycoonScreen
## Marketing: run local ad campaigns per branch. Uses the exact same
## MarketingManager commands as the rival AI — a campaign boosts offer
## appeal for citizens near the branch for its duration.

const INK: Color = Color("#3A2010")
const INK_SOFT: Color = Color("#6E4326")
const INK_MUTED: Color = Color("#9A7245")
const DEMOGRAPHICS: Array[StringName] = [&"", &"teens", &"students", &"workers", &"families", &"seniors"]

var _list: VBoxContainer
var _selected_demo: StringName = &""


func screen_title() -> String:
	return "Marketing"


func screen_icon() -> StringName:
	return &"megaphone"


func _build() -> void:
	custom_minimum_size = Vector2(620, 480)
	_list = add_scroll_list()
	MarketingManager.campaigns_changed.connect(refresh)


func refresh() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	_render_active()
	_render_create()


func _render_active() -> void:
	var heading: Label = Label.new()
	heading.text = "Active campaigns"
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color("#8a5a2b"))
	_list.add_child(heading)
	var campaigns: Array[MarketingCampaign] = MarketingManager.campaigns_for(&"player")
	if campaigns.is_empty():
		var empty: Label = Label.new()
		empty.text = "No campaigns running."
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", INK_MUTED)
		_list.add_child(empty)
	for campaign: MarketingCampaign in campaigns:
		var row: PanelContainer = make_row()
		_list.add_child(row)
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		row.add_child(line)
		var rest: RestaurantState = RestaurantManager.by_building.get(campaign.building_id)
		var info: Label = Label.new()
		var target: String = "everyone" if campaign.demographic == &"" else String(campaign.demographic)
		info.text = "%s · targets %s · $%.0f/day · %d day%s left" % [
			rest.restaurant_name if rest != null else "Branch %d" % campaign.building_id,
			target, campaign.cost_per_day, campaign.days_left,
			"" if campaign.days_left == 1 else "s"]
		info.add_theme_font_size_override("font_size", 13)
		info.add_theme_color_override("font_color", INK)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(info)
		var stop: Button = Button.new()
		stop.text = "Stop"
		stop.pressed.connect(func() -> void: MarketingManager.stop_campaign(campaign))
		line.add_child(stop)


func _render_create() -> void:
	var rest: RestaurantState = restaurant()
	var heading: Label = Label.new()
	heading.text = "New campaign — %s" % (rest.restaurant_name if rest != null else "select a restaurant")
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color("#8a5a2b"))
	_list.add_child(heading)
	if rest == null:
		return
	var pitch: Label = Label.new()
	pitch.text = "Street ads boost your appeal for customers near this branch. $150 per day, runs 7 days."
	pitch.add_theme_font_size_override("font_size", 13)
	pitch.add_theme_color_override("font_color", INK_SOFT)
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(pitch)
	var demo_label: Label = Label.new()
	demo_label.text = "Target audience"
	demo_label.add_theme_font_size_override("font_size", 13)
	demo_label.add_theme_color_override("font_color", INK_MUTED)
	_list.add_child(demo_label)
	var chips: HBoxContainer = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	_list.add_child(chips)
	for demo: StringName in DEMOGRAPHICS:
		var text: String = "Everyone" if demo == &"" else String(demo).capitalize()
		var chip: Button = BellaUi.chip(text, _selected_demo == demo)
		var choice: StringName = demo
		chip.pressed.connect(func() -> void:
			_selected_demo = choice
			refresh())
		chips.add_child(chip)
	var already: bool = false
	for campaign: MarketingCampaign in MarketingManager.campaigns_for(&"player"):
		if campaign.building_id == rest.building_id:
			already = true
			break
	var start: Button = Button.new()
	start.text = "Launch campaign ($150/day)" if not already else "Campaign already running here"
	start.disabled = already or not EconomyManager.can_afford(150.0)
	start.custom_minimum_size = Vector2(260, 44)
	TycoonTheme.apply_orange(start)
	start.add_theme_color_override("font_color", Color.WHITE)
	start.add_theme_color_override("font_hover_color", Color.WHITE)
	start.pressed.connect(func() -> void:
		var campaign: MarketingCampaign = MarketingCampaign.new()
		campaign.company_id = &"player"
		campaign.building_id = rest.building_id
		campaign.demographic = _selected_demo
		campaign.radius = 450.0
		campaign.utility_bonus = 0.15
		campaign.cost_per_day = 150.0
		campaign.days_left = 7
		var result: CommandResult = MarketingManager.start_campaign(campaign)
		if result.ok:
			EconomyManager.post_message("good", "Ad campaign launched around %s." % rest.restaurant_name)
		else:
			EconomyManager.post_message("alert", result.message)
		refresh())
	_list.add_child(start)
