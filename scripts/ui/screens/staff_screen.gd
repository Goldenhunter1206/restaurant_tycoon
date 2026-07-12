extends TycoonScreen
## Staff management in two tabs: a drag-to-schedule shift planner (pay is
## hourly — only scheduled hours are paid) and a rolling job market of
## candidates with per-role attributes and asking wages.

const ROLE_COLORS: Dictionary = {
	&"cook": Color("#c0392b"),
	&"waiter": Color("#2e7d32"),
	&"driver": Color("#2b6cb0"),
}

var _tabs: TabContainer
var _schedule_list: VBoxContainer
var _payroll_label: Label
var _market_list: VBoxContainer
## uid -> ShiftTimeline for live redraws without rebuilding rows.
var _timelines: Dictionary = {}
## uid -> Label showing daily pay + on-shift state.
var _pay_labels: Dictionary = {}
var _roster_sig: String = ""
var _market_sig: String = "?"


func screen_title() -> String:
	return "Staff"


func screen_icon() -> StringName:
	return &"people"


func _build() -> void:
	custom_minimum_size = Vector2(780, 540)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The default TabContainer panel is dark and fights the paper skin.
	_tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_content.add_child(_tabs)

	var sched: VBoxContainer = VBoxContainer.new()
	sched.name = "Schedule"
	sched.add_theme_constant_override("separation", 6)
	_tabs.add_child(sched)
	var hint: Label = Label.new()
	hint.text = "Drag a shift bar to move it, drag its right edge to resize (%.0f–%.0fh, 30min steps). Gold line = now, light band = opening hours." % [
		float(EconomyManager.tuning_value("staff.min_shift_hours", 2.0)),
		float(EconomyManager.tuning_value("staff.max_shift_hours", 8.0)),
	]
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#8a7150"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sched.add_child(hint)
	_schedule_list = _make_scroll(sched)
	_payroll_label = Label.new()
	_payroll_label.add_theme_font_size_override("font_size", 15)
	_payroll_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	sched.add_child(_payroll_label)

	var market: VBoxContainer = VBoxContainer.new()
	market.name = "Job Market"
	market.add_theme_constant_override("separation", 6)
	_tabs.add_child(market)
	var market_hint: Label = Label.new()
	market_hint.text = "Candidates come and go daily; better attributes mean a higher asking wage. New hires start on an 8h shift from opening — adjust it on the Schedule tab."
	market_hint.add_theme_font_size_override("font_size", 12)
	market_hint.add_theme_color_override("font_color", Color("#8a7150"))
	market_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	market.add_child(market_hint)
	_market_list = _make_scroll(market)

	RestaurantManager.job_market_changed.connect(_on_market_changed)


func refresh() -> void:
	var rest: RestaurantState = restaurant()
	if rest == null:
		return
	for tl: ShiftTimeline in _timelines.values():
		if is_instance_valid(tl) and tl.is_dragging():
			return
	var sig: String = ""
	for member: StaffMember in rest.staff:
		sig += "%d:%.2f:%.2f;" % [member.uid, member.shift_start, member.shift_hours]
	if sig != _roster_sig:
		_roster_sig = sig
		_rebuild_schedule(rest)
	else:
		for tl: ShiftTimeline in _timelines.values():
			if is_instance_valid(tl):
				tl.queue_redraw()
		_sync_pay_labels(rest)
	var msig: String = ""
	for cand: JobCandidate in RestaurantManager.job_market:
		msig += "%d;" % cand.uid
	if msig != _market_sig:
		_market_sig = msig
		_rebuild_market(rest)


func _on_market_changed() -> void:
	_market_sig = "?"
	refresh()


# --- Schedule tab -------------------------------------------------------------


func _rebuild_schedule(rest: RestaurantState) -> void:
	for child: Node in _schedule_list.get_children():
		child.queue_free()
	_timelines.clear()
	_pay_labels.clear()
	if rest.staff.is_empty():
		var empty: Label = Label.new()
		empty.text = "Nobody hired yet — find people on the Job Market tab."
		_schedule_list.add_child(empty)
	for member: StaffMember in rest.staff:
		_schedule_list.add_child(_make_schedule_row(rest, member))
	_update_payroll(rest)


