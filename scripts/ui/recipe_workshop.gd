class_name RecipeWorkshop
extends Control
## Full-screen recipe editor (pizza canvas or burger stack), following the
## InteriorViewer takeover pattern: hides the HUD, freezes city camera and
## selection input, restores everything in _exit_tree. Layout follows the
## Bella Vista handoff: ingredient browser left, assembly canvas center,
## component list + metrics right.

var hud: Control = null

var building_id: int = -1
var draft: RecipeDef = null
## Recipe id being edited in place, &"" when creating a new one.
var _editing_id: StringName = &""
var _dirty: bool = false

var _undo_stack: UndoStack = UndoStack.new()
var _camera_rig: Node3D = null
var _root_3d_was_disabled: bool = false

var _browser: IngredientBrowser
var _metrics: RecipeMetricsPanel
var _pizza_canvas: PizzaCanvas
var _burger_stack: BurgerStack
var _name_edit: LineEdit
var _breadcrumb: Label
var _draft_pill: Label
var _undo_button: Button
var _redo_button: Button
var _base_select: OptionButton
var _distribute_button: Button
var _info_chip_holder: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = TycoonTheme.build()
	var bg: ColorRect = ColorRect.new()
	bg.color = TycoonTheme.PALETTE["panel_dark"]
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_capture_city_input()
	_undo_stack.history_changed.connect(_refresh_history_buttons)


func _exit_tree() -> void:
	_release_city_input()


func setup(a_building_id: int, recipe: RecipeDef = null, product_type: StringName = &"pizza") -> void:
	building_id = a_building_id
	if recipe != null:
		if recipe.is_starter:
			# Starters are immutable — edit a fresh custom copy instead.
			draft = RecipeManager.clone_as_new(recipe)
			_editing_id = &""
		else:
			draft = recipe.duplicate_recipe()
			_editing_id = recipe.id
	else:
		draft = RecipeManager.new_draft(product_type, _default_base(product_type))
		_editing_id = &""
	RecipeManager.recalc(draft)
	_build_ui()
	_sync_all()


func _default_base(product_type: StringName) -> StringName:
	var ids: Array = RecipeManager.bases.keys()
	ids.sort()
	for id: StringName in ids:
		if (RecipeManager.bases[id] as RecipeBaseDef).product_type == product_type:
			return id
	return &""


func close() -> void:
	if _dirty:
		TycoonConfirmDialog.ask(self, "Discard draft?",
			"\"%s\" has unsaved changes that will be lost." % draft.display_name,
			func() -> void: _close_now(), "Discard")
	else:
		_close_now()


func _close_now() -> void:
	queue_free()
	if is_instance_valid(hud) and hud.has_method("_on_action"):
		hud.call_deferred("_on_action", &"recipes", building_id)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event
		if key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
		elif key.keycode == KEY_Z and key.is_command_or_control_pressed():
			get_viewport().set_input_as_handled()
			if key.shift_pressed:
				_redo()
			else:
				_undo()


# --- UI construction --------------------------------------------------------


