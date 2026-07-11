extends TycoonScreen
## Placeholder for features that are not implemented yet
## (Marketing, Suppliers, Reports, Rankings).

var _screen_id: StringName = &"feature"


func set_screen_id(screen_id: StringName) -> void:
	_screen_id = screen_id


func screen_title() -> String:
	return "🚧  %s" % String(_screen_id).capitalize()


func _build() -> void:
	var label: Label = Label.new()
	label.text = "Coming soon! %s is on the roadmap." % String(_screen_id).capitalize()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(400, 80)
	_content.add_child(label)
