class_name InteriorEvalPanel
extends PanelContainer
## Read-only evaluation card for the interior viewer's Evaluate mode:
## capacity, flow, condition and per-segment appeal, plus layout warnings.
## Deliberately shows separate meters — there is no single "beauty score".

const SEGMENTS: Array = [
	[&"workers", "Workers"],
	[&"students", "Students"],
	[&"families", "Families"],
	[&"seniors", "Seniors"],
	[&"teens", "Teens"],
]

var building_id: int = -1

var _content: VBoxContainer = null


func setup(target_building_id: int) -> void:
	building_id = target_building_id
	add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
	custom_minimum_size = Vector2(360, 0)
	var paper: PanelContainer = PanelContainer.new()
	paper.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	add_child(paper)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	paper.add_child(_content)
	RestaurantManager.restaurant_updated.connect(_on_updated)
	refresh()


func _exit_tree() -> void:
	if RestaurantManager.restaurant_updated.is_connected(_on_updated):
		RestaurantManager.restaurant_updated.disconnect(_on_updated)


func _on_updated(id: int) -> void:
	if id == building_id:
		refresh()


func refresh() -> void:
	for child: Node in _content.get_children():
		child.queue_free()
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null or rest.interior_layout == null:
		return
	var ev: InteriorEvaluation = RestaurantManager.interior.evaluate(rest.interior_layout)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	if UiAssets.icon(&"magnifier") != null:
		header.add_child(UiAssets.icon_rect(&"magnifier", 24))
	var title: Label = Label.new()
	title.text = "Interior Report"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	_content.add_child(header)
	header.add_child(title)
	_add_row("Tables / Seats", "%d / %d" % [ev.table_seats.size(), ev.seats])
	_add_row("Cook stations", "%d (staff can use %d)" % [ev.cook_stations, RestaurantManager.operations_snapshot(building_id).get("cook_slots", 0)])
	_add_row("Pickup slots", str(ev.pickup_slots))
	_add_row("Menu capacity", str(ev.menu_capacity))
	_add_row("Queue space", str(ev.queue_capacity))
	_add_row("Comfort", "%.1f / 5" % ev.comfort)
	_add_row("Service flow", "×%.2f" % ev.throughput_mod)
	_add_row("Condition", "%d%%" % int(ev.condition * 100.0))
	var style_text: String = "—"
	if ev.dominant_style != &"":
		style_text = "%s (%d%% coherent)" % [String(ev.dominant_style).capitalize(), int(ev.style_coherence * 100.0)]
	_add_row("Style", style_text)
	var seg_title: Label = Label.new()
	seg_title.text = "APPEAL BY SEGMENT"
	seg_title.add_theme_font_size_override("font_size", 12)
	seg_title.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_dark"])
	_content.add_child(seg_title)
	for seg: Array in SEGMENTS:
		_add_bar(String(seg[1]), float(ev.segment_appeal.get(seg[0], 0.0)))
	var policy: CheckButton = CheckButton.new()
	policy.text = "Manager auto-repair (below 50%)"
	policy.button_pressed = rest.repair_policy == &"auto"
	policy.add_theme_font_size_override("font_size", 13)
	policy.toggled.connect(func(on: bool) -> void:
		RestaurantManager.set_repair_policy_cmd(&"player", building_id, &"auto" if on else &"off", 0.5))
	_content.add_child(policy)
	if not ev.issues.is_empty():
		var warn_title: Label = Label.new()
		warn_title.text = "WARNINGS"
		warn_title.add_theme_font_size_override("font_size", 12)
		warn_title.add_theme_color_override("font_color", Color("#b3341f"))
		_content.add_child(warn_title)
		for issue: Dictionary in ev.issues.slice(0, 4):
			var row: Label = Label.new()
			row.text = ("✗ " if bool(issue.get("blocking", false)) else "⚠ ") + String(issue.get("message", ""))
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_theme_font_size_override("font_size", 13)
			row.add_theme_color_override("font_color", Color("#8a3a1f"))
			_content.add_child(row)


func _add_row(label_text: String, value_text: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	row.add_child(label)
	var value: Label = Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", TycoonTheme.PALETTE["text"])
	row.add_child(value)
	_content.add_child(row)


func _add_bar(label_text: String, value: float) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 84
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text_soft"])
	row.add_child(label)
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 3.0
	bar.value = clampf(value, 0.0, 3.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = TycoonTheme.PALETTE["accent_green"] if value >= 0.8 else TycoonTheme.PALETTE["accent_gold"]
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", BellaUi.sunk_box(6))
	row.add_child(bar)
	var value_label: Label = Label.new()
	value_label.text = "%.1f" % value
	value_label.add_theme_font_size_override("font_size", 13)
	value_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["text"])
	row.add_child(value_label)
	_content.add_child(row)
