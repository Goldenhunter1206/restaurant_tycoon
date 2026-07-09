class_name BuildingPlacer
extends RefCounted
## Computes deterministic building placements per block from the zoning
## map + building catalog. Fronts face the street; setbacks and density
## vary by district (downtown tight, rich suburbs generous yards).

const MASTER_SEED: int = 1337

# Family pools per district. Types: home, shop, office, factory, civic.
const FAMILY_TYPE := {
	"B1": "shop", "B3": "shop", "B5": "shop", "B12": "shop", "B19": "shop",
	"B16": "shop", "B25": "shop",
	"B4": "office", "B7": "office", "B15": "office", "B18": "office",
	"B21": "office", "B27": "office", "B20": "office", "B11": "office",
	"B6": "home", "B9": "home", "B17": "home", "B24": "home", "B26": "home",
	"B8": "home", "B2": "home", "B10": "home", "B14": "shop", "B13": "home",
	"B22": "civic", "B23": "civic",
	"FACTORY": "factory", "GASTANK": "factory_decor",
}

const POOLS := {
	"D": ["B15", "B18", "B21", "B27", "B4", "B9", "B6", "B20", "B11", "B26", "B17"],
	"C": ["B1", "B3", "B5", "B12", "B19", "B11", "B14", "B17", "B26", "B1", "B5"],
	"N": ["B2", "B2", "B2", "B10", "B8", "B13"],
	"R": ["B2", "B2", "B10", "B13"],
	"P": ["B8", "B24", "B26", "B17", "B9", "B8", "B24", "B13"],
}

const SETBACK := {"D": 0.6, "C": 0.6, "N": 3.5, "R": 6.0, "P": 0.8, "I": 3.0}
## Tightened after the entrance-yaw fix widened frontages (fewer fit per block).
const GAP_MIN := {"D": 0.3, "C": 0.4, "N": 2.5, "R": 4.5, "P": 0.3, "I": 4.0}
const GAP_MAX := {"D": 1.0, "C": 1.3, "N": 5.0, "R": 9.0, "P": 1.0, "I": 7.5}

## Per-family entrance-yaw correction (degrees), folded into every placement.
## The catalog records no door axis; the pipeline assumes each model's entrance
## is local +Z after the uniform glTF->Godot flip. A family whose art faces
## another way gets an offset here so its entrance still fronts the street.
## Entrance-yaw correction (degrees). Audited across the whole pack: almost every
## model's entrance sits on its local -X face, so the DEFAULT is +90 (rotate the
## entrance to the street) paired with a w/d frontage swap in _pick_variant. The
## few exceptions (entrance already on +Z, or orientation-agnostic) are listed.
const DEFAULT_FRONT_YAW := 90.0
const FAMILY_FRONT_YAW := {"B6": 0.0, "GASTANK": 0.0}
## Homes below this height/frontage ratio read as a house "lying flat" (a wide,
## shallow, low slab); such variants are re-rolled in _pick_variant.
const FLAT_MIN_RATIO := 0.7
## When a family's entrance sits on its long side, rotating it to face the street
## shows a wide, low slab. If the entrance-face height/width is below this, keep
## the narrower face to the street instead (upright look; entrance faces sideways)
## — a better trade than a building that looks like it is lying flat.
const FLAT_VIS_RATIO := 0.6
## Families authored lying on their side (centered origin, tall axis horizontal).
## Value = Euler degrees applied to the visual to stand it up. A +90 X rotation
## turns the model's Z-extent into height and Y-extent into depth, corrected in
## _pick_variant so placement/collision use the upright dimensions.
const STANDUP := {"B2": Vector3(90, 0, 0), "B19": Vector3(90, 0, 0)}


