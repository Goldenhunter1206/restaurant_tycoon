class_name IndustrialDressingPlacer
extends RefCounted
## Hand-authored "set piece" compositions stamped into the free space of
## industrial (I) lots so the belt reads worked-in rather than barren: loading
## docks, pallet yards, barrel corners, trailer rows, scrap piles and pipe
## stockyards, plus a chain-link / wall perimeter fence with a double gate on
## every road-facing edge.
##
## Compositions are data-driven offset layouts in a template-local frame
## (+Z = template front, turned toward the nearest road edge) and are
## collision-checked against building footprints (from BuildingPlacer
## placements), the ConstructionPlacer mini-site digs and each other. Prop
## origins in the pack are unreliable, so every glb is AABB-measured at bake
## for grounding, fence pitch and fence long-axis. All MultiMesh via MeshBatch
## under an "IndustrialDressing" group. Deterministic per lot.

const CO := "res://Cartoon City Massive Megapack/gLTF 2/Construction Site/Other/"
const OT := "res://Cartoon City Massive Megapack/gLTF 2/Other/"

const SEED: int = 271828182
const PROP_Y: float = 0.1        # concrete pavement top (matches sidewalk furniture)
const EDGE_KEEP: float = 4.0     # composition keep-out from the lot interior edge
const FENCE_INSET: float = 2.4   # fence line inside the lot edge (past the sidewalk band)
const FENCE_END: float = 3.0     # fence stand-off from lot corners
const BLDG_MARGIN: float = 1.8   # building footprints inflated for composition clearance
const COMP_MARGIN: float = 1.5   # minimum gap between two compositions
const AREA_PER_COMP: float = 240.0
const MAX_BLOCK: int = 3
const MAX_SUPER: int = 9
const VIS_END: float = 500.0
const CHAIN_PROB: float = 0.7    # tall chain-link vs low wall perimeter
const GATE_HALF: float = 2.0     # reserved half-width of the double-gate opening

const CHAIN: Array[String] = [
	OT + "Fence_6_1_A.glb", OT + "Fence_6_1_B.glb", OT + "Fence_6_1_C.glb",
	OT + "Fence_6_1_D.glb", OT + "Fence_6_1_E.glb",
]
const WALL: Array[String] = [
	OT + "WallFence_2_1_A.glb", OT + "WallFence_2_1_B.glb", OT + "WallFence_2_1_C.glb",
	OT + "WallFence_2_1_D.glb", OT + "WallFence_2_1_E.glb",
]
const GATES: Array[String] = [
	OT + "WallFence_3_Gate_A.glb", OT + "WallFence_3_Gate_B.glb",
	OT + "WallFence_3_Gate_C.glb", OT + "WallFence_3_Gate_D.glb",
]

## Composition templates. Local frame: origin at the footprint centre on the
## ground, +Z is the front (faces the road). Items: "p" glb path, "o" offset
## (o.y stacks props on each other), optional "yaw" degrees, optional "s" scale.
## "size" is the (x, z) footprint including working clearance.
const TEMPLATES: Array[Dictionary] = [
	{
		"name": "loading_dock", "weight": 3, "super_only": false,
		"size": Vector2(16.0, 8.0),
		"items": [
			{"p": CO + "Container_1_1.glb", "o": Vector3(-4.8, 0.0, -2.0), "yaw": 90.0},
			{"p": CO + "Container_1_3.glb", "o": Vector3(0.2, 0.0, -2.0), "yaw": 90.0},
			{"p": CO + "Container_1_7.glb", "o": Vector3(5.0, 0.0, -1.6), "yaw": 78.0},
			{"p": CO + "ForkLift.glb", "o": Vector3(1.4, 0.0, 1.6), "yaw": 180.0},
			{"p": CO + "Pallet_1_1.glb", "o": Vector3(-2.6, 0.0, 1.7), "yaw": 15.0},
			{"p": CO + "Pallet_1_2.glb", "o": Vector3(-2.6, 0.18, 1.7), "yaw": 40.0},
			{"p": CO + "Pallet_1_1.glb", "o": Vector3(-1.3, 0.0, 2.1), "yaw": 75.0},
			{"p": CO + "BoxWooden_1_A.glb", "o": Vector3(-4.2, 0.0, 1.5), "yaw": 10.0},
			{"p": CO + "BoxWooden_1_B.glb", "o": Vector3(-4.15, 0.97, 1.55), "yaw": 55.0},
			{"p": CO + "BoxWooden_1_B.glb", "o": Vector3(-5.3, 0.0, 1.9), "yaw": 30.0},
		],
	},
	{
		"name": "pallet_yard", "weight": 3, "super_only": false,
		"size": Vector2(10.0, 7.0),
		"items": [
			{"p": CO + "Pallet_1_1.glb", "o": Vector3(-3.4, 0.0, -1.8)},
			{"p": CO + "Pallet_1_2.glb", "o": Vector3(-3.4, 0.18, -1.8), "yaw": 12.0},
			{"p": CO + "Pallet_1_1.glb", "o": Vector3(-3.4, 0.36, -1.75), "yaw": 3.0},
			{"p": CO + "Pallet_1_2.glb", "o": Vector3(-2.0, 0.0, -1.8), "yaw": 5.0},
			{"p": CO + "BoxWooden_1_A.glb", "o": Vector3(-2.0, 0.18, -1.75), "yaw": 20.0},
			{"p": CO + "Pallet_1_1.glb", "o": Vector3(-0.6, 0.0, -1.85), "yaw": 352.0},
			{"p": CO + "Spool_1_1.glb", "o": Vector3(1.2, 0.0, -1.6)},
			{"p": CO + "Spool_3_A.glb", "o": Vector3(2.6, 0.0, -1.7), "yaw": 30.0},
			{"p": CO + "Spool_2_1.glb", "o": Vector3(1.9, 0.0, -0.4), "yaw": 70.0},
			{"p": CO + "WoodStock_1.glb", "o": Vector3(-2.4, 0.0, 1.5), "yaw": 90.0},
			{"p": CO + "WoodStock_2.glb", "o": Vector3(-2.2, 0.0, 2.6), "yaw": 94.0},
			{"p": CO + "Planks_2.glb", "o": Vector3(2.8, 0.0, 1.8), "yaw": 90.0},
			{"p": CO + "Planks_4.glb", "o": Vector3(2.6, 0.41, 1.9), "yaw": 84.0},
		],
	},
	{
		"name": "barrel_corner", "weight": 2, "super_only": false,
		"size": Vector2(7.0, 6.0),
		"items": [
			{"p": CO + "Barrel_1_1.glb", "o": Vector3(-1.6, 0.0, -1.2)},
			{"p": CO + "Barrel_1_2.glb", "o": Vector3(-0.8, 0.0, -1.25), "yaw": 40.0},
			{"p": CO + "Barrel_1_3.glb", "o": Vector3(0.0, 0.0, -1.2), "yaw": 110.0},
			{"p": CO + "Barrel_1_4.glb", "o": Vector3(-1.6, 0.0, -0.4), "yaw": 200.0},
			{"p": CO + "Barrel_1_5.glb", "o": Vector3(-0.8, 0.0, -0.45), "yaw": 75.0},
			{"p": CO + "Barrel_1_6.glb", "o": Vector3(0.0, 0.0, -0.4), "yaw": 290.0},
			{"p": CO + "GasCylinder_1_2.glb", "o": Vector3(1.4, 0.0, -1.0)},
			{"p": CO + "GasCylinder_1_5.glb", "o": Vector3(1.65, 0.0, -0.75), "yaw": 130.0},
			{"p": CO + "GasCylinder_2_3.glb", "o": Vector3(1.5, 0.0, -0.25), "yaw": 45.0},
			{"p": CO + "Pipes_C_2_1.glb", "o": Vector3(-0.5, 0.0, 1.4), "yaw": 90.0},
			{"p": CO + "SheetMetal_C_1.glb", "o": Vector3(1.8, 0.0, 1.2), "yaw": 15.0},
		],
	},
	{
		"name": "trailer_park", "weight": 2, "super_only": true,
		"size": Vector2(21.0, 9.0),
		"items": [
			{"p": CO + "TrailerC_1_A.glb", "o": Vector3(-8.0, 0.0, 0.0), "yaw": 4.0},
			{"p": CO + "TrailerC_1_B.glb", "o": Vector3(-4.0, 0.0, 0.2), "yaw": 357.0},
			{"p": CO + "TrailerC_1_C.glb", "o": Vector3(0.0, 0.0, 0.0), "yaw": 2.0},
			{"p": CO + "TrailerC_1_D.glb", "o": Vector3(4.0, 0.0, 0.1), "yaw": 355.0},
			{"p": CO + "TrailerC_1_E.glb", "o": Vector3(8.0, 0.0, -0.1), "yaw": 3.0},
			{"p": "res://Cartoon City Massive Megapack/gLTF 2/Street Props/Cone_1.glb", "o": Vector3(-9.6, 0.0, 3.4)},
			{"p": "res://Cartoon City Massive Megapack/gLTF 2/Street Props/Cone_2.glb", "o": Vector3(0.2, 0.0, 3.8)},
			{"p": "res://Cartoon City Massive Megapack/gLTF 2/Street Props/Cone_1.glb", "o": Vector3(9.5, 0.0, 3.2)},
		],
	},
	{
		"name": "scrap_corner", "weight": 2, "super_only": false,
		"size": Vector2(9.0, 7.0),
		"items": [
			{"p": CO + "RubbleContainer_A_1.glb", "o": Vector3(-2.0, 0.0, -1.6)},
			{"p": CO + "RubbleContainer_B_1.glb", "o": Vector3(2.6, 0.0, -1.3), "yaw": 14.0},
			{"p": OT + "TireWall_1_A.glb", "o": Vector3(-3.2, 0.0, 1.4), "yaw": 90.0},
			{"p": OT + "TireWall_2_A.glb", "o": Vector3(0.4, 0.0, 1.8), "yaw": 20.0},
			{"p": OT + "Tire.glb", "o": Vector3(1.7, 0.0, 1.2)},
			{"p": OT + "Tire.glb", "o": Vector3(2.05, 0.0, 1.5), "yaw": 60.0},
			{"p": OT + "Tire.glb", "o": Vector3(1.85, 0.33, 1.35), "yaw": 25.0},
			{"p": CO + "SheetMetal_B_1.glb", "o": Vector3(3.4, 0.0, 1.6), "yaw": 75.0},
			{"p": CO + "SheetMetal_D_2.glb", "o": Vector3(3.5, 0.05, 1.9), "yaw": 60.0},
		],
	},
	{
		"name": "pipe_stock", "weight": 2, "super_only": false,
		"size": Vector2(10.0, 6.0),
		"items": [
			{"p": CO + "PipesBulk.glb", "o": Vector3(-1.8, 0.0, -1.0), "yaw": 90.0},
			{"p": CO + "Pipes_C_2_1.glb", "o": Vector3(1.9, 0.0, -1.2), "yaw": 90.0},
			{"p": CO + "Pipes_C_1_1.glb", "o": Vector3(0.0, 0.0, 1.3), "yaw": 90.0},
			{"p": CO + "Spool_Empty.glb", "o": Vector3(3.6, 0.0, 1.0)},
			{"p": CO + "Planks_1.glb", "o": Vector3(-3.2, 0.0, 1.7), "yaw": 90.0},
		],
	},
]


