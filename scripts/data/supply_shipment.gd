class_name SupplyShipment
extends RefCounted
## Runtime-only passenger object for a cosmetic supply truck. Vehicle calls
## on_car_trip_finished(pos) when the drive completes; the manager wires a
## Callable so this class stays dependency-free. Deliveries themselves settle
## on the transfer's ETA timer — the truck is presentation, not authority.

var transfer_id: int = -1
var on_finished: Callable = Callable()


func on_car_trip_finished(pos: Vector3) -> void:
	if on_finished.is_valid():
		on_finished.call(pos)
