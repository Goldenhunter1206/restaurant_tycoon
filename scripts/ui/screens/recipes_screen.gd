extends TycoonScreen
## Recipes workspace: Recipe Book (card grid -> workshop), Base Menu (company
## defaults for new restaurants), Restaurant Menu (per-branch enable/tier/
## price/stations — the former menu_screen), Performance (per-recipe sales)
## and a locked Competitions stub.

signal open_workshop_requested(recipe_id: StringName, product_type: StringName)
signal request_screen(screen_id: StringName)

const BOOK_FILTERS: Array[Dictionary] = [
	{"id": "all", "label": "All"},
	{"id": "pizza", "label": "Pizza"},
	{"id": "burger", "label": "Burger"},
	{"id": "starter", "label": "Starter"},
	{"id": "custom", "label": "Custom"},
	{"id": "archived", "label": "Archived"},
]

var _tabs: TabContainer
var _competitions_box: VBoxContainer
var _book_filter: String = "all"
var _book_chips: Dictionary = {}
var _book_grid: GridContainer
var _base_menu_box: VBoxContainer
var _menu_rows: Dictionary = {}
var _slots_label: Label
var _buy_button: Button
var _menu_list: VBoxContainer
var _performance_box: VBoxContainer
var _command_serial: int = 0


class CardArt:
	extends Control
	## Tiny drawn illustration for a recipe card (no bespoke art assets yet).
	var product_type: StringName = &"pizza"
	var muted: bool = false

	func _init(a_product: StringName, a_muted: bool) -> void:
		product_type = a_product
		muted = a_muted
		custom_minimum_size = Vector2(0, 72)

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var alpha: float = 0.45 if muted else 1.0
		if product_type == &"pizza":
			var r: float = minf(size.y, size.x) * 0.42
			draw_circle(c, r, Color("#D89A4A", alpha))
			draw_circle(c, r * 0.82, Color("#E8503A", alpha))
			draw_circle(c, r * 0.66, Color("#F1D98C", alpha))
			draw_circle(c + Vector2(-r * 0.25, -r * 0.15), r * 0.14, Color("#B4291A", alpha))
			draw_circle(c + Vector2(r * 0.2, r * 0.2), r * 0.14, Color("#B4291A", alpha))
			draw_circle(c + Vector2(r * 0.25, -r * 0.28), r * 0.14, Color("#B4291A", alpha))
		else:
			var w: float = minf(size.x * 0.5, 86.0)
			var x: float = c.x - w * 0.5
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = Color("#D89A4A", alpha)
			style.set_corner_radius_all(14)
			draw_style_box(style, Rect2(x, c.y - 26.0, w, 18.0))
			draw_rect(Rect2(x + 3.0, c.y - 8.0, w - 6.0, 7.0), Color("#8FD24A", alpha))
			draw_rect(Rect2(x + 1.0, c.y - 1.0, w - 2.0, 10.0), Color("#5A3418", alpha))
			var bottom: StyleBoxFlat = StyleBoxFlat.new()
			bottom.bg_color = Color("#C6883A", alpha)
			bottom.corner_radius_bottom_left = 10
			bottom.corner_radius_bottom_right = 10
			draw_style_box(bottom, Rect2(x + 2.0, c.y + 9.0, w - 4.0, 12.0))


func screen_title() -> String:
	return "Recipes"


func screen_icon() -> StringName:
	return &"pizza"


func _build() -> void:
	custom_minimum_size = Vector2(960, 640)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	BellaUi.style_tabs(_tabs)
	_content.add_child(_tabs)
	_build_book_tab()
	_build_base_menu_tab()
	_build_restaurant_menu_tab()
	_build_performance_tab()
	_build_competitions_tab()
	# NOTE: connect after all tabs exist — tab_changed fires on the first add.
	_tabs.tab_changed.connect(func(_index: int) -> void: refresh())


func refresh() -> void:
	match _tabs.current_tab:
		0:
			_rebuild_book()
		1:
			_rebuild_base_menu()
		2:
			_refresh_menu_tab()
		3:
			_rebuild_performance()
		4:
			_rebuild_competitions()


