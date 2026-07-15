class_name InteriorLayoutService
extends RefCounted
## Pure-data brain of editable interiors: furniture catalog, default layout
## generation, evaluation (capacity / appeal / flow) and validation. Owned by
## RestaurantManager as `interior`. Deliberately scene-free so AI rivals and
## headless checks run the exact same logic as the player editor.

const CATALOG_DIR: String = "res://data/furniture"
const FINISH_DIR: String = "res://data/interior_finishes"
const TEMPLATE_DIR: String = "res://data/interior_templates"
## Waiters fan out from the pass between kitchen and dining.
const SERVE_CELL: Vector2i = Vector2i(11, 5)
## Column of the entrance door on the front wall; the row tracks expansion.
const DOOR_COL: int = 3
## Waiting spots along the entry wall are architectural, not furniture.
const BASE_QUEUE_CAPACITY: int = 6
## Kitchen zone of the base room: the strip behind the pass counter.
const BASE_KITCHEN_RECT: Rect2i = Rect2i(0, 0, 22, 3)

## Authored-stage dining spots (min cell of a 1x1 table; chairs at row +/- 1).
## First 8 mirror the old fixed interior; the rest extend the pattern for
## legacy restaurants whose table_count exceeded the old visual cap.
const TABLE_SPOTS: Array[Vector2i] = [
	Vector2i(3, 7), Vector2i(7, 7), Vector2i(13, 7), Vector2i(18, 7),
	Vector2i(3, 11), Vector2i(7, 11), Vector2i(13, 11), Vector2i(18, 11),
	Vector2i(3, 14), Vector2i(7, 14), Vector2i(13, 14), Vector2i(18, 14),
	Vector2i(5, 7), Vector2i(9, 7), Vector2i(15, 7),
	Vector2i(5, 11), Vector2i(9, 11), Vector2i(15, 11),
	Vector2i(5, 14), Vector2i(9, 14), Vector2i(15, 14),
	Vector2i(3, 5), Vector2i(7, 5), Vector2i(13, 5),
]
## Oven / prep column pairs of the four authored kitchen stations (row 0).
const STATION_COLS: Array[int] = [4, 8, 12, 16]

var catalog: Dictionary = {}
## Finish defs by id (floors, walls, music).
var finishes: Dictionary = {}
## Designer templates by id.
var templates: Dictionary = {}


func load_catalog() -> void:
	catalog.clear()
	var dir: DirAccess = DirAccess.open(CATALOG_DIR)
	if dir == null:
		push_warning("InteriorLayoutService: missing catalog dir %s" % CATALOG_DIR)
		return
	for file: String in dir.get_files():
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var def: FurnitureDef = load("%s/%s" % [CATALOG_DIR, file]) as FurnitureDef
		if def != null and def.id != &"":
			catalog[def.id] = def
	finishes.clear()
	var fin_dir: DirAccess = DirAccess.open(FINISH_DIR)
	if fin_dir != null:
		for file: String in fin_dir.get_files():
			if not (file.ends_with(".tres") or file.ends_with(".res")):
				continue
			var fin: InteriorFinishDef = load("%s/%s" % [FINISH_DIR, file]) as InteriorFinishDef
			if fin != null and fin.id != &"":
				finishes[fin.id] = fin
	templates.clear()
	var tpl_dir: DirAccess = DirAccess.open(TEMPLATE_DIR)
	if tpl_dir != null:
		for file: String in tpl_dir.get_files():
			if not (file.ends_with(".tres") or file.ends_with(".res")):
				continue
			var tpl: InteriorTemplateDef = load("%s/%s" % [TEMPLATE_DIR, file]) as InteriorTemplateDef
			if tpl != null and tpl.id != &"":
				templates[tpl.id] = tpl


func template_for(template_id: StringName) -> InteriorTemplateDef:
	return templates.get(template_id)


## Templates the given company may apply right now (capability-gated).
func templates_available(company_id: StringName) -> Array[InteriorTemplateDef]:
	var result: Array[InteriorTemplateDef] = []
	for tpl: InteriorTemplateDef in templates.values():
		if tpl.prereq_cap == &"" or CapabilityRegistry.has(company_id, tpl.prereq_cap):
			result.append(tpl)
	result.sort_custom(func(a: InteriorTemplateDef, b: InteriorTemplateDef) -> bool: return a.design_fee < b.design_fee)
	return result


