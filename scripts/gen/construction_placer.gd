class_name ConstructionPlacer
extends RefCounted
## Construction sites: full sites fill every X-zoned block (fenced dirt lot,
## crane, scaffolding, concrete frames/slabs, containers, sand piles), and
## sparse mini-sites drop a small dig into ~1-in-8 eligible block courtyards
## for a lived-in, work-in-progress feel. Dirt floor and hoarding fence are
## MultiMesh; the bulky props are individual instances (small counts).
## Deterministic; built under a "Construction" group. Skips merged super-lots.

const CO := "res://Cartoon City Massive Megapack/gLTF 2/Construction Site/Other/"
const CB := "res://Cartoon City Massive Megapack/gLTF 2/Construction Site/Buildings/"
const SP := "res://Cartoon City Massive Megapack/gLTF 2/Street Props/"

const DIRT: Array[String] = [
	CB + "cGround_A_1.glb", CB + "cGround_A_2.glb", CB + "cGround_A_3.glb",
	CB + "cGround_A_4.glb", CB + "cGround_A_5.glb", CB + "cGround_A_6.glb",
]
const FENCE: Array[String] = [CO + "Barier_1_1.glb", CO + "Barier_1_2.glb", CO + "Barier_1_3.glb"]
const SCAFFOLDS: Array[String] = [
	CO + "Scaffolding_A_1.glb", CO + "Scaffolding_B_1.glb", CO + "Scaffolding_C_1.glb",
	CO + "Scaffolding_D_1.glb", CO + "Scaffolding_E_1.glb",
]
const SAND: Array[String] = [
	CO + "SandHill_1_1.glb", CO + "SandHill_1_2.glb", CO + "SandHill_1_3.glb", CO + "SandHill_1_4.glb",
]
const SLABS := CB + "ConcrateSlabs_A_1_1.glb"
const CFRAME := CB + "ConcrateFrame_1_1.glb"
const CRANE := CO + "Crane.glb"
const CONTAINER := CO + "Container_1_1.glb"
const CONE := SP + "Cone_1.glb"
const ROADBAR := SP + "RoadBarier_1_A.glb"

const SEED: int = 161803398
const DIRT_TILE: float = 2.0     # cGround_A is a 2x2 flat tile
const FENCE_LEN: float = 4.1     # Barier_1 panel length along local Z
const CRANE_SCALE: float = 3.0   # Crane.glb is only ~7.7 m tall; scale it up to loom over the site
const MINI_PROB: float = 0.13
const MINI_MIN_SIZE: float = 22.0


static func build(root: Node3D) -> int:
	var grp := Node3D.new()
	grp.name = "Construction"
	root.add_child(grp)
	var dirt_node := Node3D.new()
	dirt_node.name = "Dirt"
	grp.add_child(dirt_node)
	var fence_node := Node3D.new()
	fence_node.name = "Fences"
	grp.add_child(fence_node)
	var props_node := Node3D.new()
	props_node.name = "Props"
	grp.add_child(props_node)

	var scene_cache := {}
	var mesh_cache := {}
	var dirt_x := {}
	var fence_x := {}
	var merged := _merged_cells()
	var count := 0

	for bj in range(CityBuilder.BLOCKS):
		for bi in range(CityBuilder.BLOCKS):
			var dist := CityBuilder.district(bi, bj)
			var x0 := CityBuilder.line_x(bi) + 4.0
			var x1 := CityBuilder.line_x(bi + 1) - 4.0
			var z0 := CityBuilder.line_z(bj) + 4.0
			var z1 := CityBuilder.line_z(bj + 1) - 4.0
			if dist == "X":
				count += _full_site(props_node, dirt_x, fence_x, scene_cache, bi, bj, x0, x1, z0, z1)
			elif not merged.has("%d,%d" % [bi, bj]) and dist != "" and dist != "K" and dist != "G" \
					and (x1 - x0) > MINI_MIN_SIZE and (z1 - z0) > MINI_MIN_SIZE:
				var rng := RandomNumberGenerator.new()
				rng.seed = SEED ^ ((bi * 83492791 ^ bj * 19349663) * 2654435761)
				if rng.randf() < MINI_PROB:
					count += _mini_site(props_node, dirt_x, scene_cache, x0, x1, z0, z1, rng)

	var i := 0
	for path: String in dirt_x:
		MeshBatch.emit(dirt_node, "Dirt%d" % i, path, dirt_x[path], mesh_cache)
		i += 1
	i = 0
	for path: String in fence_x:
		MeshBatch.emit(fence_node, "Fence%d" % i, path, fence_x[path], mesh_cache)
		i += 1
	return count


static func _merged_cells() -> Dictionary:
	var m := {}
	for sb: Array in CityBuilder.SUPERBLOCKS:
		for i in range(sb[0], sb[0] + sb[2]):
			for j in range(sb[1], sb[1] + sb[3]):
				m["%d,%d" % [i, j]] = true
	for cluster: Array in CityBuilder.LSHAPE_CLUSTERS:
		for cell: Array in cluster:
			m["%d,%d" % [cell[0], cell[1]]] = true
	return m