static func build(root: Node3D, placements: Array) -> int:
	var grp := Node3D.new()
	grp.name = "IndustrialDressing"
	root.add_child(grp)
	var props_node := Node3D.new()
	props_node.name = "Props"
	grp.add_child(props_node)
	var fence_node := Node3D.new()
	fence_node.name = "Fences"
	grp.add_child(fence_node)

	var mesh_cache := {}
	var meas := {}      # path -> {"min": Vector3, "max": Vector3, "ok": bool}
	var prop_x := {}    # path -> Array[Transform3D]
	var fence_x := {}
	var v_removed := CityBuilder.removed_v_segments()
	var h_removed := CityBuilder.removed_h_segments()
	var by_lot := _building_rects(placements)

	var count := 0
	for lot: Dictionary in _industrial_lots():
		var bldgs: Array = by_lot.get(lot["key"], [])
		count += _dress_lot(lot, bldgs, v_removed, h_removed, prop_x, fence_x, meas)

	var i := 0
	for path: String in prop_x:
		MeshBatch.emit(props_node, "Prop%d" % i, path, prop_x[path], mesh_cache)
		i += 1
	i = 0
	for path: String in fence_x:
		MeshBatch.emit(fence_node, "Fence%d" % i, path, fence_x[path], mesh_cache)
		i += 1
	for node: Node3D in [props_node, fence_node]:
		for c in node.get_children():
			if c is MultiMeshInstance3D:
				(c as MultiMeshInstance3D).visibility_range_end = VIS_END
	return count


