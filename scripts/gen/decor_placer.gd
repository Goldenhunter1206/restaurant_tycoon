class_name DecorPlacer
extends RefCounted
## Fresh street-decor pass: tree-lined streets + lamps as MultiMesh under a
## DecorMultimesh group node. Deterministic (seeded) so rebuilds are stable.
## Trees skip tight downtown / industrial frontages; lamps line every street.

const TREES: Array[String] = [
	"res://Cartoon City Massive Megapack/gLTF/Nature and Park/Tree_A_2.glb",
	"res://Cartoon City Massive Megapack/gLTF/Nature and Park/Tree_A_5.glb",
	"res://Cartoon City Massive Megapack/gLTF/Nature and Park/Tree_B_2.glb",
	"res://Cartoon City Massive Megapack/gLTF/Nature and Park/Tree_B_8.glb",
	"res://Cartoon City Massive Megapack/gLTF/Nature and Park/Tree_C_8.glb",
]
const LAMP: String = "res://Cartoon City Massive Megapack/gLTF/Nature and Park/StreetLamp_3_A.glb"

const TREE_OFF: float = 4.8
const LAMP_OFF: float = 4.5
const TREE_SPACING: float = 15.0
const LAMP_SPACING: float = 30.0
const END_CLEAR: float = 9.0
const SEED: int = 987654321

# Districts that get street trees along their frontage (downtown/industrial skip).
const TREE_OK := {"R": true, "N": true, "P": true, "C": true}


static func build(root: Node3D) -> int:
	var grp := Node3D.new()
	grp.name = "DecorMultimesh"
	root.add_child(grp)
	var extract_cache := {}

	# Accumulate transforms: tree_xforms[variant_index] -> Array[Transform3D];
	# lamp_xforms -> Array[Transform3D].
	var tree_xforms: Array = []
	for _t in TREES:
		tree_xforms.append([])
	var lamp_xforms: Array = []

	_gather_v_lines(tree_xforms, lamp_xforms)
	_gather_h_lines(tree_xforms, lamp_xforms)

	var tree_total := 0
	var trees_node := Node3D.new()
	trees_node.name = "StreetTrees"
	grp.add_child(trees_node)
	for v in range(TREES.size()):
		var xs: Array = tree_xforms[v]
		if xs.is_empty():
			continue
		tree_total += xs.size()
		_emit_multimesh(trees_node, "Tree%d" % v, TREES[v], xs, extract_cache)

	var lamps_node := Node3D.new()
	lamps_node.name = "Lamps"
	grp.add_child(lamps_node)
	_emit_multimesh(lamps_node, "Lamp", LAMP, lamp_xforms, extract_cache)

	return tree_total + lamp_xforms.size()


static func _gather_v_lines(tree_xforms: Array, lamp_xforms: Array) -> void:
	var v_removed := CityBuilder.removed_v_segments()
	for i in range(CityBuilder.LINES):
		var lush := i in CityBuilder.GRAND_AVENUE_V
		for j in range(CityBuilder.LINES - 1):
			if v_removed.has("%d,%d" % [i, j]):
				continue
			var x := CityBuilder.line_x(i)
			var z0 := CityBuilder.line_z(j) + END_CLEAR
			var z1 := CityBuilder.line_z(j + 1) - END_CLEAR
			# West side belongs to block (i-1, j); east side to (i, j).
			_line_side(tree_xforms, lamp_xforms, Vector3(x - TREE_OFF, 0, z0), Vector3(x - LAMP_OFF, 0, z0),
				z1 - z0, true, Vector3(-1, 0, 0), CityBuilder.district(i - 1, j), i * 31 + j, lush)
			_line_side(tree_xforms, lamp_xforms, Vector3(x + TREE_OFF, 0, z0), Vector3(x + LAMP_OFF, 0, z0),
				z1 - z0, true, Vector3(1, 0, 0), CityBuilder.district(i, j), i * 37 + j + 991, lush)


static func _gather_h_lines(tree_xforms: Array, lamp_xforms: Array) -> void:
	var h_removed := CityBuilder.removed_h_segments()
	for j in range(CityBuilder.LINES):
		var lush := j in CityBuilder.GRAND_AVENUE_H
		for i in range(CityBuilder.LINES - 1):
			if h_removed.has("%d,%d" % [i, j]):
				continue
			var z := CityBuilder.line_z(j)
			var x0 := CityBuilder.line_x(i) + END_CLEAR
			var x1 := CityBuilder.line_x(i + 1) - END_CLEAR
			# North side belongs to block (i, j-1); south side to (i, j).
			_line_side(tree_xforms, lamp_xforms, Vector3(x0, 0, z - TREE_OFF), Vector3(x0, 0, z - LAMP_OFF),
				x1 - x0, false, Vector3(0, 0, -1), CityBuilder.district(i, j - 1), i + j * 41 + 5000, lush)
			_line_side(tree_xforms, lamp_xforms, Vector3(x0, 0, z + TREE_OFF), Vector3(x0, 0, z + LAMP_OFF),
				x1 - x0, false, Vector3(0, 0, 1), CityBuilder.district(i, j), i + j * 43 + 7000, lush)


static func _line_side(tree_xforms: Array, lamp_xforms: Array, tree_start: Vector3, lamp_start: Vector3,
		length: float, along_z: bool, outward: Vector3, district: String, salt: int, lush: bool) -> void:
	if length <= 0.0:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED ^ (salt * 2654435761)
	var axis: Vector3 = Vector3(0, 0, 1) if along_z else Vector3(1, 0, 0)
	if lush or TREE_OK.has(district):
		var spacing: float = 8.0 if lush else TREE_SPACING
		var t: float = spacing * 0.5
		while t < length:
			var jitter: float = t + rng.randf_range(-1.5, 1.5)
			_place_tree(tree_xforms, rng, tree_start + axis * jitter)
			if lush:
				_place_tree(tree_xforms, rng, tree_start + outward * 3.6 + axis * jitter)
			t += spacing
	var lamp_spacing: float = 16.0 if lush else LAMP_SPACING
	var l: float = lamp_spacing * 0.5
	while l < length:
		var lyaw: float = 0.0 if along_z else PI * 0.5
		var lpos: Vector3 = lamp_start + axis * l
		# Skip lamps that fall inside a bulky sidewalk prop (no RNG here to disturb).
		if not SidewalkPlacer.is_reserved(lpos.x, lpos.z):
			lamp_xforms.append(Transform3D(Basis(Vector3.UP, lyaw), lpos))
		l += lamp_spacing


static func _place_tree(tree_xforms: Array, rng: RandomNumberGenerator, pos: Vector3) -> void:
	var v := rng.randi_range(0, TREES.size() - 1)
	var s := rng.randf_range(0.85, 1.2)
	var yaw := rng.randf_range(0.0, TAU)
	# Consume the rolls first, then drop the tree if it lands inside a bulky
	# sidewalk prop, so the RNG stream for later placements is unaffected.
	if SidewalkPlacer.is_reserved(pos.x, pos.z):
		return
	tree_xforms[v].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), pos))


static func _emit_multimesh(parent: Node3D, base_name: String, glb_path: String, xforms: Array, cache: Dictionary) -> void:
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
		push_warning("DecorPlacer: missing asset %s" % glb_path)
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