func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(_build_header())

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	# Left: ingredient browser.
	var left: PanelContainer = PanelContainer.new()
	left.add_theme_stylebox_override("panel", TycoonTheme.panel_box())
	body.add_child(left)
	var left_pad: MarginContainer = _pad(10)
	left.add_child(left_pad)
	_browser = IngredientBrowser.new()
	_browser.setup(draft.product_type)
	_browser.ingredient_armed.connect(_on_ingredient_armed)
	_browser.ingredient_disarmed.connect(_on_ingredient_disarmed)
	left_pad.add_child(_browser)

	# Center: toolbar + canvas.
	var center: VBoxContainer = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 0)
	body.add_child(center)
	center.add_child(_build_toolbar())
	var canvas_holder: Control = Control.new()
	canvas_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_holder.clip_contents = true
	center.add_child(canvas_holder)
	canvas_holder.add_child(BellaUi.radial_backdrop())
	if draft.product_type == &"pizza":
		_pizza_canvas = PizzaCanvas.new()
		_pizza_canvas.component_selected.connect(_on_component_selected)
		_pizza_canvas.place_requested.connect(_on_place_requested)
		_pizza_canvas.remove_requested.connect(_on_remove_component)
		_pizza_canvas.edit_committed.connect(_on_canvas_edit)
		_pizza_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		canvas_holder.add_child(_pizza_canvas)
	else:
		_burger_stack = BurgerStack.new()
		_burger_stack.component_selected.connect(_on_component_selected)
		_burger_stack.remove_requested.connect(_on_remove_component)
		_burger_stack.edit_committed.connect(_on_canvas_edit)
		_burger_stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		canvas_holder.add_child(_burger_stack)
	# Info chips (top-left) and hint pill (bottom-left) float over the canvas.
	_info_chip_holder = HBoxContainer.new()
	_info_chip_holder.add_theme_constant_override("separation", 6)
	_info_chip_holder.position = Vector2(16, 16)
	_info_chip_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_holder.add_child(_info_chip_holder)
	var hint_pill: PanelContainer = BellaUi.pill(
		"Click to place the armed ingredient · drag to move · double-click removes"
		if draft.product_type == &"pizza"
		else "Drag a layer up/down to reorder · double-click to remove",
		BellaUi.INK_SOFT, Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0))
	hint_pill.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_pill.position = Vector2(16, -40)
	hint_pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	canvas_holder.add_child(hint_pill)

	# Right: component list + metrics.
	var right: PanelContainer = PanelContainer.new()
	right.add_theme_stylebox_override("panel", TycoonTheme.panel_box())
	body.add_child(right)
	var right_pad: MarginContainer = _pad(10)
	right.add_child(right_pad)
	_metrics = RecipeMetricsPanel.new()
	_metrics.select_requested.connect(_on_component_selected_from_list)
	_metrics.quantity_changed.connect(_on_quantity_changed)
	_metrics.remove_requested.connect(_on_remove_component)
	_metrics.save_requested.connect(_on_save)
	_metrics.test_requested.connect(_on_test)
	right_pad.add_child(_metrics)


func _build_header() -> PanelContainer:
	var header: PanelContainer = PanelContainer.new()
	header.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	header.add_child(row)

	var back: Button = Button.new()
	UiAssets.icon_button(back, &"close", 22)
	back.text = " Back"
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(close)
	row.add_child(back)

	_breadcrumb = Label.new()
	_breadcrumb.add_theme_color_override("font_color", Color("#E6B667"))
	_breadcrumb.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
	row.add_child(_breadcrumb)

	var name_well: PanelContainer = PanelContainer.new()
	name_well.add_theme_stylebox_override("panel", BellaUi.dark_inset())
	row.add_child(name_well)
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 7)
	name_well.add_child(name_row)
	var icon: TextureRect = UiAssets.icon_rect(
		&"pizza" if draft.product_type == &"pizza" else &"burger", 22)
	if icon != null:
		name_row.add_child(icon)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(190, 34)
	_name_edit.max_length = 40
	_name_edit.flat = true
	_name_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_name_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_name_edit.add_theme_color_override("font_color", Color("#FFF4DC"))
	_name_edit.add_theme_font_size_override("font_size", 16)
	_name_edit.text_changed.connect(func(text: String) -> void:
		draft.display_name = text
		_mark_dirty())
	name_row.add_child(_name_edit)

	var pill: PanelContainer = BellaUi.pill("UNSAVED DRAFT",
		Color("#FFD23E"), Color(0.96, 0.77, 0.09, 0.2), Color("#E0A80E"))
	_draft_pill = pill.get_child(0)
	row.add_child(pill)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var convert: Button = Button.new()
	convert.text = "Make it a Burger" if draft.product_type == &"pizza" else "Make it a Pizza"
	convert.custom_minimum_size = Vector2(0, 44)
	convert.pressed.connect(_on_convert_pressed)
	row.add_child(convert)

	_undo_button = Button.new()
	_undo_button.text = "↶ Undo"
	_undo_button.custom_minimum_size = Vector2(0, 44)
	_undo_button.pressed.connect(_undo)
	row.add_child(_undo_button)
	_redo_button = Button.new()
	_redo_button.text = "↷ Redo"
	_redo_button.custom_minimum_size = Vector2(0, 44)
	_redo_button.pressed.connect(_redo)
	row.add_child(_redo_button)
	return header


