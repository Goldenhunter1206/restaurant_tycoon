class_name DevInspector
extends Control
## Developer info panel for the currently selected citizen / vehicle /
## building. Live-updates while something is selected.

var _panel: PanelContainer
var _label: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(340, 0)
	add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -352
	_panel.offset_top = 12
	_panel.offset_right = -12
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(330, 60)
	_panel.add_child(_label)
	_panel.visible = false
	SelectionManager.entity_selected.connect(_on_selected)
	SelectionManager.selection_cleared.connect(_on_cleared)


func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	var info := SelectionManager.current_info()
	if info.is_empty():
		_panel.visible = false
		return
	_render(info)


func _on_selected(info: Dictionary, _entity: Node) -> void:
	_panel.visible = true
	_render(info)


func _on_cleared() -> void:
	_panel.visible = false


func _render(info: Dictionary) -> void:
	var lines := "[b]%s[/b]\n" % String(info.get("kind", "?")).to_upper()
	for key in info:
		if key == "kind":
			continue
		lines += "[color=#9fd]%s[/color]: %s\n" % [key, str(info[key])]
	_label.text = lines
