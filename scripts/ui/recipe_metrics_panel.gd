class_name RecipeMetricsPanel
extends VBoxContainer
## Right-hand workshop panel: component/layer list with quantity and remove
## controls, cost/prep/sell stat wells, appeal bar with uncertainty band,
## segment-fit callout and validation warnings, plus Test and Save buttons.

signal select_requested(index: int)
signal quantity_changed(index: int, delta: float)
signal remove_requested(index: int)
signal save_requested
signal test_requested

const SEGMENT_LABELS: Dictionary = {
	&"teens": "Teens", &"students": "Students", &"workers": "Workers",
	&"families": "Families", &"seniors": "Seniors",
}

var draft: RecipeDef = null
var building_id: int = -1
var selected_index: int = -1

var _list_box: VBoxContainer
var _list_title: Label
var _list_count: Label
var _appeal_value: Label
var _fit_icon: TextureRect
var _cost_value: Label
var _prep_value: Label
var _sell_value: Label
var _appeal_bar: ProgressBar
var _appeal_note: Label
var _fit_box: PanelContainer
var _fit_label: Label
var _warn_box: VBoxContainer
var _save_button: Button


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(332, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# --- component list card
	var list_card: PanelContainer = PanelContainer.new()
	list_card.add_theme_stylebox_override("panel", BellaUi.tile_box(BellaUi.PAPER_EDGE, 3))
	list_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(list_card)
	var list_wrap: VBoxContainer = VBoxContainer.new()
	list_wrap.add_theme_constant_override("separation", 6)
	list_card.add_child(list_wrap)
	var header: Dictionary = BellaUi.card_header(&"basket", "Ingredients", "0 items")
	list_wrap.add_child(header["panel"])
	_list_title = header["title"]
	_list_count = header["trailing"]
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 150)
	list_wrap.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)

	# --- metrics card
	var metrics_card: PanelContainer = PanelContainer.new()
	metrics_card.add_theme_stylebox_override("panel", BellaUi.tile_box(BellaUi.PAPER_EDGE, 3))
	add_child(metrics_card)
	var metrics: VBoxContainer = VBoxContainer.new()
	metrics.add_theme_constant_override("separation", 8)
	metrics_card.add_child(metrics)

	var wells: HBoxContainer = HBoxContainer.new()
	wells.add_theme_constant_override("separation", 8)
	metrics.add_child(wells)
	_cost_value = _make_well(wells, "COST", TycoonTheme.PALETTE["bad"])
	_prep_value = _make_well(wells, "PREP", TycoonTheme.PALETTE["text"])
	_sell_value = _make_well(wells, "SELL", TycoonTheme.PALETTE["accent_gold"])

	var appeal_row: HBoxContainer = HBoxContainer.new()
	appeal_row.add_theme_constant_override("separation", 8)
	metrics.add_child(appeal_row)
	var appeal_title: Label = Label.new()
	appeal_title.text = "Appeal"
	appeal_title.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
	appeal_title.add_theme_color_override("font_color", BellaUi.INK_SOFT)
	appeal_row.add_child(appeal_title)
	_appeal_bar = ProgressBar.new()
	_appeal_bar.min_value = 0.0
	_appeal_bar.max_value = 100.0
	_appeal_bar.custom_minimum_size = Vector2(0, 24)
	_appeal_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_appeal_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_appeal_bar.show_percentage = false
	_appeal_bar.add_theme_stylebox_override("background", BellaUi.sunk_box(999))
	appeal_row.add_child(_appeal_bar)
	_appeal_value = Label.new()
	_appeal_value.custom_minimum_size.x = 44
	_appeal_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_appeal_value.add_theme_color_override("font_color", BellaUi.INK)
	appeal_row.add_child(_appeal_value)
	_appeal_note = Label.new()
	_appeal_note.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
	_appeal_note.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	metrics.add_child(_appeal_note)

	_fit_box = PanelContainer.new()
	_fit_box.add_theme_stylebox_override("panel", TycoonTheme.status_box("info"))
	metrics.add_child(_fit_box)
	var fit_row: HBoxContainer = HBoxContainer.new()
	fit_row.add_theme_constant_override("separation", 7)
	_fit_box.add_child(fit_row)
	_fit_icon = UiAssets.icon_rect(&"check", 18)
	if _fit_icon != null:
		fit_row.add_child(_fit_icon)
	_fit_label = Label.new()
	_fit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fit_label.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
	fit_row.add_child(_fit_label)

	_warn_box = VBoxContainer.new()
	_warn_box.add_theme_constant_override("separation", 4)
	metrics.add_child(_warn_box)

	# --- action buttons
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	add_child(buttons)
	var test_button: Button = Button.new()
	test_button.text = " Test"
	UiAssets.icon_button(test_button, &"play", 18)
	test_button.custom_minimum_size = Vector2(84, 46)
	test_button.pressed.connect(func() -> void: test_requested.emit())
	buttons.add_child(test_button)
	_save_button = Button.new()
	_save_button.text = " Save recipe"
	UiAssets.icon_button(_save_button, &"check", 18)
	_save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_button.custom_minimum_size = Vector2(0, 46)
	BellaUi.green_button(_save_button)
	_save_button.pressed.connect(func() -> void: save_requested.emit())
	buttons.add_child(_save_button)


