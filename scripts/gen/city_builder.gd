class_name CityBuilder
extends RefCounted
## Deterministic city layout math. Single source of truth for the road
## grid: tile placements (P1), and later the lane/sidewalk graph (P2).
## All positions derive from grid constants — never from placed meshes.
##
## Layout intent (believability): small dense blocks downtown, large
## blocks in the suburbs and industrial belt, superblocks that merge
## lots into parks/campuses/plazas so the grid reads organic, and a
## motorway along the west edge entering the map in the south and
## leaving in the north.

const TILE: float = 8.0
const BLOCKS: int = 16
const LINES: int = 17                # BLOCKS + 1 road lines per axis

## Interior width (m) of each block column/row. Must be multiples of 8.
## Downtown (i 4..10, j 4..7) is dense; edges are wide suburban blocks.
const COL_INTERIORS: Array[int] = [40, 40, 40, 48, 32, 32, 32, 32, 32, 32, 32, 40, 48, 48, 48, 40]
const ROW_INTERIORS: Array[int] = [48, 48, 40, 40, 32, 32, 32, 32, 40, 40, 40, 40, 40, 48, 48, 48]

const MOTORWAY_X: float = -53.0      # centerline; east edge -44 mates with 5 avenue tiles spanning -44..-4
const MOTORWAY_Z_START: float = -80.0
const MOTORWAY_Z_END: float = 850.0
const AVENUE_ROWS: Array[int] = [3, 11]   # horizontal lines extended west to the motorway
const ROADS_DIR: String = "res://Cartoon City Massive Megapack/gLTF 2/Roads/"

# Direction bitmask (world): N = -Z, S = +Z, E = +X, W = -X.
const N: int = 1
const S: int = 2
const E: int = 4
const W: int = 8

# Local-space connectivity of road pieces at rotation 0 (lanes along Z).
# Verified against a top-down lineup render of the asset pack.
const PIECE_STRAIGHT: int = N | S        # Road_X_1
const PIECE_T_EAST: int = N | S | E      # Road_X_5
const PIECE_CROSS: int = N | S | E | W   # Road_X_7
const PIECE_CURVE: int = S | W           # Road_X_8

## District zoning, one row per block row j (north to south), one char
## per block column i (west to east):
## D downtown, C commercial, I industrial, R rich suburb, N normal
## suburb, P poor suburb, K central park, G pocket park, X construction.
const ZONING: Array[String] = [
	"RRRRRRRRRRRRRRRR",
	"RRRRRRRRRRRRRRRR",
	"RRRRRRRRRGRRRRRR",
	"CCCCCCCCCCCCNNNN",
	"PPPCDDDDDDDCNNNN",
	"PPPCDDDDDDDCNNNN",
	"PPCCDDDDDDDCNNNN",
	"PPPCDDDDDDDCNNNN",
	"PPPCCDDKKDCCNNNN",
	"PPPCCDDKKDCCNNNN",
	"PPPNCCCCCCCNNNGN",
	"CCCCCCCCCCCCCNNN",
	"PPNNNNNGNNNXNNNN",
	"IIIIIIIIIIIIIIII",
	"IIIIIIIIIIIIIIII",
	"IIIIIIIIIIIIIIII",
]


static func district(bi: int, bj: int) -> String:
	if bi < 0 or bi >= BLOCKS or bj < 0 or bj >= BLOCKS:
		return ""
	return ZONING[bj][bi]


## Superblocks [block_i, block_j, w, h]: interior road segments removed
## so the covered blocks merge into one large lot.
const SUPERBLOCKS: Array = [
	[7, 8, 2, 2],     # central park
	[5, 5, 1, 2],     # downtown plaza (two blocks merged N-S)
	[9, 6, 2, 1],     # downtown superblock (two blocks merged E-W)
	[1, 0, 2, 1],     # rich north: estate lots
	[5, 0, 2, 1],     # rich north
	[12, 0, 2, 2],    # rich north-east: golf-course-sized estate
	[13, 5, 2, 2],    # normal east suburb
	[12, 9, 2, 1],    # normal east suburb
	[0, 6, 2, 1],     # poor west
	[1, 9, 1, 2],     # poor west
	[0, 13, 2, 2],    # industrial south-west
	[3, 13, 2, 2],    # industrial
	[6, 13, 2, 2],    # industrial
	[10, 13, 2, 2],   # industrial
	[13, 13, 2, 2],   # industrial south-east
]


static func line_x(i: int) -> float:
	var x := 0.0
	for c in range(i):
		x += float(COL_INTERIORS[c]) + TILE
	return x


static func line_z(j: int) -> float:
	var z := 0.0
	for r in range(j):
		z += float(ROW_INTERIORS[r]) + TILE
	return z


