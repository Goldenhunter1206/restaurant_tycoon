class_name ParkPlacer
extends RefCounted
## Fresh procedural parks for K (central) and G (pocket) zoned blocks.
## Fills the lot with scattered trees, a centre feature (fountain / court),
## benches, bushes, flowers and lamps. Individual instances (park counts are
## small). Deterministic per lot. Merged park superblocks fill as one lot.

const D := "res://Cartoon City Massive Megapack/gLTF 2/Nature and Park/"
const B := "res://Cartoon City Massive Megapack/gLTF 2/Basketball/"

const TREES: Array[String] = [
	D + "Tree_A_3.glb", D + "Tree_A_7.glb", D + "Tree_B_3.glb",
	D + "Tree_D_8.glb", D + "Tree_C_8.glb",
]
const BUSHES: Array[String] = [D + "Bush_1_A_1.glb", D + "Bush_1_B_2.glb", D + "Bush_2_A_1.glb"]
const FLOWERS: Array[String] = [D + "Flowers_1_A.glb", D + "Flowers_2_B.glb", D + "Flowers_3_C.glb"]
const BENCHES: Array[String] = [D + "Bench_1_A.glb", D + "Bench_2_A.glb"]
const FOUNTAIN: String = D + "Fountain_1_A.glb"
const LAMP: String = D + "StreetLamp_3_A.glb"
const TRASH: String = D + "Trashbin_1_A.glb"
const COURTS: Array[String] = [B + "Basketball_Court_1.glb", B + "Basketball_Court_2.glb", B + "Basketball_Court_4.glb"]
const STANDS: Array[String] = [B + "Basketball_Stand_A.glb", B + "Basketball_Stand_B.glb", B + "Basketball_Stand_C.glb"]
const COURT_LAMP: String = B + "Lamp_Court_1_A.glb"
const SEED: int = 246813579


static func build(root: Node3D) -> int:
	var grp := Node3D.new()
	grp.name = "Parks"
	root.add_child(grp)
	var cache := {}
	var claimed := {}
	var count := 0
	for bj in range(CityBuilder.BLOCKS):
		for bi in range(CityBuilder.BLOCKS):
			if claimed.has("%d,%d" % [bi, bj]):
				continue
			var dist := CityBuilder.district(bi, bj)
			if dist != "K" and dist != "G":
				continue
			var rect := _lot_rect(bi, bj, claimed)
			count += _fill_park(grp, dist, bi, bj, rect, cache)
	return count


static func _lot_rect(bi: int, bj: int, claimed: Dictionary) -> Array:
	# If this cell is the origin of a superblock, use the whole footprint.
	for sb: Array in CityBuilder.SUPERBLOCKS:
		if sb[0] == bi and sb[1] == bj:
			for i in range(bi, bi + sb[2]):
				for j in range(bj, bj + sb[3]):
					claimed["%d,%d" % [i, j]] = true
			return [CityBuilder.line_x(bi) + 3.0, CityBuilder.line_x(bi + sb[2]) - 3.0,
				CityBuilder.line_z(bj) + 3.0, CityBuilder.line_z(bj + sb[3]) - 3.0]
	claimed["%d,%d" % [bi, bj]] = true
	return [CityBuilder.line_x(bi) + 3.0, CityBuilder.line_x(bi + 1) - 3.0,
		CityBuilder.line_z(bj) + 3.0, CityBuilder.line_z(bj + 1) - 3.0]


