class_name GraphGenerator
extends RefCounted
## Builds the RoadGraph from CityBuilder grid math. Run once from the
## editor (godotiq exec) and serialized to res://data/road_graph.tres.

const LANE_OFF: float = 1.6          # half-lane offset from road centerline
const M_LANE_OFF: float = 3.6        # motorway carriageway offset
const STOP_SIG: float = 11.0         # stop line before the zebra tile
const STOP_PLAIN: float = 6.0
const STOP_M: float = 14.0
const EXIT_CITY: float = 4.5
const EXIT_M: float = 12.0
const SIDE_OFF: float = 5.6          # walk line: centered in the clear half of the 4.0..7.0 pavement band
const CROSS_SIG: float = 8.0         # zebra crossing distance from center
const CROSS_PLAIN: float = 6.0
const LANE_Y: float = 0.2
const SIDE_Y: float = 0.42

const RoadGraphRes := preload("res://scripts/world/road_graph.gd")

const N: int = 1
const S: int = 2
const E: int = 4
const W: int = 8
const AXIS_NONE: int = 0
const AXIS_NS: int = 1
const AXIS_EW: int = 2
const KIND_SEGMENT: int = 0
const KIND_TURN: int = 1
const KIND_MOTORWAY: int = 2


static func dir_vec(bit: int) -> Vector3:
	match bit:
		N: return Vector3(0, 0, -1)
		S: return Vector3(0, 0, 1)
		E: return Vector3(1, 0, 0)
		_: return Vector3(-1, 0, 0)


static func right_vec(bit: int) -> Vector3:
	var h := dir_vec(bit)
	return Vector3(-h.z, 0, h.x)


static func opp(bit: int) -> int:
	match bit:
		N: return S
		S: return N
		E: return W
		_: return E


