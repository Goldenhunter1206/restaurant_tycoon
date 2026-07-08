class_name MeshBatch
extends RefCounted
## Shared MultiMesh batching helpers. One glb -> one (or more, per submesh)
## MultiMeshInstance3D covering every requested transform, so thousands of
## identical static instances collapse to a handful of draw calls.
##
## Extracted from the pattern originally duplicated in DecorPlacer /
## SidewalkPlacer so the perf pass (roads/motorway/lights) and the decor
## placers all share one implementation. glb baked materials are reused
## as-is (no override).


## Extract every MeshInstance3D from a glb as [{"mesh": Mesh, "xform": Transform3D}],
## where xform is the mesh's transform local to the glb root. Memoized in `cache`.
static func extract_meshes(glb_path: String, cache: Dictionary) -> Array:
	if cache.has(glb_path):
		return cache[glb_path]
	var out: Array = []
	var ps: PackedScene = load(glb_path)
	if ps == null:
		push_warning("MeshBatch: missing asset %s" % glb_path)
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


## Emit one MultiMeshInstance3D per submesh of `glb_path`, instanced at every
## world transform in `xforms` (each combined with the submesh's local xform).
static func emit(parent: Node3D, base_name: String, glb_path: String, xforms: Array, cache: Dictionary) -> void:
	if xforms.is_empty():
		return
	var submeshes: Array = extract_meshes(glb_path, cache)
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


## Batch an array of tile dicts {"path": String, "pos": Vector3, "rot_y": float}
## into MultiMeshInstance3D nodes grouped by path. Returns the tile count.
static func emit_grouped(parent: Node3D, tiles: Array, cache: Dictionary) -> int:
	var by_path := {}
	for tile: Dictionary in tiles:
		var path: String = tile["path"]
		if not by_path.has(path):
			by_path[path] = []
		by_path[path].append(Transform3D(Basis(Vector3.UP, deg_to_rad(tile["rot_y"])), tile["pos"]))
	var idx := 0
	for path: String in by_path:
		emit(parent, "Batch_%d" % idx, path, by_path[path], cache)
		idx += 1
	return tiles.size()