func _build_toolbar() -> PanelContainer:
	var bar: PanelContainer = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", TycoonTheme.inner_box(Color("#efd9a8")))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)

	var base_label: Label = Label.new()
	base_label.text = "Base:"
	base_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	row.add_child(base_label)
	_base_select = OptionButton.new()
	var ids: Array = RecipeManager.bases.keys()
	ids.sort()
	for id: StringName in ids:
		var base_def: RecipeBaseDef = RecipeManager.bases[id]
		if base_def.product_type != draft.product_type:
			continue
		_base_select.add_item("%s (+$%.2f)" % [base_def.display_name, base_def.base_cost])
		_base_select.set_item_metadata(_base_select.item_count - 1, id)
	_base_select.item_selected.connect(func(index: int) -> void:
		_push_undo()
		draft.base_id = _base_select.get_item_metadata(index)
		_after_edit())
	row.add_child(_base_select)

	if draft.product_type == &"pizza":
		_distribute_button = Button.new()
		_distribute_button.text = "Distribute evenly"
		_distribute_button.pressed.connect(_on_distribute)
		row.add_child(_distribute_button)

	var clear: Button = Button.new()
	clear.text = "Clear"
	clear.pressed.connect(func() -> void:
		if draft.components.is_empty():
			return
		TycoonConfirmDialog.ask(self, "Clear all ingredients?",
			"All %d placed ingredients are removed. Undo can bring them back." % draft.components.size(),
			func() -> void:
				_push_undo()
				draft.components.clear()
				_after_edit(),
			"Clear"))
	row.add_child(clear)
	return bar


func _pad(margin: int) -> MarginContainer:
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_%s" % side, margin)
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return pad


# --- Editing ------------------------------------------------------------------


func _on_ingredient_armed(id: StringName) -> void:
	if _pizza_canvas != null:
		_pizza_canvas.armed_ingredient = id
	elif _burger_stack != null:
		# Burgers stack on top directly — no placement click needed.
		_add_burger_layer(id)
		_browser.disarm()


func _on_ingredient_disarmed() -> void:
	if _pizza_canvas != null:
		_pizza_canvas.armed_ingredient = &""


func _on_place_requested(norm_pos: Vector2) -> void:
	var id: StringName = _browser.armed_id
	var ing: IngredientDef = RecipeManager.ingredient(id)
	if ing == null:
		return
	_push_undo()
	var role: StringName = _pizza_role_for(ing)
	if role == &"sauce" or role == &"spread" or role == &"cheese":
		# Coverage ingredients are one component; repeat clicks add portion.
		for comp: RecipeComponent in draft.components:
			if comp.ingredient_id == id and comp.role == role:
				comp.quantity += 0.5
				_after_edit()
				return
	var comp: RecipeComponent = RecipeComponent.new()
	comp.ingredient_id = id
	comp.role = role
	comp.quantity = 1.0
	if role == &"sauce" or role == &"spread" or role == &"cheese":
		comp.pos = Vector2(0.5, 0.5)
		comp.radius = 1.0
	else:
		comp.pos = norm_pos
		comp.radius = 0.3
	draft.components.append(comp)
	_pizza_canvas.selected_index = draft.components.size() - 1
	_after_edit()


func _pizza_role_for(ing: IngredientDef) -> StringName:
	for role: StringName in [&"sauce", &"cheese", &"topping", &"spread"]:
		if ing.allows_role(role):
			return role
	return ing.roles[0] if not ing.roles.is_empty() else &"topping"