static func build() -> Resource:
	var g: Resource = RoadGraphRes.new()
	var inters: Array[Dictionary] = []

	# --- 1. Intersection records --------------------------------------
	var id_by_grid := {}
	for i in range(CityBuilder.LINES):
		for j in range(CityBuilder.LINES):
			var mask := CityBuilder.intersection_branches(i, j)
			if mask == 0:
				continue
			var rec := {
				"id": inters.size(), "i": i, "j": j,
				"pos": Vector3(CityBuilder.line_x(i), LANE_Y, CityBuilder.line_z(j)),
				"mask": mask,
				"signalized": CityBuilder.is_signalized(i, j),
				"motorway": false,
				"approaches": {},
			}
			id_by_grid["%d,%d" % [i, j]] = rec["id"]
			inters.append(rec)
	var mj_ids: Array[int] = []
	for row in CityBuilder.AVENUE_ROWS:
		var rec := {
			"id": inters.size(), "i": -1, "j": row,
			"pos": Vector3(CityBuilder.MOTORWAY_X, LANE_Y, CityBuilder.line_z(row)),
			"mask": N | S | E,
			"signalized": false,
			"motorway": true,
			"approaches": {},
		}
		mj_ids.append(rec["id"])
		inters.append(rec)

	# --- 2. Approach in/out lane nodes --------------------------------
	for rec: Dictionary in inters:
		var mask: int = rec["mask"]
		var pos: Vector3 = rec["pos"]
		for d in [N, S, E, W]:
			if not (mask & d):
				continue
			var off := LANE_OFF
			var stop := STOP_SIG if rec["signalized"] else STOP_PLAIN
			var exit_d := EXIT_CITY
			if rec["motorway"]:
				stop = STOP_M
				exit_d = EXIT_M
				if d == N or d == S:
					off = M_LANE_OFF
			var in_pos: Vector3 = pos + dir_vec(d) * stop + right_vec(opp(d)) * off
			var out_pos: Vector3 = pos + dir_vec(d) * exit_d + right_vec(d) * off
			var in_id: int = g.lane_points.size()
			g.lane_points.append(in_pos)
			var out_id: int = g.lane_points.size()
			g.lane_points.append(out_pos)
			rec["approaches"][d] = {"in": in_id, "out": out_id}

	# --- 3. Turn edges (IN of branch d -> OUT of branch d2) -----------
	for rec: Dictionary in inters:
		var mask: int = rec["mask"]
		for d in [N, S, E, W]:
			if not (mask & d):
				continue
			for d2 in [N, S, E, W]:
				if d2 == d or not (mask & d2):
					continue
				_lane_edge(g, rec["approaches"][d]["in"], rec["approaches"][d2]["out"],
					KIND_TURN, -1, 0)

	# --- 4. Segment edges ----------------------------------------------
	var v_removed := CityBuilder.removed_v_segments()
	var h_removed := CityBuilder.removed_h_segments()
	for i in range(CityBuilder.LINES):
		for j in range(CityBuilder.LINES - 1):
			if v_removed.has("%d,%d" % [i, j]):
				continue
			var p: Dictionary = inters[id_by_grid["%d,%d" % [i, j]]]
			var q: Dictionary = inters[id_by_grid["%d,%d" % [i, j + 1]]]
			_lane_edge(g, p["approaches"][S]["out"], q["approaches"][N]["in"],
				KIND_SEGMENT, q["id"], S)
			_lane_edge(g, q["approaches"][N]["out"], p["approaches"][S]["in"],
				KIND_SEGMENT, p["id"], N)
	for j in range(CityBuilder.LINES):
		for i in range(CityBuilder.LINES - 1):
			if h_removed.has("%d,%d" % [i, j]):
				continue
			var p: Dictionary = inters[id_by_grid["%d,%d" % [i, j]]]
			var q: Dictionary = inters[id_by_grid["%d,%d" % [i + 1, j]]]
			_lane_edge(g, p["approaches"][E]["out"], q["approaches"][W]["in"],
				KIND_SEGMENT, q["id"], E)
			_lane_edge(g, q["approaches"][W]["out"], p["approaches"][E]["in"],
				KIND_SEGMENT, p["id"], W)
	# Avenue segments: motorway junction E branch <-> city (0, row) W branch.
	for idx in range(CityBuilder.AVENUE_ROWS.size()):
		var row: int = CityBuilder.AVENUE_ROWS[idx]
		var mj: Dictionary = inters[mj_ids[idx]]
		var c: Dictionary = inters[id_by_grid["0,%d" % row]]
		_lane_edge(g, mj["approaches"][E]["out"], c["approaches"][W]["in"],
			KIND_SEGMENT, c["id"], E)
		_lane_edge(g, c["approaches"][W]["out"], mj["approaches"][E]["in"],
			KIND_SEGMENT, mj["id"], W)

	# --- 5. Motorway chains ---------------------------------------------
	var mx := CityBuilder.MOTORWAY_X
	var mj0: Dictionary = inters[mj_ids[0]]
	var mj1: Dictionary = inters[mj_ids[1]]
	# Downbound (+Z, heading S) on the west carriageway.
	var down_pts := [
		Vector3(mx - LANE_OFF, LANE_Y, -84), Vector3(mx - LANE_OFF, LANE_Y, -60),
		Vector3(mx - M_LANE_OFF, LANE_Y, -28),
	]
	var down_ids := _chain_nodes(g, down_pts)
	_lane_edge(g, down_ids[0], down_ids[1], KIND_MOTORWAY, -1, 0)
	_lane_edge(g, down_ids[1], down_ids[2], KIND_MOTORWAY, -1, 0)
	_lane_edge(g, down_ids[2], mj0["approaches"][N]["in"], KIND_MOTORWAY, mj0["id"], S)
	_lane_edge(g, mj0["approaches"][S]["out"], mj1["approaches"][N]["in"], KIND_MOTORWAY, mj1["id"], S)
	var down_exit := [
		Vector3(mx - M_LANE_OFF, LANE_Y, 804), Vector3(mx - LANE_OFF, LANE_Y, 836),
		Vector3(mx - LANE_OFF, LANE_Y, 860),
	]
	var dx_ids := _chain_nodes(g, down_exit)
	_lane_edge(g, mj1["approaches"][S]["out"], dx_ids[0], KIND_MOTORWAY, -1, 0)
	_lane_edge(g, dx_ids[0], dx_ids[1], KIND_MOTORWAY, -1, 0)
	_lane_edge(g, dx_ids[1], dx_ids[2], KIND_MOTORWAY, -1, 0)
	# Upbound (-Z, heading N) on the east carriageway.
	var up_pts := [
		Vector3(mx + LANE_OFF, LANE_Y, 860), Vector3(mx + LANE_OFF, LANE_Y, 836),
		Vector3(mx + M_LANE_OFF, LANE_Y, 804),
	]
	var up_ids := _chain_nodes(g, up_pts)
	_lane_edge(g, up_ids[0], up_ids[1], KIND_MOTORWAY, -1, 0)
	_lane_edge(g, up_ids[1], up_ids[2], KIND_MOTORWAY, -1, 0)
	_lane_edge(g, up_ids[2], mj1["approaches"][S]["in"], KIND_MOTORWAY, mj1["id"], N)
	_lane_edge(g, mj1["approaches"][N]["out"], mj0["approaches"][S]["in"], KIND_MOTORWAY, mj0["id"], N)
	var up_exit := [
		Vector3(mx + M_LANE_OFF, LANE_Y, -28), Vector3(mx + LANE_OFF, LANE_Y, -60),
		Vector3(mx + LANE_OFF, LANE_Y, -84),
	]
	var ux_ids := _chain_nodes(g, up_exit)
	_lane_edge(g, mj0["approaches"][N]["out"], ux_ids[0], KIND_MOTORWAY, -1, 0)
	_lane_edge(g, ux_ids[0], ux_ids[1], KIND_MOTORWAY, -1, 0)
	_lane_edge(g, ux_ids[1], ux_ids[2], KIND_MOTORWAY, -1, 0)

	# --- 6. Sidewalks (city grid only) ----------------------------------
	var side_ids := {}
	for i in range(CityBuilder.LINES):
		for j in range(CityBuilder.LINES - 1):
			if v_removed.has("%d,%d" % [i, j]):
				continue
			var p: Dictionary = inters[id_by_grid["%d,%d" % [i, j]]]
			var q: Dictionary = inters[id_by_grid["%d,%d" % [i, j + 1]]]
			var x := CityBuilder.line_x(i)
			var zc0: float = CityBuilder.line_z(j) + _cross_off(p)
			var zc1: float = CityBuilder.line_z(j + 1) - _cross_off(q)
			for side: float in [-1.0, 1.0]:
				var sx: float = x + side * SIDE_OFF
				_side_chain(g, side_ids, [
					Vector3(sx, SIDE_Y, CityBuilder.line_z(j) + SIDE_OFF),
					Vector3(sx, SIDE_Y, zc0),
					Vector3(sx, SIDE_Y, zc1),
					Vector3(sx, SIDE_Y, CityBuilder.line_z(j + 1) - SIDE_OFF),
				])
			_cross_edge(g, side_ids, Vector3(x - SIDE_OFF, SIDE_Y, zc0),
				Vector3(x + SIDE_OFF, SIDE_Y, zc0), p["id"], AXIS_NS)
			_cross_edge(g, side_ids, Vector3(x - SIDE_OFF, SIDE_Y, zc1),
				Vector3(x + SIDE_OFF, SIDE_Y, zc1), q["id"], AXIS_NS)
	for j in range(CityBuilder.LINES):
		for i in range(CityBuilder.LINES - 1):
			if h_removed.has("%d,%d" % [i, j]):
				continue
			var p: Dictionary = inters[id_by_grid["%d,%d" % [i, j]]]
			var q: Dictionary = inters[id_by_grid["%d,%d" % [i + 1, j]]]
			var z := CityBuilder.line_z(j)
			var xc0: float = CityBuilder.line_x(i) + _cross_off(p)
			var xc1: float = CityBuilder.line_x(i + 1) - _cross_off(q)
			for side: float in [-1.0, 1.0]:
				var sz: float = z + side * SIDE_OFF
				_side_chain(g, side_ids, [
					Vector3(CityBuilder.line_x(i) + SIDE_OFF, SIDE_Y, sz),
					Vector3(xc0, SIDE_Y, sz),
					Vector3(xc1, SIDE_Y, sz),
					Vector3(CityBuilder.line_x(i + 1) - SIDE_OFF, SIDE_Y, sz),
				])
			_cross_edge(g, side_ids, Vector3(xc0, SIDE_Y, z - SIDE_OFF),
				Vector3(xc0, SIDE_Y, z + SIDE_OFF), p["id"], AXIS_EW)
			_cross_edge(g, side_ids, Vector3(xc1, SIDE_Y, z - SIDE_OFF),
				Vector3(xc1, SIDE_Y, z + SIDE_OFF), q["id"], AXIS_EW)
	# Through-edges where a branch is missing (T junctions): the sidewalk
	# continues straight past the intersection face with no road to cross.
	for rec: Dictionary in inters:
		if rec["motorway"]:
			continue
		var mask: int = rec["mask"]
		var px: float = rec["pos"].x
		var pz: float = rec["pos"].z
		if not (mask & E) and (mask & N) and (mask & S):
			_plain_edge(g, side_ids, Vector3(px + SIDE_OFF, SIDE_Y, pz - SIDE_OFF),
				Vector3(px + SIDE_OFF, SIDE_Y, pz + SIDE_OFF))
		if not (mask & W) and (mask & N) and (mask & S):
			_plain_edge(g, side_ids, Vector3(px - SIDE_OFF, SIDE_Y, pz - SIDE_OFF),
				Vector3(px - SIDE_OFF, SIDE_Y, pz + SIDE_OFF))
		if not (mask & N) and (mask & E) and (mask & W):
			_plain_edge(g, side_ids, Vector3(px - SIDE_OFF, SIDE_Y, pz - SIDE_OFF),
				Vector3(px + SIDE_OFF, SIDE_Y, pz - SIDE_OFF))
		if not (mask & S) and (mask & E) and (mask & W):
			_plain_edge(g, side_ids, Vector3(px - SIDE_OFF, SIDE_Y, pz + SIDE_OFF),
				Vector3(px + SIDE_OFF, SIDE_Y, pz + SIDE_OFF))

	g.intersections = inters
	return g


