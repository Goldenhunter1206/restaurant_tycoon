@tool
class_name InteriorLayoutState
extends Resource
## Persistent furniture layout of one restaurant interior. The logical grid
## uses 1 m cells with cell (0,0) at world (-11, -9) — see cell_to_world().
## Runtime scene nodes are generated from this state; it is the only copy.

const CELL_SIZE: float = 1.0
## World-space origin of cell (0,0) at expansion level 0.
const ORIGIN_X: float = -11.0
const ORIGIN_Z: float = -9.0
const BASE_COLS: int = 22
const BASE_ROWS: int = 18
## Extra cells added on each expandable side per expansion level.
const EXPAND_STEP: int = 4

@export var expansion_level: int = 0
@export var grid_cols: int = BASE_COLS
@export var grid_rows: int = BASE_ROWS
@export var floor_finish: StringName = &"floor_checker"
@export var wall_finish: StringName = &"wall_cream"
@export var music: StringName = &"music_none"
## Cells reserved as kitchen zone (ovens must be inside).
@export var kitchen_rects: Array[Rect2i] = []
@export var placed: Array[PlacedFurnitureState] = []
## Bumped on every committed edit; views compare it to rebuild.
@export var revision: int = 0
@export var next_instance_id: int = 1


static func cell_to_world(cell: Vector2i, size: Vector2i = Vector2i.ONE) -> Vector3:
	## World-space center of a footprint whose min cell is `cell`.
	return Vector3(
		ORIGIN_X + (float(cell.x) + float(size.x) * 0.5) * CELL_SIZE,
		0.0,
		ORIGIN_Z + (float(cell.y) + float(size.y) * 0.5) * CELL_SIZE)


static func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floorf((pos.x - ORIGIN_X) / CELL_SIZE)),
		int(floorf((pos.z - ORIGIN_Z) / CELL_SIZE)))


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_cols and cell.y < grid_rows


func cells_for(item: PlacedFurnitureState, def: FurnitureDef) -> Array[Vector2i]:
	var size: Vector2i = def.footprint_cells(item.rotation)
	var cells: Array[Vector2i] = []
	for dx: int in range(size.x):
		for dy: int in range(size.y):
			cells.append(item.cell + Vector2i(dx, dy))
	return cells


func find(instance_id: int) -> PlacedFurnitureState:
	for item: PlacedFurnitureState in placed:
		if item.instance_id == instance_id:
			return item
	return null


func add(def_id: StringName, cell: Vector2i, rotation: int = 0, variant: StringName = &"") -> PlacedFurnitureState:
	var item: PlacedFurnitureState = PlacedFurnitureState.new()
	item.instance_id = next_instance_id
	next_instance_id += 1
	item.def_id = def_id
	item.cell = cell
	item.rotation = rotation
	item.variant = variant
	placed.append(item)
	return item


func remove(instance_id: int) -> bool:
	for i: int in range(placed.size()):
		if placed[i].instance_id == instance_id:
			placed.remove_at(i)
			return true
	return false


func in_kitchen(cell: Vector2i) -> bool:
	for rect: Rect2i in kitchen_rects:
		if rect.has_point(cell):
			return true
	return false


func deep_copy() -> InteriorLayoutState:
	var copy: InteriorLayoutState = InteriorLayoutState.new()
	copy.expansion_level = expansion_level
	copy.grid_cols = grid_cols
	copy.grid_rows = grid_rows
	copy.floor_finish = floor_finish
	copy.wall_finish = wall_finish
	copy.music = music
	copy.kitchen_rects = kitchen_rects.duplicate()
	copy.revision = revision
	copy.next_instance_id = next_instance_id
	for item: PlacedFurnitureState in placed:
		copy.placed.append(item.duplicate_state())
	return copy