# --- Tab 1: Recipe Book -------------------------------------------------------


func _build_book_tab() -> void:
	var tab: VBoxContainer = VBoxContainer.new()
	tab.name = "Recipe Book"
	tab.add_theme_constant_override("separation", 8)
	_tabs.add_child(tab)

	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	tab.add_child(top)
	for entry: Dictionary in BOOK_FILTERS:
		var filter_id: String = String(entry["id"])
		var chip: Button = BellaUi.chip(String(entry["label"]), filter_id == "all")
		chip.pressed.connect(func() -> void:
			_book_filter = filter_id
			for key: String in _book_chips:
				BellaUi.style_chip(_book_chips[key], key == filter_id)
			_rebuild_book())
		top.add_child(chip)
		_book_chips[filter_id] = chip
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var new_button: Button = Button.new()
	new_button.text = " New recipe"
	UiAssets.icon_button(new_button, &"check", 18)
	BellaUi.green_button(new_button)
	new_button.custom_minimum_size = Vector2(0, 40)
	new_button.pressed.connect(_ask_new_recipe)
	top.add_child(new_button)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	_book_grid = GridContainer.new()
	_book_grid.columns = 4
	_book_grid.add_theme_constant_override("h_separation", 10)
	_book_grid.add_theme_constant_override("v_separation", 10)
	_book_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_book_grid)
	_rebuild_book()


func _book_recipes() -> Array[RecipeDef]:
	var out: Array[RecipeDef] = []
	var source: Array[RecipeDef] = RecipeManager.book.archived if _book_filter == "archived" \
		else RecipeManager.book.recipes
	for rec: RecipeDef in source:
		if _book_filter != "archived" and rec.archived:
			continue
		match _book_filter:
			"pizza":
				if rec.product_type != &"pizza":
					continue
			"burger":
				if rec.product_type != &"burger":
					continue
			"starter":
				if not rec.is_starter:
					continue
			"custom":
				if rec.is_starter:
					continue
		out.append(rec)
	return out


func _rebuild_book() -> void:
	if _book_grid == null:
		return
	for child: Node in _book_grid.get_children():
		child.queue_free()
	for rec: RecipeDef in _book_recipes():
		_book_grid.add_child(_make_recipe_card(rec))
	if _book_filter != "archived":
		_book_grid.add_child(_make_new_card())


func _make_recipe_card(rec: RecipeDef) -> Control:
	var card: PanelContainer = PanelContainer.new()
	var card_style: StyleBoxFlat = BellaUi.tile_box(BellaUi.PAPER_EDGE, 3)
	card_style.set_content_margin_all(0.0)
	card.add_theme_stylebox_override("panel", card_style)
	card.clip_contents = true
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.custom_minimum_size = Vector2(200, 0)
	UiAnim.hover_pop(card, 1.02)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)

	# Colored visual header band with the product art + badge (handoff card).
	var band: PanelContainer = PanelContainer.new()
	var band_style: StyleBoxFlat = StyleBoxFlat.new()
	band_style.bg_color = Color("#C0350F") if rec.product_type == &"pizza" else Color("#A8692A")
	if rec.archived:
		band_style.bg_color = band_style.bg_color.lerp(Color("#9a8a70"), 0.5)
	band_style.corner_radius_top_left = 11
	band_style.corner_radius_top_right = 11
	band.add_theme_stylebox_override("panel", band_style)
	box.add_child(band)
	var band_stack: Control = Control.new()
	band_stack.custom_minimum_size = Vector2(0, 86)
	band.add_child(band_stack)
	var art: CardArt = CardArt.new(rec.product_type, rec.archived)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	band_stack.add_child(art)
	var badge: PanelContainer = BellaUi.pill(
		"Starter" if rec.is_starter else ("Archived" if rec.archived else rec.product_type.capitalize()),
		BellaUi.INK, BellaUi.PAPER, BellaUi.PAPER_EDGE)
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.position = Vector2(-8, 8)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	band_stack.add_child(badge)

	var body_pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		body_pad.add_theme_constant_override("margin_%s" % side, 10)
	box.add_child(body_pad)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body_pad.add_child(body)
	box = body

	var name_label: Label = Label.new()
	name_label.text = rec.display_name
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_BODY)
	name_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	box.add_child(name_label)

	var stats: Dictionary = RecipeManager.company_stats(rec.id)
	var price: float = RecipeManager.suggested_price_for(rec)
	var margin_pct: int = int((price - rec.cached_cost) / maxf(price, 0.01) * 100.0)
	var info_row: HBoxContainer = HBoxContainer.new()
	box.add_child(info_row)
	var sold: Label = Label.new()
	sold.text = "%d sold" % int(stats["units"])
	sold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sold.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
	sold.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	info_row.add_child(sold)
	var info: Label = Label.new()
	info.text = "$%.1f · %d%% marg" % [price, margin_pct]
	info.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
	info.add_theme_color_override("font_color", BellaUi.GOLD_EDGE)
	info_row.add_child(info)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)
	if rec.archived:
		var restore: Button = Button.new()
		restore.text = "Restore"
		restore.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
		restore.pressed.connect(func() -> void:
			RecipeManager.unarchive(rec)
			_rebuild_book())
		actions.add_child(restore)
	else:
		var open_label: Label = Label.new()
		open_label.text = "Open in workshop  ›"
		open_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open_label.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
		open_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["accent_gold"])
		actions.add_child(open_label)
		if not rec.is_starter:
			var archive: Button = Button.new()
			archive.text = "Archive"
			archive.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
			archive.pressed.connect(func() -> void:
				TycoonConfirmDialog.ask(self, "Archive \"%s\"?" % rec.display_name,
					"It disappears from menus and the book, but stays restorable under Archived.",
					func() -> void:
						RecipeManager.archive(rec)
						_rebuild_book(),
					"Archive"))
			actions.add_child(archive)

	if not rec.archived:
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				open_workshop_requested.emit(rec.id, rec.product_type))
	return card


func _make_new_card() -> Control:
	var card: PanelContainer = PanelContainer.new()
	var dashed: StyleBoxFlat = BellaUi.sunk_box()
	dashed.border_color = TycoonTheme.PALETTE["wood"]
	dashed.set_border_width_all(3)
	card.add_theme_stylebox_override("panel", dashed)
	UiAnim.hover_pop(card, 1.02)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.custom_minimum_size = Vector2(200, 150)
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(box)
	var icon: TextureRect = UiAssets.icon_rect(&"pizza", 36)
	if icon != null:
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
	var label: Label = Label.new()
	label.text = "Open Workshop"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	box.add_child(label)
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_ask_new_recipe())
	return card


func _ask_new_recipe() -> void:
	var picker: Control = Control.new()
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker.mouse_filter = Control.MOUSE_FILTER_STOP
	picker.z_index = 100
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.18, 0.09, 0.04, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			picker.queue_free())
	picker.add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_box())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	picker.add_child(panel)
	var inner: PanelContainer = PanelContainer.new()
	inner.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	panel.add_child(inner)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	inner.add_child(box)
	var title: Label = Label.new()
	title.text = "What are we inventing?"
	title.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	box.add_child(title)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	for product: StringName in [&"pizza", &"burger"]:
		var button: Button = Button.new()
		button.text = " Pizza" if product == &"pizza" else " Burger"
		UiAssets.icon_button(button, product, 34)
		button.custom_minimum_size = Vector2(160, 68)
		TycoonTheme.apply_orange(button)
		var chosen: StringName = product
		button.pressed.connect(func() -> void:
			picker.queue_free()
			open_workshop_requested.emit(&"", chosen))
		buttons.add_child(button)
	add_child(picker)


# --- Tab 2: Base Menu -----------------------------------------------------------


func _build_base_menu_tab() -> void:
	var tab: VBoxContainer = VBoxContainer.new()
	tab.name = "Base Menu"
	tab.add_theme_constant_override("separation", 8)
	_tabs.add_child(tab)
	var hint: Label = Label.new()
	hint.text = "Base-menu recipes are enabled automatically in every NEW restaurant (up to its kitchen stations)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	tab.add_child(hint)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	_base_menu_box = VBoxContainer.new()
	_base_menu_box.add_theme_constant_override("separation", 6)
	_base_menu_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_base_menu_box)
	_rebuild_base_menu()