static func build_placements(catalog: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var claimed := {}
	# Superblock lots first (merged multi-block lots).
	for sb: Array in CityBuilder.SUPERBLOCKS:
		var bi: int = sb[0]
		var bj: int = sb[1]
		for i in range(bi, bi + sb[2]):
			for j in range(bj, bj + sb[3]):
				claimed["%d,%d" % [i, j]] = true
		_fill_lot(out, catalog, bi, bj, sb[2], sb[3], true)
	# Non-rectangular L-shaped merged lots.
	for cluster: Array in CityBuilder.LSHAPE_CLUSTERS:
		for cell: Array in cluster:
			claimed["%d,%d" % [cell[0], cell[1]]] = true
		_fill_cluster(out, catalog, cluster, CityBuilder.district(cluster[0][0], cluster[0][1]))
	for bi in range(CityBuilder.BLOCKS):
		for bj in range(CityBuilder.BLOCKS):
			if claimed.has("%d,%d" % [bi, bj]):
				continue
			_fill_lot(out, catalog, bi, bj, 1, 1, false)
	return out


static func _fill_lot(out: Array[Dictionary], catalog: Dictionary, bi: int, bj: int, bw: int, bh: int, is_super: bool) -> void:
	var district := CityBuilder.district(bi, bj)
	if district == "K" or district == "G" or district == "X" or district == "":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = MASTER_SEED * 73856093 ^ bi * 19349663 ^ bj * 83492791
	var x0 := CityBuilder.line_x(bi) + 4.0
	var x1 := CityBuilder.line_x(bi + bw) - 4.0
	var z0 := CityBuilder.line_z(bj) + 4.0
	var z1 := CityBuilder.line_z(bj + bh) - 4.0
	match district:
		"I":
			_fill_industrial(out, catalog, rng, bi, bj, bw, bh, x0, x1, z0, z1)
		"D", "C", "N", "R", "P":
			if is_super and district == "D":
				_place_centered(out, catalog, rng, district, bi, bj, bw, bh, ["B22", "B23"], x0, x1, z0, z1)
			elif is_super and district == "N":
				_place_centered(out, catalog, rng, district, bi, bj, bw, bh, ["B16", "B25", "B23"], x0, x1, z0, z1)
			elif is_super and district == "R":
				_fill_perimeter(out, catalog, rng, "R", bi, bj, x0, x1, z0, z1)
			else:
				# A few downtown blocks host one landmark tower instead.
				if district == "D" and not is_super and rng.randf() < 0.18:
					_place_centered(out, catalog, rng, district, bi, bj, bw, bh, ["B7"], x0, x1, z0, z1)
				else:
					_fill_perimeter(out, catalog, rng, district, bi, bj, x0, x1, z0, z1)


static func _face_has_road(bi: int, bj: int, bw: int, bh: int, face: int) -> bool:
	## face: 0=N, 1=S, 2=W, 3=E — true if ANY road segment runs along it.
	var v_removed := CityBuilder.removed_v_segments()
	var h_removed := CityBuilder.removed_h_segments()
	match face:
		0:
			for i in range(bi, bi + bw):
				if not h_removed.has("%d,%d" % [i, bj]):
					return true
		1:
			for i in range(bi, bi + bw):
				if not h_removed.has("%d,%d" % [i, bj + bh]):
					return true
		2:
			for j in range(bj, bj + bh):
				if not v_removed.has("%d,%d" % [bi, j]):
					return true
		3:
			for j in range(bj, bj + bh):
				if not v_removed.has("%d,%d" % [bi + bw, j]):
					return true
	return false


## Yaw (deg) that points a building's +Z entrance at an adjacent street. Prefer
## S, then N, then E, then W — the first lot face that actually carries a road.
static func _road_facing_rot(bi: int, bj: int, bw: int, bh: int) -> float:
	if _face_has_road(bi, bj, bw, bh, 1):
		return 0.0
	if _face_has_road(bi, bj, bw, bh, 0):
		return 180.0
	if _face_has_road(bi, bj, bw, bh, 3):
		return 90.0
	if _face_has_road(bi, bj, bw, bh, 2):
		return 270.0
	return 0.0


## Entrance-yaw correction for a family (see FAMILY_FRONT_YAW).
static func _front_yaw(fam_key: String) -> float:
	return float(FAMILY_FRONT_YAW.get(fam_key, DEFAULT_FRONT_YAW))


static func _pick_variant(catalog: Dictionary, rng: RandomNumberGenerator, fam_key: String) -> Dictionary:
	var fam: Dictionary = catalog["families"][fam_key]
	var variants: Array = fam["variants"]
	var is_home: bool = FAMILY_TYPE.get(fam_key, "home") == "home"
	var base_corr := _front_yaw(fam_key)
	var can_swap := is_equal_approx(base_corr, 90.0) or is_equal_approx(base_corr, 270.0)
	var standup: Vector3 = STANDUP.get(fam_key, Vector3.ZERO)
	var v: String
	var s: Array
	var w: float
	var d: float
	var h: float
	var corr: float
	var guard := 0
	while true:
		v = variants[rng.randi_range(0, variants.size() - 1)]
		s = fam["sizes"][v]
		var w0 := float(s[0])
		var d0 := float(s[1])
		h = float(s[2])
		if standup != Vector3.ZERO:
			# +90 X standup: model Z-extent becomes height, Y-extent becomes depth.
			var nh := d0
			d0 = h
			h = nh
		corr = base_corr
		w = w0
		d = d0
		if can_swap:
			# The entrance sits on the -X face, so facing it to the street means a
			# frontage of d0. Only do that when it stays upright-looking; otherwise
			# keep the narrower face to the street (no rotation) so a deep, low
			# building reads as standing rather than lying flat.
			if d0 <= w0 or h >= FLAT_VIS_RATIO * d0:
				w = d0
				d = w0
			else:
				corr = 0.0
		guard += 1
		# Homes: re-roll a variant that is a low slab even at its narrow frontage.
		if not is_home or guard >= 10 or h >= FLAT_MIN_RATIO * w:
			break
	return {
		"path": String(fam["dir"]) + v,
		"w": w, "d": d, "h": h, "corr": corr, "standup": standup,
		"cx": -float(s[3]),
		# A +90 X standup sends the model's Z-centre offset vertical (handled by
		# sit-on-ground), so it must NOT be applied horizontally or the building
		# shifts onto the sidewalk.
		"cz": 0.0 if standup != Vector3.ZERO else -float(s[4]),
		"family": fam_key,
		"type": FAMILY_TYPE.get(fam_key, "home"),
	}


static func _fill_perimeter(out: Array[Dictionary], catalog: Dictionary, rng: RandomNumberGenerator, district: String, bi: int, bj: int, x0: float, x1: float, z0: float, z1: float) -> void:
	for f in [0, 1, 2, 3]:
		if not _face_has_road(bi, bj, 1, 1, f):
			continue
		var corner := 0.0 if f < 2 else 14.0
		_march_face(out, catalog, rng, district, bi, bj, x0, x1, z0, z1, f, corner)


## Fill one lot face (0=N,1=S,2=W,3=E) with a row of street-fronting buildings.
static func _march_face(out: Array[Dictionary], catalog: Dictionary, rng: RandomNumberGenerator, district: String, bi: int, bj: int, x0: float, x1: float, z0: float, z1: float, face_id: int, corner: float) -> void:
	var pool: Array = POOLS[district]
	var setback: float = SETBACK[district] + _avenue_setback(bi, bj, face_id)
	var is_h := face_id < 2
	var depth_limit := ((z1 - z0) if is_h else (x1 - x0)) * 0.5 - 1.5
	var rot: float
	var range_start: float
	var range_end: float
	match face_id:
		0: rot = 180.0; range_start = x0; range_end = x1
		1: rot = 0.0; range_start = x0; range_end = x1
		2: rot = 270.0; range_start = z0; range_end = z1
		_: rot = 90.0; range_start = z0; range_end = z1
	var cursor := range_start + corner + rng.randf_range(GAP_MIN[district], GAP_MAX[district]) * 0.5
	var end := range_end - corner
	var guard := 0
	while guard < 30:
		guard += 1
		var b := _pick_variant(catalog, rng, pool[rng.randi_range(0, pool.size() - 1)])
		if b["d"] > depth_limit:
			continue
		if cursor + b["w"] > end:
			break
		var along: float = cursor + b["w"] * 0.5
		var pos: Vector3
		if is_h:
			var depth_z: float = (z0 + setback + b["d"] * 0.5) if rot == 180.0 else (z1 - setback - b["d"] * 0.5)
			pos = Vector3(along, 0, depth_z)
		else:
			var depth_x: float = (x0 + setback + b["d"] * 0.5) if rot == 270.0 else (x1 - setback - b["d"] * 0.5)
			pos = Vector3(depth_x, 0, along)
		_emit(out, b, pos, rot, district, bi, bj)
		cursor += b["w"] + rng.randf_range(GAP_MIN[district], GAP_MAX[district])


## Fill a non-rectangular (L-shaped) cluster: buildings on every cell edge whose
## neighbour is outside the cluster (an exposed street frontage).
static func _fill_cluster(out: Array[Dictionary], catalog: Dictionary, cells: Array, district: String) -> void:
	if not POOLS.has(district):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = MASTER_SEED * 39916801 ^ int(cells[0][0]) * 2654435761 ^ int(cells[0][1]) * 40503
	var cellset := {}
	for c: Array in cells:
		cellset["%d,%d" % [c[0], c[1]]] = true
	var neigh := [[0, -1], [0, 1], [-1, 0], [1, 0]]   # N, S, W, E
	for c: Array in cells:
		var bi: int = c[0]
		var bj: int = c[1]
		if CityBuilder.district(bi, bj) in ["K", "G", "X"]:
			continue
		var x0 := CityBuilder.line_x(bi) + 4.0
		var x1 := CityBuilder.line_x(bi + 1) - 4.0
		var z0 := CityBuilder.line_z(bj) + 4.0
		var z1 := CityBuilder.line_z(bj + 1) - 4.0
		for f in range(4):
			var nk := "%d,%d" % [bi + neigh[f][0], bj + neigh[f][1]]
			if cellset.has(nk):
				continue
			if not _face_has_road(bi, bj, 1, 1, f):
				continue
			var corner := 2.0 if f < 2 else 6.0
			_march_face(out, catalog, rng, district, bi, bj, x0, x1, z0, z1, f, corner)


static func _place_centered(out: Array[Dictionary], catalog: Dictionary, rng: RandomNumberGenerator, district: String, bi: int, bj: int, bw: int, bh: int, fams: Array, x0: float, x1: float, z0: float, z1: float) -> void:
	var b := _pick_variant(catalog, rng, fams[rng.randi_range(0, fams.size() - 1)])
	var guard := 0
	while (b["w"] > (x1 - x0) - 3.0 or b["d"] > (z1 - z0) - 3.0) and guard < 12:
		b = _pick_variant(catalog, rng, fams[rng.randi_range(0, fams.size() - 1)])
		guard += 1
	if b["w"] > (x1 - x0) - 1.0 or b["d"] > (z1 - z0) - 1.0:
		return
	var pos := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	var rot := _road_facing_rot(bi, bj, bw, bh)
	_emit(out, b, pos, rot, district, bi, bj)


static func _fill_industrial(out: Array[Dictionary], catalog: Dictionary, rng: RandomNumberGenerator, bi: int, bj: int, bw: int, bh: int, x0: float, x1: float, z0: float, z1: float) -> void:
	var w := x1 - x0
	var rot := _road_facing_rot(bi, bj, bw, bh)
	var slots := int(floorf(w / 24.0))
	var pitch := w / maxf(1.0, float(slots))
	for s in range(slots):
		var b := _pick_variant(catalog, rng, "FACTORY")
		var guard := 0
		while b["d"] > (z1 - z0) - 4.0 and guard < 8:
			b = _pick_variant(catalog, rng, "FACTORY")
			guard += 1
		if b["d"] > (z1 - z0) - 2.0 or b["w"] > pitch - 2.0:
			continue
		var pos := Vector3(x0 + pitch * (float(s) + 0.5), 0, (z0 + z1) * 0.5)
		_emit(out, b, pos, rot, "I", bi, bj)
	# Gas tank cluster in a corner.
	if rng.randf() < 0.6:
		var t := _pick_variant(catalog, rng, "GASTANK")
		var pos := Vector3(x1 - t["w"] * 0.5 - 2.0, 0, z1 - t["d"] * 0.5 - 2.0)
		_emit(out, t, pos, 0.0, "I", bi, bj)


## Extra planted setback (m) when a lot face fronts a grand avenue.
static func _avenue_setback(bi: int, bj: int, face_id: int) -> float:
	match face_id:
		0: return 5.0 if bj in CityBuilder.GRAND_AVENUE_H else 0.0
		1: return 5.0 if (bj + 1) in CityBuilder.GRAND_AVENUE_H else 0.0
		2: return 5.0 if bi in CityBuilder.GRAND_AVENUE_V else 0.0
		_: return 5.0 if (bi + 1) in CityBuilder.GRAND_AVENUE_V else 0.0


static func _emit(out: Array[Dictionary], b: Dictionary, pos: Vector3, rot: float, district: String, bi: int, bj: int) -> void:
	# Fold in the entrance-yaw correction, then correct for the mesh AABB center
	# offset so footprints stay in-lot (same total rot for both).
	var corr: float = b["corr"]
	rot = fmod(rot + corr + 360.0, 360.0)
	var c := Vector3(b["cx"], 0, b["cz"])
	var rotated_c := c.rotated(Vector3.UP, deg_to_rad(rot))
	# World direction the entrance faces (the street). Entrance is local +Z when
	# uncorrected, else local -X, rotated into place with the building. Kept so
	# city.gd door anchors + yard dressing use the true front, not basis.z.
	var ent_local := Vector3(0, 0, 1) if is_zero_approx(corr) else Vector3(-1, 0, 0)
	var front := ent_local.rotated(Vector3.UP, deg_to_rad(rot))
	out.append({
		"path": b["path"], "pos": pos + rotated_c, "rot_y": rot,
		"w": b["w"], "d": b["d"], "h": b["h"], "front": front, "standup": b["standup"],
		"district": district, "type": b["type"],
		"family": b["family"], "block": [bi, bj],
	})
