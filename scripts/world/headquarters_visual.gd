class_name HeadquartersVisual
extends Node3D
## Reusable rooftop dressing for an acquired office. Geometry is authored in
## HeadquartersVisual.tscn; this script only fits it to generated building bounds.

@onready var _scale_root: Node3D = $ScaleRoot
@onready var _construction: Node3D = $ScaleRoot/Construction
@onready var _tier_one: Node3D = $ScaleRoot/TierOne
@onready var _tier_two: Node3D = $ScaleRoot/TierTwo
@onready var _tier_three: Node3D = $ScaleRoot/TierThree
@onready var _name_label: Label3D = $NameLabel
@onready var _progress_label: Label3D = $ProgressLabel

var _state: HeadquartersState
var _company: CompanyState
var _building_size: Vector3 = Vector3(12.0, 8.0, 12.0)


func setup(state: HeadquartersState, company: CompanyState) -> void:
	_state = state
	_company = company
	var info: Dictionary = CityData.get_building(state.building_id)
	var body: Node3D = null
	var node_path: NodePath = info.get("node_path", NodePath())
	if not node_path.is_empty():
		body = get_tree().root.get_node_or_null(node_path) as Node3D
	if body != null and body.has_meta("size"):
		_building_size = body.get_meta("size") as Vector3
	var base: Vector3 = Vector3(info.get("position", Vector3.ZERO))
	global_position = Vector3(base.x, _building_size.y + 0.15, base.z)
	if body != null:
		global_rotation = Vector3(0.0, body.global_rotation.y, 0.0)
	_scale_root.scale = Vector3(
		clampf(_building_size.x / 12.0, 0.65, 2.0),
		1.0,
		clampf(_building_size.z / 12.0, 0.65, 2.0)
	)
	set_meta("entity_kind", &"headquarters")
	set_meta("company_id", company.id)
	set_meta("building_id", state.building_id)
	_name_label.text = "%s HQ" % company.display_name
	_name_label.modulate = company.brand_color.lerp(Color("#fff1c7"), 0.55)
	_name_label.outline_modulate = company.brand_color.darkened(0.45)
	_refresh()


func _process(_delta: float) -> void:
	if _state != null:
		_refresh_project()


func _refresh() -> void:
	var tier: int = _state.tier if _state != null else 0
	_tier_one.visible = tier >= 1
	_tier_two.visible = tier >= 2
	_tier_three.visible = tier >= 3
	_construction.visible = _state != null and _state.has_active_project()
	_refresh_project()


func _refresh_project() -> void:
	if _state == null:
		_progress_label.visible = false
		return
	var project: UpgradeProjectState = _state.active_project()
	_progress_label.visible = project != null
	if project == null:
		return
	var percent: int = roundi(project.progress_at(GameClock.total_minutes()) * 100.0)
	_progress_label.text = "BUILDING  %d%%" % percent