func _rebuild_base_menu() -> void:
	if _base_menu_box == null:
		return
	for child: Node in _base_menu_box.get_children():
		child.queue_free()
	for rec: RecipeDef in RecipeManager.live_recipes():
		var row: PanelContainer = make_row()
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		row.add_child(box)
		var check: CheckBox = CheckBox.new()
		check.set_pressed_no_signal(RecipeManager.book.base_menu_ids.has(rec.id))
		var rec_id: StringName = rec.id
		check.toggled.connect(func(on: bool) -> void:
			if on and not RecipeManager.book.base_menu_ids.has(rec_id):
				RecipeManager.book.base_menu_ids.append(rec_id)
			elif not on:
				RecipeManager.book.base_menu_ids.erase(rec_id))
		box.add_child(check)
		var name_label: Label = Label.new()
		name_label.text = "%s  (%s)" % [rec.display_name, rec.product_type.capitalize()]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(name_label)
		var price: Label = Label.new()
		price.text = "$%.1f" % RecipeManager.suggested_price_for(rec)
		price.add_theme_color_override("font_color", TycoonTheme.PALETTE["accent_gold"])
		box.add_child(price)
		_base_menu_box.add_child(row)


# --- Tab 3: Restaurant Menu (former menu_screen) --------------------------------


func _build_restaurant_menu_tab() -> void:
	var tab: VBoxContainer = VBoxContainer.new()
	tab.name = "Restaurant Menu"
	tab.add_theme_constant_override("separation", 8)
	_tabs.add_child(tab)
	var hint: Label = Label.new()
	hint.text = "Tick a recipe to sell it here. Quality changes ingredient cost and reputation; every enabled item needs a kitchen station."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	tab.add_child(hint)
	var slots_row: HBoxContainer = HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 10)
	_slots_label = Label.new()
	_slots_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_label.add_theme_color_override("font_color", Color("#8a5a2b"))
	slots_row.add_child(_slots_label)
	_buy_button = Button.new()
	_buy_button.disabled = true
	_buy_button.tooltip_text = "Kitchen capacity now comes from the interior: place prep counters and shelves in Edit Interior."
	slots_row.add_child(_buy_button)
	tab.add_child(slots_row)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	_menu_list = VBoxContainer.new()
	_menu_list.add_theme_constant_override("separation", 6)
	_menu_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_menu_list)
	_rebuild_menu_rows()


func _rebuild_menu_rows() -> void:
	for child: Node in _menu_list.get_children():
		child.queue_free()
	_menu_rows.clear()
	var rest: RestaurantState = restaurant()
	if rest == null:
		var none: Label = Label.new()
		none.text = "Select one of your restaurants first."
		_menu_list.add_child(none)
		return
	for entry: MenuEntry in rest.menu:
		var item: Dictionary = RestaurantManager.resolve_item(entry.dish_id)
		if item.is_empty():
			continue
		_menu_list.add_child(_make_menu_row(entry, item))


