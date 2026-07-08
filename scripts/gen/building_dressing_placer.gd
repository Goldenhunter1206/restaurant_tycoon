class_name BuildingDressingPlacer
extends RefCounted
## Dresses buildings with rooftop clutter, rooftop billboards and fire escapes.
## Driven off BuildingPlacer placements (world pos + rot_y + w/h/d + district +
## type), so props sit on roofs and against facades. All MultiMesh (via
## MeshBatch) under a "BuildingDressing" group. Deterministic per building id.

const RP := "res://Cartoon City Massive Megapack/gLTF 2/Roof Props/"
const SP := "res://Cartoon City Massive Megapack/gLTF 2/Street Props/"

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
# FireEscape_A_2 is an already-upright ~3.3 m section, thin on local X (faces
# +X), so it mounts directly onto a building's +X/-X facade (see _dress).
const FE_ASSET := SP + "FireEscape_A_2.glb"

const SEED: int = 314159265

const ROOF_MIN_H: float = 12.0
const ROOF_INSET: float = 1.8      # keep props off the roof edge
const ROOF_STEP: float = 3.6
const ROOF_PROB: float = 0.42
const ROOF_MAX: int = 8            # props per roof cap
const BILL_MIN_H: float = 24.0
const BILL_SCALE: float = 1.6
const FE_MIN_H: float = 9.0
const FE_SECTION: float = 3.3      # FireEscape_A_2 upright section height
const FE_START: float = 3.0        # first landing above the ground floor
const FE_MAX: int = 4


static func build(root: Node3D, placements: Array) -> int:
	var grp := Node3D.new()
	grp.name = "BuildingDressing"
	root.add_child(grp)
	var cache := {}
	var roof_x := {}       # path -> Array[Transform3D]
	var bill_x := {}       # path -> Array[Transform3D]
	var fe_x: Array = []   # single asset -> Array[Transform3D]

	for idx in range(placements.size()):
		_dress(placements[idx] as Dictionary, idx, roof_x, bill_x, fe_x)

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


static func _dress(p: Dictionary, idx: int, roof_x: Dictionary, bill_x: Dictionary, fe_x: Array) -> void:
	var h: float = p["h"]
	var w: float = p["w"]
	var d: float = p["d"]
	var district: String = p["district"]
	var btype: String = p["type"]
	var pos: Vector3 = p["pos"]
	var basis := Basis(Vector3.UP, deg_to_rad(p["rot_y"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED ^ (idx * 2654435761)
	var commercial := district == "D" or district == "C"
	var roofy := commercial or btype == "office" or btype == "civic"

	# Rooftop clutter on a jittered grid inset from the roof edge.
	if roofy and h >= ROOF_MIN_H:
		var roof_center := pos + Vector3(0.0, h, 0.0)
		var placed := 0
		var lx := -w * 0.5 + ROOF_INSET
		while lx <= w * 0.5 - ROOF_INSET and placed < ROOF_MAX:
			var lz := -d * 0.5 + ROOF_INSET
			while lz <= d * 0.5 - ROOF_INSET and placed < ROOF_MAX:
				if rng.randf() < ROOF_PROB:
					var local := Vector3(lx + rng.randf_range(-1.0, 1.0), 0.0, lz + rng.randf_range(-1.0, 1.0))
					var wp: Vector3 = roof_center + basis * local
					var path: String = ROOF_PROPS[rng.randi_range(0, ROOF_PROPS.size() - 1)]
					var s := rng.randf_range(0.8, 1.15)
					var yaw := rng.randf_range(0.0, TAU)
					if not roof_x.has(path):
						roof_x[path] = []
					roof_x[path].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), wp))
					placed += 1
				lz += ROOF_STEP
			lx += ROOF_STEP

	# Rooftop billboard on the tallest towers, at the street-facing (+Z) edge.
	if commercial and h >= BILL_MIN_H:
		var wp := pos + Vector3(0.0, h, 0.0) + basis * Vector3(0.0, 0.0, d * 0.5 - 1.2)
		var path: String = ROOF_BILLBOARDS[rng.randi_range(0, ROOF_BILLBOARDS.size() - 1)]
		if not bill_x.has(path):
			bill_x[path] = []
		bill_x[path].append(Transform3D(basis.scaled(Vector3(BILL_SCALE, BILL_SCALE, BILL_SCALE)), wp))

	# Fire escape: a stack of upright sections flush to one side facade.
	# FireEscape_A_2 is already upright and faces +X, so the building's own basis
	# (optionally flipped 180 deg for the -X side) mounts it directly -- no
	# stand-up rotation. It is 0.8 thin on X, 2.6 wide on Z, 3.3 tall.
	if commercial and h >= FE_MIN_H:
		var base_yaw := deg_to_rad(p["rot_y"])
		if rng.randf() < 0.5:
			base_yaw += PI
		var fb := Basis(Vector3.UP, base_yaw)
		var outward := fb.x
		var tangent := fb.z
		var count := clampi(int((h - FE_START) / FE_SECTION), 1, FE_MAX)
		for k in range(count):
			var anchor: Vector3 = pos + outward * (w * 0.5 + 0.4) - tangent * 1.1
			anchor.y = FE_START + float(k) * FE_SECTION
			fe_x.append(Transform3D(fb, anchor))
