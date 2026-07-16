extends TycoonScreen
## E4 · Awards & Competitions — the company prestige hub. Calendar lists the
## quarterly award categories and upcoming contests; Active Entry hosts the
## competition cards (frozen entry well, participant chips, reward rail,
## submit/change/challenge flows and the results podium); Restaurant Awards
## and Trophy Case archive what the company has won. Click-only rebuilds;
## the active tab persists across the per-minute refresh.

const TABS: Array[Array] = [
	[&"calendar", "Calendar"],
	[&"active", "Active Entry"],
	[&"restaurant", "Restaurant Awards"],
	[&"trophies", "Trophy Case"],
]

var _active_tab: StringName = &"active"
var _body: VBoxContainer
var _picker_layer: Control


func screen_title() -> String:
	return "Awards & Competitions"


func screen_icon() -> StringName:
	return &"trophy"


func wants_spring_open() -> bool:
	return true


func _build() -> void:
	custom_minimum_size = Vector2(940, 620)
	_body = add_scroll_list()


func refresh() -> void:
	if _body == null:
		return
	if _picker_layer != null and is_instance_valid(_picker_layer):
		return  # Keep the entry picker open through the minute tick.
	for child: Node in _body.get_children():
		child.queue_free()
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_body.add_child(tabs)
	for tab: Array in TABS:
		var chip: Button = BellaUi.chip(String(tab[1]), StringName(tab[0]) == _active_tab)
		chip.pressed.connect(_on_tab.bind(StringName(tab[0])))
		tabs.add_child(chip)
	match _active_tab:
		&"calendar":
			_render_calendar()
		&"active":
			_render_active()
		&"restaurant":
			_render_restaurant_awards()
		&"trophies":
			_render_trophy_case()


func _on_tab(tab_id: StringName) -> void:
	_active_tab = tab_id
	refresh()


# --- Calendar ---------------------------------------------------------------------


func _render_calendar() -> void:
	var awards: Node = _awards()
	if awards == null:
		return
	var cadence: int = maxi(7, int(EconomyManager.tuning_value("awards.cadence_days", 42)))
	var next_day: int = ((GameClock.day / cadence) + 1) * cadence
	add_section("City Awards — Next Ceremony Day %d (%s)" % [next_day, GameClock.month_name_for(next_day)])
	var active: Array = EconomyManager.tuning_value("awards.active_categories", [])
	for def_id_raw: Variant in active:
		var def: AwardDef = awards.award_defs.get(StringName(String(def_id_raw)))
		if def == null:
			continue
		var row: PanelContainer = make_row()
		_body.add_child(row)
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		row.add_child(box)
		box.add_child(UiAssets.icon_rect(def.icon, 26))
		var text: VBoxContainer = VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(text)
		var title: Label = Label.new()
		title.text = def.display_name
		text.add_child(title)
		var detail: Label = Label.new()
		detail.text = "%s %s" % [def.blurb, _eligibility_text(def)]
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_theme_font_size_override("font_size", 12)
		detail.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		text.add_child(detail)
		var latest: AwardResult = _latest_result(def.id)
		if latest != null:
			var holder: Label = Label.new()
			holder.text = "Holder: %s (%s)" % [latest.winner_name, latest.period_label]
			holder.add_theme_font_size_override("font_size", 12)
			holder.add_theme_color_override("font_color", BellaUi.GOLD_EDGE)
			text.add_child(holder)
		box.add_child(_reward_pill(def.reward_cash))
	add_section("Upcoming Contests")
	var beats: Array = awards.upcoming_competition_events(4)
	if beats.is_empty():
		_hint("Nothing scheduled — challenge a rival from the Active Entry tab.")
	for beat: Dictionary in beats:
		var row: PanelContainer = make_row()
		_body.add_child(row)
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		row.add_child(box)
		box.add_child(UiAssets.icon_rect(&"trophy", 20))
		var label: Label = Label.new()
		label.text = "%s — day %d (%s)" % [String(beat["title"]), int(beat["day"]), String(beat["when"])]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(label)


# --- Active entry -------------------------------------------------------------------


func _render_active() -> void:
	var awards: Node = _awards()
	if awards == null:
		return
	var shown: int = 0
	for comp: CompetitionState in awards.competitions:
		if comp.status == &"closed" and not _is_recent(comp):
			continue
		shown += 1
		_body.add_child(_competition_card(comp))
	if shown == 0:
		_hint("No contest is running. Scheduled cups appear here — or throw down a challenge below.")
	_render_challenge_row()


func _competition_card(comp: CompetitionState) -> Control:
	var awards: Node = _awards()
	var def: CompetitionDef = awards.competition_defs.get(comp.def_id)
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.tile_box())
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	card.add_child(split)
	var main: VBoxContainer = VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)
	split.add_child(main)
	# Header: icon, title/brief, countdown pill.
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	main.add_child(head)
	head.add_child(UiAssets.icon_rect(def.icon if def != null else &"trophy", 32))
	var head_text: VBoxContainer = VBoxContainer.new()
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_text)
	var title: Label = Label.new()
	title.text = def.display_name if def != null else String(comp.def_id)
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	head_text.add_child(title)
	var brief: Label = Label.new()
	brief.text = def.brief if def != null else ""
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.add_theme_font_size_override("font_size", 12)
	brief.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	head_text.add_child(brief)
	head.add_child(_status_pill(comp))
	if comp.status == &"judged" or comp.status == &"closed":
		_add_podium(main, comp)
	else:
		# Frozen entry well.
		var well: PanelContainer = PanelContainer.new()
		well.add_theme_stylebox_override("panel", BellaUi.sunk_box())
		main.add_child(well)
		var well_box: VBoxContainer = VBoxContainer.new()
		well.add_child(well_box)
		var eyebrow: Label = Label.new()
		eyebrow.text = "YOUR ENTRY (FROZEN)"
		eyebrow.add_theme_font_size_override("font_size", 10)
		eyebrow.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		well_box.add_child(eyebrow)
		var entry: Dictionary = comp.entry_for(CompanyManager.player.id)
		var entry_label: Label = Label.new()
		if entry.is_empty():
			entry_label.text = "No entry yet."
		else:
			var recipe: RecipeDef = entry["recipe"]
			var appeal: float = awards._score_competition_recipe(
				recipe, StringName(entry.get("tier", &"med")),
				def.target_demographics if def != null else [])
			entry_label.text = "%s · appeal %d" % [recipe.display_name, int(appeal * 100.0)]
		well_box.add_child(entry_label)
		# Participants.
		var who: Label = Label.new()
		who.text = "PARTICIPANTS · %d" % comp.entries.size()
		who.add_theme_font_size_override("font_size", 10)
		who.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		main.add_child(who)
		var chips: HBoxContainer = HBoxContainer.new()
		chips.add_theme_constant_override("separation", 6)
		main.add_child(chips)
		for entered: Dictionary in comp.entries:
			var company: CompanyState = CompanyManager.company(StringName(entered["company_id"]))
			var swatch: ColorRect = ColorRect.new()
			swatch.custom_minimum_size = Vector2(26, 26)
			swatch.color = company.brand_color if company != null else Color.GRAY
			swatch.tooltip_text = company.display_name if company != null else "?"
			chips.add_child(swatch)
	# Right rail: reward + actions.
	var rail: VBoxContainer = VBoxContainer.new()
	rail.custom_minimum_size = Vector2(220, 0)
	rail.add_theme_constant_override("separation", 8)
	split.add_child(rail)
	var reward: PanelContainer = PanelContainer.new()
	reward.add_theme_stylebox_override("panel", _gold_box())
	rail.add_child(reward)
	var reward_box: VBoxContainer = VBoxContainer.new()
	reward_box.alignment = BoxContainer.ALIGNMENT_CENTER
	reward.add_child(reward_box)
	var cup: TextureRect = UiAssets.icon_rect(&"trophy", 44)
	cup.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reward_box.add_child(cup)
	var reward_title: Label = Label.new()
	reward_title.text = "Reward"
	reward_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_box.add_child(reward_title)
	var reward_body: Label = Label.new()
	var extras: PackedStringArray = []
	if def != null and def.reward_trend_days > 0:
		extras.append("citywide trend")
	if def != null and def.reward_reputation > 0.0:
		extras.append("reputation")
	reward_body.text = "$%s%s" % [_fmt(def.reward_cash if def != null else 0.0),
		"" if extras.is_empty() else " + " + " + ".join(extras)]
	reward_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward_body.add_theme_font_size_override("font_size", 12)
	reward_box.add_child(reward_body)
	if comp.status == &"entry":
		var has_entry: bool = not comp.entry_for(CompanyManager.player.id).is_empty()
		var submit: Button = Button.new()
		if has_entry:
			submit.text = "Change Entry"
		else:
			var fee: float = def.entry_fee if def != null else 0.0
			submit.text = "Submit Entry · $%s" % _fmt(fee) if fee > 0.0 else "Submit Entry"
		BellaUi.green_button(submit)
		submit.pressed.connect(_open_entry_picker.bind(comp))
		rail.add_child(submit)
	return card


