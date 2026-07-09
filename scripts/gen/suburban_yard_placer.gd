class_name SuburbanYardPlacer
extends RefCounted
## Dresses suburban homes (districts R/N/P) with front yards, driveways and
## back-yard life so the suburbs read lived-in and playful. Consumes the
## BuildingPlacer `placements` array (each home's pos / rot_y / footprint /
## district, entrance = local +Z toward the street) and, per home, lays a
## driveway (+ optional car), a curb-line fence with a driveway gap (walls +
## gates for rich, pickets for normal), a mailbox, front-yard hedges/bushes/
## flowers, and — for rich lots — a back-yard patio set and the odd basketball
## hoop. Richness scales strictly by tier. Everything is MultiMesh (via
## MeshBatch), grouped by asset, with a far-field fade. Deterministic; built
## under a "SuburbanYards" group. Run inside CityRebuilder.rebuild_all.

const NP := "res://Cartoon City Massive Megapack/gLTF 2/Nature and Park/"
const SP := "res://Cartoon City Massive Megapack/gLTF 2/Street Props/"
const OT := "res://Cartoon City Massive Megapack/gLTF 2/Other/"
const FP := "res://Cartoon City Massive Megapack/gLTF 2/Food Props/"
const TILES := "res://Cartoon City Massive Megapack/gLTF 2/Tiles/"
const V := "res://Cartoon City Massive Megapack/gLTF 2/Vehicles/"
const B := "res://Cartoon City Massive Megapack/gLTF 2/Basketball/"

const PICKET: Array[String] = [SP + "Fence_1_A_1.glb", SP + "Fence_1_C_1.glb"]   # length ~1.97 m along local Z
const PICKET_LEN: float = 1.97
const WALL: Array[String] = [OT + "WallFence_1_1_A.glb", OT + "WallFence_1_1_B.glb", OT + "WallFence_1_1_C.glb"]  # ~2.10 m along local X
const WALL_LEN: float = 2.10
const GATES: Array[String] = [OT + "WallFence_3_Gate_A.glb", OT + "WallFence_3_Gate_B.glb"]
const MAILBOXES: Array[String] = [SP + "PostBox_1_A.glb", SP + "PostBox_1_B.glb", SP + "PostBox_1_C.glb"]
const DRIVE_TILE: String = TILES + "StreetTile_1_A_1.glb"
const HEDGE: Array[String] = [NP + "Bush_1_A_1.glb", NP + "Bush_1_C_1.glb"]        # long low bush -> hedge (length ~2.2 m along local Z)
const HEDGE_LEN: float = 2.2
const BUSHES: Array[String] = [NP + "Bush_1_A_2.glb", NP + "Bush_1_B_2.glb", NP + "Bush_2_A_1.glb"]
const FLOWERS: Array[String] = [NP + "Flowers_1_A.glb", NP + "Flowers_2_B.glb", NP + "Flowers_3_C.glb", NP + "Flower_1_A.glb"]
const TABLES: Array[String] = [FP + "Table_1_A.glb", FP + "Table_1_C.glb"]
const CHAIRS: Array[String] = [FP + "Chair_1_A.glb", FP + "Chair_1_B.glb"]
const PARASOLS: Array[String] = [FP + "Parasol_1_A.glb", FP + "Parasol_1_C.glb"]
const HOOP: String = B + "Basketball_Stand_A.glb"
const CARS: Array[String] = [V + "Car 5/Car_5_A.gltf", V + "Car 5/Car_5_C.gltf", V + "Car 1/Car_1_A.gltf", V + "Car 5/Car_5_B.gltf"]

## Front-to-curb yard depth per tier (mirrors BuildingPlacer.SETBACK).
const SETBACKS := {"R": 6.0, "N": 3.5, "P": 0.8}
## Per-tier richness: fence style, chances and counts.
const CFG := {
	"R": {"fence": "wall", "car": 0.7, "bushes": 4, "flowers": 3, "hedge": true, "patio": 0.55, "hoop": 0.22},
	"N": {"fence": "picket", "car": 0.4, "bushes": 3, "flowers": 1, "hedge": false, "patio": 0.12, "hoop": 0.05},
	"P": {"fence": "none", "car": 0.0, "bushes": 1, "flowers": 0, "hedge": false, "patio": 0.0, "hoop": 0.0},
}