## Drops placements whose definitions no longer exist in the catalog and
## credits a flat scrap refund per removed item (spec: missing content must
## never break a save). Returns {removed: int, refund: float}.
func reconcile_catalog(layout: InteriorLayoutState) -> Dictionary:
	var removed: int = 0
	var refund: float = 0.0
	for i: int in range(layout.placed.size() - 1, -1, -1):
		var item: PlacedFurnitureState = layout.placed[i]
		if not catalog.has(item.def_id):
			layout.placed.remove_at(i)
			removed += 1
			refund += 60.0
	if not finishes.has(layout.floor_finish):
		layout.floor_finish = &"floor_checker"
	if not finishes.has(layout.wall_finish):
		layout.wall_finish = &"wall_cream"
	if not finishes.has(layout.music):
		layout.music = &"music_none"
	return {"removed": removed, "refund": refund}


## Headless template pick for AI branches: the priciest set the company can
## afford (furniture delta + fee within budget) that passes validation.
func choose_template_for(rest: RestaurantState, budget: float) -> InteriorTemplateDef:
	var best: InteriorTemplateDef = null
	var best_value: float = -INF
	for tpl: InteriorTemplateDef in templates_available(rest.company_id):
		var draft: InteriorLayoutState = tpl.build_layout()
		var ev: InteriorEvaluation = evaluate(draft)
		if not ev.is_valid():
			continue
		var diff: Dictionary = price_diff(rest.interior_layout if rest.interior_layout != null else InteriorLayoutState.new(), draft)
		var total: float = float(diff["net"]) + tpl.design_fee
		if total > budget:
			continue
		var appeal_sum: float = 0.0
		for value: float in ev.segment_appeal.values():
			appeal_sum += value
		if appeal_sum > best_value:
			best_value = appeal_sum
			best = tpl
	return best


func finish_for(finish_id: StringName) -> InteriorFinishDef:
	return finishes.get(finish_id)


func finishes_by_kind(kind: StringName) -> Array[InteriorFinishDef]:
	var result: Array[InteriorFinishDef] = []
	for fin: InteriorFinishDef in finishes.values():
		if fin.kind == kind:
			result.append(fin)
	result.sort_custom(func(a: InteriorFinishDef, b: InteriorFinishDef) -> bool: return a.price < b.price)
	return result


func def_for(def_id: StringName) -> FurnitureDef:
	return catalog.get(def_id)


func catalog_by_category(category: StringName) -> Array[FurnitureDef]:
	var result: Array[FurnitureDef] = []
	for def: FurnitureDef in catalog.values():
		if def.category == category:
			result.append(def)
	result.sort_custom(func(a: FurnitureDef, b: FurnitureDef) -> bool: return a.price < b.price)
	return result


# --- Default layout ----------------------------------------------------------


## Recreates the old fixed interior as placed furniture. Honors the
## restaurant's pre-existing table_count so legacy saves keep their capacity.
func default_layout_for(rest: RestaurantState) -> InteriorLayoutState:
	var layout: InteriorLayoutState = InteriorLayoutState.new()
	layout.kitchen_rects = [BASE_KITCHEN_RECT] as Array[Rect2i]
	# Kitchen stations: oven + prep counter pairs along the back wall.
	var chair_defs: Array[StringName] = [&"chair_simple", &"chair_padded", &"chair_modern"]
	var table_defs: Array[StringName] = [&"table_diner", &"table_bistro", &"table_cafe"]
	for col: int in STATION_COLS:
		layout.add(&"oven", Vector2i(col, 0), 0)
		layout.add(&"range_hood", Vector2i(col, 0), 0)
		layout.add(&"prep_table", Vector2i(col + 1, 0), 0)
	layout.add(&"sink", Vector2i(20, 0), 0)
	layout.add(&"coffee_machine", Vector2i(1, 0), 0)
	# Pass counter divider between kitchen and dining.
	for col: int in range(5, 16):
		layout.add(&"counter", Vector2i(col, 3), 0)
	# Pickup counters near the door for delivery drivers.
	for i: int in range(4):
		layout.add(&"pickup_counter", Vector2i(15 + i, 16), 0)
	# Dining spots: one table + two facing chairs each.
	var wanted: int = clampi(rest.table_count, 0, TABLE_SPOTS.size())
	for i: int in range(wanted):
		var spot: Vector2i = TABLE_SPOTS[i]
		layout.add(table_defs[i % table_defs.size()], spot, 0)
		layout.add(chair_defs[i % chair_defs.size()], spot + Vector2i(0, 1), 180)
		layout.add(chair_defs[i % chair_defs.size()], spot + Vector2i(0, -1), 0)
	layout.revision = 1
	return layout