func _add_podium(parent: VBoxContainer, comp: CompetitionState) -> void:
	var eyebrow: Label = Label.new()
	eyebrow.text = "RESULTS — EVERY SCORE COMPONENT"
	eyebrow.add_theme_font_size_override("font_size", 10)
	eyebrow.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	parent.add_child(eyebrow)
	for row: Dictionary in comp.results:
		var line: PanelContainer = PanelContainer.new()
		line.add_theme_stylebox_override("panel",
			_gold_box() if int(row["rank"]) == 1 else BellaUi.sunk_box())
		parent.add_child(line)
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		line.add_child(box)
		var rank: Label = Label.new()
		rank.text = "#%d" % int(row["rank"])
		rank.add_theme_font_size_override("font_size", 17)
		rank.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
		box.add_child(rank)
		var company: CompanyState = CompanyManager.company(StringName(row["company_id"]))
		var swatch: ColorRect = ColorRect.new()
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = company.brand_color if company != null else Color.GRAY
		box.add_child(swatch)
		var text: VBoxContainer = VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(text)
		var who: Label = Label.new()
		who.text = "%s — %s" % [company.display_name if company != null else "?", String(row["recipe_name"])]
		text.add_child(who)
		var breakdown: Label = Label.new()
		breakdown.text = "Recipe %d · compliance %d · novelty %d · judging %+.1f%% (range ±%d%%)" % [
			int(float(row["recipe_score"]) * 100.0), int(float(row["compliance"]) * 100.0),
			int(float(row["novelty"]) * 100.0), float(row["noise"]) * 100.0,
			int(float(row["noise_range"]) * 100.0)]
		breakdown.add_theme_font_size_override("font_size", 11)
		breakdown.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		text.add_child(breakdown)
		var total: Label = Label.new()
		total.text = "%.2f" % float(row["total"])
		total.add_theme_font_size_override("font_size", 17)
		total.add_theme_color_override("font_color", BellaUi.GOLD_EDGE)
		box.add_child(total)


func _render_challenge_row() -> void:
	var awards: Node = _awards()
	add_section("Challenge a Rival")
	var row: PanelContainer = make_row()
	_body.add_child(row)
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	row.add_child(box)
	var rival_pick: OptionButton = OptionButton.new()
	for company: CompanyState in CompanyManager.companies:
		if company.is_player or company.is_bankrupt:
			continue
		rival_pick.add_item(company.display_name)
		rival_pick.set_item_metadata(rival_pick.item_count - 1, company.id)
	box.add_child(rival_pick)
	var format_pick: OptionButton = OptionButton.new()
	for def_id: StringName in awards.competition_defs:
		var def: CompetitionDef = awards.competition_defs[def_id]
		if def.cadence_days > 0:
			continue  # Scheduled cups run on the calendar; duels are cadence-free.
		format_pick.add_item(def.display_name)
		format_pick.set_item_metadata(format_pick.item_count - 1, def.id)
	box.add_child(format_pick)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var throw_down: Button = Button.new()
	throw_down.text = "Challenge"
	TycoonTheme.apply_orange(throw_down)
	throw_down.pressed.connect(func() -> void:
		if rival_pick.selected < 0 or format_pick.selected < 0:
			return
		var rival_id: StringName = rival_pick.get_item_metadata(rival_pick.selected)
		var def_id: StringName = format_pick.get_item_metadata(format_pick.selected)
		var result: CommandResult = awards.challenge_rival(CompanyManager.player.id, rival_id, def_id)
		if not result.ok:
			EconomyManager.post_message("alert", result.message)
		refresh())
	box.add_child(throw_down)