## All industrial lots, superblock-merged lots first (same claiming order as
## BuildingPlacer.build_placements so lot keys match placement "block" keys).
static func _industrial_lots() -> Array[Dictionary]:
	var lots: Array[Dictionary] = []
	var claimed := {}
	for sb: Array in CityBuilder.SUPERBLOCKS:
		for i in range(sb[0], sb[0] + sb[2]):
			for j in range(sb[1], sb[1] + sb[3]):
				claimed["%d,%d" % [i, j]] = true
		if CityBuilder.district(sb[0], sb[1]) == "I":
			lots.append(_lot(sb[0], sb[1], sb[2], sb[3], true))
	for cluster: Array in CityBuilder.LSHAPE_CLUSTERS:
		for cell: Array in cluster:
			claimed["%d,%d" % [cell[0], cell[1]]] = true
	for bi in range(CityBuilder.BLOCKS):
		for bj in range(CityBuilder.BLOCKS):
			if claimed.has("%d,%d" % [bi, bj]):
				continue
			if CityBuilder.district(bi, bj) == "I":
				lots.append(_lot(bi, bj, 1, 1, false))
	return lots


static func _lot(bi: int, bj: int, bw: int, bh: int, is_super: bool) -> Dictionary:
	return {
		"key": "%d,%d" % [bi, bj], "bi": bi, "bj": bj, "bw": bw, "bh": bh,
		"x0": CityBuilder.line_x(bi) + 4.0, "x1": CityBuilder.line_x(bi + bw) - 4.0,
		"z0": CityBuilder.line_z(bj) + 4.0, "z1": CityBuilder.line_z(bj + bh) - 4.0,
		"is_super": is_super,
	}


## Industrial building footprints per lot key, from placements (world extents
## honour the rot_y w<->d swap; pos already carries the mesh-centre correction).
static func _building_rects(placements: Array) -> Dictionary:
	var by_lot := {}
	for p: Dictionary in placements:
		if p["district"] != "I":
			continue
		var blk: Array = p["block"]
		var key := "%d,%d" % [blk[0], blk[1]]
		var ex: float = p["w"]
		var ez: float = p["d"]
		if absi(int(roundf(p["rot_y"]))) % 180 != 0:
			ex = p["d"]
			ez = p["w"]
		var pos: Vector3 = p["pos"]
		var raw := Rect2(pos.x - ex * 0.5, pos.z - ez * 0.5, ex, ez)
		if not by_lot.has(key):
			by_lot[key] = []
		by_lot[key].append({
			"raw": raw, "rect": raw.grow(BLDG_MARGIN),
			"family": p["family"], "pos": pos, "half": maxf(ex, ez) * 0.5,
		})
	return by_lot


