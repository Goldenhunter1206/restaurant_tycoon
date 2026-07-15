class_name InteriorEditor
extends Control
## Edit-mode chrome of the interior editor, styled after the Bella Vista D9
## mock: catalog sidebar (category chips + priced item tiles), live capacity
## strip, budget pill and undo / save / discard controls. Owns the DRAFT
## layout and its UndoStack; all 3D interaction happens in the paired
## InteriorEditController. Money only moves on "Save layout", which routes
## through RestaurantManager.edit_interior().

signal closed(applied: bool)

const CATEGORIES: Array = [
	[&"seating", "Seating"],
	[&"kitchen", "Kitchen"],
	[&"service", "Service"],
	[&"decor", "Decor"],
	[&"entertainment", "Fun"],
	[&"utility", "Utility"],
	[&"finishes", "Style"],
	[&"sets", "Sets"],
]

var building_id: int = -1

var _controller: InteriorEditController = null
var _view: Node3D = null
var _service: InteriorLayoutService = null
var _undo: UndoStack = UndoStack.new()
var _last_snapshot: InteriorLayoutState = null
var _active_category: StringName = &"seating"
## Designer set loaded into the draft; its fee is charged on commit.
var _pending_template: InteriorTemplateDef = null

var _category_row: HBoxContainer = null
var _tile_grid: GridContainer = null
var _budget_label: Label = null
var _stats_label: Label = null
var _hover_label: Label = null
var _warning_label: Label = null
var _undo_button: Button = null
var _redo_button: Button = null


func setup(target_building_id: int, controller: InteriorEditController, view: Node3D) -> void:
	building_id = target_building_id
	_controller = controller
	_view = view
	_service = RestaurantManager.interior
	_last_snapshot = controller.draft.deep_copy()
	controller.draft_changed.connect(_on_draft_changed)
	controller.hover_changed.connect(_on_hover_changed)
	_undo.history_changed.connect(_refresh_history_buttons)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_sidebar()
	_build_bottom_bar()
	_build_status_strip()
	_refresh_catalog()
	_refresh_stats()


# --- UI construction ------------------------------------------------------------


func _build_sidebar() -> void:
	var side: PanelContainer = PanelContainer.new()
	side.name = "Catalog"
	side.mouse_filter = Control.MOUSE_FILTER_STOP
	side.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	side.offset_top = 74.0
	side.offset_bottom = -86.0
	side.offset_left = 12.0
	side.offset_right = 262.0
	side.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
	add_child(side)
	var paper: PanelContainer = PanelContainer.new()
	paper.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	side.add_child(paper)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	paper.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	if UiAssets.icon(&"hammer") != null:
		header.add_child(UiAssets.icon_rect(&"hammer", 24))
	var title: Label = Label.new()
	title.text = "BUILD"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	header.add_child(title)
	column.add_child(header)
	_category_row = HBoxContainer.new()
	_category_row.add_theme_constant_override("separation", 4)
	column.add_child(_category_row)
	var second_row: HBoxContainer = HBoxContainer.new()
	second_row.name = "CategoryRow2"
	second_row.add_theme_constant_override("separation", 4)
	column.add_child(second_row)
	for i: int in range(CATEGORIES.size()):
		var cat: StringName = CATEGORIES[i][0]
		var chip: Button = BellaUi.chip(String(CATEGORIES[i][1]), cat == _active_category)
		chip.pressed.connect(func() -> void:
			_active_category = cat
			_refresh_catalog())
		(_category_row if i < 4 else second_row).add_child(chip)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_tile_grid = GridContainer.new()
	_tile_grid.columns = 2
	_tile_grid.add_theme_constant_override("h_separation", 8)
	_tile_grid.add_theme_constant_override("v_separation", 8)
	_tile_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_tile_grid)
	var hint: Label = Label.new()
	hint.text = "LMB place/select · drag move\nR rotate · V recolor · D copy\nDel sell · RMB cancel"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	column.add_child(hint)