# --- Archives ---------------------------------------------------------------------


func _render_restaurant_awards() -> void:
	var awards: Node = _awards()
	if awards == null:
		return
	var branch_ids: Dictionary = {}
	for rest: RestaurantState in RestaurantManager.owned:
		branch_ids[rest.building_id] = rest.restaurant_name
	var rows: int = 0
	for result: AwardResult in awards.award_results:
		if result.kind != &"award" or not branch_ids.has(result.winner_building_id):
			continue
		rows += 1
		_body.add_child(_result_row(result, String(branch_ids[result.winner_building_id])))
	if rows == 0:
		_hint("No restaurant awards yet. Check each branch's Rating panel for what the judges want.")


func _render_trophy_case() -> void:
	var awards: Node = _awards()
	if awards == null:
		return
	var mine: Array[AwardResult] = awards.results_for(CompanyManager.player.id)
	if mine.is_empty():
		_hint("The shelf is empty — win a city award or a recipe cup and it lands here.")
		return
	for i: int in range(mine.size() - 1, -1, -1):
		_body.add_child(_result_row(mine[i], ""))


func _result_row(result: AwardResult, branch_name: String) -> Control:
	var row: PanelContainer = make_row()
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)
	box.add_child(UiAssets.icon_rect(&"medal" if result.kind == &"medal" else &"trophy", 28))
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	var title: Label = Label.new()
	var suffix: String = "" if branch_name.is_empty() else " — %s" % branch_name
	title.text = "%s (%s)%s" % [result.display_name, result.period_label, suffix]
	text.add_child(title)
	var detail: Label = Label.new()
	detail.text = result.explanation
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	text.add_child(detail)
	return row


# --- Entry picker -------------------------------------------------------------------


func _open_entry_picker(comp: CompetitionState) -> void:
	var awards: Node = _awards()
	var def: CompetitionDef = awards.competition_defs.get(comp.def_id)
	_picker_layer = Control.new()
	_picker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().add_child(_picker_layer)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close_picker())
	_picker_layer.add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 320)
	_picker_layer.add_child(panel)
	var paper: PanelContainer = PanelContainer.new()
	paper.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	panel.add_child(paper)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	paper.add_child(box)
	var title: Label = Label.new()
	title.text = "Pick Your Entry"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	box.add_child(title)
	var tier_row: HBoxContainer = HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 8)
	box.add_child(tier_row)
	var tier_label: Label = Label.new()
	tier_label.text = "Ingredient tier"
	tier_row.add_child(tier_label)
	var tier_pick: OptionButton = OptionButton.new()
	for tier: Array in [[&"low", "Budget"], [&"med", "Standard"], [&"high", "Premium"]]:
		tier_pick.add_item(String(tier[1]))
		tier_pick.set_item_metadata(tier_pick.item_count - 1, tier[0])
	tier_pick.selected = 1
	tier_row.add_child(tier_pick)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var candidates: int = 0
	for recipe: RecipeDef in RecipeManager.live_recipes():
		if def != null and def.product_type != &"" and recipe.product_type != def.product_type:
			continue
		candidates += 1
		var pick: Button = Button.new()
		var appeal: float = awards._score_competition_recipe(
			recipe, &"med", def.target_demographics if def != null else [])
		pick.text = "%s · appeal %d" % [recipe.display_name, int(appeal * 100.0)]
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.pressed.connect(func() -> void:
			var tier: StringName = tier_pick.get_item_metadata(tier_pick.selected)
			_confirm_entry(comp, def, recipe, tier))
		list.add_child(pick)
	if candidates == 0:
		var none: Label = Label.new()
		none.text = "No matching recipe in your book. Craft one in the Recipe Workshop first."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(none)
	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_close_picker)
	box.add_child(cancel)