# --- Evaluation ---------------------------------------------------------------


func evaluate(layout: InteriorLayoutState) -> InteriorEvaluation:
	var ev: InteriorEvaluation = InteriorEvaluation.new()
	var nav: InteriorNavGrid = InteriorNavGrid.new()
	nav.build(layout, catalog)
	var reachable: Dictionary = nav.reachable_from(door_cell(layout))
	if reachable.is_empty():
		ev.issues.append({
			"code": &"entrance_blocked",
			"instance_id": nav.occupant(door_cell(layout)),
			"message": "The entrance is blocked.",
			"blocking": true,
		})
	# Cell -> item index for pairing lookups.
	var cell_owner: Dictionary = {}
	for item: PlacedFurnitureState in layout.placed:
		var def: FurnitureDef = catalog.get(item.def_id)
		if def == null:
			continue
		for cell: Vector2i in layout.cells_for(item, def):
			if def.blocks_walk:
				cell_owner[cell] = item
			if not layout.in_bounds(cell):
				ev.issues.append({
					"code": &"out_of_bounds",
					"instance_id": item.instance_id,
					"message": "%s is outside the room." % def.display_name,
					"blocking": true,
				})
				break
	var tables: Array[PlacedFurnitureState] = []
	var seat_items: Array[PlacedFurnitureState] = []
	var ovens: Array[PlacedFurnitureState] = []
	var pickups: Array[PlacedFurnitureState] = []
	var styled: Dictionary = {}
	var styled_total: int = 0
	var condition_sum: float = 0.0
	for item: PlacedFurnitureState in layout.placed:
		var def: FurnitureDef = catalog.get(item.def_id)
		if def == null or not item.enabled:
			continue
		ev.furniture_value += def.price
		condition_sum += item.condition()
		ev.menu_capacity += def.menu_capacity
		ev.queue_capacity += def.queue_capacity
		ev.entertainment += def.entertainment * item.condition()
		if def.is_table:
			tables.append(item)
		if def.seats > 0:
			seat_items.append(item)
		if def.cook_slots > 0:
			ovens.append(item)
		if def.pickup_slots > 0:
			pickups.append(item)
		for tag: StringName in def.style_tags:
			styled[tag] = int(styled.get(tag, 0)) + 1
			styled_total += 1
	ev.queue_capacity += BASE_QUEUE_CAPACITY
	if not layout.placed.is_empty():
		ev.condition = condition_sum / float(layout.placed.size())
	# Style coherence.
	for tag: StringName in styled:
		if int(styled[tag]) > int(styled.get(ev.dominant_style, 0)):
			ev.dominant_style = tag
	if styled_total > 0:
		ev.style_coherence = float(styled.get(ev.dominant_style, 0)) / float(styled_total)
	# Seat -> table pairing: a seat serves the table its facing cell touches.
	var comfort_sum: float = 0.0
	for seat: PlacedFurnitureState in seat_items:
		var seat_def: FurnitureDef = catalog.get(seat.def_id)
		# Probe every cell just beyond the seat's facing edge (multi-cell
		# sofas face with their whole edge, not a single cell).
		var owner: PlacedFurnitureState = null
		var offset: Vector2i = facing_offset(seat.rotation)
		for cell: Vector2i in layout.cells_for(seat, seat_def):
			var probe: PlacedFurnitureState = cell_owner.get(cell + offset)
			if probe != null and probe != seat:
				owner = probe
				break
		if owner == null:
			continue
		var owner_def: FurnitureDef = catalog.get(owner.def_id)
		if owner_def == null or not owner_def.is_table:
			continue
		if not nav.adjacent_reachable(seat.cell, reachable):
			ev.issues.append({
				"code": &"seat_unreachable",
				"instance_id": seat.instance_id,
				"message": "%s cannot be reached." % seat_def.display_name,
				"blocking": false,
			})
			continue
		var list: Array = ev.table_seats.get(owner.instance_id, [])
		list.append(seat.instance_id)
		ev.table_seats[owner.instance_id] = list
		ev.seats += seat_def.seats
		comfort_sum += seat_def.comfort * seat.condition()
	if ev.seats > 0:
		ev.comfort = comfort_sum / float(ev.seats)
	# Usable tables need at least one paired seat and waiter access.
	for table: PlacedFurnitureState in tables:
		var table_def: FurnitureDef = catalog.get(table.def_id)
		if not ev.table_seats.has(table.instance_id):
			ev.issues.append({
				"code": &"table_no_seats",
				"instance_id": table.instance_id,
				"message": "%s has no chairs." % table_def.display_name,
				"blocking": false,
			})
			continue
		var accessible: bool = false
		for cell: Vector2i in layout.cells_for(table, table_def):
			if nav.adjacent_reachable(cell, reachable):
				accessible = true
				break
		if not accessible:
			ev.table_seats.erase(table.instance_id)
			ev.issues.append({
				"code": &"table_unreachable",
				"instance_id": table.instance_id,
				"message": "Waiters cannot reach this %s." % table_def.display_name,
				"blocking": false,
			})
	# Kitchen stations: ovens inside the kitchen zone with a free cook spot.
	for oven: PlacedFurnitureState in ovens:
		var oven_def: FurnitureDef = catalog.get(oven.def_id)
		var inside: bool = true
		for cell: Vector2i in layout.cells_for(oven, oven_def):
			if not layout.in_kitchen(cell):
				inside = false
				break
		if not inside:
			ev.issues.append({
				"code": &"oven_outside_kitchen",
				"instance_id": oven.instance_id,
				"message": "%s must stand in the kitchen zone." % oven_def.display_name,
				"blocking": true,
			})
			continue
		var cook_cell: Vector2i = oven.cell + facing_offset(oven.rotation)
		if not reachable.has(cook_cell):
			ev.issues.append({
				"code": &"station_blocked",
				"instance_id": oven.instance_id,
				"message": "No room for a cook in front of this %s." % oven_def.display_name,
				"blocking": false,
			})
			continue
		var station: Dictionary = {"prep_id": 0, "throughput": 0.0}
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: PlacedFurnitureState = cell_owner.get(oven.cell + offset)
			if neighbor == null or neighbor == oven:
				continue
			var neighbor_def: FurnitureDef = catalog.get(neighbor.def_id)
			if neighbor_def != null and neighbor_def.throughput > 0.0:
				station["prep_id"] = neighbor.instance_id
				station["throughput"] = neighbor_def.throughput
				break
		ev.stations[oven.instance_id] = station
		ev.cook_stations += oven_def.cook_slots
	# A dining room where no table survives pairing/reachability is a broken
	# commit, not a tuning choice — same for a kitchen with dead ovens.
	if not tables.is_empty() and ev.table_seats.is_empty():
		ev.issues.append({
			"code": &"no_usable_tables",
			"instance_id": tables[0].instance_id,
			"message": "No table can be reached and seated.",
			"blocking": true,
		})
	if not ovens.is_empty() and ev.cook_stations == 0:
		ev.issues.append({
			"code": &"no_usable_stations",
			"instance_id": ovens[0].instance_id,
			"message": "No oven has a reachable cook spot in the kitchen.",
			"blocking": true,
		})
	# Pickup counters: driver side must be reachable from the door.
	pickups.sort_custom(func(a: PlacedFurnitureState, b: PlacedFurnitureState) -> bool:
		return a.cell.y * 1000 + a.cell.x < b.cell.y * 1000 + b.cell.x)
	for pickup: PlacedFurnitureState in pickups:
		var pickup_def: FurnitureDef = catalog.get(pickup.def_id)
		if nav.adjacent_reachable(pickup.cell, reachable):
			ev.pickup_counters.append(pickup.instance_id)
			ev.pickup_slots += pickup_def.pickup_slots
		else:
			ev.issues.append({
				"code": &"pickup_unreachable",
				"instance_id": pickup.instance_id,
				"message": "Drivers cannot reach this %s." % pickup_def.display_name,
				"blocking": false,
			})
	# Finishes: floor / wall / music contribute comfort, style and appeal.
	var active_finishes: Array[InteriorFinishDef] = []
	for finish_id: StringName in [layout.floor_finish, layout.wall_finish, layout.music]:
		var fin: InteriorFinishDef = finishes.get(finish_id)
		if fin != null:
			active_finishes.append(fin)
			ev.comfort += fin.comfort
			for tag: StringName in fin.style_tags:
				styled[tag] = int(styled.get(tag, 0)) + 2  # Room-wide: weighs like two items.
				styled_total += 2
	# Re-derive coherence including finish styles.
	ev.dominant_style = &""
	for tag: StringName in styled:
		if int(styled[tag]) > int(styled.get(ev.dominant_style, 0)):
			ev.dominant_style = tag
	if styled_total > 0:
		ev.style_coherence = float(styled.get(ev.dominant_style, 0)) / float(styled_total)
	# Flow: how far waiters walk from the pass to the average table, and how
	# congested the dining floor is. Two equal-value layouts with different
	# flow SHOULD serve at different speeds.
	var dist_sum: float = 0.0
	var dist_n: int = 0
	for table_id: int in ev.table_seats:
		var table: PlacedFurnitureState = layout.find(table_id)
		var dist: int = nav.service_distance(SERVE_CELL, table.cell, reachable)
		if dist >= 0:
			dist_sum += float(dist)
			dist_n += 1
	var avg_dist: float = dist_sum / float(dist_n) if dist_n > 0 else 10.0
	var free_cells: int = 0
	var open_cells: int = 0
	for col: int in range(layout.grid_cols):
		for row: int in range(layout.grid_rows):
			var cell: Vector2i = Vector2i(col, row)
			if layout.in_kitchen(cell):
				continue
			open_cells += 1
			if nav.is_walkable(cell):
				free_cells += 1
	var free_ratio: float = float(free_cells) / float(open_cells) if open_cells > 0 else 1.0
	var crowding: float = clampf((0.55 - free_ratio) * 2.0, 0.0, 0.4)
	ev.throughput_mod = clampf(1.12 - 0.015 * avg_dist - crowding, 0.6, 1.15)
	ev.comfort = clampf(ev.comfort - crowding * 2.0, 0.0, 5.0)
	# Per-segment appeal: furniture + finishes + coherent styling, dulled by
	# poor condition and crowding. No single beauty score on purpose.
	for segment: StringName in [&"workers", &"students", &"families", &"seniors", &"teens"]:
		var total: float = 0.0
		for item: PlacedFurnitureState in layout.placed:
			var def: FurnitureDef = catalog.get(item.def_id)
			if def == null or not item.enabled:
				continue
			total += float(def.segment_appeal.get(segment, 0.0)) * item.condition()
		for fin: InteriorFinishDef in active_finishes:
			total += float(fin.segment_appeal.get(segment, 0.0))
		total += ev.style_coherence * 0.5
		total += clampf(ev.entertainment * 0.15, 0.0, 0.45)
		total += clampf(ev.comfort * 0.1, 0.0, 0.5)
		total -= crowding
		total *= 0.5 + 0.5 * ev.condition
		ev.segment_appeal[segment] = total
	return ev


