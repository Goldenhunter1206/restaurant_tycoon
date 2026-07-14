class_name TycoonConfirmDialog
extends Control
## Themed modal confirmation with an explicit consequence line. Focus defaults
## to Cancel so destructive actions need a deliberate choice (accessibility
## rule: destructive confirmations default focus to Cancel).
##
## Usage: TycoonConfirmDialog.ask(parent, "Clear pizza?",
##     "All 6 placed ingredients are removed.", func() -> void: _clear())

var _on_confirm: Callable


static func ask(parent: Node, title: String, consequence: String,
		on_confirm: Callable, confirm_label: String = "Confirm") -> void:
	var dialog: TycoonConfirmDialog = TycoonConfirmDialog.new()
	dialog._on_confirm = on_confirm
	parent.add_child(dialog)
	dialog._build(title, consequence, confirm_label)


func _build(title: String, consequence: String, confirm_label: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.18, 0.09, 0.04, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", TycoonTheme.wood_frame_box())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var inner: PanelContainer = PanelContainer.new()
	inner.add_theme_stylebox_override("panel", TycoonTheme.paper_box())
	panel.add_child(inner)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(340, 0)
	inner.add_child(box)

	var title_label: Label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", TycoonTheme.FONT_SIZE_TITLE)
	title_label.add_theme_color_override("font_color", TycoonTheme.PALETTE["wood_deep"])
	box.add_child(title_label)

	var body: Label = Label.new()
	body.text = consequence
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", TycoonTheme.PALETTE["text"])
	box.add_child(body)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)

	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(96, 40)
	cancel.pressed.connect(queue_free)
	buttons.add_child(cancel)

	var confirm: Button = Button.new()
	confirm.text = confirm_label
	confirm.custom_minimum_size = Vector2(110, 40)
	TycoonTheme.apply_orange(confirm)
	confirm.pressed.connect(func() -> void:
		queue_free()
		if _on_confirm.is_valid():
			_on_confirm.call())
	buttons.add_child(confirm)

	cancel.grab_focus()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
