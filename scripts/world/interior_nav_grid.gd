class_name InteriorNavGrid
extends RefCounted
## Walkability grid + pathfinding over an InteriorLayoutState. Pure data —
## built from layout state only, no scene access, so validation and the AI
## can run headless. Rebuilt on committed edits, never per-frame.

var cols: int = 0
var rows: int = 0
## cell index (y * cols + x) -> true when walkable.
var _walkable: PackedByteArray = PackedByteArray()
## cell index -> blocking instance_id (0 when free).
var _occupant: PackedInt32Array = PackedInt32Array()


func build(layout: InteriorLayoutState, catalog: Dictionary) -> void:
	cols = layout.grid_cols
	rows = layout.grid_rows
	_walkable.resize(cols * rows)
	_walkable.fill(1)
	_occupant.resize(cols * rows)
	_occupant.fill(0)
	for item: PlacedFurnitureState in layout.placed:
		var def: FurnitureDef = catalog.get(item.def_id)
		if def == null or not def.blocks_walk:
			continue
		for cell: Vector2i in layout.cells_for(item, def):
			if _in_bounds(cell):
				var idx: int = cell.y * cols + cell.x
				_walkable[idx] = 0
				_occupant[idx] = item.instance_id


func is_walkable(cell: Vector2i) -> bool:
	return _in_bounds(cell) and _walkable[cell.y * cols + cell.x] == 1


func occupant(cell: Vector2i) -> int:
	if not _in_bounds(cell):
		return 0
	return _occupant[cell.y * cols + cell.x]


## Every walkable cell reachable from `from` (4-neighbour flood fill).
## Returns a Dictionary used as a set: cell -> true.
func reachable_from(from: Vector2i) -> Dictionary:
	var seen: Dictionary = {}
	if not is_walkable(from):
		return seen
	var frontier: Array[Vector2i] = [from]
	seen[from] = true
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + offset
			if seen.has(next) or not is_walkable(next):
				continue
			seen[next] = true
			frontier.append(next)
	return seen


## True when `cell` (possibly occupied) touches a reachable walkable cell.
func adjacent_reachable(cell: Vector2i, reachable: Dictionary) -> bool:
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if reachable.has(cell + offset):
			return true
	return false


## A* over walkable cells; returns [] when no path exists.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not is_walkable(from) or not is_walkable(to):
		return []
	if from == to:
		return [from]
	var open: Array[Vector2i] = [from]
	var came: Dictionary = {}
	var g_cost: Dictionary = {from: 0}
	while not open.is_empty():
		var best: int = 0
		var best_f: int = _f_cost(open[0], g_cost, to)
		for i: int in range(1, open.size()):
			var f: int = _f_cost(open[i], g_cost, to)
			if f < best_f:
				best_f = f
				best = i
		var current: Vector2i = open[best]
		open.remove_at(best)
		if current == to:
			var path: Array[Vector2i] = [to]
			var walk: Vector2i = to
			while came.has(walk):
				walk = came[walk]
				path.push_front(walk)
			return path
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + offset
			if not is_walkable(next):
				continue
			var cost: int = int(g_cost[current]) + 1
			if g_cost.has(next) and cost >= int(g_cost[next]):
				continue
			g_cost[next] = cost
			came[next] = current
			if not open.has(next):
				open.append(next)
	return []


## Path length in cells between two (possibly occupied) endpoints, routed via
## their nearest reachable neighbours. -1 when disconnected.
func service_distance(from: Vector2i, to: Vector2i, reachable: Dictionary) -> int:
	var start: Vector2i = _nearest_reachable_neighbor(from, reachable)
	var goal: Vector2i = _nearest_reachable_neighbor(to, reachable)
	if start.x < 0 or goal.x < 0:
		return -1
	var path: Array[Vector2i] = find_path(start, goal)
	if path.is_empty():
		return -1
	return path.size()


func _nearest_reachable_neighbor(cell: Vector2i, reachable: Dictionary) -> Vector2i:
	if reachable.has(cell):
		return cell
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if reachable.has(cell + offset):
			return cell + offset
	return Vector2i(-1, -1)


func _f_cost(cell: Vector2i, g_cost: Dictionary, to: Vector2i) -> int:
	return int(g_cost.get(cell, 0)) + absi(cell.x - to.x) + absi(cell.y - to.y)


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows
