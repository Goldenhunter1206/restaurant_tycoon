class_name SidewalkPlacer
extends RefCounted
## Paves sidewalks and lines them with street furniture. For every block, a
## 2 m pavement band (StreetTile MultiMesh) runs along each road-facing lot
## edge, and furniture (hydrants, bins, benches, post boxes, meters, bus
## stops, kiosks, food carts...) is placed at the curb facing the road.
## Deterministic; built under a "Sidewalks" group node.

const TILES := "res://Cartoon City Massive Megapack/gLTF 2/Tiles/"
const SP := "res://Cartoon City Massive Megapack/gLTF 2/Street Props/"
const NP := "res://Cartoon City Massive Megapack/gLTF 2/Nature and Park/"

const PAVERS: Array[String] = [TILES + "StreetTile_1_A_1.glb", TILES + "StreetTile_1_C_1.glb"]
const KERB: Array[String] = [SP + "Kerbstone_A_1.glb", SP + "Kerbstone_A_2.glb", SP + "Kerbstone_A_3.glb"]
const KERB_LEN: float = 2.0    # kerbstone length along its local Z
const BAND: float = 2.0            # sidewalk depth = one tile
const PAVE_Y: float = 0.0
const FURN_Y: float = 0.1          # furniture rests on the pavement top
const CURB_INSET: float = 0.75     # furniture distance from the curb into the sidewalk
const CORNER_CLEAR: float = 5.0    # keep furniture away from intersections
const SEED: int = 51413

## Furniture table. d = allowed district letters ("" = any); along = long prop
## laid parallel to the kerb; big = bulky prop (commercial frontages only).
const FURN: Array[Dictionary] = [
	{"p": SP + "Hydrant.glb", "w": 4, "d": ""},
	{"p": NP + "Trashbin_1_A.glb", "w": 4, "d": ""},
	{"p": SP + "PostBox_1_A.glb", "w": 2, "d": ""},
	{"p": SP + "Bench_4_A.glb", "w": 3, "d": "DCNRP", "along": true},
	{"p": SP + "Parkomat.glb", "w": 3, "d": "DC"},
	{"p": SP + "NewspaperH.glb", "w": 2, "d": "DC"},
	{"p": SP + "BikePlace.glb", "w": 2, "d": "DCNP", "along": true},
	{"p": SP + "BusStop_A.glb", "w": 1, "d": "DC", "big": true},
	{"p": SP + "Kiosk_1_A.glb", "w": 1, "d": "DC", "big": true},
	{"p": SP + "FoodCart_1_A.glb", "w": 1, "d": "D", "big": true},
]


static func build(root: Node3D) -> Dictionary:
	var grp := Node3D.new()
	grp.name = "Sidewalks"
	root.add_child(grp)
	var cache := {}

	var paver_xforms: Array = []
	for _p in PAVERS:
		paver_xforms.append([])
	var kerb_xforms: Array = []
	for _k in KERB:
		kerb_xforms.append([])
	var furn_xforms := {}
	_gather(paver_xforms, kerb_xforms, furn_xforms)

	var pave_node := Node3D.new()
	pave_node.name = "Pavement"
	grp.add_child(pave_node)
	var pave_count := 0
	for v in range(PAVERS.size()):
		var xs: Array = paver_xforms[v]
		if xs.is_empty():
			continue
		pave_count += xs.size()
		_emit_mm(pave_node, "Pave%d" % v, PAVERS[v], xs, cache)

	var kerb_node := Node3D.new()
	kerb_node.name = "Kerb"
	grp.add_child(kerb_node)
	var kerb_count := 0
	for v in range(KERB.size()):
		var kxs: Array = kerb_xforms[v]
		if kxs.is_empty():
			continue
		kerb_count += kxs.size()
		MeshBatch.emit(kerb_node, "Kerb%d" % v, KERB[v], kxs, cache)

	var furn_node := Node3D.new()
	furn_node.name = "StreetFurniture"
	grp.add_child(furn_node)
	var furn_count := 0
	var idx := 0
	for path: String in furn_xforms:
		var xs: Array = furn_xforms[path]
		furn_count += xs.size()
		_emit_mm(furn_node, "Furn%d" % idx, path, xs, cache)
		idx += 1

	return {"pavement": pave_count, "kerb": kerb_count, "furniture": furn_count}