func _make_menu_row(entry: MenuEntry, item: Dictionary) -> Control:
	var row: PanelContainer = make_row()
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)

	var enabled: CheckBox = CheckBox.new()
	enabled.button_pressed = entry.enabled
	box.add_child(enabled)

	var name_label: Label = Label.new()
	name_label.text = String(item["display_name"])
	name_label.custom_minimum_size.x = 150
	box.add_child(name_label)

	var prep: Label = Label.new()
	prep.text = "⏱ %d min" % int(item["prep_minutes"])
	prep.add_theme_color_override("font_color", Color("#8a7150"))
	box.add_child(prep)

	var tier_select: OptionButton = OptionButton.new()
	for tier: QualityTier in item["tiers"]:
		tier_select.add_item("%s ($%.2f)" % [tier.display_name, tier.ingredient_cost])
		tier_select.set_item_metadata(tier_select.item_count - 1, tier.tier)
	_select_tier(tier_select, entry.tier)
	box.add_child(tier_select)

	var price: SpinBox = SpinBox.new()
	price.min_value = 0.5
	price.max_value = 99.0
	price.step = 0.5
	price.prefix = "$"
	price.value = entry.price
	box.add_child(price)

	var margin: Label = Label.new()
	margin.custom_minimum_size.x = 110
	box.add_child(margin)

	_menu_rows[entry.dish_id] = {
		"enabled": enabled, "tier": tier_select, "price": price, "margin": margin,
	}
	var apply: Callable = func(_arg: Variant = null) -> void:
		_apply_menu_row(entry.dish_id)
		refresh()
	enabled.toggled.connect(apply)
	price.value_changed.connect(apply)
	tier_select.item_selected.connect(apply)
	_update_margin(entry.dish_id)
	return row


func _refresh_menu_tab() -> void:
	var rest: RestaurantState = restaurant()
	if rest == null or _slots_label == null:
		return
	_slots_label.text = "Kitchen stations: %d/%d used · menu upkeep $%.0f/day" % [
		rest.enabled_dish_count(), rest.menu_slots, RestaurantManager.menu_upkeep_for(rest)]
	_buy_button.text = "Build prep counters in Edit Interior"
	_buy_button.disabled = true
	# New book entries (fresh saves from the workshop) need new rows.
	var expected: int = 0
	for entry: MenuEntry in rest.menu:
		if not RestaurantManager.resolve_item(entry.dish_id).is_empty():
			expected += 1
	if expected != _menu_rows.size():
		_rebuild_menu_rows()
		return
	for dish_id: StringName in _menu_rows:
		var entry: MenuEntry = null
		for candidate: MenuEntry in rest.menu:
			if candidate.dish_id == dish_id:
				entry = candidate
				break
		if entry == null:
			continue
		var row: Dictionary = _menu_rows[dish_id]
		var checkbox: CheckBox = row["enabled"]
		checkbox.set_pressed_no_signal(entry.enabled)
		var full: bool = rest.enabled_dish_count() >= rest.menu_slots
		checkbox.disabled = full and not entry.enabled
		checkbox.tooltip_text = "All kitchen stations are in use." if checkbox.disabled else ""
		(row["price"] as SpinBox).set_value_no_signal(entry.price)
		_select_tier(row["tier"] as OptionButton, entry.tier)
		_update_margin(dish_id)


func _apply_menu_row(dish_id: StringName) -> void:
	var row: Dictionary = _menu_rows[dish_id]
	var tier_select: OptionButton = row["tier"]
	var tier: StringName = tier_select.get_item_metadata(tier_select.selected)
	var router := get_node_or_null("/root/BranchCommandRouter")
	if router == null or CompanyManager.player == null:
		EconomyManager.post_message("alert", "The branch command router is unavailable.")
		return
	_command_serial += 1
	var result := router.call("execute", &"menu.set_entry", {
		"building_id": building_id,
		"dish_id": dish_id,
		"price": (row["price"] as SpinBox).value,
		"tier": tier,
		"enabled": (row["enabled"] as CheckBox).button_pressed,
	}, {
		"kind": &"player",
		"id": "recipes_workspace",
		"company_id": CompanyManager.player.id,
	}, "ui:menu:%d:%s:%d:%d" % [building_id, dish_id,
		GameClock.total_minutes(), _command_serial]) as CommandResult
	if result == null or not result.ok:
		EconomyManager.post_message("alert",
			result.message if result != null else "The menu command was unavailable.")
		return
	_update_margin(dish_id)