func _add_burger_layer(id: StringName) -> void:
	var ing: IngredientDef = RecipeManager.ingredient(id)
	if ing == null:
		return
	_push_undo()
	var comp: RecipeComponent = RecipeComponent.new()
	comp.ingredient_id = id
	comp.role = _burger_role_for(ing)
	comp.quantity = 1.0
	comp.thickness = _thickness_for(ing, comp.role)
	if comp.role == &"sauce" or comp.role == &"spread":
		comp.coverage = 0.8
	var top: int = -1
	for existing: RecipeComponent in draft.components:
		top = maxi(top, existing.stack_index)
	comp.stack_index = top + 1
	draft.components.append(comp)
	if _burger_stack != null:
		_burger_stack.selected_index = draft.components.size() - 1
	_after_edit()


func _burger_role_for(ing: IngredientDef) -> StringName:
	for role: StringName in [&"patty", &"layer", &"cheese", &"sauce", &"spread"]:
		if ing.allows_role(role):
			return role
	return ing.roles[0] if not ing.roles.is_empty() else &"layer"


func _thickness_for(ing: IngredientDef, role: StringName) -> float:
	if role == &"patty":
		return 1.6
	if role == &"sauce" or role == &"spread":
		return 0.2
	if ing.category == &"cheese":
		return 0.3
	return 0.4


func _on_component_selected(index: int) -> void:
	_metrics.set_selected(index)


func _on_component_selected_from_list(index: int) -> void:
	if _pizza_canvas != null:
		_pizza_canvas.selected_index = index
		_pizza_canvas.queue_redraw()
	if _burger_stack != null:
		_burger_stack.selected_index = index
		_burger_stack.queue_redraw()
	_metrics.set_selected(index)


func _on_quantity_changed(index: int, delta: float) -> void:
	if index < 0 or index >= draft.components.size():
		return
	_push_undo()
	var comp: RecipeComponent = draft.components[index]
	comp.quantity = maxf(1.0, comp.quantity + delta)
	_after_edit()


func _on_remove_component(index: int) -> void:
	if index < 0 or index >= draft.components.size():
		return
	_push_undo()
	draft.components.remove_at(index)
	if _pizza_canvas != null:
		_pizza_canvas.selected_index = -1
	if _burger_stack != null:
		_burger_stack.selected_index = -1
	_metrics.set_selected(-1)
	_after_edit()


func _on_canvas_edit() -> void:
	# Canvas already mutated the draft (drag/keys); snapshot went in on press.
	_push_undo_post_edit()
	_after_edit()


func _on_distribute() -> void:
	var toppings: Array[RecipeComponent] = []
	for comp: RecipeComponent in draft.components:
		if comp.role == &"topping":
			toppings.append(comp)
	if toppings.is_empty():
		return
	_push_undo()
	for i: int in toppings.size():
		var angle: float = float(i) * TAU / float(toppings.size()) - PI / 2.0
		toppings[i].pos = Vector2(0.5, 0.5) + Vector2.from_angle(angle) * 0.16
		toppings[i].radius = 0.55
		toppings[i].rotation = angle
	_after_edit()


func _on_convert_pressed() -> void:
	var target: StringName = &"burger" if draft.product_type == &"pizza" else &"pizza"
	var kept: int = 0
	for comp: RecipeComponent in draft.components:
		var ing: IngredientDef = RecipeManager.ingredient(comp.ingredient_id)
		if ing != null and ing.allows_product(target):
			kept += 1
	var lost: int = draft.components.size() - kept
	TycoonConfirmDialog.ask(self, "Convert to %s?" % target.capitalize(),
		"A converted copy opens in the %s workshop. %d of %d ingredients carry over%s." % [
			target, kept, draft.components.size(),
			"" if lost == 0 else "; %d incompatible ones are dropped" % lost],
		func() -> void: _convert_to(target), "Convert")


func _convert_to(target: StringName) -> void:
	var converted: RecipeDef = RecipeManager.new_draft(target, _default_base(target))
	converted.display_name = draft.display_name
	var next_stack: int = 0
	for comp: RecipeComponent in draft.components:
		var ing: IngredientDef = RecipeManager.ingredient(comp.ingredient_id)
		if ing == null or not ing.allows_product(target):
			continue
		var moved: RecipeComponent = comp.duplicate_component()
		if target == &"burger":
			moved.role = _burger_role_for(ing)
			moved.thickness = _thickness_for(ing, moved.role)
			moved.stack_index = next_stack
			next_stack += 1
		else:
			moved.role = _pizza_role_for(ing)
			moved.pos = Vector2(0.5, 0.5)
			moved.radius = 0.5
		converted.components.append(moved)
	RecipeManager.recalc(converted)
	var parent_hud: Control = hud
	var bid: int = building_id
	queue_free()
	if is_instance_valid(parent_hud) and parent_hud.has_method("_open_workshop"):
		parent_hud.call_deferred("_open_workshop", bid, converted, target)


