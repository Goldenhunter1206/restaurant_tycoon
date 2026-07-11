extends TycoonScreen
## Placeholder for features that are not implemented yet
## (Marketing, Suppliers, Reports, Rankings).

var _screen_id: StringName = &"feature"


func set_screen_id(screen_id: StringName) -> void:
	_screen_id = screen_id


func screen_title() -> String:
	return String(_screen_id).capitalize()


func screen_icon() -> StringName:
	const ICONS: Dictionary = {
		&"marketing": &"megaphone", &"suppliers": &"truck",
		&"reports": &"chart_bars", &"rankings": &"trophy",
	}
	return ICONS.get(_screen_id, &"pizza")


func _build() -> void:
	var assets: GDScript = load("res://scripts/ui/ui_assets.gd")
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(box)
	var big_icon: TextureRect = assets.icon_rect(screen_icon(), 64)
	big_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	big_icon.modulate = Color(1, 1, 1, 0.55)
	box.add_child(big_icon)
	var label: Label = Label.new()
	label.text = "Coming soon! %s is on the roadmap." % String(_screen_id).capitalize()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(400, 40)
	box.add_child(label)