static func _cross_off(rec: Dictionary) -> float:
	return CROSS_SIG if rec["signalized"] else CROSS_PLAIN


static func _lane_edge(g: RoadGraph, from_id: int, to_id: int, kind: int, enters: int, heading: int) -> void:
	g.lane_from.append(from_id)
	g.lane_to.append(to_id)
	g.lane_kind.append(kind)
	g.lane_enters.append(enters)
	g.lane_enter_heading.append(heading)


static func _chain_nodes(g: RoadGraph, points: Array) -> Array[int]:
	var ids: Array[int] = []
	for p: Vector3 in points:
		ids.append(g.lane_points.size())
		g.lane_points.append(p)
	return ids


static func _side_node(g: RoadGraph, side_ids: Dictionary, pos: Vector3) -> int:
	var key := "%.1f|%.1f" % [pos.x, pos.z]
	if side_ids.has(key):
		return side_ids[key]
	var node_id := g.side_points.size()
	g.side_points.append(pos)
	side_ids[key] = node_id
	return node_id


static func _side_chain(g: RoadGraph, side_ids: Dictionary, points: Array) -> void:
	for idx in range(points.size() - 1):
		_plain_edge(g, side_ids, points[idx], points[idx + 1])


static func _plain_edge(g: RoadGraph, side_ids: Dictionary, a: Vector3, b: Vector3) -> void:
	if a.distance_squared_to(b) < 0.01:
		return
	var a_id := _side_node(g, side_ids, a)
	var b_id := _side_node(g, side_ids, b)
	g.side_from.append(a_id)
	g.side_to.append(b_id)
	g.side_crossing.append(-1)
	g.side_cross_axis.append(AXIS_NONE)


static func _cross_edge(g: RoadGraph, side_ids: Dictionary, a: Vector3, b: Vector3, inter_id: int, axis: int) -> void:
	var a_id := _side_node(g, side_ids, a)
	var b_id := _side_node(g, side_ids, b)
	g.side_from.append(a_id)
	g.side_to.append(b_id)
	g.side_crossing.append(inter_id)
	g.side_cross_axis.append(axis)
