extends Control
## Load Game screen (design A4, single slot): shows the save with its
## version state. Pre-v4 saves surface as incompatible with a delete option.

const INK: Color = Color("#3A2010")
const INK_SOFT: Color = Color("#6E4326")

var _column: VBoxContainer


func _ready() -> void:
	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_lg_box())
	panel.custom_minimum_size = Vector2(540, 0)
	center.add_child(panel)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 12)
	panel.add_child(_column)
	_rebuild()


func _rebuild() -> void:
	for child: Node in _column.get_children():
		child.queue_free()
	var title: Label = Label.new()
	title.text = "Load Game"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", INK)
	_column.add_child(title)

	var state: StringName = SaveSystem.save_state()
	match state:
		&"ok":
			_build_slot()
		&"incompatible":
			_build_incompatible()
		_:
			var empty: Label = Label.new()
			empty.text = "No saved game yet."
			empty.add_theme_color_override("font_color", INK_SOFT)
			_column.add_child(empty)

	var back: Button = Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 44)
	back.pressed.connect(func() -> void: get_parent().show_title())
	_column.add_child(back)


func _build_slot() -> void:
	var save: SaveGame = SaveSystem.load_game()
	var slot: PanelContainer = PanelContainer.new()
	slot.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	_column.add_child(slot)
	var info: VBoxContainer = VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	slot.add_child(info)
	var player: CompanyState = null
	for company: CompanyState in save.companies:
		if company.is_player:
			player = company
			break
	var name_label: Label = Label.new()
	name_label.text = player.display_name if player != null else "Saved game"
	name_label.add_theme_font_size_override("font_size", 19)
	name_label.add_theme_color_override("font_color", INK)
	info.add_child(name_label)
	var detail: Label = Label.new()
	var rivals: int = maxi(0, save.companies.size() - 1)
	detail.text = "Day %d · $%.0f · %d rival%s" % [
		save.day,
		player.cash if player != null else 0.0,
		rivals,
		"" if rivals == 1 else "s",
	]
	detail.add_theme_font_size_override("font_size", 14)
	detail.add_theme_color_override("font_color", INK_SOFT)
	info.add_child(detail)
	var load_btn: Button = Button.new()
	load_btn.text = "Load"
	load_btn.custom_minimum_size = Vector2(200, 48)
	load_btn.add_theme_font_size_override("font_size", 18)
	TycoonTheme.apply_orange(load_btn)
	load_btn.add_theme_color_override("font_color", Color.WHITE)
	load_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	load_btn.pressed.connect(func() -> void: get_parent().load_saved_game())
	_column.add_child(load_btn)
	_column.add_child(_delete_button())


func _build_incompatible() -> void:
	var note: Label = Label.new()
	note.text = "This save is from an older version (before rival companies) and can't be loaded. Start a new game — or delete the old file."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(460, 0)
	note.add_theme_color_override("font_color", INK_SOFT)
	_column.add_child(note)
	_column.add_child(_delete_button())


func _delete_button() -> Button:
	var delete_btn: Button = Button.new()
	delete_btn.text = "Delete Save"
	delete_btn.custom_minimum_size = Vector2(160, 40)
	delete_btn.add_theme_color_override("font_color", Color("#C7331C"))
	delete_btn.pressed.connect(func() -> void:
		TycoonConfirmDialog.ask(self, "Delete the save?",
			"This permanently removes the saved game.",
			func() -> void:
				SaveSystem.delete_save()
				_rebuild(),
			"Delete"))
	return delete_btn