static func city_extent() -> Rect2:
	## World-space rectangle of the road grid (line centers).
	return Rect2(0.0, 0.0, line_x(LINES - 1), line_z(LINES - 1))


static func line_theme(index: int) -> String:
	return "A" if (index >= 3 and index <= 11) else "B"


static func removed_v_segments() -> Dictionary:
	## Keys "i,j": vertical-line i segment between rows j and j+1.
	var removed := {}
	for sb: Array in SUPERBLOCKS:
		var bi: int = sb[0]
		var bj: int = sb[1]
		var w: int = sb[2]
		var h: int = sb[3]
		for i in range(bi + 1, bi + w):
			for j in range(bj, bj + h):
				removed["%d,%d" % [i, j]] = true
	return removed


static func removed_h_segments() -> Dictionary:
	## Keys "i,j": horizontal-line j segment between cols i and i+1.
	var removed := {}
	for sb: Array in SUPERBLOCKS:
		var bi: int = sb[0]
		var bj: int = sb[1]
		var w: int = sb[2]
		var h: int = sb[3]
		for j in range(bj + 1, bj + h):
			for i in range(bi, bi + w):
				removed["%d,%d" % [i, j]] = true
	return removed


static func intersection_branches(i: int, j: int) -> int:
	## World-space branch mask of the intersection at grid point (i, j).
	var v_removed := removed_v_segments()
	var h_removed := removed_h_segments()
	var mask := 0
	if j > 0 and not v_removed.has("%d,%d" % [i, j - 1]):
		mask |= N
	if j < LINES - 1 and not v_removed.has("%d,%d" % [i, j]):
		mask |= S
	if i < LINES - 1 and not h_removed.has("%d,%d" % [i, j]):
		mask |= E
	if i > 0 and not h_removed.has("%d,%d" % [i - 1, j]):
		mask |= W
	if i == 0 and j in AVENUE_ROWS:
		mask |= W   # avenue to the motorway
	return mask


static func is_signalized(i: int, j: int) -> bool:
	## Downtown/commercial band gets working traffic lights.
	if i < 3 or i > 11 or j < 3 or j > 11:
		return false
	var mask := intersection_branches(i, j)
	return _bit_count(mask) >= 3


static func rotate_mask_cw(mask: int) -> int:
	## Connectivity mask after rotating the piece by +90 deg around Y
	## (Godot: +Z -> +X, +X -> -Z), i.e. S->E, E->N, N->W, W->S.
	var out := 0
	if mask & S:
		out |= E
	if mask & E:
		out |= N
	if mask & N:
		out |= W
	if mask & W:
		out |= S
	return out


static func rotation_for(base_mask: int, target_mask: int) -> float:
	## Yaw degrees that map a piece's local mask onto the target, or -1.0.
	var m := base_mask
	for step in range(4):
		if m == target_mask:
			return float(step) * 90.0
		m = rotate_mask_cw(m)
	return -1.0


static func road_piece(theme: String, kind: String) -> String:
	var names := {
		"straight": "Road_%s_1",
		"xwalk": "Road_%s_2_1",
		"t_east": "Road_%s_5",
		"cross": "Road_%s_7",
		"curve": "Road_%s_8",
	}
	return ROADS_DIR + (names[kind] % theme) + ".glb"


static func build_v_segment_tiles() -> Array:
	## Straight tiles of all vertical road lines (lanes along Z, rot 0).
	var v_removed := removed_v_segments()
	var tiles := []
	for i in range(LINES):
		var theme := line_theme(i)
		for j in range(LINES - 1):
			if v_removed.has("%d,%d" % [i, j]):
				continue
			var tile_count := ROW_INTERIORS[j] / 8
			for k in range(tile_count):
				var z := line_z(j) + TILE * float(k + 1)
				var kind := "straight"
				if k == 0 and is_signalized(i, j):
					kind = "xwalk"
				elif k == tile_count - 1 and is_signalized(i, j + 1):
					kind = "xwalk"
				tiles.append({
					"path": road_piece(theme, kind),
					"pos": Vector3(line_x(i), 0.0, z),
					"rot_y": 0.0,
					"group": "VLine_%d" % i,
				})
	return tiles


static func build_h_segment_tiles() -> Array:
	## Straight tiles of all horizontal road lines (rotated 90 deg).
	var h_removed := removed_h_segments()
	var tiles := []
	for j in range(LINES):
		var theme := line_theme(j)
		for i in range(LINES - 1):
			if h_removed.has("%d,%d" % [i, j]):
				continue
			var tile_count := COL_INTERIORS[i] / 8
			for k in range(tile_count):
				var x := line_x(i) + TILE * float(k + 1)
				var kind := "straight"
				if k == 0 and is_signalized(i, j):
					kind = "xwalk"
				elif k == tile_count - 1 and is_signalized(i + 1, j):
					kind = "xwalk"
				tiles.append({
					"path": road_piece(theme, kind),
					"pos": Vector3(x, 0.0, line_z(j)),
					"rot_y": 90.0,
					"group": "HLine_%d" % j,
				})
	return tiles