static func _full_site(props: Node3D, dirt_x: Dictionary, fence_x: Dictionary, cache: Dictionary,
		bi: int, bj: int, x0: float, x1: float, z0: float, z1: float) -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED ^ ((bi * 19349663 ^ bj * 83492791) * 2654435761)
	var n: int = 0
	n += _dirt_fill(dirt_x, x0 + 1.0, x1 - 1.0, z0 + 1.0, z1 - 1.0)
	n += _fence_ring(fence_x, x0, x1, z0, z1)
	# Foundation slab + tower crane anchoring the lot.
	_emit(props, SLABS, Vector3(lerp(x0, x1, 0.35), 0.03, lerp(z0, z1, 0.4)), 0.0, 1.0, cache)
	_emit(props, CRANE, Vector3(lerp(x0, x1, 0.65), 0.0, lerp(z0, z1, 0.6)), rng.randf_range(0.0, TAU), CRANE_SCALE, cache)
	n += 2
	# Scattered bulky props on a jittered grid.
	var step: float = 7.0
	var gx: float = x0 + 4.0
	while gx < x1 - 3.0:
		var gz: float = z0 + 4.0
		while gz < z1 - 3.0:
			if rng.randf() < 0.45:
				var path: String = _big_prop(rng)
				var p: Vector3 = Vector3(gx + rng.randf_range(-1.5, 1.5), 0.0, gz + rng.randf_range(-1.5, 1.5))
				_emit(props, path, p, float(rng.randi_range(0, 3)) * PI * 0.5, 1.0, cache)
				n += 1
			gz += step
		gx += step
	# A cluster of cones near a corner "entrance".
	for c in range(3):
		_emit(props, CONE, Vector3(x1 - 3.0 - float(c) * 1.2, 0.0, z0 + 3.0), 0.0, 1.0, cache)
		n += 1
	return n


static func _mini_site(props: Node3D, dirt_x: Dictionary, cache: Dictionary,
		x0: float, x1: float, z0: float, z1: float, rng: RandomNumberGenerator) -> int:
	var cx: float = (x0 + x1) * 0.5
	var cz: float = (z0 + z1) * 0.5
	var n: int = _dirt_fill(dirt_x, cx - 3.0, cx + 3.0, cz - 3.0, cz + 3.0)
	# One bulky element in the middle of the dig.
	_emit(props, _big_prop(rng), Vector3(cx + rng.randf_range(-1.0, 1.0), 0.0, cz + rng.randf_range(-1.0, 1.0)),
		float(rng.randi_range(0, 3)) * PI * 0.5, 1.0, cache)
	n += 1
	# Cones / barriers ringing it.
	for i in range(4):
		var ang: float = float(i) * PI * 0.5 + rng.randf_range(-0.2, 0.2)
		var p: Vector3 = Vector3(cx + cos(ang) * 3.6, 0.0, cz + sin(ang) * 3.6)
		var path: String = CONE if rng.randf() < 0.6 else ROADBAR
		_emit(props, path, p, rng.randf_range(0.0, TAU), 1.0, cache)
		n += 1
	return n


static func _big_prop(rng: RandomNumberGenerator) -> String:
	match rng.randi_range(0, 3):
		0: return SCAFFOLDS[rng.randi_range(0, SCAFFOLDS.size() - 1)]
		1: return CFRAME
		2: return CONTAINER
		_: return SAND[rng.randi_range(0, SAND.size() - 1)]


static func _dirt_fill(dirt_x: Dictionary, x0: float, x1: float, z0: float, z1: float) -> int:
	var count := 0
	var gx := x0 + DIRT_TILE * 0.5
	while gx < x1:
		var gz := z0 + DIRT_TILE * 0.5
		while gz < z1:
			var v := absi(int(gx * 3.0 + gz * 7.0)) % DIRT.size()
			var path: String = DIRT[v]
			if not dirt_x.has(path):
				dirt_x[path] = []
			dirt_x[path].append(Transform3D(Basis.IDENTITY, Vector3(gx, 0.0, gz)))
			count += 1
			gz += DIRT_TILE
		gx += DIRT_TILE
	return count


static func _fence_ring(fence_x: Dictionary, x0: float, x1: float, z0: float, z1: float) -> int:
	var count := 0
	count += _fence_line(fence_x, x0, x1, z0, true)
	count += _fence_line(fence_x, x0, x1, z1, true)
	count += _fence_line(fence_x, z0, z1, x0, false)
	count += _fence_line(fence_x, z0, z1, x1, false)
	return count


static func _fence_line(fence_x: Dictionary, a0: float, a1: float, fixed: float, along_x: bool) -> int:
	var count := 0
	var n := int((a1 - a0) / FENCE_LEN)
	for k in range(n):
		var c := a0 + FENCE_LEN * (float(k) + 0.5)
		var pos: Vector3 = Vector3(c, 0.0, fixed) if along_x else Vector3(fixed, 0.0, c)
		# Panel length runs along local Z; rotate 90 deg for lines along X.
		var yaw: float = PI * 0.5 if along_x else 0.0
		var path: String = FENCE[absi(int(c)) % FENCE.size()]
		if not fence_x.has(path):
			fence_x[path] = []
		fence_x[path].append(Transform3D(Basis(Vector3.UP, yaw), pos))
		count += 1
	return count


static func _emit(parent: Node3D, path: String, pos: Vector3, yaw: float, scale: float, cache: Dictionary) -> void:
	if not cache.has(path):
		cache[path] = load(path)
	if cache[path] == null:
		push_warning("ConstructionPlacer: missing asset %s" % path)
		return
	var inst: Node3D = (cache[path] as PackedScene).instantiate()
	inst.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale)), pos)
	parent.add_child(inst)
