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
	"delivery_stage": "Delivery stage", "driver": "Driver", "restaurant": "Restaurant",
	"destination": "Destination", "order_detail": "Order", "thought": "Thinking",
}
## Keys never shown to the player.
const HIDDEN_FIELDS: Array[String] = [
	"position", "kind", "id", "family", "wake", "work_start", "home_hour",
	"stopped_at_light", "route_points", "destination_position", "our_delivery_car",
]

var _title: Label
var _body: RichTextLabel
var _action_btn: Button
var _current_building: int = -1
var _accum: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(300, 0)
	visible = false
	add_theme_stylebox_override("panel", TycoonTheme.wood_frame_sm_box())
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
	var assets: GDScript = load("res://scripts/ui/ui_assets.gd")
	if assets.icon(&"close") != null:
		close_btn.text = ""
		assets.icon_button(close_btn, &"close", 16)
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
			return String(info.get("name", "Citizen"))
		"vehicle":
			if bool(info.get("our_delivery_car", false)):
				return "OUR DELIVERY CAR"
			return String(info.get("owner", "Vehicle"))
		"delivery driver":
			return "Driver %s" % info.get("name", "")
		"building":
			var b_type: String = String(info.get("type", ""))
			if RestaurantManager.by_building.has(_current_building):
				return "Restaurant · Building #%d" % _current_building
			return "Building #%d (%s)" % [_current_building, b_type]
	return kind.capitalize()


func _update_action(kind: String) -> void:
	_action_btn.visible = false
	if kind != "building" or _current_building < 0:
		return
	if RestaurantManager.by_building.has(_current_building):
		_action_btn.text = "Manage restaurant"
		var assets: GDScript = load("res://scripts/ui/ui_assets.gd")
		assets.icon_button(_action_btn, &"store", 18)
		_action_btn.visible = true
	elif RestaurantManager.is_purchasable(_current_building):
		var fee: float = RestaurantManager.signing_fee_for(_current_building)
		_action_btn.text = "Sign lease for $%.0f" % fee
		var assets_buy: GDScript = load("res://scripts/ui/ui_assets.gd")
		assets_buy.icon_button(_action_btn, &"hammer", 18)
		_action_btn.disabled = not EconomyManager.can_afford(fee)
		_action_btn.visible = true


func _on_action() -> void:
	if _current_building < 0:
		return
	if RestaurantManager.by_building.has(_current_building):
		manage_requested.emit(_current_building)
	elif RestaurantManager.purchase(_current_building):
		_update_action("building")
