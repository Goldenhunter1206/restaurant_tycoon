class_name ParkingRegistry
extends RefCounted
## Legal curb-parking slots derived from the lane graph: straight city
## segments only (never turn/intersection edges or motorways), clear of
## corners/zebras, one car per slot. Slots blocked by the decorative
## ParkedCarPlacer fleet are marked occupied at init so dynamic cars
## never park inside a static one.

const SLOT_SPACING: float = 5.5    # matches ParkedCarPlacer spacing
const CORNER_CLEAR: float = 7.0    # keep clear of intersections / crosswalks
const CURB_OFFSET: float = 1.65    # lane centre -> parked-car centre (kerb side)
const CELL: float = 24.0
const STATIC_BLOCK_RADIUS: float = 3.0

var slot_lane_point: PackedVector3Array = PackedVector3Array()
var slot_pos: PackedVector3Array = PackedVector3Array()
var slot_heading: PackedVector3Array = PackedVector3Array()
var slot_edge: PackedInt32Array = PackedInt32Array()

## slot id -> holder instance id (0 = permanently blocked by static decor).
var _occupied: Dictionary = {}
var _cells: Dictionary = {}   # Vector2i -> PackedInt32Array of slot ids


func build(graph: RoadGraph) -> void:
	for e in range(graph.lane_from.size()):
		if graph.lane_kind[e] != RoadGraph.KIND_SEGMENT:
			continue
		var p0 := graph.lane_points[graph.lane_from[e]]
		var p1 := graph.lane_points[graph.lane_to[e]]
		var seg := p1 - p0
		seg.y = 0.0
		var seg_len := seg.length()
		if seg_len < 2.0 * CORNER_CLEAR + SLOT_SPACING:
			continue
		var dir := seg / seg_len
		var right := Vector3(-dir.z, 0.0, dir.x)
		var t := CORNER_CLEAR
		while t <= seg_len - CORNER_CLEAR:
			var lane_pt := p0 + dir * t
			var id := slot_pos.size()
			slot_lane_point.append(lane_pt)
			slot_pos.append(lane_pt + right * CURB_OFFSET)
			slot_heading.append(dir)
			slot_edge.append(e)
			_cell_insert(slot_pos[id], id)
			t += SLOT_SPACING


func _cell_insert(pos: Vector3, id: int) -> void:
	var cell := Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))
	var arr: PackedInt32Array = _cells.get(cell, PackedInt32Array())
	arr.append(id)
	_cells[cell] = arr


func block_static_at(pos: Vector3) -> void:
	## Mark the slot a static decorative car sits in as permanently taken.
	var id := _nearest_slot(pos, STATIC_BLOCK_RADIUS, false)
	if id >= 0:
		_occupied[id] = 0


func reserve_near(pos: Vector3, max_radius: float, holder: int) -> int:
	## Nearest free slot within max_radius, reserved for holder; -1 if none.
	var id := _nearest_slot(pos, max_radius, true)
	if id >= 0:
		_occupied[id] = holder
	return id


func release(slot_id: int, holder: int) -> void:
	if slot_id >= 0 and int(_occupied.get(slot_id, -1)) == holder:
		_occupied.erase(slot_id)


func _nearest_slot(pos: Vector3, max_radius: float, must_be_free: bool) -> int:
	var span := int(ceilf(max_radius / CELL))
	var center := Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))
	var best := -1
	var best_sq := max_radius * max_radius
	for cx in range(center.x - span, center.x + span + 1):
		for cz in range(center.y - span, center.y + span + 1):
			var bucket: PackedInt32Array = _cells.get(Vector2i(cx, cz), PackedInt32Array())
			for id in bucket:
				if must_be_free and _occupied.has(id):
					continue
				var dx := slot_pos[id].x - pos.x
				var dz := slot_pos[id].z - pos.z
				var d_sq := dx * dx + dz * dz
				if d_sq < best_sq:
					best_sq = d_sq
					best = id
	return best
