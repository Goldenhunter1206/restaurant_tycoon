class_name InspectorPanel
extends PanelContainer
## Click-to-inspect panel for citizens, houses, cars and drivers.
## For shop buildings it doubles as the purchase flow: shows the asking
## price and a Buy button; owned restaurants get a Manage button.

signal manage_requested(building_id: int)

const REFRESH_INTERVAL: float = 0.4

const FIELD_LABELS: Dictionary = {
	"name": "Name", "state": "State", "goal": "Doing", "home": "Home",
	"job": "Job", "shift": "Shift", "owns_car": "Owns car", "money": "Money",
	"wage": "Wage", "likes": "Likes", "vehicle_kind": "Type", "owner": "Owner",
	"passenger": "Passenger", "district": "District", "type": "Type",
	"residents": "Residents", "workers": "Workers", "employer": "Employer",
	"order": "Carrying", "capacity_residents": "Beds", "capacity_workers": "Jobs",
}
## Keys never shown to the player.
const HIDDEN_FIELDS: Array[String] = [
	"position", "kind", "id", "family", "wake", "work_start", "home_hour",
	"stopped_at_light",
]

var _title: Label
var _body: RichTextLabel
var _action_btn: Button
var _current_building: int = -1
var _accum: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(300, 0)
	visible = false
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var header: HBoxContainer = HBoxContainer.new()
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 17)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close_btn: Button = Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(func() -> void: visible = false)
	header.add_child(close_btn)
	box.add_child(header)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.custom_minimum_size = Vector2(280, 0)
	box.add_child(_body)
	_action_btn = Button.new()
	_action_btn.visible = false
	_action_btn.pressed.connect(_on_action)
	box.add_child(_action_btn)
	SelectionManager.entity_selected.connect(_on_selected)
	SelectionManager.selection_cleared.connect(func() -> void: visible = false)


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum >= REFRESH_INTERVAL:
		_accum = 0.0
		var info: Dictionary = SelectionManager.current_info()
		if info.is_empty():
			visible = false
		else:
			_render(info)


func _on_selected(info: Dictionary, _entity: Node) -> void:
	visible = true
	_render(info)


func _render(info: Dictionary) -> void:
	var kind: String = String(info.get("kind", "?"))
	_current_building = int(info.get("id", -1)) if kind == "building" else -1
	_title.text = _title_for(kind, info)
	var lines: PackedStringArray = PackedStringArray()
	for key: String in info:
		if key in HIDDEN_FIELDS:
			continue
		var label: String = FIELD_LABELS.get(key, String(key).capitalize())
		lines.append("[color=#8a5a2b]%s:[/color] %s" % [label, str(info[key])])
	_body.text = "\n".join(lines)
	_update_action(kind)


func _title_for(kind: String, info: Dictionary) -> String:
	match kind:
		"citizen":
			return "👤 %s" % info.get("name", "Citizen")
		"vehicle":
			return "🚗 %s" % info.get("owner", "Vehicle")
		"delivery driver":
			return "🛵 %s" % info.get("name", "Driver")
		"building":
			var b_type: String = String(info.get("type", ""))
			var icon: String = "🏠" if b_type == "home" else "🏢"
			if RestaurantManager.by_building.has(_current_building):
				icon = "🍕"
			return "%s Building #%d (%s)" % [icon, _current_building, b_type]
	return kind.capitalize()


func _update_action(kind: String) -> void:
	_action_btn.visible = false
	if kind != "building" or _current_building < 0:
		return
	if RestaurantManager.by_building.has(_current_building):
		_action_btn.text = "🍕 Manage restaurant"
		_action_btn.visible = true
	elif RestaurantManager.is_purchasable(_current_building):
		var price: float = RestaurantManager.price_for(_current_building)
		_action_btn.text = "🏗 Buy for $%.0f" % price
		_action_btn.disabled = not EconomyManager.can_afford(price)
		_action_btn.visible = true


func _on_action() -> void:
	if _current_building < 0:
		return
	if RestaurantManager.by_building.has(_current_building):
		manage_requested.emit(_current_building)
	elif RestaurantManager.purchase(_current_building):
		_update_action("building")