static func build_intersection_tiles() -> Array:
	var tiles := []
	for i in range(LINES):
		for j in range(LINES):
			var mask := intersection_branches(i, j)
			var bits := _bit_count(mask)
			if bits == 0:
				continue
			var theme := line_theme(i)
			var pos := Vector3(line_x(i), 0.0, line_z(j))
			var kind: String
			var base: int
			if bits == 4:
				kind = "cross"
				base = PIECE_CROSS
			elif bits == 3:
				kind = "t_east"
				base = PIECE_T_EAST
			elif bits == 2 and (mask == (N | S) or mask == (E | W)):
				kind = "straight"
				base = PIECE_STRAIGHT
			elif bits == 2:
				kind = "curve"
				base = PIECE_CURVE
			else:
				kind = "straight"
				base = PIECE_STRAIGHT
				mask = N | S if (mask & (N | S)) else E | W
			var rot := rotation_for(base, mask)
			if rot < 0.0:
				rot = 0.0
			tiles.append({
				"path": road_piece(theme, kind),
				"pos": pos,
				"rot_y": rot,
				"group": "Junctions",
			})
	return tiles


static func build_motorway_tiles() -> Array:
	## Motorway west of the grid. A 2-lane country road enters the map in
	## the south, widens through a taper (2L_1_3) into a 4-lane divided
	## carriageway (2L_1_1 slices), connects to the city at two avenue
	## junctions (2L_1_4, side stub facing east), then narrows back and
	## leaves the map in the north.
	## Slice lattice: carriageway slice centers are multiples of 8, which
	## line_z(3) and line_z(11) also are, so junction pieces (z +/- 12)
	## replace exactly three slices each.
	var tiles := []
	var junction_zs: Array[float] = []
	for row in AVENUE_ROWS:
		junction_zs.append(line_z(row))

	# South country-road tail (spans -84..-60, off the map edge).
	for z_tail in [-80.0, -72.0, -64.0]:
		tiles.append({
			"path": ROADS_DIR + "Road_A_2.glb",
			"pos": Vector3(MOTORWAY_X, 0.0, z_tail),
			"rot_y": 0.0,
			"group": "Motorway",
		})
	# South taper: narrow end south (base has narrow end at -Z -> 180).
	tiles.append({
		"path": ROADS_DIR + "Road_A_2L_1_3.glb",
		"pos": Vector3(MOTORWAY_X, 0.0, -44.0),
		"rot_y": 180.0,
		"group": "Motorway",
	})
	# Main carriageway slices, skipping the three-slice junction footprints.
	var z := -24.0
	while z <= 800.0:
		var in_junction := false
		for jz in junction_zs:
			if absf(z - jz) <= 8.1:
				in_junction = true
		if not in_junction:
			tiles.append({
				"path": ROADS_DIR + "Road_A_2L_1_1.glb",
				"pos": Vector3(MOTORWAY_X, 0.0, z),
				"rot_y": 0.0,
				"group": "Motorway",
			})
		z += TILE
	# Junction pieces: stub faces the city (east).
	for jz in junction_zs:
		tiles.append({
			"path": ROADS_DIR + "Road_A_2L_1_4.glb",
			"pos": Vector3(MOTORWAY_X, 0.0, jz),
			"rot_y": 180.0,
			"group": "Motorway",
		})
	# North taper: narrow end north (base orientation).
	tiles.append({
		"path": ROADS_DIR + "Road_A_2L_1_3.glb",
		"pos": Vector3(MOTORWAY_X, 0.0, 820.0),
		"rot_y": 0.0,
		"group": "Motorway",
	})
	# North country-road tail (spans 836..860, off the map edge).
	for z_tail in [840.0, 848.0, 856.0]:
		tiles.append({
			"path": ROADS_DIR + "Road_A_2.glb",
			"pos": Vector3(MOTORWAY_X, 0.0, z_tail),
			"rot_y": 0.0,
			"group": "Motorway",
		})
	# Avenue connector tiles between junction stub (-36) and grid line 0 (-4).
	for row in AVENUE_ROWS:
		for k in range(4):
			tiles.append({
				"path": road_piece("A", "straight"),
				"pos": Vector3(-32.0 + float(k) * TILE, 0.0, line_z(row)),
				"rot_y": 90.0,
				"group": "Avenues",
			})
	return tiles


static func _bit_count(mask: int) -> int:
	var count := 0
	for bit in [N, S, E, W]:
		if mask & bit:
			count += 1
	return count