func _build_bottom_bar() -> void:
	var budget: PanelContainer = PanelContainer.new()
	budget.name = "BudgetPill"
	budget.mouse_filter = Control.MOUSE_FILTER_STOP
	budget.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	budget.offset_left = 12.0
	budget.offset_top = -74.0
	budget.offset_bottom = -14.0
	budget.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	add_child(budget)
	_budget_label = Label.new()
	_budget_label.add_theme_font_size_override("font_size", 18)
	_budget_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	budget.add_child(_budget_label)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 8)
	actions.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	actions.offset_right = -12.0
	actions.offset_top = -66.0
	actions.offset_bottom = -14.0
	actions.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(actions)
	_undo_button = Button.new()
	_undo_button.text = "↩ Undo"
	_undo_button.custom_minimum_size = Vector2(96, 48)
	TycoonTheme.apply_orange(_undo_button)
	_undo_button.pressed.connect(_do_undo)
	actions.add_child(_undo_button)
	_redo_button = Button.new()
	_redo_button.text = "Redo ↪"
	_redo_button.custom_minimum_size = Vector2(96, 48)
	TycoonTheme.apply_orange(_redo_button)
	_redo_button.pressed.connect(_do_redo)
	actions.add_child(_redo_button)
	var repair: Button = Button.new()
	repair.text = "🔧 Repair"
	repair.tooltip_text = "Repair and clean the selected furniture (everything when nothing is selected). Paid immediately."
	repair.custom_minimum_size = Vector2(110, 48)
	TycoonTheme.apply_orange(repair)
	repair.pressed.connect(_repair_selected)
	actions.add_child(repair)
	var discard: Button = Button.new()
	discard.text = "Discard"
	discard.custom_minimum_size = Vector2(110, 48)
	TycoonTheme.apply_orange(discard)
	discard.pressed.connect(func() -> void: closed.emit(false))
	actions.add_child(discard)
	var save: Button = Button.new()
	save.text = "✓ Save Layout"
	save.custom_minimum_size = Vector2(150, 48)
	BellaUi.green_button(save)
	save.pressed.connect(_commit)
	actions.add_child(save)
	_refresh_history_buttons()


func _build_status_strip() -> void:
	var strip: PanelContainer = PanelContainer.new()
	strip.name = "StatusStrip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	strip.offset_left = -560.0
	strip.offset_right = -12.0
	strip.offset_top = 74.0
	strip.offset_bottom = 148.0
	strip.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	add_child(strip)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	strip.add_child(box)
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 16)
	_stats_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	box.add_child(_stats_label)
	_warning_label = Label.new()
	_warning_label.add_theme_font_size_override("font_size", 13)
	_warning_label.add_theme_color_override("font_color", Color("#b3341f"))
	box.add_child(_warning_label)
	_hover_label = Label.new()
	_hover_label.add_theme_font_size_override("font_size", 13)
	_hover_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	box.add_child(_hover_label)


# --- Catalog --------------------------------------------------------------------


func _refresh_catalog() -> void:
	for i: int in range(_category_row.get_child_count()):
		BellaUi.style_chip(_category_row.get_child(i), CATEGORIES[i][0] == _active_category)
	var row2: Node = _category_row.get_parent().get_node("CategoryRow2")
	for i: int in range(row2.get_child_count()):
		BellaUi.style_chip(row2.get_child(i), CATEGORIES[i + 4][0] == _active_category)
	for child: Node in _tile_grid.get_children():
		child.queue_free()
	if _active_category == &"finishes":
		_fill_finish_tiles()
		return
	if _active_category == &"sets":
		_fill_template_tiles()
		return
	for def: FurnitureDef in _service.catalog_by_category(_active_category):
		_tile_grid.add_child(_make_tile(def))


func _fill_template_tiles() -> void:
	var expand_tile: Button = Button.new()
	expand_tile.custom_minimum_size = Vector2(212, 56)
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	var level: int = rest.interior_layout.expansion_level
	if level >= 2:
		expand_tile.text = "Fully expanded"
		expand_tile.disabled = true
	else:
		var cost: float = maxf(2000.0, rest.property_value * 0.25) * float(level + 1)
		expand_tile.text = "🔨 Expand room · $%s" % _fmt(cost)
		expand_tile.tooltip_text = "Pushes the front wall out by 4 m. Paid immediately."
	TycoonTheme.apply_orange(expand_tile)
	expand_tile.pressed.connect(_expand_room)
	_tile_grid.add_child(expand_tile)
	_tile_grid.add_child(Control.new())
	for tpl: InteriorTemplateDef in _service.templates.values():
		_tile_grid.add_child(_make_template_tile(tpl))


func _make_template_tile(tpl: InteriorTemplateDef) -> Button:
	var unlocked: bool = tpl.prereq_cap == &"" or CapabilityRegistry.has(&"player", tpl.prereq_cap)
	var tile: Button = Button.new()
	tile.custom_minimum_size = Vector2(212, 84)
	tile.add_theme_stylebox_override("normal", BellaUi.tile_box())
	tile.add_theme_stylebox_override("hover", BellaUi.tile_box(TycoonTheme.PALETTE["accent_gold"], 2))
	tile.add_theme_stylebox_override("pressed", BellaUi.tile_box(TycoonTheme.PALETTE["accent_gold"], 3))
	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile.add_child(box)
	var name_label: Label = Label.new()
	name_label.text = ("🔒 " if not unlocked else "") + tpl.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text"])
	box.add_child(name_label)
	var detail: Label = Label.new()
	var draft_cost: Dictionary = _service.price_diff(_controller.draft, tpl.build_layout())
	detail.text = "≈ $%s + $%s fee" % [_fmt(maxf(0.0, float(draft_cost["net"]))), _fmt(tpl.design_fee)]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", Color("#b5810a"))
	box.add_child(detail)
	if unlocked:
		tile.tooltip_text = "%s\nLoads this set into the draft — review, then Save Layout to buy. The design fee is charged on save." % tpl.blurb
		tile.pressed.connect(func() -> void: _load_template(tpl))
	else:
		tile.tooltip_text = CapabilityRegistry.explain(&"player", tpl.prereq_cap)
		tile.disabled = true
	return tile