func _make_well(parent: Control, title: String, value_color: Color) -> Label:
	var well: PanelContainer = PanelContainer.new()
	well.add_theme_stylebox_override("panel", BellaUi.sunk_box())
	well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(well)
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	well.add_child(box)
	var title_label: Label = Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	box.add_child(title_label)
	var value: Label = Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_TITLE)
	value.add_theme_color_override("font_color", value_color)
	box.add_child(value)
	return value


func set_draft(a_draft: RecipeDef, a_building_id: int) -> void:
	draft = a_draft
	building_id = a_building_id
	refresh()


func set_selected(index: int) -> void:
	selected_index = index
	_rebuild_list()


func refresh() -> void:
	if draft == null or _list_box == null:
		return
	_list_title.text = "Layers" if draft.product_type == &"burger" else "Ingredients"
	_list_count.text = "top → bottom" if draft.product_type == &"burger" else "%d items" % draft.components.size()
	_rebuild_list()
	_cost_value.text = "$%.2f" % draft.cached_cost
	_prep_value.text = "%.0fm" % draft.cached_prep
	_sell_value.text = "$%.1f" % RecipeManager.suggested_price_for(draft)
	var overall: float = _overall_appeal()
	_appeal_bar.value = overall * 100.0
	_appeal_value.text = "%d%%" % int(overall * 100.0)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color("#6FB63A") if overall >= 0.6 else (Color("#E0A80E") if overall >= 0.4 else Color("#EA4A2F"))
	fill.set_corner_radius_all(8)
	_appeal_bar.add_theme_stylebox_override("fill", fill)
	var uncertainty: float = RecipeManager.uncertainty_for(draft.id) if draft.id != &"" else 1.0
	if uncertainty > 0.05:
		_appeal_note.text = "Appeal %d%% · estimate ±%d — sharpens with real sales" \
			% [int(overall * 100.0), int(uncertainty * 15.0)]
	else:
		_appeal_note.text = "Appeal %d%% · confirmed by sales" % int(overall * 100.0)
	_refresh_fit()
	_refresh_warnings()


func _overall_appeal() -> float:
	if draft.cached_appeal.is_empty():
		return 0.0
	if building_id >= 0:
		var profile: Dictionary = DemandManager.customer_profile(building_id)
		if not profile.is_empty():
			var blended: float = 0.0
			for segment: StringName in draft.cached_appeal:
				blended += float(draft.cached_appeal[segment]) * float(profile.get(segment, 0.0))
			return blended
	var total: float = 0.0
	for segment: StringName in draft.cached_appeal:
		total += float(draft.cached_appeal[segment])
	return total / float(draft.cached_appeal.size())


