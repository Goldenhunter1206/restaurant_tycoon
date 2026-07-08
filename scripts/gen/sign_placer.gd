class_name SignPlacer
extends RefCounted
## Street signage for commercial districts: sign holders at real street corners
## (C/D blocks) and freestanding billboards lining the grand-avenue frontages,
## facing the avenue. All MultiMesh (via MeshBatch) under a "Signage" group.
## Deterministic per block. Uses the assets' baked textures.

const SG := "res://Cartoon City Massive Megapack/gLTF 2/Signs/"

const HOLDERS: Array[String] = [
	SG + "SignHolder_1_A.glb", SG + "SignHolder_1_B.glb",
	SG + "SignHolder_2_A.glb", SG + "SignHolder_3_A.glb", SG + "SignHolder_3_B.glb",
]
const BILLBOARDS: Array[String] = [
	SG + "Bilboard_1_A.glb", SG + "Bilboard_1_B.glb", SG + "Bilboard_1_C.glb",
	SG + "Bilboard_2_A.glb", SG + "Bilboard_2_B.glb",
]

const SEED: int = 271828182
const CORNER_INSET: float = 1.6
const CORNER_PROB: float = 0.55
const BILL_SETBACK: float = 1.0    # into the sidewalk from the kerb


static func build(root: Node3D) -> int:
	var grp := Node3D.new()
	grp.name = "Signage"
	root.add_child(grp)
	var cache := {}
	var holder_x := {}   # path -> Array[Transform3D]
	var bill_x := {}     # path -> Array[Transform3D]

	var v_removed := CityBuilder.removed_v_segments()
	var h_removed := CityBuilder.removed_h_segments()
	for bi in range(CityBuilder.BLOCKS):
		for bj in range(CityBuilder.BLOCKS):
			var dist := CityBuilder.district(bi, bj)
			if dist != "C" and dist != "D":
				continue
			var x0 := CityBuilder.line_x(bi) + 4.0
			var x1 := CityBuilder.line_x(bi + 1) - 4.0
			var z0 := CityBuilder.line_z(bj) + 4.0
			var z1 := CityBuilder.line_z(bj + 1) - 4.0
			var n_road := not h_removed.has("%d,%d" % [bi, bj])
			var s_road := not h_removed.has("%d,%d" % [bi, bj + 1])
			var w_road := not v_removed.has("%d,%d" % [bi, bj])
			var e_road := not v_removed.has("%d,%d" % [bi + 1, bj])
			var rng := RandomNumberGenerator.new()
			rng.seed = SEED ^ ((bi * 73856093 ^ bj * 19349663) * 2654435761)

			# Sign holders at the four street corners.
			_corner(holder_x, rng, x0 + CORNER_INSET, z0 + CORNER_INSET, w_road and n_road)
			_corner(holder_x, rng, x1 - CORNER_INSET, z0 + CORNER_INSET, e_road and n_road)
			_corner(holder_x, rng, x0 + CORNER_INSET, z1 - CORNER_INSET, w_road and s_road)
			_corner(holder_x, rng, x1 - CORNER_INSET, z1 - CORNER_INSET, e_road and s_road)

			# Billboards along grand-avenue frontages, facing the avenue.
			if bi in CityBuilder.GRAND_AVENUE_V and w_road:
				_bill_edge(bill_x, rng, z0, z1, x0 + BILL_SETBACK, true, Vector3(-1, 0, 0))
			if (bi + 1) in CityBuilder.GRAND_AVENUE_V and e_road:
				_bill_edge(bill_x, rng, z0, z1, x1 - BILL_SETBACK, true, Vector3(1, 0, 0))
			if bj in CityBuilder.GRAND_AVENUE_H and n_road:
				_bill_edge(bill_x, rng, x0, x1, z0 + BILL_SETBACK, false, Vector3(0, 0, -1))
			if (bj + 1) in CityBuilder.GRAND_AVENUE_H and s_road:
				_bill_edge(bill_x, rng, x0, x1, z1 - BILL_SETBACK, false, Vector3(0, 0, 1))

	var total := 0
	var holder_node := Node3D.new()
	holder_node.name = "CornerSigns"
	grp.add_child(holder_node)
	var i := 0
	for path: String in holder_x:
		total += (holder_x[path] as Array).size()
		MeshBatch.emit(holder_node, "Sign%d" % i, path, holder_x[path], cache)
		i += 1

	var bill_node := Node3D.new()
	bill_node.name = "Billboards"
	grp.add_child(bill_node)
	i = 0
	for path: String in bill_x:
		total += (bill_x[path] as Array).size()
		MeshBatch.emit(bill_node, "Bill%d" % i, path, bill_x[path], cache)
		i += 1

	return total


static func _corner(holder_x: Dictionary, rng: RandomNumberGenerator, cx: float, cz: float, ok: bool) -> void:
	if not ok or rng.randf() >= CORNER_PROB:
		return
	var path: String = HOLDERS[rng.randi_range(0, HOLDERS.size() - 1)]
	if not holder_x.has(path):
		holder_x[path] = []
	holder_x[path].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), Vector3(cx, 0.0, cz)))


static func _bill_edge(bill_x: Dictionary, rng: RandomNumberGenerator, a0: float, a1: float,
		fixed: float, along_z: bool, face: Vector3) -> void:
	# Local +X of the billboard is the panel normal; aim it at the avenue.
	var yaw: float = atan2(-face.z, face.x)
	for f in [0.35, 0.65]:
		var c: float = lerp(a0, a1, f)
		var pos: Vector3 = Vector3(fixed, 0.0, c) if along_z else Vector3(c, 0.0, fixed)
		var path: String = BILLBOARDS[rng.randi_range(0, BILLBOARDS.size() - 1)]
		if not bill_x.has(path):
			bill_x[path] = []
		bill_x[path].append(Transform3D(Basis(Vector3.UP, yaw), pos))