## Loads a designer set into the draft for preview; money moves on commit.
func _load_template(tpl: InteriorTemplateDef) -> void:
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	var draft: InteriorLayoutState = tpl.build_layout()
	draft.expansion_level = rest.interior_layout.expansion_level
	draft.grid_rows = rest.interior_layout.grid_rows
	draft.grid_cols = rest.interior_layout.grid_cols
	_pending_template = tpl
	_controller.draft = draft
	_controller.clear_tool()
	_view.rebuild_preview(draft)
	_controller.notify_draft_changed()


func _expand_room() -> void:
	var result: CommandResult = RestaurantManager.expand_interior_cmd(&"player", building_id)
	if not result.ok:
		_warning_label.text = "✗ %s" % result.message
		return
	# Sync the draft to the grown room and rebuild the scene shell.
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	_controller.draft.expansion_level = rest.interior_layout.expansion_level
	_controller.draft.grid_rows = rest.interior_layout.grid_rows
	_view.rebuild_preview(_controller.draft)
	_controller.notify_draft_changed()
	_refresh_catalog()


func _fill_finish_tiles() -> void:
	var draft: InteriorLayoutState = _controller.draft
	for group: Array in [[&"floor", "FLOOR"], [&"wall", "WALLS"], [&"music", "MUSIC"]]:
		var header: Label = Label.new()
		header.text = String(group[1])
		header.add_theme_font_size_override("font_size", 13)
		header.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_dark"])
		_tile_grid.add_child(header)
		_tile_grid.add_child(Control.new())
		for fin: InteriorFinishDef in _service.finishes_by_kind(group[0]):
			_tile_grid.add_child(_make_finish_tile(fin, draft))


func _make_finish_tile(fin: InteriorFinishDef, draft: InteriorLayoutState) -> Button:
	var active: bool = (
		(fin.kind == &"floor" and draft.floor_finish == fin.id)
		or (fin.kind == &"wall" and draft.wall_finish == fin.id)
		or (fin.kind == &"music" and draft.music == fin.id))
	var tile: Button = Button.new()
	tile.custom_minimum_size = Vector2(104, 66)
	var border: Color = TycoonTheme.PALETTE["accent_green"] if active else TycoonTheme.PALETTE["panel_dark"]
	tile.add_theme_stylebox_override("normal", BellaUi.tile_box(border, 3 if active else 2))
	tile.add_theme_stylebox_override("hover", BellaUi.tile_box(TycoonTheme.PALETTE["accent_gold"], 2))
	tile.add_theme_stylebox_override("pressed", BellaUi.tile_box(TycoonTheme.PALETTE["accent_gold"], 3))
	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile.add_child(box)
	var name_label: Label = Label.new()
	name_label.text = fin.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text"])
	box.add_child(name_label)
	var price: Label = Label.new()
	price.text = "$%.0f/day" % fin.daily_cost if fin.kind == &"music" else ("$%.0f" % fin.price if fin.price > 0.0 else "Included")
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_font_size_override("font_size", 12)
	price.add_theme_color_override("font_color", Color("#b5810a"))
	box.add_child(price)
	tile.pressed.connect(func() -> void:
		match fin.kind:
			&"floor":
				_controller.draft.floor_finish = fin.id
			&"wall":
				_controller.draft.wall_finish = fin.id
			&"music":
				_controller.draft.music = fin.id
		_controller.notify_draft_changed()
		_refresh_catalog())
	return tile


func _make_tile(def: FurnitureDef) -> Button:
	var tile: Button = Button.new()
	tile.custom_minimum_size = Vector2(104, 92)
	tile.tooltip_text = "%s\n%s" % [def.display_name, def.blurb]
	tile.add_theme_stylebox_override("normal", BellaUi.tile_box())
	tile.add_theme_stylebox_override("hover", BellaUi.tile_box(TycoonTheme.PALETTE["accent_gold"], 2))
	tile.add_theme_stylebox_override("pressed", BellaUi.tile_box(TycoonTheme.PALETTE["accent_gold"], 3))
	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile.add_child(box)
	if UiAssets.icon(def.icon) != null:
		var icon: TextureRect = UiAssets.icon_rect(def.icon, 34)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
	var name_label: Label = Label.new()
	name_label.text = def.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text"])
	box.add_child(name_label)
	var price: Label = Label.new()
	price.text = "$%.0f" % def.price
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_font_size_override("font_size", 13)
	price.add_theme_color_override("font_color", Color("#b5810a"))
	box.add_child(price)
	tile.pressed.connect(func() -> void: _controller.set_place_def(def))
	return tile


