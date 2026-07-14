class_name IngredientBrowser
extends VBoxContainer
## Left-hand ingredient palette of the recipe workshop: search, category
## filter chips and a 2-column tile grid. Clicking a tile arms it (gold
## border); the workshop then places it on the canvas (pizza) or stacks it on
## top (burger). Clicking the armed tile again disarms.

signal ingredient_armed(id: StringName)
signal ingredient_disarmed

const CATEGORIES: Array[Dictionary] = [
	{"id": &"", "label": "All"},
	{"id": &"sauce", "label": "Sauce"},
	{"id": &"cheese", "label": "Cheese"},
	{"id": &"meat", "label": "Meat"},
	{"id": &"veg", "label": "Veg"},
	{"id": &"extra", "label": "Extra"},
]

var product_type: StringName = &"pizza"
var armed_id: StringName = &""

var _search: LineEdit
var _grid: GridContainer
var _category: StringName = &""
var _chip_buttons: Dictionary = {}
var _tiles: Dictionary = {}


class SwatchIcon:
	extends Control
	var color: Color = Color.WHITE
	var shape: StringName = &"dot"

	func _init(a_color: Color, a_shape: StringName) -> void:
		color = a_color
		shape = a_shape
		custom_minimum_size = Vector2(30, 30)

	func _draw() -> void:
		var p: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.42
		var outline: Color = color.darkened(0.45)
		match shape:
			&"ring":
				draw_circle(p, r, outline)
				draw_circle(p, r * 0.76, color)
				draw_circle(p, r * 0.36, outline.lightened(0.25))
			&"square":
				draw_rect(Rect2(p - Vector2(r, r) * 0.9, Vector2(r, r) * 1.8), outline)
				draw_rect(Rect2(p - Vector2(r, r) * 0.75, Vector2(r, r) * 1.5), color)
			&"triangle":
				var pts: PackedVector2Array = PackedVector2Array()
				for k: int in 3:
					pts.append(p + Vector2.from_angle(-PI / 2.0 + float(k) * TAU / 3.0) * r)
				draw_colored_polygon(pts, color)
				pts.append(pts[0])
				draw_polyline(pts, outline, 2.0)
			_:
				draw_circle(p, r, outline)
				draw_circle(p, r * 0.82, color)


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(280, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var search_well: PanelContainer = PanelContainer.new()
	search_well.add_theme_stylebox_override("panel", BellaUi.sunk_box(12))
	add_child(search_well)
	var search_row: HBoxContainer = HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 6)
	search_well.add_child(search_row)
	var glass: TextureRect = UiAssets.icon_rect(&"magnifier", 18)
	if glass != null:
		search_row.add_child(glass)
	_search = LineEdit.new()
	_search.placeholder_text = "Search ingredients…"
	_search.clear_button_enabled = true
	_search.flat = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_search.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_search.add_theme_color_override("font_color", BellaUi.INK)
	_search.text_changed.connect(func(_t: String) -> void: _rebuild_grid())
	search_row.add_child(_search)

	var chips: HFlowContainer = HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 5)
	chips.add_theme_constant_override("v_separation", 5)
	add_child(chips)
	for cat: Dictionary in CATEGORIES:
		var cat_id: StringName = cat["id"]
		var chip: Button = BellaUi.chip(String(cat["label"]), cat_id == &"")
		chip.pressed.connect(func() -> void: _select_category(cat_id))
		chips.add_child(chip)
		_chip_buttons[cat_id] = chip

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	var footer: PanelContainer = PanelContainer.new()
	var footer_style: StyleBoxFlat = StyleBoxFlat.new()
	footer_style.bg_color = Color("#A8692A")
	footer_style.border_color = BellaUi.WOOD_DEEP
	footer_style.border_width_top = 2
	footer_style.set_corner_radius_all(8)
	footer_style.set_content_margin_all(9.0)
	footer.add_theme_stylebox_override("panel", footer_style)
	add_child(footer)
	var hint: Label = Label.new()
	hint.text = "Click a tile, then click the canvas to place."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
	hint.add_theme_color_override("font_color", Color("#FFF4DC"))
	footer.add_child(hint)

	_rebuild_grid()


func setup(a_product_type: StringName) -> void:
	product_type = a_product_type
	disarm()
	if _grid != null:
		_rebuild_grid()


func disarm() -> void:
	armed_id = &""
	_refresh_tile_styles()
	ingredient_disarmed.emit()


func _select_category(cat_id: StringName) -> void:
	_category = cat_id
	for key: StringName in _chip_buttons:
		BellaUi.style_chip(_chip_buttons[key], key == cat_id)
	_rebuild_grid()


func _rebuild_grid() -> void:
	for child: Node in _grid.get_children():
		child.queue_free()
	_tiles.clear()
	var query: String = _search.text.strip_edges().to_lower()
	var ids: Array = RecipeManager.ingredients.keys()
	ids.sort()
	for id: StringName in ids:
		var ing: IngredientDef = RecipeManager.ingredients[id]
		if not ing.allows_product(product_type):
			continue
		if _category != &"" and ing.category != _category:
			continue
		if query != "" and not ing.display_name.to_lower().contains(query):
			continue
		_grid.add_child(_make_tile(ing))
	_refresh_tile_styles()


func _make_tile(ing: IngredientDef) -> Control:
	var tile: PanelContainer = PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.tooltip_text = "%s · $%.2f" % [ing.display_name, ing.unit_cost]

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	tile.add_child(box)
	box.add_child(SwatchIcon.new(ing.swatch_color, ing.marker_shape))

	var name_label: Label = Label.new()
	name_label.text = ing.display_name
	name_label.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
	name_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text"])
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name_label)

	var cost: Label = Label.new()
	cost.text = "$%.2f" % ing.unit_cost
	cost.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_SMALL)
	cost.add_theme_color_override("font_color", BellaUi.GOLD_EDGE)
	box.add_child(cost)

	var id: StringName = ing.id
	tile.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_on_tile_pressed(id))
	_tiles[id] = tile
	return tile


func _on_tile_pressed(id: StringName) -> void:
	if armed_id == id:
		disarm()
		return
	armed_id = id
	_refresh_tile_styles()
	ingredient_armed.emit(id)


func _refresh_tile_styles() -> void:
	for id: StringName in _tiles:
		var tile: PanelContainer = _tiles[id]
		if not is_instance_valid(tile):
			continue
		if id == armed_id:
			tile.add_theme_stylebox_override("panel", BellaUi.tile_box(BellaUi.GOLD, 3))
		else:
			tile.add_theme_stylebox_override("panel", BellaUi.tile_box())
