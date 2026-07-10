class_name GraffitiPlacer
extends RefCounted
## Graffiti pass: the pack's 10 unused spray-art PNGs, placed as textured
## quads flush against building walls. Density follows the neighbourhood --
## heavy on industrial lots, moderate in the poor suburbs, an occasional tag
## downtown/commercial, none on rich or normal suburban homes -- so the effect
## reads lived-in rather than wallpapered.
##
## Placement is done in each building's BODY-LOCAL frame against the measured
## mesh AABB (via BuildingDressingPlacer.measure), low on a weighted-random
## wall (rear/side preferred, entrance facade rare), with per-wall separation
## so quads never overlap (which also keeps alpha blending sort-safe: every
## quad only ever composites against the opaque wall behind it). One QuadMesh
## + MultiMesh per texture under a "Graffiti" group => ~10 draw calls total.
## Deterministic per placement index.

const TEX_DIR := "res://assets/graffiti/"
const TEX_COUNT: int = 10

const SEED: int = 998244353
const MIN_H: float = 4.0          # skip tiny structures
const SIZE_MIN: float = 1.5
const SIZE_MAX: float = 3.0
const WALL_OFF: float = 0.05      # quad stand-off from the facade (no z-fighting)
const EDGE_INSET: float = 0.5     # extra inset from wall corners
const ROLL_MAX: float = 6.0       # random tilt, degrees
const SEP_PAD: float = 0.3        # min clear gap between two tags on one wall
const VIS_END: float = 350.0
const FE_MIN_H: float = 9.0       # mirror of the fire-escape predicate in dressing
const FE_CLEAR: float = 3.0       # keep-out around the rear-wall midpoint (FE stack)

## Per-district: [hit probability, min quads, max quads, front-wall weight].
const DENSITY := {
	"I": [0.55, 1, 3, 0.25],
	"P": [0.28, 1, 2, 0.10],
	"C": [0.08, 1, 1, 0.10],
	"D": [0.08, 1, 1, 0.10],
}