# --- Draft bookkeeping ------------------------------------------------------------


func _on_draft_changed() -> void:
	_undo.push(_last_snapshot)
	_last_snapshot = _controller.draft.deep_copy()
	_refresh_stats()


func _do_undo() -> void:
	var snapshot: Variant = _undo.undo(_controller.draft.deep_copy())
	if snapshot == null:
		return
	_restore(snapshot)


func _do_redo() -> void:
	var snapshot: Variant = _undo.redo(_controller.draft.deep_copy())
	if snapshot == null:
		return
	_restore(snapshot)


func _restore(snapshot: InteriorLayoutState) -> void:
	_controller.draft = snapshot
	_last_snapshot = snapshot.deep_copy()
	_view.rebuild_preview(snapshot)
	_controller.clear_tool()
	_refresh_stats()


func _refresh_history_buttons() -> void:
	if _undo_button != null:
		_undo_button.disabled = not _undo.can_undo()
	if _redo_button != null:
		_redo_button.disabled = not _undo.can_redo()


func _refresh_stats() -> void:
	var draft: InteriorLayoutState = _controller.draft
	var ev: InteriorEvaluation = _service.evaluate(draft)
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null:
		return
	_stats_label.text = "Tables %d · Seats %d · Stations %d · Pickup %d · Menu %d" % [
		ev.table_seats.size(), ev.seats, ev.cook_stations, ev.pickup_slots, ev.menu_capacity]
	var blocking: Array[Dictionary] = ev.blocking_issues()
	if not blocking.is_empty():
		_warning_label.text = "✗ %s" % String(blocking[0].get("message", ""))
	elif not ev.issues.is_empty():
		_warning_label.text = "⚠ %s" % String(ev.issues[0].get("message", ""))
	else:
		_warning_label.text = ""
	var diff: Dictionary = _service.price_diff(rest.interior_layout, draft)
	var net: float = float(diff["net"])
	var cash: float = rest.company().cash
	var verdict: String = "" if net <= cash else "  · CAN'T AFFORD"
	_budget_label.text = "Cash $%s   ·   This plan: %s$%s%s" % [
		_fmt(cash), "-" if net > 0.0 else "+", _fmt(absf(net)), verdict]


func _on_hover_changed(text: String) -> void:
	if _hover_label != null:
		_hover_label.text = text


func _fmt(value: float) -> String:
	var raw: String = "%.0f" % absf(value)
	var out: String = ""
	var count: int = 0
	for i: int in range(raw.length() - 1, -1, -1):
		out = raw[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


func _repair_selected() -> void:
	var ids: Array[int] = _controller.selected_ids()
	if ids.is_empty():
		for item: PlacedFurnitureState in _controller.draft.placed:
			ids.append(item.instance_id)
	var result: CommandResult = RestaurantManager.repair_furniture_cmd(&"player", building_id, ids)
	if not result.ok:
		_warning_label.text = "✗ %s" % result.message
		return
	# Mirror the repaired condition into the draft (same instance ids).
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	for id: int in ids:
		var live: PlacedFurnitureState = rest.interior_layout.find(id)
		var mine: PlacedFurnitureState = _controller.draft.find(id)
		if live != null and mine != null:
			mine.durability = live.durability
			mine.cleanliness = live.cleanliness
	var info: Dictionary = result.payload
	_hover_label.text = "Repaired %d items for $%.0f" % [int(info["count"]), float(info["cost"])]
	_refresh_stats()


# --- Commit ----------------------------------------------------------------------


func _commit() -> void:
	if _pending_template != null:
		# Route through the template command so the design fee applies.
		if _layouts_equal(_controller.draft, _pending_template):
			var template_result: CommandResult = RestaurantManager.apply_template_cmd(&"player", building_id, _pending_template.id)
			if not template_result.ok:
				_warning_label.text = "✗ %s" % template_result.message
				return
			closed.emit(true)
			return
	var result: CommandResult = RestaurantManager.edit_interior(building_id, _controller.draft)
	if not result.ok:
		_warning_label.text = "✗ %s" % result.message
		return
	closed.emit(true)


func _layouts_equal(draft: InteriorLayoutState, tpl: InteriorTemplateDef) -> bool:
	## True while the loaded set is untouched (same item count and finishes).
	return (
		draft.placed.size() == tpl.items.size()
		and draft.floor_finish == tpl.floor_finish
		and draft.wall_finish == tpl.wall_finish
		and draft.music == tpl.music)