static func _gather(paver_xforms: Array, kerb_xforms: Array, furn_xforms: Dictionary) -> void:
	var v_removed := CityBuilder.removed_v_segments()
	var h_removed := CityBuilder.removed_h_segments()
	for bi in range(CityBuilder.BLOCKS):
		for bj in range(CityBuilder.BLOCKS):
			var x0 := CityBuilder.line_x(bi) + 4.0
			var x1 := CityBuilder.line_x(bi + 1) - 4.0
			var z0 := CityBuilder.line_z(bj) + 4.0
			var z1 := CityBuilder.line_z(bj + 1) - 4.0
			var dist := CityBuilder.district(bi, bj)
			var n_road := not h_removed.has("%d,%d" % [bi, bj])
			var s_road := not h_removed.has("%d,%d" % [bi, bj + 1])
			var w_road := not v_removed.has("%d,%d" % [bi, bj])
			var e_road := not v_removed.has("%d,%d" % [bi + 1, bj])
			# Pavement bands (N/S span full width; W/E skip the shared corners).
			if n_road:
				_pave_row(paver_xforms, x0, x1, z0 + BAND * 0.5, true)
				_kerb_row(kerb_xforms, x0, x1, z0, true)
			if s_road:
				_pave_row(paver_xforms, x0, x1, z1 - BAND * 0.5, true)
				_kerb_row(kerb_xforms, x0, x1, z1, true)
			if w_road:
				_pave_row(paver_xforms, z0 + BAND, z1 - BAND, x0 + BAND * 0.5, false)
				_kerb_row(kerb_xforms, z0 + BAND, z1 - BAND, x0, false)
			if e_road:
				_pave_row(paver_xforms, z0 + BAND, z1 - BAND, x1 - BAND * 0.5, false)
				_kerb_row(kerb_xforms, z0 + BAND, z1 - BAND, x1, false)
			# Street furniture along each kerb.
			if dist == "" or dist == "X":
				continue
			if n_road:
				_furn_row(furn_xforms, x0, x1, z0 + CURB_INSET, true, Vector3(0, 0, -1), dist, bi * 71 + bj)
			if s_road:
				_furn_row(furn_xforms, x0, x1, z1 - CURB_INSET, true, Vector3(0, 0, 1), dist, bi * 71 + bj + 313)
			if w_road:
				_furn_row(furn_xforms, z0, z1, x0 + CURB_INSET, false, Vector3(-1, 0, 0), dist, bi * 91 + bj + 613)
			if e_road:
				_furn_row(furn_xforms, z0, z1, x1 - CURB_INSET, false, Vector3(1, 0, 0), dist, bi * 91 + bj + 907)


static func _pave_row(paver_xforms: Array, a0: float, a1: float, fixed: float, along_x: bool) -> void:
	var count := int(round((a1 - a0) / BAND))
	for k in range(count):
		var c := a0 + BAND * (float(k) + 0.5)
		var pos: Vector3 = Vector3(c, PAVE_Y, fixed) if along_x else Vector3(fixed, PAVE_Y, c)
		var key := int(c * 3.0 + fixed * 7.0)
		var v := absi(key) % PAVERS.size()
		var quarter := absi(key / 5) % 4
		paver_xforms[v].append(Transform3D(Basis(Vector3.UP, float(quarter) * PI * 0.5), pos))


static func _kerb_row(kerb_xforms: Array, a0: float, a1: float, fixed: float, along_x: bool) -> void:
	var count := int(round((a1 - a0) / KERB_LEN))
	for k in range(count):
		var c := a0 + KERB_LEN * (float(k) + 0.5)
		var pos: Vector3 = Vector3(c, 0.0, fixed) if along_x else Vector3(fixed, 0.0, c)
		var key := int(c * 2.0 + fixed * 5.0)
		var v := absi(key) % KERB.size()
		# Kerbstone length runs along local Z; rotate 90 deg for rows along X.
		var yaw: float = PI * 0.5 if along_x else 0.0
		kerb_xforms[v].append(Transform3D(Basis(Vector3.UP, yaw), pos))


static func _furn_row(furn: Dictionary, a0: float, a1: float, fixed: float, along_x: bool,
		face: Vector3, dist: String, salt: int) -> void:
	if a1 - a0 < 2.0 * CORNER_CLEAR + 2.0:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED ^ (salt * 2654435761)
	var yaw_base: float = atan2(face.x, face.z)
	var t: float = a0 + CORNER_CLEAR + rng.randf_range(0.0, 4.0)
	while t < a1 - CORNER_CLEAR:
		var item: Dictionary = _pick(rng, dist)
		if not item.is_empty():
			var pos: Vector3 = Vector3(t, FURN_Y, fixed) if along_x else Vector3(fixed, FURN_Y, t)
			var yaw: float = yaw_base + (PI * 0.5 if item.get("along", false) else 0.0)
			if not furn.has(item["p"]):
				furn[item["p"]] = []
			furn[item["p"]].append(Transform3D(Basis(Vector3.UP, yaw), pos))
		t += rng.randf_range(11.0, 17.0)


static func _pick(rng: RandomNumberGenerator, dist: String) -> Dictionary:
	var pool: Array = []
	var total := 0
	for item: Dictionary in FURN:
		var d: String = item["d"]
		if d != "" and not d.contains(dist):
			continue
		total += int(item["w"])
		pool.append(item)
	if pool.is_empty():
		return {}
	var roll := rng.randi_range(0, total - 1)
	for item: Dictionary in pool:
		roll -= int(item["w"])
		if roll < 0:
			return item
	return pool[0]


static func _emit_mm(parent: Node3D, base_name: String, glb_path: String, xforms: Array, cache: Dictionary) -> void:
	var submeshes: Array = _extract_meshes(glb_path, cache)
	for si in range(submeshes.size()):
		var sm: Dictionary = submeshes[si]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = sm["mesh"]
		mm.instance_count = xforms.size()
		var local: Transform3D = sm["xform"]
		for k in range(xforms.size()):
			mm.set_instance_transform(k, (xforms[k] as Transform3D) * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [base_name, si]
		mmi.multimesh = mm
		parent.add_child(mmi)


static func _extract_meshes(glb_path: String, cache: Dictionary) -> Array:
	if cache.has(glb_path):
		return cache[glb_path]
	var out: Array = []
	var ps: PackedScene = load(glb_path)
	if ps == null:
		push_warning("SidewalkPlacer: missing asset %s" % glb_path)
		cache[glb_path] = out
		return out
	var inst: Node = ps.instantiate()
	_walk(inst, Transform3D.IDENTITY, out)
	inst.free()
	cache[glb_path] = out
	return out


static func _walk(node: Node, accum: Transform3D, out: Array) -> void:
	var local := accum
	if node is Node3D:
		local = accum * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append({"mesh": (node as MeshInstance3D).mesh, "xform": local})
	for c in node.get_children():
		_walk(c, local, out)
