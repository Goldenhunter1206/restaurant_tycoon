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
	"N": ["B2", "B2", "B2", "B10", "B8"],
	"R": ["B2", "B2", "B10"],
	"P": ["B8", "B24", "B26", "B17", "B9", "B8", "B24"],
}

const SETBACK := {"D": 0.6, "C": 0.6, "N": 3.5, "R": 6.0, "P": 0.8, "I": 3.0}
const GAP_MIN := {"D": 0.4, "C": 0.5, "N": 4.0, "R": 9.0, "P": 0.4, "I": 6.0}
const GAP_MAX := {"D": 1.4, "C": 1.6, "N": 7.0, "R": 15.0, "P": 1.2, "I": 10.0}


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
			_fill_industrial(out, catalog, rng, bi, bj, x0, x1, z0, z1)
		"D", "C", "N", "R", "P":
			if is_super and district == "D":
				_place_centered(out, catalog, rng, district, bi, bj, ["B22", "B23"], x0, x1, z0, z1)
			elif is_super and district == "N":
				_place_centered(out, catalog, rng, district, bi, bj, ["B16", "B25", "B23"], x0, x1, z0, z1)
			elif is_super and district == "R":
				_fill_perimeter(out, catalog, rng, "R", bi, bj, x0, x1, z0, z1)
			else:
				# A few downtown blocks host one landmark tower instead.
				if district == "D" and not is_super and rng.randf() < 0.18:
					_place_centered(out, catalog, rng, district, bi, bj, ["B7"], x0, x1, z0, z1)
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


static func _pick_variant(catalog: Dictionary, rng: RandomNumberGenerator, fam_key: String) -> Dictionary:
	var fam: Dictionary = catalog["families"][fam_key]
	var variants: Array = fam["variants"]
	var v: String = variants[rng.randi_range(0, variants.size() - 1)]
	var s: Array = fam["sizes"][v]
	return {
		"path": String(fam["dir"]) + v,
		"w": float(s[0]), "d": float(s[1]), "h": float(s[2]),
		"cx": -float(s[3]), "cz": -float(s[4]),   # glTF -> Godot yaw-180 flip
		"family": fam_key,
		"type": FAMILY_TYPE.get(fam_key, "home"),
	}


static func _fill_perimeter(out: Array[Dictionary], catalog: Dictionary, rng: RandomNumberGenerator, district: String, bi: int, bj: int, x0: float, x1: float, z0: float, z1: float) -> void:
	var pool: Array = POOLS[district]
	var setback: float = SETBACK[district]
	var depth_limit_ns := (z1 - z0) * 0.5 - 1.5
	var depth_limit_ew := (x1 - x0) * 0.5 - 1.5
	var corner := 14.0
	# faces: [start, end, is_horizontal, rot_y, corner_margin, depth_limit]
	var faces := [
		[x0, x1, true, 180.0, 0.0, depth_limit_ns],    # N face, front looks -Z
		[x0, x1, true, 0.0, 0.0, depth_limit_ns],      # S face, front looks +Z
		[z0, z1, false, 270.0, corner, depth_limit_ew],  # W face, front looks -X
		[z0, z1, false, 90.0, corner, depth_limit_ew],   # E face, front looks +X
	]
	var face_ids := [0, 1, 2, 3]
	for f in face_ids:
		if not _face_has_road(bi, bj, 1, 1, f):
			continue
		var fd: Array = faces[f]
		var start: float = fd[0] + fd[4]
		var end: float = fd[1] - fd[4]
		var cursor := start + rng.randf_range(GAP_MIN[district], GAP_MAX[district]) * 0.5
		var guard := 0
		while guard < 30:
			guard += 1
			var b := _pick_variant(catalog, rng, pool[rng.randi_range(0, pool.size() - 1)])
			if b["d"] > fd[5]:
				continue
			if cursor + b["w"] > end:
				break
			var along: float = cursor + b["w"] * 0.5
			var pos: Vector3
			var rot: float = fd[3]
			if fd[2]:  # horizontal face (N/S)
				var depth_z: float = (z0 + setback + b["d"] * 0.5) if rot == 180.0 else (z1 - setback - b["d"] * 0.5)
				pos = Vector3(along, 0, depth_z)
			else:
				var depth_x: float = (x0 + setback + b["d"] * 0.5) if rot == 270.0 else (x1 - setback - b["d"] * 0.5)
				pos = Vector3(depth_x, 0, along)
			_emit(out, b, pos, rot, district, bi, bj)
			cursor += b["w"] + rng.randf_range(GAP_MIN[district], GAP_MAX[district])


static func _place_centered(out: Array[Dictionary], catalog: Dictionary, rng: RandomNumberGenerator, district: String, bi: int, bj: int, fams: Array, x0: float, x1: float, z0: float, z1: float) -> void:
	var b := _pick_variant(catalog, rng, fams[rng.randi_range(0, fams.size() - 1)])
	var guard := 0
	while (b["w"] > (x1 - x0) - 3.0 or b["d"] > (z1 - z0) - 3.0) and guard < 12:
		b = _pick_variant(catalog, rng, fams[rng.randi_range(0, fams.size() - 1)])
		guard += 1
	if b["w"] > (x1 - x0) - 1.0 or b["d"] > (z1 - z0) - 1.0:
		return
	var pos := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	var rot := 0.0 if _face_has_road(bi, bj, 1, 1, 1) else 180.0
	_emit(out, b, pos, rot, district, bi, bj)


static func _fill_industrial(out: Array[Dictionary], catalog: Dictionary, rng: RandomNumberGenerator, bi: int, bj: int, x0: float, x1: float, z0: float, z1: float) -> void:
	var w := x1 - x0
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
		_emit(out, b, pos, 0.0 if bj % 2 == 0 else 180.0, "I", bi, bj)
	# Gas tank cluster in a corner.
	if rng.randf() < 0.6:
		var t := _pick_variant(catalog, rng, "GASTANK")
		var pos := Vector3(x1 - t["w"] * 0.5 - 2.0, 0, z1 - t["d"] * 0.5 - 2.0)
		_emit(out, t, pos, 0.0, "I", bi, bj)


static func _emit(out: Array[Dictionary], b: Dictionary, pos: Vector3, rot: float, district: String, bi: int, bj: int) -> void:
	# Correct for the mesh AABB center offset so footprints stay in-lot.
	var c := Vector3(b["cx"], 0, b["cz"])
	var rotated_c := c.rotated(Vector3.UP, deg_to_rad(rot))
	out.append({
		"path": b["path"], "pos": pos + rotated_c, "rot_y": rot,
		"w": b["w"], "d": b["d"], "h": b["h"],
		"district": district, "type": b["type"],
		"family": b["family"], "block": [bi, bj],
	})
