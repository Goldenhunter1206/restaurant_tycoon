extends TycoonScreen
## D10 · Rating & Awards — per-restaurant star rating panel. Summary shows the
## big composite + dimension bars + the gold "to reach the next star" callout;
## Dimensions adds trends, Inspections the food-guide history, Awards this
## branch's trophies, Improvement the prioritized blockers. Click-only, so the
## per-minute refresh_active() full rebuild is safe; the active tab and the
## selected branch persist as members.

const TABS: Array[Array] = [
	[&"summary", "Summary"],
	[&"dimensions", "Dimensions"],
	[&"inspections", "Inspections"],
	[&"awards", "Awards"],
	[&"improvement", "Improvement"],
]
const DIM_META: Dictionary = {
	&"food": ["Food", Color("#6FB63A")],
	&"service": ["Service", Color("#F99A1C")],
	&"atmosphere": ["Atmosphere", Color("#F5C518")],
	&"cleanliness": ["Cleanliness", Color("#EA4A2F")],
	&"value": ["Value", Color("#3AA6D6")],
	&"consistency": ["Consistency", Color("#A97142")],
}

var _active_tab: StringName = &"summary"
var _body: VBoxContainer


func screen_title() -> String:
	return "Rating & Awards"


func screen_icon() -> StringName:
	return &"star"


func _build() -> void:
	custom_minimum_size = Vector2(880, 600)
	_build_branch_picker()
	_body = add_scroll_list()


func refresh() -> void:
	if _body == null:
		return
	for child: Node in _body.get_children():
		child.queue_free()
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_body.add_child(tabs)
	for tab: Array in TABS:
		var chip: Button = BellaUi.chip(String(tab[1]), StringName(tab[0]) == _active_tab)
		chip.pressed.connect(_on_tab.bind(StringName(tab[0])))
		tabs.add_child(chip)
	var state: RestaurantRatingState = _rating_state()
	if state == null or restaurant() == null:
		var hint: Label = Label.new()
		hint.text = "Ratings start collecting after the first day close."
		hint.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		_body.add_child(hint)
		return
	match _active_tab:
		&"summary":
			_render_summary(state)
		&"dimensions":
			_render_dimensions(state)
		&"inspections":
			_render_inspections(state)
		&"awards":
			_render_awards()
		&"improvement":
			_render_improvement(state)


func _on_tab(tab_id: StringName) -> void:
	_active_tab = tab_id
	refresh()


# --- Tabs -----------------------------------------------------------------------


func _render_summary(state: RestaurantRatingState) -> void:
	var rest: RestaurantState = restaurant()
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	_body.add_child(split)
	# Big score card.
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", BellaUi.tile_box())
	card.custom_minimum_size = Vector2(260, 0)
	split.add_child(card)
	var card_box: VBoxContainer = VBoxContainer.new()
	card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	card_box.add_theme_constant_override("separation", 4)
	card.add_child(card_box)
	card_box.add_child(_eyebrow("This Restaurant"))
	var score: Label = Label.new()
	score.text = "%.1f" % rest.star_rating
	score.add_theme_font_size_override("font_size", 54)
	score.add_theme_color_override("font_color", BellaUi.GOLD_EDGE)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_box.add_child(score)
	var stars: HBoxContainer = TycoonTheme.star_row(rest.star_rating, 22)
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	card_box.add_child(stars)
	var sub: Label = Label.new()
	sub.text = "Certified %d-star · %s" % [state.star_ceiling, _week_delta_text(state)]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	card_box.add_child(sub)
	# Dimension bars + blocker callout.
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)
	right.add_child(_eyebrow("Dimensions"))
	for key: StringName in RestaurantRatingState.DIMENSION_KEYS:
		right.add_child(_dimension_bar(key, state.dim(key)))
	right.add_child(_blocker_callout(state))