func _make_schedule_row(rest: RestaurantState, member: StaffMember) -> Control:
	var row: PanelContainer = make_row()
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)
	var def: StaffTypeDef = RestaurantManager.staff_type(member.type_id)

	var name_box: VBoxContainer = VBoxContainer.new()
	name_box.custom_minimum_size = Vector2(180, 0)
	name_box.add_theme_constant_override("separation", 0)
	var name_label: Label = Label.new()
	name_label.text = "%s %s" % [_role_emoji(def), member.staff_name]
	name_box.add_child(name_label)
	var attr_label: Label = Label.new()
	attr_label.text = _attr_text(member.attributes)
	attr_label.add_theme_font_size_override("font_size", 11)
	attr_label.add_theme_color_override("font_color", Color("#8a7150"))
	name_box.add_child(attr_label)
	box.add_child(name_box)

	var tl: ShiftTimeline = ShiftTimeline.new()
	tl.setup(member, rest.open_hour, rest.close_hour,
		ROLE_COLORS.get(member.type_id, TycoonTheme.PALETTE.get("accent_gold", Color.ORANGE)))
	tl.shift_changed.connect(func(start: float, hours: float) -> void:
		RestaurantManager.set_shift(building_id, member.uid, start, hours)
		refresh())
	box.add_child(tl)

	var pay_label: Label = Label.new()
	pay_label.custom_minimum_size = Vector2(120, 0)
	pay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pay_labels[member.uid] = pay_label
	box.add_child(pay_label)

	var fire_btn: Button = Button.new()
	fire_btn.text = "Fire"
	fire_btn.pressed.connect(func() -> void:
		RestaurantManager.fire(building_id, member.uid)
		refresh())
	box.add_child(fire_btn)

	_timelines[member.uid] = tl
	_sync_pay_label(member)
	return row


func _sync_pay_labels(rest: RestaurantState) -> void:
	for member: StaffMember in rest.staff:
		_sync_pay_label(member)
	_update_payroll(rest)


func _sync_pay_label(member: StaffMember) -> void:
	var label: Label = _pay_labels.get(member.uid)
	if label == null or not is_instance_valid(label):
		return
	var on_now: bool = member.on_shift(GameClock.game_hours)
	label.text = "$%.2f/h\n$%.0f/day %s" % [member.hourly_wage, member.daily_pay(), "●" if on_now else "○"]
	label.add_theme_color_override("font_color", Color("#2e7d32") if on_now else Color("#8a7150"))


func _update_payroll(rest: RestaurantState) -> void:
	var total: float = 0.0
	for member: StaffMember in rest.staff:
		total += member.daily_pay()
	_payroll_label.text = "Daily payroll: $%.0f for %d employees" % [total, rest.staff.size()]


# --- Job market tab ------------------------------------------------------------


func _rebuild_market(rest: RestaurantState) -> void:
	for child: Node in _market_list.get_children():
		child.queue_free()
	for type_id: StringName in RestaurantManager.staff_types:
		var def: StaffTypeDef = RestaurantManager.staff_types[type_id]
		var header: Label = Label.new()
		header.text = "%s %s — base rate $%.2f/h" % [_role_emoji(def), def.display_name, def.base_hourly_wage]
		header.add_theme_font_size_override("font_size", 15)
		header.add_theme_color_override("font_color", Color("#8a5a2b"))
		_market_list.add_child(header)
		var cands: Array[JobCandidate] = RestaurantManager.candidates_for(type_id)
		if cands.is_empty():
			var empty: Label = Label.new()
			empty.text = "    No candidates right now — check back tomorrow."
			empty.add_theme_font_size_override("font_size", 12)
			_market_list.add_child(empty)
			continue
		for cand: JobCandidate in cands:
			_market_list.add_child(_make_candidate_row(rest, cand))


func _make_candidate_row(rest: RestaurantState, cand: JobCandidate) -> Control:
	var row: PanelContainer = make_row()
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)

	var name_label: Label = Label.new()
	name_label.text = cand.candidate_name
	name_label.custom_minimum_size = Vector2(150, 0)
	box.add_child(name_label)

	var attr_label: Label = Label.new()
	attr_label.text = _attr_text(cand.attributes)
	attr_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attr_label.add_theme_color_override("font_color", Color("#6b5137"))
	box.add_child(attr_label)

	var wage_label: Label = Label.new()
	wage_label.text = "$%.2f/h · $%.0f/8h day" % [cand.hourly_wage, cand.hourly_wage * 8.0]
	wage_label.custom_minimum_size = Vector2(150, 0)
	wage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(wage_label)

	var hire_btn: Button = Button.new()
	hire_btn.text = "Hire"
	hire_btn.pressed.connect(func() -> void:
		RestaurantManager.hire_candidate(building_id, cand.uid, rest.open_hour, 8.0)
		refresh())
	box.add_child(hire_btn)
	return row


# --- Helpers --------------------------------------------------------------------


func _make_scroll(parent: Control) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	parent.add_child(scroll)
	return list


func _role_emoji(def: StaffTypeDef) -> String:
	if def == null:
		return "👤"
	if def.cook_slots > 0:
		return "🍳"
	if def.is_driver:
		return "🛵"
	return "🤵"


func _attr_text(attrs: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: StringName in attrs:
		parts.append("%s %s" % [String(key).capitalize(), _notches(float(attrs[key]))])
	return "  ".join(parts)


func _notches(value: float) -> String:
	var filled: int = clampi(int(roundf(value * 5.0)), 0, 5)
	return "▮".repeat(filled) + "▯".repeat(5 - filled)