func _refresh_fit() -> void:
	if draft.cached_appeal.is_empty():
		_fit_box.visible = false
		return
	var segments: Array = draft.cached_appeal.keys()
	segments.sort_custom(func(a: StringName, b: StringName) -> bool:
		return float(draft.cached_appeal[a]) > float(draft.cached_appeal[b]))
	var top_value: float = float(draft.cached_appeal[segments[0]])
	if top_value < 0.45:
		_fit_box.visible = true
		_fit_box.add_theme_stylebox_override("panel", TycoonTheme.status_box("warning"))
		_fit_label.text = "No segment loves this yet — try bolder ingredients."
		return
	_fit_box.visible = true
	_fit_box.add_theme_stylebox_override("panel", TycoonTheme.status_box("info"))
	_fit_label.text = "Great fit for %s & %s" % [
		SEGMENT_LABELS.get(segments[0], "?"), SEGMENT_LABELS.get(segments[1], "?")]


func _refresh_warnings() -> void:
	for child: Node in _warn_box.get_children():
		child.queue_free()
	var has_error: bool = false
	for issue: Dictionary in RecipeManager.validate(draft):
		var severity: String = String(issue["severity"])
		if severity == "error":
			has_error = true
		var row: PanelContainer = PanelContainer.new()
		row.add_theme_stylebox_override("panel",
			TycoonTheme.status_box("critical" if severity == "error" else "warning"))
		var label: Label = Label.new()
		label.text = String(issue["msg"])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
		row.add_child(label)
		_warn_box.add_child(row)
	_save_button.disabled = has_error
	_save_button.tooltip_text = "Fix the errors above first." if has_error else ""


func _rebuild_list() -> void:
	for child: Node in _list_box.get_children():
		child.queue_free()
	if draft == null:
		return
	var order: Array[int] = []
	if draft.product_type == &"burger":
		# Show top -> bottom like the mock; stack is bottom -> top.
		var stack: Array[RecipeComponent] = draft.sorted_stack()
		for i: int in range(stack.size() - 1, -1, -1):
			order.append(draft.components.find(stack[i]))
	else:
		for i: int in draft.components.size():
			order.append(i)
	for index: int in order:
		_list_box.add_child(_make_row(index))


func _make_row(index: int) -> Control:
	var comp: RecipeComponent = draft.components[index]
	var ing: IngredientDef = RecipeManager.ingredient(comp.ingredient_id)
	var row: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = TycoonTheme.inner_box()
	if index == selected_index:
		style.border_color = TycoonTheme.PALETTE["accent_gold"]
		style.set_border_width_all(3)
	row.add_theme_stylebox_override("panel", style)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			select_requested.emit(index))

	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	row.add_child(box)

	if ing != null:
		box.add_child(IngredientBrowser.SwatchIcon.new(ing.swatch_color, ing.marker_shape))
	var name_label: Label = Label.new()
	name_label.text = ing.display_name if ing != null else "%s (missing)" % comp.ingredient_id
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text"])
	box.add_child(name_label)

	var minus: Button = Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(28, 28)
	minus.pressed.connect(func() -> void: quantity_changed.emit(index, -1.0))
	box.add_child(minus)
	var qty: Label = Label.new()
	qty.text = "×%d" % int(comp.quantity)
	qty.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	box.add_child(qty)
	var plus: Button = Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(28, 28)
	plus.pressed.connect(func() -> void: quantity_changed.emit(index, 1.0))
	box.add_child(plus)

	var cost: Label = Label.new()
	cost.text = "$%.2f" % ((ing.unit_cost if ing != null else 0.0) * comp.quantity)
	cost.custom_minimum_size.x = 46
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.add_theme_color_override("font_color", TycoonTheme.PALETTE["accent_gold"])
	box.add_child(cost)

	var remove: Button = Button.new()
	remove.text = "✕"
	remove.custom_minimum_size = Vector2(28, 28)
	remove.tooltip_text = "Remove"
	remove.pressed.connect(func() -> void: remove_requested.emit(index))
	box.add_child(remove)
	return row