func _render_dimensions(state: RestaurantRatingState) -> void:
	for key: StringName in RestaurantRatingState.DIMENSION_KEYS:
		var row: PanelContainer = make_row()
		_body.add_child(row)
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		row.add_child(box)
		var left: VBoxContainer = VBoxContainer.new()
		left.custom_minimum_size = Vector2(300, 0)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(left)
		left.add_child(_dimension_bar(key, state.dim(key)))
		var spark: Sparkline = Sparkline.new()
		spark.custom_minimum_size = Vector2(170, 40)
		var values: Array = []
		for entry: Dictionary in state.history.slice(maxi(0, state.history.size() - 28)):
			values.append(float((entry.get("dimensions", {}) as Dictionary).get(key, 50.0)))
		spark.set_values(values)
		box.add_child(spark)


func _render_inspections(state: RestaurantRatingState) -> void:
	var next_row: PanelContainer = PanelContainer.new()
	next_row.add_theme_stylebox_override("panel", _gold_box())
	_body.add_child(next_row)
	var next_box: HBoxContainer = HBoxContainer.new()
	next_box.add_theme_constant_override("separation", 10)
	next_row.add_child(next_box)
	next_box.add_child(UiAssets.icon_rect(&"magnifier", 26))
	var next_label: Label = Label.new()
	var wait: int = maxi(0, state.next_inspection_day - GameClock.day)
	next_label.text = "Next food-guide visit: %s (in %d days). The guide favors cleanliness and food." % [
		GameClock.month_name_for(state.next_inspection_day), wait]
	next_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	next_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_box.add_child(next_label)
	if state.inspections.is_empty():
		_hint("No visits yet — the first inspection certifies your stars.")
		return
	for i: int in range(state.inspections.size() - 1, -1, -1):
		var visit: Dictionary = state.inspections[i]
		var row: PanelContainer = make_row()
		_body.add_child(row)
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		row.add_child(box)
		box.add_child(UiAssets.icon_rect(&"check" if bool(visit["passed"]) else &"close", 20))
		var text: Label = Label.new()
		var verdict: String = "certified %d-star" % int(visit["level"])
		if bool(visit.get("raised", false)):
			verdict = "raised to %d stars!" % int(visit["level"])
		elif not bool(visit["passed"]):
			verdict = "below your %d-star status" % state.star_ceiling
		text.text = "Day %d — score %d/100, %s (leniency %+.1f)" % [
			int(visit["day"]), int(visit["score"]), verdict, float(visit["leniency"])]
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(text)


func _render_awards() -> void:
	var awards: Node = _awards()
	if awards == null:
		return
	var rows: int = 0
	for result: AwardResult in awards.award_results:
		if result.winner_building_id != building_id:
			continue
		rows += 1
		var row: PanelContainer = make_row()
		_body.add_child(row)
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		row.add_child(box)
		box.add_child(UiAssets.icon_rect(&"medal" if result.kind == &"medal" else &"trophy", 26))
		var text: VBoxContainer = VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(text)
		var title: Label = Label.new()
		title.text = "%s — %s" % [result.display_name, result.period_label]
		text.add_child(title)
		var detail: Label = Label.new()
		detail.text = result.explanation
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_theme_font_size_override("font_size", 12)
		detail.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		text.add_child(detail)
	if rows == 0:
		_hint("No awards here yet. Quarterly winners appear with period and city record.")