static func _fill_park(grp: Node3D, dist: String, bi: int, bj: int, rect: Array, cache: Dictionary) -> int:
	var x0: float = rect[0]
	var x1: float = rect[1]
	var z0: float = rect[2]
	var z1: float = rect[3]
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var w := x1 - x0
	var h := z1 - z0
	if w < 8.0 or h < 8.0:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED ^ (bi * 73856093) ^ (bj * 19349663)
	var n := 0
	var area := w * h

	# Centre feature. A basketball court (with hoops + court lamps) needs room
	# for its 16 m long axis, laid along the park's longer dimension.
	var court_yaw: float = 0.0 if w >= h else PI * 0.5
	if dist == "K" and area > 3000.0:
		n += _add_court(grp, Vector3(cx, 0, cz), court_yaw, rng, cache)
		_emit(grp, FOUNTAIN, Vector3(x0 + w * 0.25, 0, z0 + h * 0.25), 0.0, 1.2, cache); n += 1
	elif minf(w, h) >= 18.0 and area > 1400.0:
		n += _add_court(grp, Vector3(cx, 0, cz), court_yaw, rng, cache)
	elif area > 700.0:
		_emit(grp, FOUNTAIN, Vector3(cx, 0, cz), 0.0, 1.0, cache); n += 1

	# Benches ringing the centre feature.
	var bench_r := minf(w, h) * 0.22
	for b in range(4):
		var ang := float(b) * PI * 0.5
		var bp := Vector3(cx + cos(ang) * bench_r, 0, cz + sin(ang) * bench_r)
		_emit(grp, BENCHES[b % BENCHES.size()], bp, ang + PI, 1.0, cache); n += 1
	_emit(grp, TRASH, Vector3(cx + bench_r + 2.0, 0, cz), 0.0, 1.0, cache); n += 1

	# Scattered trees on a jittered grid, keeping the centre clear.
	var step := 9.0
	var gx := x0 + 3.0
	while gx < x1 - 3.0:
		var gz := z0 + 3.0
		while gz < z1 - 3.0:
			var px := gx + rng.randf_range(-2.5, 2.5)
			var pz := gz + rng.randf_range(-2.5, 2.5)
			if Vector2(px - cx, pz - cz).length() < minf(w, h) * 0.16:
				gz += step
				continue
			var roll := rng.randf()
			if roll < 0.6:
				_emit(grp, TREES[rng.randi_range(0, TREES.size() - 1)], Vector3(px, 0, pz),
					rng.randf_range(0.0, TAU), rng.randf_range(0.85, 1.25), cache)
			elif roll < 0.8:
				_emit(grp, BUSHES[rng.randi_range(0, BUSHES.size() - 1)], Vector3(px, 0, pz),
					rng.randf_range(0.0, TAU), rng.randf_range(0.9, 1.2), cache)
			elif roll < 0.92:
				_emit(grp, FLOWERS[rng.randi_range(0, FLOWERS.size() - 1)], Vector3(px, 0, pz),
					rng.randf_range(0.0, TAU), 1.0, cache)
			else:
				gz += step
				continue
			n += 1
			gz += step
		gx += step

	# Lamps near the corners.
	for corner: Array in [[x0 + 4.0, z0 + 4.0], [x1 - 4.0, z0 + 4.0], [x0 + 4.0, z1 - 4.0], [x1 - 4.0, z1 - 4.0]]:
		_emit(grp, LAMP, Vector3(corner[0], 0, corner[1]), 0.0, 1.0, cache); n += 1
	return n


static func _add_court(grp: Node3D, center: Vector3, yaw: float, rng: RandomNumberGenerator, cache: Dictionary) -> int:
	# Court long axis is local Z (16 m); hoops sit near each Z end facing inward.
	var basis := Basis(Vector3.UP, yaw)
	_emit(grp, COURTS[rng.randi_range(0, COURTS.size() - 1)], center, yaw, 1.0, cache)
	_emit(grp, STANDS[rng.randi_range(0, STANDS.size() - 1)], center + basis * Vector3(0.0, 0.0, 7.2), yaw + PI, 1.0, cache)
	_emit(grp, STANDS[rng.randi_range(0, STANDS.size() - 1)], center + basis * Vector3(0.0, 0.0, -7.2), yaw, 1.0, cache)
	var n := 3
	for corner: Array in [[3.5, 7.5], [-3.5, 7.5], [3.5, -7.5], [-3.5, -7.5]]:
		_emit(grp, COURT_LAMP, center + basis * Vector3(corner[0], 0.0, corner[1]), yaw, 1.0, cache)
		n += 1
	return n


static func _emit(grp: Node3D, path: String, pos: Vector3, yaw: float, scale: float, cache: Dictionary) -> void:
	if not cache.has(path):
		cache[path] = load(path)
	if cache[path] == null:
		push_warning("ParkPlacer: missing asset %s" % path)
		return
	var inst: Node3D = (cache[path] as PackedScene).instantiate()
	inst.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale)), pos)
	grp.add_child(inst)
