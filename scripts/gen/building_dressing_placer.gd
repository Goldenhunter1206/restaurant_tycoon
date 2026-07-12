class_name BuildingDressingPlacer
extends RefCounted
## Dresses buildings with rooftop clutter, rooftop billboards and fire escapes.
## Driven off BuildingPlacer placements (world pos + rot_y + district + type).
##
## Placement is done in each building's BODY-LOCAL frame, using the model's
## MEASURED mesh AABB (loaded + measured at bake time), NOT the catalog w/h/d.
## The catalog dims are unreliable for dressing: the entrance-yaw fix in
## BuildingPlacer swaps w<->d for most families, and every mesh is offset from
## its body origin by (center_x, center_z) -- so trusting w/d/pos put props on a
## transposed, off-centre footprint and floated fire escapes off the facade.
## Measuring the real AABB and building transforms as body_xf * local_xf fixes
## both the height (true roof top) and the horizontal centring in one shot.
## All MultiMesh (via MeshBatch) under a "BuildingDressing" group. Deterministic.

const RP := "res://Cartoon City Massive Megapack/gLTF/Roof Props/"
const SP := "res://Cartoon City Massive Megapack/gLTF/Street Props/"

const ROOF_PROPS: Array[String] = [
	RP + "WaterTank_1_A.glb", RP + "WaterTank_1_C.glb", RP + "WaterTank_2_A.glb",
	RP + "Vent_1_A_1.glb", RP + "Vent_1_C_1.glb", RP + "Vent_1_E_1.glb",
	RP + "TFan_A.glb", RP + "TFan_C.glb",
	RP + "Turbine_1_A.glb", RP + "Turbine_1_D.glb",
	RP + "Chimney_1_A_1.glb", RP + "Chimney_1_C_2.glb",
	RP + "Antene_1_A_1.glb", RP + "Antene_1_C_1.glb",
	RP + "HeliLanding_1_A.glb",
]
const ROOF_BILLBOARDS: Array[String] = [
	RP + "Bilboard_1_A.glb", RP + "Bilboard_1_B.glb",
	RP + "Bilboard_1_C.glb", RP + "Bilboard_1_D.glb",
]
# FireEscape_A_2 is an already-upright section, thin on local X (faces +X), so it
# mounts directly onto a building's +X/-X facade with the building basis (see
# _dress). Measured AABB: x[-0.40,0.37] y[0.00,3.25] z[-0.19,2.40] (origin at the
# base; the constants below encode that so it hangs flush against the wall).
const FE_ASSET := SP + "FireEscape_A_2.glb"

const SEED: int = 314159265

const ROOF_MIN_H: float = 12.0
const ROOF_INSET: float = 1.8      # keep props off the roof edge
const ROOF_STEP: float = 4.5
const ROOF_MAX: int = 3            # curated props per roof cap
const BILL_MIN_H: float = 24.0
const BILL_SCALE: float = 1.6
const BILL_EDGE_INSET: float = 1.2 # billboard back-off from the roof +Z edge
const FE_MIN_H: float = 9.0
const FE_SECTION: float = 3.3      # FireEscape_A_2 upright section height
const FE_START: float = 3.0        # first landing above the ground floor
const FE_MAX: int = 3
const FE_MOUNT: float = 0.40       # escape mesh -X face offset from its origin
const FE_ZC: float = 1.10          # escape mesh Z-centre offset from its origin
const FE_BITE: float = 0.04        # minimal facade bite: attached, never visibly embedded