func _render_improvement(state: RestaurantRatingState) -> void:
	var awards: Node = _awards()
	if awards == null:
		return
	var blockers: Array[Dictionary] = awards.next_star_blockers(building_id)
	if blockers.is_empty():
		_hint("Top of the city — five certified stars. Hold the line!")
		return
	add_section("To Reach %d Stars" % mini(state.star_ceiling + 1, 5))
	for gap: Dictionary in blockers:
		var row: PanelContainer = make_row()
		_body.add_child(row)
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		row.add_child(box)
		var text: Label = Label.new()
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		match StringName(gap["kind"]):
			&"dimension":
				var meta: Array = DIM_META.get(StringName(gap["dimension"]), ["?", Color.WHITE])
				box.add_child(UiAssets.icon_rect(&"chart_up", 20))
				text.text = "Raise %s above %d (now %d)." % [
					String(meta[0]).to_lower(), int(gap["needed"]), int(gap["value"])]
			&"sustain":
				box.add_child(UiAssets.icon_rect(&"hourglass", 20))
				text.text = "Hold this quality %d more days (%d of %d)." % [
					int(gap["needed_days"]) - int(gap["days"]), int(gap["days"]), int(gap["needed_days"])]
			&"inspection":
				box.add_child(UiAssets.icon_rect(&"magnifier", 20))
				text.text = "Pass the food-guide inspection on day %d." % int(gap["next_day"])
		box.add_child(text)


# --- Widgets --------------------------------------------------------------------


func _build_branch_picker() -> void:
	var owned: Array = RestaurantManager.owned
	if owned.size() <= 1:
		return
	var picker: OptionButton = OptionButton.new()
	for rest: RestaurantState in owned:
		picker.add_item(rest.restaurant_name, rest.building_id)
	picker.selected = maxi(0, picker.get_item_index(building_id) if building_id >= 0 else 0)
	if building_id < 0 and not owned.is_empty():
		building_id = owned[0].building_id
	picker.item_selected.connect(func(index: int) -> void:
		building_id = picker.get_item_id(index)
		refresh())
	_content.add_child(picker)
	_content.move_child(picker, 1)


func _dimension_bar(key: StringName, value: float) -> Control:
	var meta: Array = DIM_META.get(key, ["?", Color.WHITE])
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var name_label: Label = Label.new()
	name_label.text = String(meta[0])
	name_label.custom_minimum_size = Vector2(96, 0)
	box.add_child(name_label)
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 22)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override("background", BellaUi.sunk_box(9))
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = meta[1]
	fill.set_corner_radius_all(9)
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	var value_label: Label = Label.new()
	value_label.text = "%d" % int(value)
	value_label.custom_minimum_size = Vector2(30, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(value_label)
	return box


func _blocker_callout(state: RestaurantRatingState) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _gold_box())
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var title: Label = Label.new()
	if state.star_ceiling >= 5:
		title.text = "Five Stars"
	else:
		title.text = "To Reach %d Stars" % (state.star_ceiling + 1)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", BellaUi.WOOD_DEEP)
	box.add_child(title)
	var body: Label = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 12)
	var awards: Node = _awards()
	var parts: PackedStringArray = []
	if awards != null:
		for gap: Dictionary in awards.next_star_blockers(building_id).slice(0, 3):
			match StringName(gap["kind"]):
				&"dimension":
					var meta: Array = DIM_META.get(StringName(gap["dimension"]), ["?"])
					parts.append("raise %s above %d" % [String(meta[0]).to_lower(), int(gap["needed"])])
				&"sustain":
					parts.append("hold quality %d more days" % (int(gap["needed_days"]) - int(gap["days"])))
				&"inspection":
					parts.append("pass the day-%d inspection" % int(gap["next_day"]))
	body.text = "Hold the line!" if parts.is_empty() else String("; ".join(parts)).capitalize() + "."
	box.add_child(body)
	return panel


func _week_delta_text(state: RestaurantRatingState) -> String:
	if state.history.size() < 8:
		return "collecting data"
	var now: float = float(state.history[-1]["stars"])
	var then: float = float(state.history[-8]["stars"])
	return "%+.1f this week" % (now - then)


func _eyebrow(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


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
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 9.0
	box.content_margin_bottom = 9.0
	return box


func _rating_state() -> RestaurantRatingState:
	var awards: Node = _awards()
	if awards == null:
		return null
	return awards.rating_for(building_id)


func _awards() -> Node:
	return get_tree().root.get_node_or_null(^"AwardsManager")
