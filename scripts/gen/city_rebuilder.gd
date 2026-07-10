class_name CityRebuilder
extends RefCounted
## Regenerates the baked City scene and road graph from CityBuilder math.
## Run from the editor via godotiq exec:
##     CityRebuilder.rebuild_all()
## Writes res://scenes/world/City.tscn and res://data/road_graph.tres.
##
## Roads / motorway / traffic lights are individual glb instances; buildings
## are wrapped in a StaticBody3D (selection + registration metadata). Trees,
## lamps and parks are a fresh procedural pass — see DecorPlacer / ParkPlacer,
## loaded dynamically so the core can be rebuilt without them.

const CITY_SCENE: String = "res://scenes/world/City.tscn"
const GRAPH_PATH: String = "res://data/road_graph.tres"
const CATALOG_PATH: String = "res://data/building_catalog.json"
const LIGHT_GLB: String = "res://Cartoon City Massive Megapack/gLTF 2/Signs/Lights_6_A.glb"
const CITY_SCRIPT: String = "res://scripts/world/city.gd"
const DECOR_SCRIPT: String = "res://scripts/gen/decor_placer.gd"
const PARK_SCRIPT: String = "res://scripts/gen/park_placer.gd"
const SIDEWALK_SCRIPT: String = "res://scripts/gen/sidewalk_placer.gd"
const CONCRETE_SCRIPT: String = "res://scripts/gen/concrete_placer.gd"
const YARD_SCRIPT: String = "res://scripts/gen/suburban_yard_placer.gd"
const INDUSTRIAL_SCRIPT: String = "res://scripts/gen/industrial_dressing_placer.gd"
const GRAFFITI_SCRIPT: String = "res://scripts/gen/graffiti_placer.gd"
const GROUND_ALBEDO: Color = Color(0.45, 0.76, 0.32)
const GROUND_GRASS_TEX: String = "res://Cartoon City Massive Megapack/gLTF 2/Tiles/GrassTile_D_1_Grass.png"
const GROUND_UV_TILES: float = 120.0   # texture repeats across the 1500 m plane (~12.5 m per tile)
const VIS_RANGE_END: float = 900.0
const VIS_RANGE_MARGIN: float = 80.0

const N: int = 1
const S: int = 2
const E: int = 4
const W: int = 8


static func rebuild_all(with_decor: bool = true) -> Dictionary:
	var counts := {}
	var cache := {}
	var root := Node3D.new()
	root.name = "City"
	root.set_script(load(CITY_SCRIPT))

	var road_tiles: Array = CityBuilder.build_v_segment_tiles()
	road_tiles.append_array(CityBuilder.build_h_segment_tiles())
	road_tiles.append_array(CityBuilder.build_intersection_tiles())
	counts["roads"] = _build_flat_group(root, "Roads", road_tiles, cache)

	var cat: Dictionary = load(CATALOG_PATH).data
	var placements: Array[Dictionary] = BuildingPlacer.build_placements(cat)
	counts["buildings"] = _build_buildings(root, cache, placements)
	counts["lights"] = _build_lights(root, cache)
	counts["motorway"] = _build_flat_group(root, "Motorway", CityBuilder.build_motorway_tiles(), cache)
	_build_ground(root)

	if with_decor:
		var sw: Object = load(SIDEWALK_SCRIPT)
		counts["sidewalks"] = sw.build(root)
		var cp: Object = load(CONCRETE_SCRIPT)
		counts["concrete"] = cp.build(root)
		var dp: Object = load(DECOR_SCRIPT)
		counts["decor"] = dp.build(root)
		var pp: Object = load(PARK_SCRIPT)
		counts["parks"] = pp.build(root)
		counts["dressing"] = BuildingDressingPlacer.build(root, placements)
		counts["signage"] = SignPlacer.build(root)
		counts["construction"] = ConstructionPlacer.build(root)
		counts["parked_cars"] = ParkedCarPlacer.build(root)
		var ip: Object = load(INDUSTRIAL_SCRIPT)
		counts["industrial"] = ip.build(root, placements)
		var gp: Object = load(GRAFFITI_SCRIPT)
		counts["graffiti"] = gp.build(root, placements)
		var yp: Object = load(YARD_SCRIPT)
		counts["yards"] = yp.build(root, placements)

	_set_owner_rec(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	counts["scene_err"] = ResourceSaver.save(packed, CITY_SCENE)
	root.free()

	var graph: Resource = GraphGenerator.build()
	counts["graph_err"] = ResourceSaver.save(graph, GRAPH_PATH)
	counts["lane_nodes"] = graph.lane_points.size()
	counts["side_nodes"] = graph.side_points.size()
	return counts


static func _cached_scene(cache: Dictionary, path: String) -> PackedScene:
	if not cache.has(path):
		cache[path] = load(path)
	return cache[path]


static func _build_flat_group(root: Node3D, group_name: String, tiles: Array, cache: Dictionary) -> int:
	var grp := Node3D.new()
	grp.name = group_name
	root.add_child(grp)
	return MeshBatch.emit_grouped(grp, tiles, cache)


static func _build_buildings(root: Node3D, cache: Dictionary, placements: Array[Dictionary]) -> int:
	var grp := Node3D.new()
	grp.name = "Buildings"
	root.add_child(grp)
	var shape_cache := {}
	var id := 0
	for p: Dictionary in placements:
		var body := StaticBody3D.new()
		body.name = "Bldg_%d" % id
		body.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(p["rot_y"])), p["pos"])
		body.set_meta("building_id", id)
		body.set_meta("district", p["district"])
		body.set_meta("btype", p["type"])
		body.set_meta("family", p["family"])
		body.set_meta("size", Vector3(p["w"], p["h"], p["d"]))
		body.set_meta("front_dir", p.get("front", Vector3(0, 0, 1)))
		grp.add_child(body)
		var vis: Node = _cached_scene(cache, p["path"]).instantiate()
		body.add_child(vis)
		_apply_vis_range(vis)
		var su: Vector3 = p.get("standup", Vector3.ZERO)
		if su != Vector3.ZERO and vis is Node3D:
			(vis as Node3D).rotation_degrees = su
		_sit_on_ground(vis)
		var col := CollisionShape3D.new()
		col.shape = _cached_box(shape_cache, p["w"], p["h"], p["d"])
		col.position = Vector3(0.0, p["h"] * 0.5, 0.0)
		body.add_child(col)
		id += 1
	return id