# --- Undo/redo ----------------------------------------------------------------


func _snapshot() -> Dictionary:
	var comps: Array[Dictionary] = []
	for comp: RecipeComponent in draft.components:
		comps.append({
			"ingredient_id": comp.ingredient_id, "role": comp.role,
			"quantity": comp.quantity, "prep_choice": comp.prep_choice,
			"pos": comp.pos, "radius": comp.radius, "rotation": comp.rotation,
			"scale": comp.scale, "stack_index": comp.stack_index,
			"thickness": comp.thickness, "coverage": comp.coverage,
		})
	return {"name": draft.display_name, "base_id": draft.base_id, "components": comps}


var _pre_edit_snapshot: Dictionary = {}


func _push_undo() -> void:
	_undo_stack.push(_snapshot())


## For canvas drags the mutation already happened when we learn about it, so
## the snapshot for undo is captured continuously before each gesture.
func _push_undo_post_edit() -> void:
	if not _pre_edit_snapshot.is_empty():
		_undo_stack.push(_pre_edit_snapshot)
	_pre_edit_snapshot = {}


func _process(_delta: float) -> void:
	# Keep a pre-gesture snapshot ready while the user is not mid-drag.
	var dragging: bool = (_pizza_canvas != null and _pizza_canvas.is_dragging()) \
		or (_burger_stack != null and _burger_stack.is_dragging())
	if not dragging:
		_pre_edit_snapshot = _snapshot()


func _apply_snapshot(snapshot: Dictionary) -> void:
	draft.display_name = String(snapshot["name"])
	draft.base_id = snapshot["base_id"]
	draft.components.clear()
	for row: Dictionary in snapshot["components"]:
		var comp: RecipeComponent = RecipeComponent.new()
		comp.ingredient_id = row["ingredient_id"]
		comp.role = row["role"]
		comp.quantity = row["quantity"]
		comp.prep_choice = row["prep_choice"]
		comp.pos = row["pos"]
		comp.radius = row["radius"]
		comp.rotation = row["rotation"]
		comp.scale = row["scale"]
		comp.stack_index = row["stack_index"]
		comp.thickness = row["thickness"]
		comp.coverage = row["coverage"]
		draft.components.append(comp)
	_after_edit()


func _undo() -> void:
	var snapshot: Variant = _undo_stack.undo(_snapshot())
	if snapshot != null:
		_apply_snapshot(snapshot)


func _redo() -> void:
	var snapshot: Variant = _undo_stack.redo(_snapshot())
	if snapshot != null:
		_apply_snapshot(snapshot)


func _refresh_history_buttons() -> void:
	if _undo_button != null:
		_undo_button.disabled = not _undo_stack.can_undo()
		_redo_button.disabled = not _undo_stack.can_redo()


# --- Sync ----------------------------------------------------------------------


func _mark_dirty() -> void:
	_dirty = true
	if _draft_pill != null:
		(_draft_pill.get_parent() as Control).visible = true


func _after_edit() -> void:
	RecipeManager.recalc(draft)
	_mark_dirty()
	if _pizza_canvas != null:
		_pizza_canvas.queue_redraw()
	if _burger_stack != null:
		_burger_stack.queue_redraw()
	_metrics.refresh()
	_refresh_info_chips()


