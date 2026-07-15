class_name LogisticsService
extends RefCounted
## Warehouse capacity math, transfer orders and road-network ETAs.
## Autoload-free: the road graph, inventories and clocks are passed in, so
## the service stays headless-testable. Vehicle visuals live in SupplyManager.

## Matches Vehicle.CITY_SPEED (world units per real second at speed 1, where
## one real second is one game minute).
const CITY_UNITS_PER_MINUTE: float = 9.0
## Loading dock overhead added to every transfer.
const HANDLING_MINUTES: float = 25.0
## Schedule buffer over the raw drive time (lights, turns, traffic).
const DRIVE_BUFFER: float = 1.2


## Door-to-door ETA in game minutes, or -1.0 when no road route exists.
func route_eta_minutes(graph: RoadGraph, from_pos: Vector3, to_pos: Vector3) -> float:
	if graph == null:
		return -1.0
	var start: int = graph.nearest_lane_node(from_pos)
	var goal: int = graph.nearest_lane_node(to_pos)
	if start < 0 or goal < 0:
		return -1.0
	var path: PackedInt32Array = graph.find_lane_path(start, goal)
	if path.size() < 2:
		return -1.0
	var length: float = 0.0
	for i: int in range(path.size() - 1):
		length += graph.lane_points[path[i]].distance_to(graph.lane_points[path[i + 1]])
	return HANDLING_MINUTES + length / CITY_UNITS_PER_MINUTE * DRIVE_BUFFER


## Vehicle cost for one transfer leg.
func transfer_cost(eta_minutes: float, base_fee: float, per_minute: float) -> float:
	return base_fee + maxf(eta_minutes - HANDLING_MINUTES, 0.0) * per_minute


## Free space in one storage class (capacity 0/absent = unlimited).
func free_capacity(inv: InventoryState, storage_class: StringName,
		class_of: Callable, volume_of: Callable) -> float:
	var cap: float = float(inv.capacity_by_class.get(storage_class, 0.0))
	if cap <= 0.0:
		return INF
	return maxf(cap - inv.used_volume(storage_class, class_of, volume_of), 0.0)


## Build a transfer order by extracting FEFO lot snapshots from the source.
## Returns null when nothing could be extracted.
func build_transfer(inventory_service: InventoryService, next_id: int,
		company_id: StringName, warehouse: WarehouseState, dest_restaurant_id: int,
		wants: Array[Dictionary], eta_minutes: float, cost: float,
		now_minute: int, auto_generated: bool) -> TransferOrder:
	var lines: Array[Dictionary] = []
	for want: Dictionary in wants:
		var ing: StringName = want.get("ingredient_id", &"")
		var qty: float = float(want.get("qty", 0.0))
		if ing == &"" or qty <= 0.0:
			continue
		for snapshot: Dictionary in inventory_service.extract_lots(warehouse.inventory, ing, qty):
			lines.append(snapshot)
	if lines.is_empty():
		return null
	var transfer: TransferOrder = TransferOrder.new()
	transfer.id = next_id
	transfer.company_id = company_id
	transfer.from_warehouse_id = warehouse.id
	transfer.dest_restaurant_id = dest_restaurant_id
	transfer.lines = lines
	transfer.status = &"in_transit"
	transfer.created_minute = now_minute
	transfer.eta_minute = now_minute + int(maxf(eta_minutes, 1.0))
	transfer.cost = cost
	transfer.auto_generated = auto_generated
	return transfer


## Deliver an arrived transfer into the destination inventory (lot snapshots
## keep their original expiry — freshness survives the trip).
func deliver_transfer(inventory_service: InventoryService, transfer: TransferOrder,
		dest_inv: InventoryState) -> void:
	for snapshot: Dictionary in transfer.lines:
		inventory_service.insert_lot_snapshot(dest_inv, snapshot)
	transfer.status = &"delivered"


## Return an undeliverable transfer's goods to the warehouse.
func bounce_transfer(inventory_service: InventoryService, transfer: TransferOrder,
		warehouse_inv: InventoryState) -> void:
	for snapshot: Dictionary in transfer.lines:
		inventory_service.insert_lot_snapshot(warehouse_inv, snapshot)
	transfer.status = &"cancelled"


## Hourly settle: returns transfers whose ETA passed, already delivered or
## bounced. events: [{transfer, kind: &"delivered"|&"bounced"}].
func tick(inventory_service: InventoryService, transfers: Array[TransferOrder],
		now_minute: int, dest_inv_lookup: Callable, warehouse_inv_lookup: Callable) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for transfer: TransferOrder in transfers:
		if transfer.status != &"in_transit" or now_minute < transfer.eta_minute:
			continue
		var dest_inv: InventoryState = dest_inv_lookup.call(transfer.dest_restaurant_id)
		if dest_inv != null:
			deliver_transfer(inventory_service, transfer, dest_inv)
			events.append({"transfer": transfer, "kind": &"delivered"})
		else:
			var wh_inv: InventoryState = warehouse_inv_lookup.call(transfer.from_warehouse_id)
			if wh_inv != null:
				bounce_transfer(inventory_service, transfer, wh_inv)
			else:
				transfer.status = &"cancelled"
			events.append({"transfer": transfer, "kind": &"bounced"})
	return events