## Lot faces (0=N z0, 1=S z1, 2=W x0, 3=E x1) that carry at least one road
## segment (merged-away edges excluded) — same semantics as BuildingPlacer.
static func _road_faces(lot: Dictionary, v_removed: Dictionary, h_removed: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var bi: int = lot["bi"]
	var bj: int = lot["bj"]
	var bw: int = lot["bw"]
	var bh: int = lot["bh"]
	for i in range(bi, bi + bw):
		if not h_removed.has("%d,%d" % [i, bj]):
			out.append(0)
			break
	for i in range(bi, bi + bw):
		if not h_removed.has("%d,%d" % [i, bj + bh]):
			out.append(1)
			break
	for j in range(bj, bj + bh):
		if not v_removed.has("%d,%d" % [bi, j]):
			out.append(2)
			break
	for j in range(bj, bj + bh):
		if not v_removed.has("%d,%d" % [bi + bw, j]):
			out.append(3)
			break
	return out


static func _dress_lot(lot: Dictionary, bldgs: Array, v_removed: Dictionary, h_removed: Dictionary, prop_x: Dictionary, fence_x: Dictionary, meas: Dictionary) -> int:
	var bi: int = lot["bi"]
	var bj: int = lot["bj"]
	var x0: float = lot["x0"]
	var x1: float = lot["x1"]
	var z0: float = lot["z0"]
	var z1: float = lot["z1"]
	var is_super: bool = lot["is_super"]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED ^ ((bi * 19349663 ^ bj * 83492791) * 2654435761)

	var keep: Array[Rect2] = []
	for b: Dictionary in bldgs:
		keep.append(b["rect"])
	if not is_super:
		var mini: Variant = ConstructionPlacer.mini_site_rect(bi, bj)
		if mini != null:
			keep.append(mini)
	var roads := _road_faces(lot, v_removed, h_removed)

	var occ := 0.0
	for r: Rect2 in keep:
		occ += r.size.x * r.size.y
	var free_area := maxf(0.0, (x1 - x0) * (z1 - z0) - occ)
	var want := clampi(int(free_area / AREA_PER_COMP), 1, MAX_SUPER if is_super else MAX_BLOCK)

	var count := 0
	var placed_rects: Array[Rect2] = []
	var attempts := want * 6
	while placed_rects.size() < want and attempts > 0:
		attempts -= 1
		var t := _pick_template(rng, lot)
		if t.is_empty():
			break
		var sz: Vector2 = t["size"]
		var half := maxf(sz.x, sz.y) * 0.5
		var ax := rng.randf_range(x0 + EDGE_KEEP + half, x1 - EDGE_KEEP - half)
		var az := rng.randf_range(z0 + EDGE_KEEP + half, z1 - EDGE_KEEP - half)
		# Barrel corners belong next to the gas tanks when the lot has one.
		if String(t["name"]) == "barrel_corner":
			for b: Dictionary in bldgs:
				if String(b["family"]) == "GASTANK":
					var tp: Vector3 = b["pos"]
					var dv := Vector3((x0 + x1) * 0.5 - tp.x, 0.0, (z0 + z1) * 0.5 - tp.z)
					var dir := Vector3(signf(dv.x), 0.0, 0.0) if absf(dv.x) >= absf(dv.z) else Vector3(0.0, 0.0, signf(dv.z))
					var dist: float = float(b["half"]) + BLDG_MARGIN + half + 0.8
					ax = clampf(tp.x + dir.x * dist + rng.randf_range(-1.5, 1.5), x0 + EDGE_KEEP + half, x1 - EDGE_KEEP - half)
					az = clampf(tp.z + dir.z * dist + rng.randf_range(-1.5, 1.5), z0 + EDGE_KEEP + half, z1 - EDGE_KEEP - half)
					break
		# Face the nearest road-bearing lot edge.
		var yaw := 0.0
		var best := 1.0e9
		for f: int in roads:
			var d: float
			match f:
				0: d = az - z0
				1: d = z1 - az
				2: d = ax - x0
				_: d = x1 - ax
			if d < best:
				best = d
				match f:
					0: yaw = 180.0
					1: yaw = 0.0
					2: yaw = 270.0
					_: yaw = 90.0
		var fw := sz.x if absi(int(roundf(yaw))) % 180 == 0 else sz.y
		var fd := sz.y if absi(int(roundf(yaw))) % 180 == 0 else sz.x
		var rect := Rect2(ax - fw * 0.5 - COMP_MARGIN, az - fd * 0.5 - COMP_MARGIN,
			fw + 2.0 * COMP_MARGIN, fd + 2.0 * COMP_MARGIN)
		var blocked := SidewalkPlacer.is_reserved(ax, az)
		if not blocked:
			for r: Rect2 in keep:
				if rect.intersects(r):
					blocked = true
					break
		if not blocked:
			for r: Rect2 in placed_rects:
				if rect.intersects(r):
					blocked = true
					break
		if blocked:
			continue
		placed_rects.append(rect)
		count += _stamp(t, Vector3(ax, 0.0, az), yaw, prop_x, meas)

	count += _fence_lot(lot, roads, bldgs, rng, fence_x, meas)
	return count


## Weighted template pick among those that fit the lot's usable interior.
static func _pick_template(rng: RandomNumberGenerator, lot: Dictionary) -> Dictionary:
	var usable := minf(float(lot["x1"]) - float(lot["x0"]), float(lot["z1"]) - float(lot["z0"])) - 2.0 * EDGE_KEEP
	var pool: Array[Dictionary] = []
	var total := 0
	for t: Dictionary in TEMPLATES:
		if bool(t["super_only"]) and not bool(lot["is_super"]):
			continue
		var sz: Vector2 = t["size"]
		if maxf(sz.x, sz.y) > usable:
			continue
		pool.append(t)
		total += int(t["weight"])
	if pool.is_empty():
		return {}
	var roll := rng.randi_range(0, total - 1)
	for t: Dictionary in pool:
		roll -= int(t["weight"])
		if roll < 0:
			return t
	return pool[0]


## Emit one template instance at `anchor` turned by `yaw` degrees. Each item is
## grounded on its measured AABB min-y; o.y stacks props on each other.
static func _stamp(t: Dictionary, anchor: Vector3, yaw: float, prop_x: Dictionary, meas: Dictionary) -> int:
	var comp_basis := Basis(Vector3.UP, deg_to_rad(yaw))
	var count := 0
	for item: Dictionary in t["items"]:
		var path: String = item["p"]
		var m := _measure(path, meas)
		if not bool(m["ok"]):
			continue
		var s: float = item.get("s", 1.0)
		var o: Vector3 = item["o"]
		var world_o: Vector3 = comp_basis * Vector3(o.x, 0.0, o.z)
		var y: float = PROP_Y + o.y - (m["min"] as Vector3).y * s
		var b := Basis(Vector3.UP, deg_to_rad(yaw + float(item.get("yaw", 0.0)))).scaled(Vector3(s, s, s))
		var pos := Vector3(anchor.x + world_o.x, y, anchor.z + world_o.z)
		if not prop_x.has(path):
			prop_x[path] = []
		prop_x[path].append(Transform3D(b, pos))
		count += 1
	return count


## Perimeter fence with a double gate on each road-facing edge. Panel pitch and
## long-axis come from the measured AABB (fence families disagree on the axis).
static func _fence_lot(lot: Dictionary, roads: Array[int], bldgs: Array, rng: RandomNumberGenerator, fence_x: Dictionary, meas: Dictionary) -> int:
	var panels: Array[String] = CHAIN if rng.randf() < CHAIN_PROB else WALL
	var gate: String = GATES[rng.randi_range(0, GATES.size() - 1)]
	var pm := _measure(panels[0], meas)
	if not bool(pm["ok"]):
		return 0
	var pmin: Vector3 = pm["min"]
	var pmax: Vector3 = pm["max"]
	var plen := maxf(pmax.x - pmin.x, pmax.z - pmin.z)
	var p_axis_x := (pmax.x - pmin.x) >= (pmax.z - pmin.z)
	var count := 0
	for f: int in roads:
		var along_x := f < 2
		var fixed: float
		match f:
			0: fixed = float(lot["z0"]) + FENCE_INSET
			1: fixed = float(lot["z1"]) - FENCE_INSET
			2: fixed = float(lot["x0"]) + FENCE_INSET
			_: fixed = float(lot["x1"]) - FENCE_INSET
		var a0 := (float(lot["x0"]) if along_x else float(lot["z0"])) + FENCE_END
		var a1 := (float(lot["x1"]) if along_x else float(lot["z1"])) - FENCE_END
		if a1 - a0 < plen:
			continue
		# Double gate somewhere in the first half of the edge, skipped if the
		# opening would land inside a building footprint.
		var gate_c := lerpf(a0, a1, 0.4 + rng.randf_range(-0.1, 0.1))
		var has_gate := not _span_blocked(gate_c - GATE_HALF, gate_c + GATE_HALF, fixed, along_x, bldgs)
		var yaw_deg := (0.0 if p_axis_x else 90.0) if along_x else (90.0 if p_axis_x else 0.0)
		var n := int((a1 - a0) / plen)
		for k in range(n):
			var c := a0 + plen * (float(k) + 0.5)
			if has_gate and absf(c - gate_c) < GATE_HALF + plen * 0.5:
				continue
			if _span_blocked(c - plen * 0.5, c + plen * 0.5, fixed, along_x, bldgs):
				continue
			var path: String = panels[absi(int(c)) % panels.size()]
			var vm := _measure(path, meas)
			_append_centered(fence_x, path, vm, c, fixed, along_x, yaw_deg)
			count += 1
		if has_gate:
			var gm := _measure(gate, meas)
			if bool(gm["ok"]):
				var leaf_half := ((gm["max"] as Vector3).x - (gm["min"] as Vector3).x) * 0.5
				var base_yaw := 0.0 if along_x else 90.0
				_append_centered(fence_x, gate, gm, gate_c + leaf_half, fixed, along_x, base_yaw)
				_append_centered(fence_x, gate, gm, gate_c - leaf_half, fixed, along_x, base_yaw + 180.0)
				count += 2
	return count


## True when the fence-line span [c0, c1] at `fixed` crosses a building
## footprint (slightly inflated so panels never kiss a facade).
static func _span_blocked(c0: float, c1: float, fixed: float, along_x: bool, bldgs: Array) -> bool:
	for b: Dictionary in bldgs:
		var r := (b["raw"] as Rect2).grow(0.5)
		var lo := r.position.x if along_x else r.position.y
		var hi := lo + (r.size.x if along_x else r.size.y)
		var f0 := r.position.y if along_x else r.position.x
		var f1 := f0 + (r.size.y if along_x else r.size.x)
		if fixed >= f0 and fixed <= f1 and c1 >= lo and c0 <= hi:
			return true
	return false


## Append a fence piece so its measured XZ centre lands exactly on the fence
## line at marching coordinate `c` (pack fence origins are off-centre).
static func _append_centered(fence_x: Dictionary, path: String, m: Dictionary, c: float, fixed: float, along_x: bool, yaw_deg: float) -> void:
	if not bool(m["ok"]):
		return
	var mn: Vector3 = m["min"]
	var mx: Vector3 = m["max"]
	var center := (mn + mx) * 0.5
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var desired := Vector3(c, 0.0, fixed) if along_x else Vector3(fixed, 0.0, c)
	var off: Vector3 = basis * Vector3(center.x, 0.0, center.z)
	var pos := Vector3(desired.x - off.x, PROP_Y - mn.y, desired.z - off.z)
	if not fence_x.has(path):
		fence_x[path] = []
	fence_x[path].append(Transform3D(basis, pos))


## Bake-time AABB measurement (pack origins are unreliable). Cached per path.
static func _measure(path: String, meas: Dictionary) -> Dictionary:
	if meas.has(path):
		return meas[path]
	var res := {"min": Vector3.ZERO, "max": Vector3.ZERO, "ok": false}
	var ps: PackedScene = load(path)
	if ps != null:
		var inst: Node = ps.instantiate()
		var acc: Array = [Vector3(1.0e9, 1.0e9, 1.0e9), Vector3(-1.0e9, -1.0e9, -1.0e9)]
		_aabb(inst, Transform3D.IDENTITY, acc)
		inst.free()
		if acc[0].x < 1.0e8:
			res = {"min": acc[0], "max": acc[1], "ok": true}
	else:
		push_warning("IndustrialDressingPlacer: missing asset %s" % path)
	meas[path] = res
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