const SEED: int = 777211
const VIS_END: float = 420.0
const GAP_HALF: float = 1.9   # half-width of the driveway gap left in the fence


static func build(root: Node3D, placements: Array) -> Dictionary:
	var grp := Node3D.new()
	grp.name = "SuburbanYards"
	root.add_child(grp)
	var batches := {}
	var homes := 0
	var idx := 0
	for p: Dictionary in placements:
		if p["type"] == "home" and CFG.has(p["district"]):
			_dress_home(batches, p, idx)
			homes += 1
		idx += 1

	var cache := {}
	var props := 0
	var i := 0
	for path: String in batches:
		var xs: Array = batches[path]
		props += xs.size()
		MeshBatch.emit(grp, "Yard_%d" % i, path, xs, cache)
		i += 1
	for c in grp.get_children():
		if c is MultiMeshInstance3D:
			(c as MultiMeshInstance3D).visibility_range_end = VIS_END
	return {"homes": homes, "props": props}


static func _dress_home(batches: Dictionary, p: Dictionary, idx: int) -> void:
	var dist: String = p["district"]
	var cfg: Dictionary = CFG[dist]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED ^ (idx * 2654435761)

	var pos: Vector3 = p["pos"]
	# Front = the true entrance/street direction (from BuildingPlacer), not
	# basis.z — most models' entrances sit on a side face.
	var fwd: Vector3 = p.get("front", Vector3(sin(deg_to_rad(float(p["rot_y"]))), 0.0, cos(deg_to_rad(float(p["rot_y"])))))
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var right := Vector3(fwd.z, 0.0, -fwd.x)        # perpendicular, to fwd's right
	var w: float = p["w"]
	var d: float = p["d"]
	var setback: float = SETBACKS[dist]
	var front := pos + fwd * (d * 0.5)              # street-facing wall
	var curb := front + fwd * (setback - 0.4)       # fence line, just inside the lot edge
	var half: float = w * 0.5 + 1.4                 # frontage half-width
	var drive_u: float = w * 0.30                   # driveway offset along +right
	var has_drive: bool = dist != "P" and setback >= 2.5

	# --- Driveway + parked car ---
	if has_drive:
		var dd := 1.0
		while dd <= setback - 0.2:
			var dp := front + fwd * dd + right * drive_u
			_add(batches, DRIVE_TILE, Transform3D(Basis(), Vector3(dp.x, 0.0, dp.z)))
			dd += 2.0
		if setback >= 3.0 and rng.randf() < float(cfg["car"]):
			var car: String = CARS[rng.randi_range(0, CARS.size() - 1)]
			var cp := curb - fwd * 1.9 + right * drive_u
			var car_yaw := atan2(-fwd.z, fwd.x)   # car art faces +X -> aim it along fwd
			_add(batches, car, Transform3D(Basis(Vector3.UP, car_yaw), Vector3(cp.x, 0.24, cp.z)))

	# --- Front fence with a driveway gap (+ gate for rich) ---
	if cfg["fence"] != "none":
		var is_wall: bool = cfg["fence"] == "wall"
		var panel_len: float = WALL_LEN if is_wall else PICKET_LEN
		var line_yaw: float = atan2(-right.z, right.x) if is_wall else atan2(right.x, right.z)
		var fence_list: Array = WALL if is_wall else PICKET
		var u := -half
		while u + panel_len <= half + 0.01:
			var uc := u + panel_len * 0.5
			if has_drive and absf(uc - drive_u) < GAP_HALF:
				u += panel_len
				continue
			var fp := curb + right * uc
			var fpath: String = fence_list[absi(int(uc * 10.0)) % fence_list.size()]
			_add(batches, fpath, Transform3D(Basis(Vector3.UP, line_yaw), Vector3(fp.x, 0.0, fp.z)))
			u += panel_len
		if is_wall and has_drive:
			var gp := curb + right * drive_u
			var gate: String = GATES[rng.randi_range(0, GATES.size() - 1)]
			_add(batches, gate, Transform3D(Basis(Vector3.UP, line_yaw), Vector3(gp.x, 0.0, gp.z)))

	# --- Mailbox at the curb, beside the driveway ---
	var mb_u: float = drive_u + GAP_HALF + 0.5
	if mb_u > half:
		mb_u = drive_u - GAP_HALF - 0.5
	var mbp := curb + right * mb_u
	_add(batches, MAILBOXES[rng.randi_range(0, MAILBOXES.size() - 1)],
		Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z)), Vector3(mbp.x, 0.0, mbp.z)))

	# --- Rich hedge row just inside the fence ---
	if cfg["hedge"]:
		var hz := curb - fwd * 1.2
		var hyaw := atan2(right.x, right.z)   # hedge bush long axis is local Z
		var hu := -half + 0.4
		while hu + HEDGE_LEN <= half:
			var huc := hu + HEDGE_LEN * 0.5
			if not (has_drive and absf(huc - drive_u) < GAP_HALF + 0.6):
				var hp := hz + right * huc
				_add(batches, HEDGE[absi(int(huc * 7.0)) % HEDGE.size()],
					Transform3D(Basis(Vector3.UP, hyaw), Vector3(hp.x, 0.0, hp.z)))
			hu += HEDGE_LEN

	# --- Scattered front-yard bushes + flower beds (avoid the driveway) ---
	var fy_depth: float = maxf(1.0, setback - 1.0)
	for k in range(int(cfg["bushes"])):
		var su := rng.randf_range(-half + 0.5, half - 0.5)
		if has_drive and absf(su - drive_u) < GAP_HALF:
			continue
		var sp := front + fwd * rng.randf_range(0.8, fy_depth) + right * su
		_add(batches, BUSHES[rng.randi_range(0, BUSHES.size() - 1)],
			_sxform(sp, rng.randf_range(0.0, TAU), rng.randf_range(0.8, 1.15)))
	for k in range(int(cfg["flowers"])):
		var fu := rng.randf_range(-half + 0.5, half - 0.5)
		if has_drive and absf(fu - drive_u) < GAP_HALF:
			continue
		var flp := front + fwd * rng.randf_range(0.8, fy_depth) + right * fu
		_add(batches, FLOWERS[rng.randi_range(0, FLOWERS.size() - 1)],
			_sxform(flp, rng.randf_range(0.0, TAU), 1.0))

	# --- Back-yard patio + optional basketball hoop (rich mostly) ---
	var back := pos - fwd * (d * 0.5)
	if rng.randf() < float(cfg["patio"]):
		var pc := back - fwd * 3.0
		_add(batches, TABLES[rng.randi_range(0, TABLES.size() - 1)], _sxform(pc, rng.randf_range(0.0, TAU), 1.0))
		_add(batches, PARASOLS[rng.randi_range(0, PARASOLS.size() - 1)], _sxform(pc, 0.0, 1.0))
		for a in range(3):
			var ang := float(a) * TAU / 3.0 + rng.randf_range(0.0, 0.6)
			var chp := pc + Vector3(cos(ang), 0.0, sin(ang)) * 1.1
			_add(batches, CHAIRS[rng.randi_range(0, CHAIRS.size() - 1)], _sxform(chp, ang + PI, 1.0))
	if rng.randf() < float(cfg["hoop"]):
		var hp := back - fwd * 2.0 + right * (w * 0.4)
		_add(batches, HOOP, Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), Vector3(hp.x, 0.0, hp.z)))


static func _add(batches: Dictionary, path: String, xform: Transform3D) -> void:
	if not batches.has(path):
		batches[path] = []
	batches[path].append(xform)


static func _sxform(pos: Vector3, yaw: float, s: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(pos.x, 0.0, pos.z))
