class_name ConcretePlacer
extends RefCounted
## Paves the bare interiors of downtown (D), commercial (C) and industrial (I)
## blocks with a StreetTile MultiMesh field, so those districts read as concrete
## plazas / parking / yards instead of the default grass. Suburbs (R/N/P) keep
## grass and get the SuburbanYardPlacer treatment instead; parks (K/G) and
## construction (X) are skipped. Tiles snap to a global 2 m lattice so merged
## super-lots pave continuously. Deterministic; built under a "ConcreteLots"
## group. Run inside CityRebuilder.rebuild_all after SidewalkPlacer.

const TILES := "res://Cartoon City Massive Megapack/gLTF 2/Tiles/"
const PAVERS: Array[String] = [TILES + "StreetTile_1_A_1.glb", TILES + "StreetTile_1_C_1.glb"]
const TILE_SZ: float = 2.0        # StreetTile is a 2x2 m paver
const EDGE_INSET: float = 7.0     # clear the road (4) + sidewalk band (3) on road-facing edges
const PAVE_Y: float = 0.0         # match the sidewalk pavers (ground plane sits at -0.02)
const VIS_END: float = 600.0
const PAVE_DISTRICTS: String = "DCI"


static func build(root: Node3D) -> Dictionary:
	var grp := Node3D.new()
	grp.name = "ConcreteLots"
	root.add_child(grp)
	var cache := {}
	var v_removed := CityBuilder.removed_v_segments()
	var h_removed := CityBuilder.removed_h_segments()
	var xforms: Array = []
	for _p in PAVERS:
		xforms.append([])
	for bi in range(CityBuilder.BLOCKS):
		for bj in range(CityBuilder.BLOCKS):
			if not PAVE_DISTRICTS.contains(CityBuilder.district(bi, bj)):
				continue
			# Inset road-facing edges past the sidewalk; extend merged (road-
			# removed) edges to the block line so neighbours meet seamlessly.
			var w_road := not v_removed.has("%d,%d" % [bi, bj])
			var e_road := not v_removed.has("%d,%d" % [bi + 1, bj])
			var n_road := not h_removed.has("%d,%d" % [bi, bj])
			var s_road := not h_removed.has("%d,%d" % [bi, bj + 1])
			var px0 := CityBuilder.line_x(bi) + (EDGE_INSET if w_road else 0.0)
			var px1 := CityBuilder.line_x(bi + 1) - (EDGE_INSET if e_road else 0.0)
			var pz0 := CityBuilder.line_z(bj) + (EDGE_INSET if n_road else 0.0)
			var pz1 := CityBuilder.line_z(bj + 1) - (EDGE_INSET if s_road else 0.0)
			_fill_rect(xforms, px0, px1, pz0, pz1)

	var total := 0
	for v in range(PAVERS.size()):
		var xs: Array = xforms[v]
		if xs.is_empty():
			continue
		total += xs.size()
		MeshBatch.emit(grp, "Concrete%d" % v, PAVERS[v], xs, cache)
	for c in grp.get_children():
		if c is MultiMeshInstance3D:
			(c as MultiMeshInstance3D).visibility_range_end = VIS_END
	return {"tiles": total}


static func _fill_rect(xforms: Array, x0: float, x1: float, z0: float, z1: float) -> void:
	var cx := _first_center(x0)
	while cx + TILE_SZ * 0.5 <= x1 + 0.01:
		var cz := _first_center(z0)
		while cz + TILE_SZ * 0.5 <= z1 + 0.01:
			# Hash the lattice cell for paver variety + a quarter-turn, exactly
			# like the sidewalk pavers, so the field is not visibly repetitive.
			var key := int(cx * 3.0 + cz * 7.0)
			var v := absi(key) % PAVERS.size()
			var quarter := absi(key / 5) % 4
			xforms[v].append(Transform3D(Basis(Vector3.UP, float(quarter) * PI * 0.5), Vector3(cx, PAVE_Y, cz)))
			cz += TILE_SZ
		cx += TILE_SZ


static func _first_center(a0: float) -> float:
	## Global 2 m lattice with tile centres at odd metres (tile spans [c-1, c+1]);
	## the smallest centre whose tile lies fully at or above a0.
	return ceil(a0 / TILE_SZ) * TILE_SZ + 1.0
