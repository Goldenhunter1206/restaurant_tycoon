class_name AdProps
extends Node3D
## World visuals for marketing: a billboard prop on every rented placement
## site (city megapack sign + generated poster art) and a branded zeppelin
## circling the skyline while a citywide campaign runs. Rebuilds only when
## placements/campaigns change — max ~24 small props, never per-frame work.

const BILLBOARD_SCENE: String = "res://Cartoon City Massive Megapack/gLTF/Signs/Bilboard_1_A.glb"
const POSTER_DIR: String = "res://assets/ads"
const BILLBOARD_VISIBILITY_RANGE: float = 420.0
const BILLBOARD_SCALE: float = 2.0
const ZEPPELIN_ALTITUDE: float = 130.0
const ZEPPELIN_ORBIT_RADIUS: float = 260.0
const ZEPPELIN_SPEED: float = 0.03

var _billboards: Node3D
var _zeppelin: Node3D
var _zeppelin_angle: float = 0.0
var _city_center: Vector3 = Vector3(400, 0, 400)


func _ready() -> void:
	_billboards = Node3D.new()
	_billboards.name = "Billboards"
	add_child(_billboards)
	MarketingManager.placements_changed.connect(_rebuild_billboards)
	MarketingManager.campaigns_changed.connect(_on_campaigns_changed)
	_compute_center.call_deferred()
	_rebuild_billboards.call_deferred()
	_on_campaigns_changed.call_deferred()


func _process(delta: float) -> void:
	if _zeppelin == null:
		return
	_zeppelin_angle += ZEPPELIN_SPEED * delta
	var pos: Vector3 = _city_center + Vector3(
		cos(_zeppelin_angle) * ZEPPELIN_ORBIT_RADIUS,
		ZEPPELIN_ALTITUDE,
		sin(_zeppelin_angle) * ZEPPELIN_ORBIT_RADIUS)
	_zeppelin.position = pos
	# Nose along the orbit tangent.
	_zeppelin.rotation.y = -_zeppelin_angle


func _rebuild_billboards() -> void:
	for child: Node in _billboards.get_children():
		child.queue_free()
	for site: AdPlacement in MarketingManager.placements:
		if site.vacant():
			continue
		_billboards.add_child(_make_billboard(site))


func _on_campaigns_changed() -> void:
	var wanted: MarketingCampaign = null
	for campaign: MarketingCampaign in MarketingManager.campaigns:
		var def: MarketingChannelDef = MarketingManager.channel(campaign.channel_id)
		if def != null and def.world_prop == &"zeppelin":
			wanted = campaign
			break
	if wanted == null and _zeppelin != null:
		_zeppelin.queue_free()
		_zeppelin = null
	elif wanted != null and _zeppelin == null:
		_zeppelin = _make_zeppelin(wanted)
		add_child(_zeppelin)
	# Poster art follows the campaign on the site.
	_rebuild_billboards()


func _make_billboard(site: AdPlacement) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = "Billboard_%d" % site.id
	holder.position = site.world_pos
	holder.rotation.y = site.yaw
	holder.scale = Vector3.ONE * BILLBOARD_SCALE
	var packed: PackedScene = load(BILLBOARD_SCENE)
	if packed != null:
		var structure: Node3D = packed.instantiate()
		_limit_visibility(structure)
		holder.add_child(structure)
	# Poster face on the panel front (middle band of the portrait art).
	var face: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2.9, 1.45)
	face.mesh = quad
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var poster: Texture2D = _poster_for(site)
	if poster != null:
		material.albedo_texture = poster
		material.uv1_scale = Vector3(1.0, 0.45, 1.0)
		material.uv1_offset = Vector3(0.0, 0.28, 0.0)
	face.material_override = material
	face.position = Vector3(-0.46, 1.55, 0.0)
	face.rotation.y = -PI / 2.0
	face.visibility_range_end = BILLBOARD_VISIBILITY_RANGE
	holder.add_child(face)
	# Thin brand-color band under the art so ownership reads at a glance.
	var band: MeshInstance3D = MeshInstance3D.new()
	var band_mesh: BoxMesh = BoxMesh.new()
	band_mesh.size = Vector3(0.06, 0.14, 2.9)
	band.mesh = band_mesh
	var band_material: StandardMaterial3D = StandardMaterial3D.new()
	band_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var owner_company: CompanyState = CompanyManager.company(site.owner_company)
	band_material.albedo_color = owner_company.brand_color if owner_company != null else Color.WHITE
	band.material_override = band_material
	band.position = Vector3(-0.46, 0.74, 0.0)
	band.visibility_range_end = BILLBOARD_VISIBILITY_RANGE
	holder.add_child(band)
	return holder