static func _cached_box(shape_cache: Dictionary, w: float, h: float, d: float) -> BoxShape3D:
	var key := "%d_%d_%d" % [roundi(w * 10.0), roundi(h * 10.0), roundi(d * 10.0)]
	if not shape_cache.has(key):
		var box := BoxShape3D.new()
		box.size = Vector3(w, h, d)
		shape_cache[key] = box
	return shape_cache[key]


static func _build_lights(root: Node3D, cache: Dictionary) -> int:
	var grp := Node3D.new()
	grp.name = "TrafficLights"
	root.add_child(grp)
	var xforms: Array = []
	for i in range(CityBuilder.LINES):
		for j in range(CityBuilder.LINES):
			if not CityBuilder.is_signalized(i, j):
				continue
			var mask := CityBuilder.intersection_branches(i, j)
			var center := Vector3(CityBuilder.line_x(i), 0.0, CityBuilder.line_z(j))
			for d in [N, S, E, W]:
				if not (mask & d):
					continue
				var fwd := _dir_vec(d)
				var right := Vector3(-fwd.z, 0.0, fwd.x)
				var pos := center + fwd * 5.5 + right * 5.5
				xforms.append(Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), Vector3(pos.x, 0.42, pos.z)))
	MeshBatch.emit(grp, "Sig", LIGHT_GLB, xforms, cache)
	return xforms.size()


static func _build_ground(root: Node3D) -> void:
	var grp := Node3D.new()
	grp.name = "Nature"
	root.add_child(grp)
	var mi := MeshInstance3D.new()
	mi.name = "GroundPlane"
	var pm := PlaneMesh.new()
	pm.size = Vector2(1500.0, 1500.0)
	var mat := StandardMaterial3D.new()
	var tex: Texture2D = load(GROUND_GRASS_TEX)
	if tex != null:
		mat.albedo_texture = tex
		mat.uv1_scale = Vector3(GROUND_UV_TILES, GROUND_UV_TILES, 1.0)
		mat.albedo_color = Color.WHITE
	else:
		mat.albedo_color = GROUND_ALBEDO
	mat.roughness = 1.0
	mat.metallic = 0.0
	pm.material = mat
	mi.mesh = pm
	var ext := CityBuilder.city_extent()
	mi.position = Vector3(ext.size.x * 0.5, -0.02, ext.size.y * 0.5)
	grp.add_child(mi)


static func _dir_vec(bit: int) -> Vector3:
	match bit:
		N: return Vector3(0, 0, -1)
		S: return Vector3(0, 0, 1)
		E: return Vector3(1, 0, 0)
		_: return Vector3(-1, 0, 0)


## Some pack building glbs have their origin at the model CENTRE (e.g. Building_2
## has min-y ~= -3.1), so placing them at y=0 sinks half the building underground
## and it reads as a flat slab. Offset the visual up so its base sits on y=0.
static func _sit_on_ground(vis: Node) -> void:
	if not (vis is Node3D):
		return
	var miny := _mesh_min_y(vis, Transform3D.IDENTITY)
	if miny < 1.0e8 and absf(miny) > 0.05:
		(vis as Node3D).position.y -= miny


static func _mesh_min_y(node: Node, xf: Transform3D) -> float:
	var m := xf
	if node is Node3D:
		m = xf * (node as Node3D).transform
	var lo := 1.0e9
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var a: AABB = (node as MeshInstance3D).mesh.get_aabb()
		for ix in [0.0, 1.0]:
			for iy in [0.0, 1.0]:
				for iz in [0.0, 1.0]:
					lo = minf(lo, (m * (a.position + Vector3(a.size.x * ix, a.size.y * iy, a.size.z * iz))).y)
	for c in node.get_children():
		lo = minf(lo, _mesh_min_y(c, m))
	return lo


## Balanced far-field fade so only distant buildings thin out; the near/mid
## skyline stays intact. Applied to every GeometryInstance3D in the glb visual.
static func _apply_vis_range(node: Node) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.visibility_range_end = VIS_RANGE_END
		gi.visibility_range_end_margin = VIS_RANGE_MARGIN
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for c in node.get_children():
		_apply_vis_range(c)


static func _set_owner_rec(node: Node, owner: Node) -> void:
	for c in node.get_children():
		if c != owner:
			c.owner = owner
		_set_owner_rec(c, owner)