func _confirm_entry(comp: CompetitionState, def: CompetitionDef, recipe: RecipeDef, tier: StringName) -> void:
	var awards: Node = _awards()
	var has_entry: bool = not comp.entry_for(CompanyManager.player.id).is_empty()
	var fee_line: String = "Your recipe is frozen as it stands — later edits stay out of the contest."
	if not has_entry and def != null and def.entry_fee > 0.0:
		fee_line = "Entry fee $%s. " % _fmt(def.entry_fee) + fee_line
	TycoonConfirmDialog.ask(self, "Enter \"%s\"?" % recipe.display_name, fee_line, func() -> void:
		var result: CommandResult = awards.enter_competition(CompanyManager.player.id, comp.uid, recipe, tier)
		if not result.ok:
			EconomyManager.post_message("alert", result.message)
		_close_picker()
		refresh(), "Lock It In")


func _close_picker() -> void:
	if _picker_layer != null and is_instance_valid(_picker_layer):
		_picker_layer.queue_free()
	_picker_layer = null


# --- Small helpers -------------------------------------------------------------------


func _status_pill(comp: CompetitionState) -> Control:
	match comp.status:
		&"entry":
			var wait: int = maxi(0, comp.deadline_day - GameClock.day)
			return BellaUi.pill("Closes in %d days" % wait, Color.WHITE, BellaUi.RED_ACTIVE, BellaUi.RED_EDGE)
		&"locked":
			return BellaUi.pill("Judging day %d" % comp.judging_day, BellaUi.INK, BellaUi.PAPER_SUNK, BellaUi.PAPER_EDGE)
		_:
			return BellaUi.pill("Results", BellaUi.INK, BellaUi.GOLD, BellaUi.GOLD_EDGE)


func _reward_pill(cash: float) -> Control:
	return BellaUi.pill("$%s" % _fmt(cash), BellaUi.INK, BellaUi.GOLD, BellaUi.GOLD_EDGE)


func _eligibility_text(def: AwardDef) -> String:
	var parts: PackedStringArray = []
	if def.eligibility.has("min_guests"):
		parts.append("%d guests/quarter" % int(def.eligibility["min_guests"]))
	if def.eligibility.has("min_stars"):
		parts.append("%.1f stars" % float(def.eligibility["min_stars"]))
	if bool(def.eligibility.get("requires_delivery", false)):
		parts.append("delivery service")
	if def.eligibility.has("max_age_days"):
		parts.append("opened within %d days" % int(def.eligibility["max_age_days"]))
	if parts.is_empty():
		return ""
	return "Needs %s." % ", ".join(parts)


func _latest_result(award_id: StringName) -> AwardResult:
	var awards: Node = _awards()
	for i: int in range(awards.award_results.size() - 1, -1, -1):
		var result: AwardResult = awards.award_results[i]
		if result.award_id == award_id:
			return result
	return null


func _is_recent(comp: CompetitionState) -> bool:
	return GameClock.day - comp.judging_day <= 3


func _fmt(value: float) -> String:
	return TycoonHud._fmt(value)


func _hint(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	_body.add_child(label)


func _gold_box() -> StyleBoxFlat:
	var box: StyleBoxFlat = BellaUi.sunk_box(13)
	box.bg_color = Color(0.961, 0.773, 0.094, 0.14)
	box.border_color = BellaUi.GOLD
	box.set_border_width_all(3)
	return box


func _awards() -> Node:
	return get_tree().root.get_node_or_null(^"AwardsManager")