func apply_to_restaurant(rest: RestaurantState, ev: InteriorEvaluation) -> void:
	rest.table_count = ev.table_seats.size()
	rest.cook_station_cap = ev.cook_stations
	rest.interior_appeal = ev.segment_appeal
	rest.interior_comfort = ev.comfort
	rest.interior_throughput_mod = ev.throughput_mod
	# Menu-dish capacity now comes from placed kitchen gear. Never shrinks
	# below the saved value so pre-interior purchases stay honored.
	rest.menu_slots = maxi(rest.menu_slots, ev.menu_capacity)


## Money delta between the live layout and an edited draft. Instances are
## matched by instance_id: new ids are purchases at catalog price, missing
## ids are sales refunded by resale_factor scaled with condition. Moves,
## rotations and recolors are free.
func price_diff(current: InteriorLayoutState, draft: InteriorLayoutState) -> Dictionary:
	var current_ids: Dictionary = {}
	for item: PlacedFurnitureState in current.placed:
		current_ids[item.instance_id] = item
	var draft_ids: Dictionary = {}
	var buy: float = 0.0
	var bought: Array[StringName] = []
	for item: PlacedFurnitureState in draft.placed:
		draft_ids[item.instance_id] = item
		if not current_ids.has(item.instance_id):
			var def: FurnitureDef = catalog.get(item.def_id)
			if def != null:
				buy += def.price
				bought.append(def.id)
	var refund: float = 0.0
	var sold: Array[StringName] = []
	for item: PlacedFurnitureState in current.placed:
		if not draft_ids.has(item.instance_id):
			var def: FurnitureDef = catalog.get(item.def_id)
			if def != null:
				refund += def.price * def.resale_factor * item.condition()
				sold.append(def.id)
	# Finish changes are one-off renovation purchases (music just switches).
	for pair: Array in [[current.floor_finish, draft.floor_finish], [current.wall_finish, draft.wall_finish]]:
		if pair[0] != pair[1]:
			var fin: InteriorFinishDef = finishes.get(pair[1])
			if fin != null:
				buy += fin.price
				bought.append(fin.id)
	return {"buy": buy, "refund": refund, "net": buy - refund, "bought": bought, "sold": sold}