func _make_zeppelin(campaign: MarketingCampaign) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = "AdZeppelin"
	var company: CompanyState = CompanyManager.company(campaign.company_id)
	var brand: Color = company.brand_color if company != null else Color("#EA4A2F")
	# Body: stretched capsule, brand-tinted.
	var body: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: CapsuleMesh = CapsuleMesh.new()
	body_mesh.radius = 6.0
	body_mesh.height = 40.0
	body.mesh = body_mesh
	body.rotation.z = PI / 2.0
	var body_material: StandardMaterial3D = StandardMaterial3D.new()
	body_material.albedo_color = brand.lerp(Color.WHITE, 0.35)
	body.material_override = body_material
	holder.add_child(body)
	# Tail fins.
	for angle: float in [0.0, PI / 2.0]:
		var fin: MeshInstance3D = MeshInstance3D.new()
		var fin_mesh: BoxMesh = BoxMesh.new()
		fin_mesh.size = Vector3(6.0, 8.0, 0.5)
		fin.mesh = fin_mesh
		fin.position = Vector3(-17.0, 0.0, 0.0)
		fin.rotation.x = angle
		var fin_material: StandardMaterial3D = StandardMaterial3D.new()
		fin_material.albedo_color = brand
		fin.material_override = fin_material
		holder.add_child(fin)
	# Banner strips on both flanks.
	var banner: Texture2D = load("%s/banner_zeppelin.png" % POSTER_DIR)
	for side: float in [1.0, -1.0]:
		var strip: MeshInstance3D = MeshInstance3D.new()
		var strip_mesh: QuadMesh = QuadMesh.new()
		strip_mesh.size = Vector2(30.0, 9.0)
		strip.mesh = strip_mesh
		var strip_material: StandardMaterial3D = StandardMaterial3D.new()
		strip_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if banner != null:
			strip_material.albedo_texture = banner
		strip.material_override = strip_material
		strip.position = Vector3(0.0, -1.0, side * 6.2)
		if side < 0.0:
			strip.rotation.y = PI
		strip.material_override = strip_material
		holder.add_child(strip)
	return holder


## Poster art keyed to the campaign running on the site (claim/recipe/segment),
## falling back to a per-site stable default.
func _poster_for(site: AdPlacement) -> Texture2D:
	var campaign: MarketingCampaign = null
	for entry: MarketingCampaign in MarketingManager.campaigns:
		if entry.placement_ids.has(site.id):
			campaign = entry
			break
	var name: String = "poster_generic_slice"
	if campaign != null:
		if campaign.promoted_recipe != &"":
			name = "poster_new_recipe"
		elif campaign.claim == &"lowest_price":
			name = "poster_value_deal"
		elif campaign.claim == &"highest_quality" or campaign.claim == &"best_staff":
			name = "poster_premium"
		elif campaign.segments().has(&"families"):
			name = "poster_family_night"
		elif campaign.segments().has(&"teens") or campaign.segments().has(&"students"):
			name = "poster_spicy_special"
		elif campaign.days_run <= 1:
			name = "poster_grand_opening"
	var path: String = "%s/%s.png" % [POSTER_DIR, name]
	if not ResourceLoader.exists(path):
		path = "%s/poster_generic_slice.png" % POSTER_DIR
	if not ResourceLoader.exists(path):
		return null
	return load(path)


func _limit_visibility(node: Node) -> void:
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		for child: Node in current.get_children():
			stack.push_back(child)
		if current is GeometryInstance3D:
			(current as GeometryInstance3D).visibility_range_end = BILLBOARD_VISIBILITY_RANGE


func _compute_center() -> void:
	if CityData.buildings.is_empty():
		return
	var total: Vector3 = Vector3.ZERO
	for info: Dictionary in CityData.buildings.values():
		total += info.get("position", Vector3.ZERO)
	_city_center = total / CityData.buildings.size()
	_city_center.y = 0.0