static func build(root: Node3D, placements: Array) -> int:
	var grp := Node3D.new()
	grp.name = "Graffiti"
	root.add_child(grp)

	var textures: Array[Texture2D] = []
	var valid: Array[int] = []
	for i in range(TEX_COUNT):
		var tex: Texture2D = load(TEX_DIR + "gr%d.png" % (i + 1))
		if tex == null:
			push_warning("GraffitiPlacer: missing texture gr%d.png" % (i + 1))
		else:
			valid.append(i)
		textures.append(tex)
	if valid.is_empty():
		push_warning("GraffitiPlacer: no graffiti textures found, skipping pass")
		return 0

	var xforms: Array = []   # per texture index -> Array[Transform3D]
	for _i in range(TEX_COUNT):
		xforms.append([])
	var count := 0
	for idx in range(placements.size()):
		count += _tag_building(placements[idx] as Dictionary, idx, valid, xforms)

	for i in range(TEX_COUNT):
		var xs: Array = xforms[i]
		if xs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _quad_mesh(textures[i])
		mm.instance_count = xs.size()
		for k in range(xs.size()):
			mm.set_instance_transform(k, xs[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Gr%d" % (i + 1)
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = VIS_END
		grp.add_child(mmi)
	return count


static func _tag_building(p: Dictionary, idx: int, valid: Array[int], xforms: Array) -> int:
	var district: String = p["district"]
	if not DENSITY.has(district):
		return 0
	var h: float = p["h"]
	if h < MIN_H:
		return 0
	var cfg: Array = DENSITY[district]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED ^ (idx * 2654435761)
	if rng.randf() >= float(cfg[0]):
		return 0

	var mcache := _shared_mcache()
	var m: Dictionary = BuildingDressingPlacer.measure(p["path"], p.get("standup", Vector3.ZERO), mcache)
	var roof_y: float = m["roof_y"]
	if roof_y <= 0.0:
		return 0
	var minx: float = m["minx"]
	var maxx: float = m["maxx"]
	var minz: float = m["minz"]
	var maxz: float = m["maxz"]
	var body_xf := Transform3D(Basis(Vector3.UP, deg_to_rad(p["rot_y"])), p["pos"])

	# Walls in body-local space; the entrance facade is tagged least.
	var local_front: Vector3 = body_xf.basis.inverse() * (p.get("front", Vector3.FORWARD) as Vector3).normalized()
	var front_id := ""
	if absf(local_front.x) >= absf(local_front.z):
		front_id = "px" if local_front.x >= 0.0 else "nx"
	else:
		front_id = "pz" if local_front.z >= 0.0 else "nz"
	var rear_id: String = {"px": "nx", "nx": "px", "pz": "nz", "nz": "pz"}[front_id]
	var walls := [
		{"id": "px", "len": maxz - minz},
		{"id": "nx", "len": maxz - minz},
		{"id": "pz", "len": maxx - minx},
		{"id": "nz", "len": maxx - minx},
	]
	for w: Dictionary in walls:
		var wid: String = w["id"]
		w["weight"] = float(cfg[3]) if wid == front_id else (1.3 if wid == rear_id else 1.0)

	# Fire-escape keep-out: dressing mounts an escape stack on the rear wall
	# midpoint of tall offices/factories -- do not tag through it.
	var btype: String = p["type"]
	var fe_on_rear := (btype == "office" or btype == "factory") and h >= FE_MIN_H

	var want := rng.randi_range(int(cfg[1]), int(cfg[2]))
	var used := {}   # wall id -> Array of [t, size]
	var count := 0
	for _q in range(want):
		for _try in range(4):
			var w := _pick_wall(rng, walls)
			var wid: String = w["id"]
			var wall_len: float = w["len"]
			var s := rng.randf_range(SIZE_MIN, SIZE_MAX)
			s = minf(s, minf(0.55 * roof_y, wall_len - 1.2))
			if s < 1.2:
				continue
			var inset := s * 0.5 + EDGE_INSET
			var lo: float = (minz if wid.ends_with("x") else minx) + inset
			var hi: float = (maxz if wid.ends_with("x") else maxx) - inset
			if hi <= lo:
				continue
			var t := rng.randf_range(lo, hi)
			if fe_on_rear and wid == rear_id and absf(t - (lo + hi) * 0.5) < FE_CLEAR:
				continue
			var clear := true
			for prior: Array in used.get(wid, []):
				if absf(t - float(prior[0])) < (s + float(prior[1])) * 0.5 + SEP_PAD:
					clear = false
					break
			if not clear:
				continue
			var y := s * 0.5 + rng.randf_range(0.05, 0.5)
			var local := _wall_transform(wid, t, y, s, minx, maxx, minz, maxz, rng)
			var tex_i: int = valid[rng.randi_range(0, valid.size() - 1)]
			(xforms[tex_i] as Array).append(body_xf * local)
			if not used.has(wid):
				used[wid] = []
			used[wid].append([t, s])
			count += 1
			break
	return count


static func _pick_wall(rng: RandomNumberGenerator, walls: Array) -> Dictionary:
	var total := 0.0
	for w: Dictionary in walls:
		total += float(w["weight"])
	var roll := rng.randf() * total
	for w: Dictionary in walls:
		roll -= float(w["weight"])
		if roll <= 0.0:
			return w
	return walls[0]


## Body-local transform of a quad flush on wall `wid` at along-wall coordinate
## `t`, centre height `y`, scale `s`, with a small random roll around the
## wall normal. QuadMesh faces +Z, so yaw the local +Z onto the outward normal.
static func _wall_transform(wid: String, t: float, y: float, s: float, minx: float, maxx: float, minz: float, maxz: float, rng: RandomNumberGenerator) -> Transform3D:
	var yaw: float
	var pos: Vector3
	match wid:
		"px":
			yaw = PI * 0.5
			pos = Vector3(maxx + WALL_OFF, y, t)
		"nx":
			yaw = -PI * 0.5
			pos = Vector3(minx - WALL_OFF, y, t)
		"pz":
			yaw = 0.0
			pos = Vector3(t, y, maxz + WALL_OFF)
		_:
			yaw = PI
			pos = Vector3(t, y, minz - WALL_OFF)
	var roll := deg_to_rad(rng.randf_range(-ROLL_MAX, ROLL_MAX))
	# Scale must be right-multiplied (local space): Basis.scaled() scales in
	# WORLD axes, which squishes yawed quads to 1 m wide.
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), roll) * Basis.from_scale(Vector3(s, s, 1.0))
	return Transform3D(basis, pos)


static func _quad_mesh(tex: Texture2D) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.disable_receive_shadows = true
	mesh.material = mat
	return mesh


## One measurement cache for the whole pass (static fn scripts have no
## instance state; keyed off a static var so repeated calls stay cheap).
static var _mcache: Dictionary = {}

static func _shared_mcache() -> Dictionary:
	return _mcache