# --- Placement validation (cheap, per-frame while dragging) -------------------


func validate_place(layout: InteriorLayoutState, def: FurnitureDef, cell: Vector2i, rotation: int, ignore_ids: Array[int] = []) -> Dictionary:
	var size: Vector2i = def.footprint_cells(rotation)
	for dx: int in range(size.x):
		for dy: int in range(size.y):
			var probe: Vector2i = cell + Vector2i(dx, dy)
			if not layout.in_bounds(probe):
				return {"ok": false, "reason": "Outside the room", "blocker": 0}
			if def.placement_zone == &"kitchen" and not layout.in_kitchen(probe):
				return {"ok": false, "reason": "Kitchen equipment only fits the kitchen zone", "blocker": 0}
			if probe == door_cell(layout) and def.blocks_walk:
				return {"ok": false, "reason": "Blocks the entrance", "blocker": 0}
	for other: PlacedFurnitureState in layout.placed:
		if ignore_ids.has(other.instance_id):
			continue
		var other_def: FurnitureDef = catalog.get(other.def_id)
		if other_def == null:
			continue
		# Blocking items collide with each other; non-blocking (wall/ceiling)
		# items only collide with non-blocking items on the same layer.
		var both_block: bool = def.blocks_walk and other_def.blocks_walk
		var same_overlay_layer: bool = (
			not def.blocks_walk and not other_def.blocks_walk
			and def.is_wall_item == other_def.is_wall_item)
		if not both_block and not same_overlay_layer:
			continue
		var other_size: Vector2i = other_def.footprint_cells(other.rotation)
		var overlap: bool = (
			cell.x < other.cell.x + other_size.x and cell.x + size.x > other.cell.x
			and cell.y < other.cell.y + other_size.y and cell.y + size.y > other.cell.y)
		if overlap:
			return {"ok": false, "reason": "Overlaps %s" % other_def.display_name, "blocker": other.instance_id}
	return {"ok": true, "reason": "", "blocker": 0}


## The inside-the-door walk cell: hugs the front wall, which moves outward
## with each expansion level.
static func door_cell(layout: InteriorLayoutState) -> Vector2i:
	return Vector2i(DOOR_COL, layout.grid_rows - 2)


static func facing_offset(rotation: int) -> Vector2i:
	match ((rotation % 360) + 360) % 360:
		90:
			return Vector2i(1, 0)
		180:
			return Vector2i(0, -1)
		270:
			return Vector2i(-1, 0)
		_:
			return Vector2i(0, 1)
