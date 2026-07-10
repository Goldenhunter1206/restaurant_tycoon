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
const MARGIN: float = 0.5          # min clear gap between adjacent furniture footprints
const ROAD_CLEAR: float = 0.2      # deep prop's road-side face kept this far behind the kerb
const DEEP_DEPTH: float = 1.5      # props deeper than this get pushed back / facade-checked
const RESERVE_INFLATE: float = 0.6 # margin grown around a reserved footprint
const RESERVE_MIN_EXTENT: float = 0.0  # every item reserves a buffer from trees and lamps
const SEED: int = 51413

## Typical building-front setback from the kerb per district (mirrors
## BuildingPlacer.SETBACK); grand-avenue faces add +5 m. Used to skip bulky
## props that would otherwise punch through a downtown frontage.
const SETBACK := {"D": 0.6, "C": 0.6, "N": 3.5, "R": 6.0, "P": 0.8, "I": 3.0}

## World-XZ footprints of bulky furniture, filled during build() and read by
## DecorPlacer so it never plants a tree/lamp inside a kiosk, bus stop, etc.
static var reserved_rects: Array[Rect2] = []

## Furniture table. d = allowed district letters ("" = any); along = long prop
## laid parallel to the kerb; big = bulky prop (commercial frontages only).
## sx/sz/cx/cz = measured model-local AABB size and centre offset (metres) from
## each glb, used for along-kerb interval packing, the deep-prop inset push and
## the decor reservation rects. Do not hand-edit; re-measure from the glb AABBs.
const FURN: Array[Dictionary] = [
	{"p": SP + "Hydrant.glb", "w": 4, "d": "", "sx": 0.41, "sz": 0.59, "cx": -0.02, "cz": 0.00},
	{"p": NP + "Trashbin_1_A.glb", "w": 4, "d": "", "sx": 0.45, "sz": 0.45, "cx": 0.00, "cz": 0.00},
	{"p": SP + "PostBox_1_A.glb", "w": 2, "d": "", "sx": 0.51, "sz": 0.57, "cx": 0.00, "cz": 0.00},
	{"p": SP + "Bench_4_A.glb", "w": 3, "d": "DCNRP", "along": true, "sx": 0.61, "sz": 1.94, "cx": 0.00, "cz": 0.00},
	{"p": SP + "Parkomat.glb", "w": 3, "d": "DC", "sx": 0.18, "sz": 0.34, "cx": 0.01, "cz": -0.01},
	{"p": SP + "NewspaperH.glb", "w": 2, "d": "DC", "sx": 0.49, "sz": 0.57, "cx": -0.19, "cz": 0.01},
	{"p": SP + "BikePlace.glb", "w": 2, "d": "DCNP", "along": true, "sx": 0.58, "sz": 1.73, "cx": -0.01, "cz": 0.00},
	{"p": SP + "BusStop_A.glb", "w": 1, "d": "DC", "big": true, "sx": 1.53, "sz": 4.03, "cx": 0.61, "cz": 0.00},
	{"p": SP + "Kiosk_1_A.glb", "w": 1, "d": "DC", "big": true, "sx": 2.97, "sz": 4.54, "cx": 0.09, "cz": 0.08},
	{"p": SP + "FoodCart_1_A.glb", "w": 1, "d": "D", "big": true, "sx": 2.44, "sz": 2.65, "cx": -0.11, "cz": -0.20},
]


static func build(root: Node3D) -> Dictionary:
	reserved_rects.clear()
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
			# Street furniture along each kerb. Pass the kerb line (not a pre-insetted
			# coordinate) plus the district's building-front distance so deep props can
			# be set back and facade-checked per edge.
			if dist == "" or dist == "X":
				continue
			var set_base: float = SETBACK.get(dist, 6.0)
			if n_road:
				_furn_row(furn_xforms, x0, x1, z0, true, Vector3(0, 0, -1), dist,
					set_base + (5.0 if bj in CityBuilder.GRAND_AVENUE_H else 0.0), bi * 71 + bj)
			if s_road:
				_furn_row(furn_xforms, x0, x1, z1, true, Vector3(0, 0, 1), dist,
					set_base + (5.0 if (bj + 1) in CityBuilder.GRAND_AVENUE_H else 0.0), bi * 71 + bj + 313)
			if w_road:
				_furn_row(furn_xforms, z0, z1, x0, false, Vector3(-1, 0, 0), dist,
					set_base + (5.0 if bi in CityBuilder.GRAND_AVENUE_V else 0.0), bi * 91 + bj + 613)
			if e_road:
				_furn_row(furn_xforms, z0, z1, x1, false, Vector3(1, 0, 0), dist,
					set_base + (5.0 if (bi + 1) in CityBuilder.GRAND_AVENUE_V else 0.0), bi * 91 + bj + 907)


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