func _update_margin(dish_id: StringName) -> void:
	var row: Dictionary = _menu_rows[dish_id]
	var item: Dictionary = RestaurantManager.resolve_item(dish_id)
	var tier_select: OptionButton = row["tier"]
	if item.is_empty() or tier_select.selected < 0:
		return
	var tier_id: StringName = tier_select.get_item_metadata(tier_select.selected)
	var tier: QualityTier = null
	for t: QualityTier in item["tiers"]:
		if t.tier == tier_id:
			tier = t
			break
	if tier == null:
		return
	var price: float = (row["price"] as SpinBox).value
	var margin: float = price - tier.ingredient_cost
	var label: Label = row["margin"]
	label.text = "profit $%.2f · $%.0f/day" % [margin, RestaurantManager.upkeep_for_id(dish_id, tier.tier)]
	label.add_theme_color_override(
		"font_color", Color("#2e7d32") if margin > 0.0 else Color("#c0392b"))


func _select_tier(tier_select: OptionButton, tier: StringName) -> void:
	for i: int in tier_select.item_count:
		if tier_select.get_item_metadata(i) == tier:
			tier_select.select(i)
			return


# --- Tab 4: Performance ----------------------------------------------------------


func _build_performance_tab() -> void:
	var tab: VBoxContainer = VBoxContainer.new()
	tab.name = "Performance"
	tab.add_theme_constant_override("separation", 8)
	_tabs.add_child(tab)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	_performance_box = VBoxContainer.new()
	_performance_box.add_theme_constant_override("separation", 6)
	_performance_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_performance_box)
	_rebuild_performance()


func _rebuild_performance() -> void:
	if _performance_box == null:
		return
	for child: Node in _performance_box.get_children():
		child.queue_free()
	# Product-type comparison summary.
	var totals: Dictionary = {&"pizza": {"units": 0, "revenue": 0.0}, &"burger": {"units": 0, "revenue": 0.0}}
	for rec: RecipeDef in RecipeManager.live_recipes():
		var stats: Dictionary = RecipeManager.company_stats(rec.id)
		if totals.has(rec.product_type):
			totals[rec.product_type]["units"] += int(stats["units"])
			totals[rec.product_type]["revenue"] += float(stats["revenue"])
	var summary: Label = Label.new()
	summary.text = "Pizza: %d sold · $%.0f      Burger: %d sold · $%.0f" % [
		totals[&"pizza"]["units"], totals[&"pizza"]["revenue"],
		totals[&"burger"]["units"], totals[&"burger"]["revenue"]]
	summary.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	summary.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_TITLE)
	_performance_box.add_child(summary)
	var any_sales: bool = false
	for rec: RecipeDef in RecipeManager.live_recipes():
		var row: Control = _make_performance_row(rec)
		if row != null:
			any_sales = true
			_performance_box.add_child(row)
	if not any_sales:
		var placeholder: Label = Label.new()
		placeholder.text = "Sell some recipes to see performance data — enable them on the Restaurant Menu tab."
		placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		placeholder.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		_performance_box.add_child(placeholder)


