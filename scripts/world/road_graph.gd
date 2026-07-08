class_name RoadGraph
extends Resource
## Lane + sidewalk waypoint graph. Generated deterministically from
## CityBuilder grid math (see graph_generator.gd) — never from meshes.
##
## Lanes are DIRECTED edges (right-hand traffic). An edge whose
## `lane_enters` is >= 0 ends on that intersection's stop line; vehicles
## must check the signal phase for `lane_enter_heading` before crossing.
## Sidewalk edges are UNDIRECTED; edges with `side_crossing` >= 0 are
## zebra/corner crossings tied to an intersection and may only be used
## by pedestrians when the conflicting car axis is stopped.

# Heading bits (world): N = -Z, S = +Z, E = +X, W = -X.
const N: int = 1
const S: int = 2
const E: int = 4
const W: int = 8

const AXIS_NONE: int = 0
const AXIS_NS: int = 1   # crossing edge spans a north-south road
const AXIS_EW: int = 2   # crossing edge spans an east-west road

const KIND_SEGMENT: int = 0
const KIND_TURN: int = 1
const KIND_MOTORWAY: int = 2

## Cell size for the node spatial index (ring queries by ambient life,
## leisure strolling). ~4 tiles: big enough that ring scans touch few
## cells, small enough to avoid huge buckets.
const CELL_SIZE: float = 32.0

@export var lane_points: PackedVector3Array
@export var lane_from: PackedInt32Array
@export var lane_to: PackedInt32Array
@export var lane_kind: PackedInt32Array
@export var lane_enters: PackedInt32Array          # intersection id or -1
@export var lane_enter_heading: PackedInt32Array   # heading bit, 0 if none

@export var side_points: PackedVector3Array
@export var side_from: PackedInt32Array
@export var side_to: PackedInt32Array
@export var side_crossing: PackedInt32Array        # intersection id or -1
@export var side_cross_axis: PackedInt32Array      # AXIS_* of the road being crossed

## Per intersection: {id, i, j, pos: Vector3, mask, signalized: bool,
## approaches: {heading_bit: {in: node_id, out: node_id}}}
@export var intersections: Array[Dictionary] = []

# --- runtime lookup (not serialized) ---
var _lane_out: Dictionary = {}        # node id -> Array[edge index]
var _side_adj: Dictionary = {}        # node id -> Array[edge index]
var _lane_edge_by_pair: Dictionary = {}   # "from:to" -> edge index
var _lane_astar := AStar3D.new()
var _side_astar := AStar3D.new()
var _side_cells: Dictionary = {}      # Vector2i cell -> PackedInt32Array side node ids
var _lane_cells: Dictionary = {}      # Vector2i cell -> PackedInt32Array lane node ids
var _runtime_ready: bool = false


func build_runtime() -> void:
	_lane_out.clear()
	_side_adj.clear()
	_lane_edge_by_pair.clear()
	_lane_astar.clear()
	_side_astar.clear()
	_lane_astar.reserve_space(lane_points.size())
	_side_astar.reserve_space(side_points.size())
	for idx in range(lane_points.size()):
		_lane_astar.add_point(idx, lane_points[idx])
	for idx in range(side_points.size()):
		_side_astar.add_point(idx, side_points[idx])
	for e in range(lane_from.size()):
		var from_id := lane_from[e]
		if not _lane_out.has(from_id):
			_lane_out[from_id] = []
		_lane_out[from_id].append(e)
		_lane_edge_by_pair["%d:%d" % [from_id, lane_to[e]]] = e
		_lane_astar.connect_points(from_id, lane_to[e], false)
	for e in range(side_from.size()):
		for node_id in [side_from[e], side_to[e]]:
			if not _side_adj.has(node_id):
				_side_adj[node_id] = []
			_side_adj[node_id].append(e)
		_side_astar.connect_points(side_from[e], side_to[e], true)
	_side_cells.clear()
	_lane_cells.clear()
	for idx in range(side_points.size()):
		_cell_insert(_side_cells, side_points[idx], idx)
	for idx in range(lane_points.size()):
		_cell_insert(_lane_cells, lane_points[idx], idx)
	_runtime_ready = true