static func _furn_row(furn: Dictionary, a0: float, a1: float, kerb: float, along_x: bool,
		face: Vector3, dist: String, front_dist: float, salt: int) -> void:
	if a1 - a0 < 2.0 * CORNER_CLEAR + 2.0:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED ^ (salt * 2654435761)
	var yaw_base: float = atan2(face.x, face.z)
	# Perpendicular axis sign: face_perp points toward the road, inward into the lot.
	var face_perp: float = face.z if along_x else face.x
	var inward: float = -face_perp
	# Fixed anchors make each frontage calm and intentional, not scattered.
	var t: float = a0 + CORNER_CLEAR + 2.0
	# Along-kerb right edge of the last committed prop's footprint. Everything on
	# this kerb shares one line, so a single 1D interval frontier keeps props from
	# overlapping: a candidate is nudged forward until its measured footprint clears
	# the previous one by MARGIN. The RNG call sequence (pick then step) is never
	# altered and the pass is strictly left-to-right, so output stays deterministic.
	var frontier: float = -INF
	while t < a1 - CORNER_CLEAR:
		var item: Dictionary = _pick_curated(dist, int((t - a0) / 14.0) + salt)
		if not item.is_empty():
			var along: bool = item.get("along", false)
			var sx: float = item["sx"]
			var sz: float = item["sz"]
			var yaw: float = yaw_base + (PI * 0.5 if along else 0.0)
			# Footprint is axis-aligned in world XZ (yaw is a multiple of 90 deg).
			var swap: bool = (int(round(yaw / (PI * 0.5))) & 1) == 1
			var ex: float = (sz if swap else sx) * 0.5
			var ez: float = (sx if swap else sz) * 0.5
			var wc: Vector2 = Vector2(item["cx"], item["cz"]).rotated(-yaw)
			# Along-kerb interval (centre offset + half-extent along the kerb axis).
			var along_c: float = wc.x if along_x else wc.y
			var along_e: float = ex if along_x else ez
			# Perpendicular reach toward the road and into the lot.
			var perp_c: float = wc.y if along_x else wc.x
			var depth_e: float = ez if along_x else ex
			var reach_road: float = depth_e + face_perp * perp_c
			var reach_lot: float = depth_e - face_perp * perp_c
			# Deep props are set back so their road face clears the kerb by ROAD_CLEAR;
			# small props keep the base inset.
			var inset: float = maxf(CURB_INSET, reach_road + ROAD_CLEAR)
			var deep: bool = (reach_road + reach_lot) > DEEP_DEPTH
			# A deep prop that would punch through the building frontage is dropped
			# (roll already consumed, so the stream is undisturbed).
			if deep and inset + reach_lot > front_dist:
				t += 14.0
				continue
			# Along-kerb overlap guard.
			if t + along_c - along_e < frontier + MARGIN:
				t = frontier + MARGIN - along_c + along_e
			if t >= a1 - CORNER_CLEAR:
				break
			frontier = t + along_c + along_e
			var fixed: float = kerb + inward * inset
			var pos: Vector3 = Vector3(t, FURN_Y, fixed) if along_x else Vector3(fixed, FURN_Y, t)
			if not furn.has(item["p"]):
				furn[item["p"]] = []
			furn[item["p"]].append(Transform3D(Basis(Vector3.UP, yaw), pos))
			# Reserve bulky footprints (world XZ, inflated) so DecorPlacer skips any
			# tree/lamp that would land inside them.
			if maxf(sx, sz) >= RESERVE_MIN_EXTENT:
				reserved_rects.append(Rect2(
					pos.x + wc.x - ex - RESERVE_INFLATE, pos.z + wc.y - ez - RESERVE_INFLATE,
					2.0 * (ex + RESERVE_INFLATE), 2.0 * (ez + RESERVE_INFLATE)))
		t += 14.0


## True when (px, pz) lies inside any bulky-furniture footprint reserved this
## build. Read by DecorPlacer to avoid planting trees/lamps inside props.
static func is_reserved(px: float, pz: float) -> bool:
	var p := Vector2(px, pz)
	for r: Rect2 in reserved_rects:
		if r.has_point(p):
			return true
	return false


static func _pick_curated(dist: String, step: int) -> Dictionary:
	# A small editorial palette per district. Large kiosks and carts are kept
	# out of this automatic pass; they need bespoke plaza placement instead.
	var palette: Array[int] = [0, 1, 2, 3]
	if dist == "D" or dist == "C":
		palette = [4, 6, 3, 2, 0]
	elif dist == "N" or dist == "R" or dist == "P":
		palette = [3, 1, 0, 2]
	return FURN[palette[posmod(step, palette.size())]]


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