func _refresh_info_chips() -> void:
	if _info_chip_holder == null:
		return
	for child: Node in _info_chip_holder.get_children():
		child.queue_free()
	var texts: Array[String] = []
	if draft.product_type == &"pizza":
		var portions: float = 0.0
		for comp: RecipeComponent in draft.components:
			portions += comp.quantity
		var label: String = "Light"
		if portions >= 9.0:
			label = "Loaded"
		elif portions >= 4.0:
			label = "Generous"
		texts.append("%d ingredients" % draft.components.size())
		texts.append("Portion: %s" % label)
	else:
		var height: float = 0.0
		for comp: RecipeComponent in draft.components:
			height += comp.thickness * comp.quantity
		texts.append("%d layers · %.0fmm tall" % [draft.components.size(), 60.0 + height * 30.0])
	for text: String in texts:
		_info_chip_holder.add_child(BellaUi.pill(text,
			BellaUi.INK, BellaUi.PAPER, BellaUi.WOOD_EDGE))


func _sync_all() -> void:
	_breadcrumb.text = "Recipes  ›  Recipe Book  ›  %s Workshop" % draft.product_type.capitalize()
	_name_edit.text = draft.display_name
	(_draft_pill.get_parent() as Control).visible = _dirty
	for i: int in _base_select.item_count:
		if _base_select.get_item_metadata(i) == draft.base_id:
			_base_select.select(i)
			break
	if _pizza_canvas != null:
		_pizza_canvas.set_recipe(draft)
	if _burger_stack != null:
		_burger_stack.set_recipe(draft)
	_metrics.set_draft(draft, building_id)
	_refresh_history_buttons()
	_refresh_info_chips()


# --- Save / test ----------------------------------------------------------------


func _on_save() -> void:
	if RecipeManager.has_errors(draft):
		return
	if draft.display_name.strip_edges() == "":
		draft.display_name = "Unnamed %s" % draft.product_type.capitalize()
	draft.id = _editing_id
	if _editing_id == &"":
		draft.created_day = GameClock.day
	var saved_id: StringName = RecipeManager.save_recipe(draft)
	_editing_id = saved_id
	_dirty = false
	EconomyManager.post_message("good", "Recipe \"%s\" saved to the company book." % draft.display_name)
	_close_now()


func _on_test() -> void:
	var result: Dictionary = RecipeManager.score(draft)
	var lines: Array[String] = []
	var by_segment: Dictionary = result["by_segment"]
	var order: Array = by_segment.keys()
	order.sort_custom(func(a: StringName, b: StringName) -> bool:
		return float(by_segment[a]) > float(by_segment[b]))
	for segment: StringName in order:
		var value: float = float(by_segment[segment])
		var bar: String = "█".repeat(int(value * 10.0)) + "░".repeat(10 - int(value * 10.0))
		lines.append("%-10s %s %d%%" % [String(segment).capitalize(), bar, int(value * 100.0)])
	if draft.product_type == &"burger":
		lines.append("")
		lines.append("Structure: %d%%" % int(float(result["structure"]) * 100.0))
	lines.append("Cost $%.2f · Prep %.0fm · Suggested $%.1f" % [
		draft.cached_cost, draft.cached_prep, RecipeManager.suggested_price_for(draft)])
	TycoonConfirmDialog.ask(self, "Test kitchen — %s" % draft.display_name,
		"\n".join(lines), Callable(), "OK")


# --- City input capture (InteriorViewer pattern) --------------------------------


func _capture_city_input() -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		_camera_rig = scene_root.get_node_or_null("CameraRig")
	if _camera_rig != null:
		_camera_rig.set_process(false)
		_camera_rig.set_process_input(false)
		_camera_rig.set_process_unhandled_input(false)
	SelectionManager.set_process_unhandled_input(false)
	if hud != null:
		hud.visible = false
	var root_viewport: Viewport = get_viewport()
	if root_viewport != null:
		_root_3d_was_disabled = root_viewport.disable_3d
		root_viewport.disable_3d = true


func _release_city_input() -> void:
	if is_instance_valid(_camera_rig):
		_camera_rig.set_process(true)
		_camera_rig.set_process_input(true)
		_camera_rig.set_process_unhandled_input(true)
	SelectionManager.set_process_unhandled_input(true)
	if is_instance_valid(hud):
		hud.visible = true
	var root_viewport: Viewport = get_viewport()
	if root_viewport != null:
		root_viewport.disable_3d = _root_3d_was_disabled