func _cell_insert(cells: Dictionary, pos: Vector3, idx: int) -> void:
	var cell := Vector2i(floori(pos.x / CELL_SIZE), floori(pos.z / CELL_SIZE))
	var arr: PackedInt32Array = cells.get(cell, PackedInt32Array())
	arr.append(idx)
	cells[cell] = arr


func lane_out_edges(node_id: int) -> Array:
	return _lane_out.get(node_id, [])


func side_edges(node_id: int) -> Array:
	return _side_adj.get(node_id, [])


func side_other_end(edge: int, node_id: int) -> int:
	return side_to[edge] if side_from[edge] == node_id else side_from[edge]


func nearest_lane_node(pos: Vector3) -> int:
	if not _runtime_ready:
		build_runtime()
	return int(_lane_astar.get_closest_point(pos))


func nearest_side_node(pos: Vector3) -> int:
	if not _runtime_ready:
		build_runtime()
	return int(_side_astar.get_closest_point(pos))


func find_lane_path(start_node: int, goal_node: int) -> PackedInt32Array:
	## A* over directed lane edges (native AStar3D). Returns node ids
	## incl. start + goal, empty if unreachable.
	if not _runtime_ready:
		build_runtime()
	if start_node < 0 or goal_node < 0:
		return PackedInt32Array()
	var ids := _lane_astar.get_id_path(start_node, goal_node)
	var out := PackedInt32Array()
	for node_id in ids:
		out.append(int(node_id))
	return out


func find_side_path(start_node: int, goal_node: int) -> PackedInt32Array:
	if not _runtime_ready:
		build_runtime()
	if start_node < 0 or goal_node < 0:
		return PackedInt32Array()
	var ids := _side_astar.get_id_path(start_node, goal_node)
	var out := PackedInt32Array()
	for node_id in ids:
		out.append(int(node_id))
	return out


func side_nodes_near(pos: Vector3, min_d: float, max_d: float) -> PackedInt32Array:
	## Sidewalk node ids in the ring [min_d, max_d] around pos (XZ plane).
	if not _runtime_ready:
		build_runtime()
	return _nodes_near(_side_cells, side_points, pos, min_d, max_d)


func lane_nodes_near(pos: Vector3, min_d: float, max_d: float) -> PackedInt32Array:
	## Lane node ids in the ring [min_d, max_d] around pos (XZ plane).
	if not _runtime_ready:
		build_runtime()
	return _nodes_near(_lane_cells, lane_points, pos, min_d, max_d)


func _nodes_near(cells: Dictionary, points: PackedVector3Array, pos: Vector3, min_d: float, max_d: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r := int(ceil(max_d / CELL_SIZE))
	var cx := floori(pos.x / CELL_SIZE)
	var cz := floori(pos.z / CELL_SIZE)
	var min_sq := min_d * min_d
	var max_sq := max_d * max_d
	for ix in range(cx - r, cx + r + 1):
		for iz in range(cz - r, cz + r + 1):
			var bucket: PackedInt32Array = cells.get(Vector2i(ix, iz), PackedInt32Array())
			for node_id in bucket:
				var dx := points[node_id].x - pos.x
				var dz := points[node_id].z - pos.z
				var d_sq := dx * dx + dz * dz
				if d_sq >= min_sq and d_sq <= max_sq:
					out.append(node_id)
	return out


func lane_edge_between(from_id: int, to_id: int) -> int:
	if not _runtime_ready:
		build_runtime()
	return _lane_edge_by_pair.get("%d:%d" % [from_id, to_id], -1)


func get_intersection(inter_id: int) -> Dictionary:
	if inter_id >= 0 and inter_id < intersections.size():
		return intersections[inter_id]
	return {}


func lane_astar() -> AStar3D:
	if not _runtime_ready:
		build_runtime()
	return _lane_astar


func side_astar() -> AStar3D:
	if not _runtime_ready:
		build_runtime()
	return _side_astar