func _make_performance_row(rec: RecipeDef) -> Control:
	var stats: Dictionary = RecipeManager.company_stats(rec.id)
	var units: int = int(stats["units"])
	if units <= 0:
		return null
	var revenue: float = float(stats["revenue"])
	var cost: float = float(stats["cost"])
	var row: PanelContainer = make_row()
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	row.add_child(box)

	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)
	var icon: TextureRect = UiAssets.icon_rect(
		&"pizza" if rec.product_type == &"pizza" else &"burger", 22)
	if icon != null:
		top.add_child(icon)
	var name_label: Label = Label.new()
	name_label.text = "%s  (v%d)" % [rec.display_name, rec.version]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	top.add_child(name_label)
	var numbers: Label = Label.new()
	var margin_pct: int = int((revenue - cost) / maxf(revenue, 0.01) * 100.0)
	numbers.text = "%d sold · $%.0f revenue · %d%% margin" % [units, revenue, margin_pct]
	numbers.add_theme_color_override("font_color", BellaUi.GOLD_EDGE)
	top.add_child(numbers)

	var detail: HBoxContainer = HBoxContainer.new()
	detail.add_theme_constant_override("separation", 12)
	box.add_child(detail)
	var appeal_label: Label = Label.new()
	var overall: float = 0.0
	for segment: StringName in rec.cached_appeal:
		overall += float(rec.cached_appeal[segment])
	if not rec.cached_appeal.is_empty():
		overall /= float(rec.cached_appeal.size())
	var uncertainty: float = RecipeManager.uncertainty_for(rec.id)
	appeal_label.text = "Appeal %d%%%s" % [int(overall * 100.0),
		"" if uncertainty < 0.05 else " ±%d" % int(uncertainty * 15.0)]
	appeal_label.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
	appeal_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	detail.add_child(appeal_label)
	# Predicted vs observed segment response.
	var seg_counts: Dictionary = stats["by_segment"]
	for segment: StringName in RecipeManager.SEGMENTS:
		var observed: float = float(seg_counts.get(segment, 0)) / float(units)
		var seg_label: Label = Label.new()
		seg_label.text = "%s %d%%" % [String(segment).capitalize().left(3), int(observed * 100.0)]
		seg_label.tooltip_text = "%s: %d%% of sales · predicted appeal %d%%" % [
			String(segment).capitalize(), int(observed * 100.0),
			int(float(rec.cached_appeal.get(segment, 0.0)) * 100.0)]
		seg_label.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
		seg_label.add_theme_color_override("font_color",
			TycoonTheme.PALETTE["good"] if observed >= 0.25 else TycoonTheme.PALETTE["text_soft"])
		detail.add_child(seg_label)
	# Older archived versions, for comparison.
	for old: RecipeDef in RecipeManager.book.archived:
		if old.id != rec.id:
			continue
		var old_stats: Dictionary = RecipeManager.company_stats(old.id, old.version)
		if int(old_stats["units"]) <= 0:
			continue
		var old_label: Label = Label.new()
		old_label.text = "    v%d: %d sold · $%.0f" % [old.version, int(old_stats["units"]), float(old_stats["revenue"])]
		old_label.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
		old_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		box.add_child(old_label)
	return row


# --- Tab 5: Competitions ------------------------------------------------------------


func _build_competitions_tab() -> void:
	var tab: VBoxContainer = VBoxContainer.new()
	tab.name = "Competitions"
	tab.add_theme_constant_override("separation", 8)
	_tabs.add_child(tab)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	_competitions_box = VBoxContainer.new()
	_competitions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_competitions_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_competitions_box)
	_rebuild_competitions()


## Live contest list — the full flow (entries, podium, challenges) lives on
## the Awards & Competitions screen; this tab is the recipe-side doorway.
func _rebuild_competitions() -> void:
	for child: Node in _competitions_box.get_children():
		child.queue_free()
	var awards: Node = get_tree().root.get_node_or_null(^"AwardsManager")
	var open_btn: Button = Button.new()
	open_btn.text = "Open Awards & Competitions"
	TycoonTheme.apply_orange(open_btn)
	open_btn.pressed.connect(func() -> void: request_screen.emit(&"awards"))
	_competitions_box.add_child(open_btn)
	if awards == null:
		return
	var player_id: StringName = CompanyManager.player.id
	var shown: int = 0
	for comp: CompetitionState in awards.active_competitions():
		var def: CompetitionDef = awards.competition_defs.get(comp.def_id)
		if def == null:
			continue
		shown += 1
		var row: PanelContainer = make_row()
		_competitions_box.add_child(row)
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		row.add_child(box)
		box.add_child(UiAssets.icon_rect(def.icon, 24))
		var text: VBoxContainer = VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(text)
		var title: Label = Label.new()
		title.text = def.display_name
		text.add_child(title)
		var detail: Label = Label.new()
		var entered: String = "entered" if comp.has_entry(player_id) else "no entry yet"
		match comp.status:
			&"entry":
				detail.text = "%s · entries close day %d · %s" % [def.brief, comp.deadline_day, entered]
			&"locked":
				detail.text = "Entries locked · judging day %d · %s" % [comp.judging_day, entered]
			_:
				detail.text = "Results are in — see the podium on the Awards screen."
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_theme_font_size_override("font_size", 12)
		detail.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		text.add_child(detail)
	if shown == 0:
		var hint: Label = Label.new()
		hint.text = "No contest is running. Your frozen recipe versions are the entries when one opens."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
		_competitions_box.add_child(hint)