static func build(root: Node3D, placements: Array) -> int:
	var grp := Node3D.new()
	grp.name = "BuildingDressing"
	root.add_child(grp)
	var cache := {}
	var mcache := {}       # path -> measured body-local bounds
	var roof_x := {}       # path -> Array[Transform3D]
	var bill_x := {}       # path -> Array[Transform3D]
	var fe_x: Array = []   # single asset -> Array[Transform3D]

	for idx in range(placements.size()):
		_dress(placements[idx] as Dictionary, idx, roof_x, bill_x, fe_x, mcache)

	var total := 0
	var roof_node := Node3D.new()
	roof_node.name = "Rooftops"
	grp.add_child(roof_node)
	var i := 0
	for path: String in roof_x:
		total += (roof_x[path] as Array).size()
		MeshBatch.emit(roof_node, "Roof%d" % i, path, roof_x[path], cache)
		i += 1

	var sign_node := Node3D.new()
	sign_node.name = "RooftopSigns"
	grp.add_child(sign_node)
	i = 0
	for path: String in bill_x:
		total += (bill_x[path] as Array).size()
		MeshBatch.emit(sign_node, "RoofSign%d" % i, path, bill_x[path], cache)
		i += 1

	var fe_node := Node3D.new()
	fe_node.name = "FireEscapes"
	grp.add_child(fe_node)
	total += fe_x.size()
	MeshBatch.emit(fe_node, "FE", FE_ASSET, fe_x, cache)

	return total


static func _dress(p: Dictionary, idx: int, roof_x: Dictionary, bill_x: Dictionary, fe_x: Array, mcache: Dictionary) -> void:
	var h: float = p["h"]
	var district: String = p["district"]
	var btype: String = p["type"]
	var pos: Vector3 = p["pos"]
	var basis := Basis(Vector3.UP, deg_to_rad(p["rot_y"]))
	var body_xf := Transform3D(basis, pos)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED ^ (idx * 2654435761)
	var commercial := district == "D" or district == "C"
	var roofy := commercial or btype == "office" or btype == "civic"

	# Cheap eligibility gate on the catalog height (h is the true model height --
	# only w/d are swapped by the entrance-yaw fix, never h). Only measure the
	# real mesh when the building will actually be dressed.
	var want_roof := roofy and h >= ROOF_MIN_H
	# Escapes are reserved for the few building types that plausibly need them.
	# This avoids a noisy, game-like repetition on every commercial facade.
	var want_fe := (btype == "office" or btype == "factory") and h >= FE_MIN_H
	if not (want_roof or want_fe):
		return

	var m: Dictionary = _measure(p["path"], p.get("standup", Vector3.ZERO), mcache)
	var minx: float = m["minx"]
	var maxx: float = m["maxx"]
	var minz: float = m["minz"]
	var maxz: float = m["maxz"]
	var roof_y: float = m["roof_y"]
	if roof_y <= 0.0:
		return
	var cx := (minx + maxx) * 0.5
	var cz := (minz + maxz) * 0.5

	# Rooftop clutter on a jittered grid inset from the real roof edge, at the
	# real roof height. Props have their origin at the base, so y = roof_y sits
	# them on the roof.
	if want_roof:
		# Deliberate roof layouts: a small, aligned service cluster, never a
		# random scatter. The placement index only chooses one of three curated
		# asset trios; spacing, scale and orientation stay consistent city-wide.
		var layout: Array[String] = [
			ROOF_PROPS[0], ROOF_PROPS[3], ROOF_PROPS[6],
		]
		var slots: Array[Vector2] = [
			Vector2(minx + ROOF_INSET, minz + ROOF_INSET),
			Vector2(maxx - ROOF_INSET, minz + ROOF_INSET),
			Vector2(minx + ROOF_INSET, maxz - ROOF_INSET),
		]
		var placed := 0
		for slot: Vector2 in slots:
			if placed >= ROOF_MAX:
				break
			if slot.x > maxx - ROOF_INSET or slot.y > maxz - ROOF_INSET:
				continue
			var path: String = layout[(idx + placed) % layout.size()]
			if not roof_x.has(path):
				roof_x[path] = []
			var local := Vector3(slot.x, roof_y, slot.y)
			roof_x[path].append(body_xf * Transform3D(Basis(), local))
			placed += 1

	# Rooftop billboard on the tallest towers, at the roof's +Z edge, facing +Z.
	if commercial and h >= BILL_MIN_H:
		var local := Vector3(cx, roof_y, maxz - BILL_EDGE_INSET)
		var path: String = ROOF_BILLBOARDS[rng.randi_range(0, ROOF_BILLBOARDS.size() - 1)]
		if not bill_x.has(path):
			bill_x[path] = []
		var lxf := Transform3D(Basis().scaled(Vector3(BILL_SCALE, BILL_SCALE, BILL_SCALE)), local)
		bill_x[path].append(body_xf * lxf)

	# Fire escape: a stack of upright sections flush to one side facade. Built in
	# body-local space against the real +X (or -X) wall so it hangs on the mesh,
	# not on the body origin. FireEscape_A_2 is upright and its inner face is on
	# its local -X (FE_MOUNT from origin); on the -X wall it is turned 180 deg.
	if want_fe:
		# Mount a single stack on the facade opposite the entrance. This is a
		# stable, readable rear-service treatment rather than a random side choice.
		var front: Vector3 = p.get("front", Vector3.FORWARD)
		var local_front := body_xf.basis.inverse() * front.normalized()
		var rear := -local_front
		var fb: Basis
		var local: Vector3
		if absf(rear.x) >= absf(rear.z):
			var side_x := 1.0 if rear.x >= 0.0 else -1.0
			var wall_x := maxx if side_x > 0.0 else minx
			fb = Basis() if side_x > 0.0 else Basis(Vector3.UP, PI)
			local = Vector3(wall_x + side_x * (FE_MOUNT - FE_BITE), FE_START, cz - side_x * FE_ZC)
		else:
			var side_z := 1.0 if rear.z >= 0.0 else -1.0
			var wall_z := maxz if side_z > 0.0 else minz
			fb = Basis(Vector3.UP, -PI * 0.5) if side_z > 0.0 else Basis(Vector3.UP, PI * 0.5)
			local = Vector3(cx - side_z * FE_ZC, FE_START, wall_z + side_z * (FE_MOUNT - FE_BITE))
		var count := clampi(int((roof_y - FE_START) / FE_SECTION), 1, FE_MAX)
		for k in range(count):
			local.y = FE_START + float(k) * FE_SECTION
			fe_x.append(body_xf * Transform3D(fb, local))


