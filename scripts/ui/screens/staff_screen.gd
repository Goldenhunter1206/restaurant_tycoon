extends TycoonScreen
## Staff management: hire per role with a chosen shift start, see and fire
## current employees. Each worker covers at most 8 hours — longer opening
## hours need a second shift.

var _list: VBoxContainer
var _hire_shift: Dictionary = {}


func screen_title() -> String:
	return "👥  Staff"


func _build() -> void:
	add_section("Hire staff per role. One worker covers 8h — use shifts for longer hours.")
	var hire_bar: HBoxContainer = HBoxContainer.new()
	hire_bar.add_theme_constant_override("separation", 8)
	_content.add_child(hire_bar)
	for type_id: StringName in RestaurantManager.staff_types:
		var def: StaffTypeDef = RestaurantManager.staff_types[type_id]
		var chunk: VBoxContainer = VBoxContainer.new()
		var hire_btn: Button = Button.new()
		hire_btn.text = "+ %s ($%.0f/day)" % [def.display_name, def.base_daily_wage]
		hire_btn.pressed.connect(func() -> void: _hire(type_id))
		chunk.add_child(hire_btn)
		var shift: OptionButton = OptionButton.new()
		for start: int in [6, 8, 10, 12, 14, 16, 18]:
			shift.add_item("shift %02d:00–%02d:00" % [start, (start + 8) % 24])
			shift.set_item_metadata(shift.item_count - 1, float(start))
		shift.select(2)
		chunk.add_child(shift)
		_hire_shift[type_id] = shift
		hire_bar.add_child(chunk)
	add_section("Employees")
	_list = add_scroll_list()


func refresh() -> void:
	var rest: RestaurantState = restaurant()
	if rest == null:
		return
	for child: Node in _list.get_children():
		child.queue_free()
	if rest.staff.is_empty():
		var empty: Label = Label.new()
		empty.text = "Nobody hired yet."
		_list.add_child(empty)
		return
	for member: StaffMember in rest.staff:
		_list.add_child(_make_member_row(member))


func _make_member_row(member: StaffMember) -> Control:
	var row: PanelContainer = make_row()
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)
	var def: StaffTypeDef = RestaurantManager.staff_type(member.type_id)
	var icon: String = "🍳" if (def != null and def.cook_slots > 0) \
		else ("🛵" if def != null and def.is_driver else "🤵")
	var label: Label = Label.new()
	label.text = "%s %s — %s, %02d:00–%02d:00, $%.0f/day" % [
		icon, member.staff_name,
		def.display_name if def != null else String(member.type_id),
		int(member.shift_start), int(member.shift_start + member.shift_hours) % 24,
		member.daily_wage,
	]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)
	var on_now: Label = Label.new()
	on_now.text = "● on shift" if member.on_shift(GameClock.game_hours) else "○ off"
	on_now.add_theme_color_override(
		"font_color",
		Color("#2e7d32") if member.on_shift(GameClock.game_hours) else Color("#8a7150"))
	box.add_child(on_now)
	var fire_btn: Button = Button.new()
	fire_btn.text = "Fire"
	fire_btn.pressed.connect(func() -> void:
		RestaurantManager.fire(building_id, member.uid)
		refresh())
	box.add_child(fire_btn)
	return row


func _hire(type_id: StringName) -> void:
	var shift: OptionButton = _hire_shift[type_id]
	var start: float = float(shift.get_item_metadata(shift.selected))
	RestaurantManager.hire(building_id, type_id, start)
	refresh()