## Public alias so other placers (GraffitiPlacer) reuse the same measured
## body-local bounds instead of re-deriving them from the catalog.
static func measure(path: String, standup: Vector3, mcache: Dictionary) -> Dictionary:
	return _measure(path, standup, mcache)


## Load + measure a model's mesh AABB in its body-local frame (standup applied,
## matching CityRebuilder). Returns roof_y (true height above the ground-sat
## base) and the x/z bounds. Cached per path. Editor/bake-time only.
static func _measure(path: String, standup: Vector3, mcache: Dictionary) -> Dictionary:
	if mcache.has(path):
		return mcache[path]
	var res := {"minx": 0.0, "maxx": 0.0, "minz": 0.0, "maxz": 0.0, "roof_y": 0.0}
	var ps: PackedScene = load(path)
	if ps != null:
		var inst: Node = ps.instantiate()
		if standup != Vector3.ZERO and inst is Node3D:
			(inst as Node3D).rotation_degrees = standup
		var acc: Array = [Vector3(1.0e9, 1.0e9, 1.0e9), Vector3(-1.0e9, -1.0e9, -1.0e9)]
		_aabb(inst, Transform3D.IDENTITY, acc)
		inst.free()
		if acc[0].x < 1.0e8:
			res = {
				"minx": acc[0].x, "maxx": acc[1].x,
				"minz": acc[0].z, "maxz": acc[1].z,
				"roof_y": acc[1].y - acc[0].y,
			}
	mcache[path] = res
	return res


static func _aabb(node: Node, xf: Transform3D, acc: Array) -> void:
	var m := xf
	if node is Node3D:
		m = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var a: AABB = (node as MeshInstance3D).mesh.get_aabb()
		for ix in [0.0, 1.0]:
			for iy in [0.0, 1.0]:
				for iz in [0.0, 1.0]:
					var wp: Vector3 = m * (a.position + Vector3(a.size.x * ix, a.size.y * iy, a.size.z * iz))
					acc[0] = Vector3(minf(acc[0].x, wp.x), minf(acc[0].y, wp.y), minf(acc[0].z, wp.z))
					acc[1] = Vector3(maxf(acc[1].x, wp.x), maxf(acc[1].y, wp.y), maxf(acc[1].z, wp.z))
	for c in node.get_children():
		_aabb(c, m, acc)
