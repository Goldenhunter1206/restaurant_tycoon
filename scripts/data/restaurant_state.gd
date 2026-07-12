class_name RestaurantState
extends Resource
## Full state of one player-owned restaurant. Exported fields are persisted
## by the save system; the rest is runtime-only and rebuilt on load.

@export var building_id: int = -1
@export var restaurant_name: String = ""
@export var district: String = "N"
@export var table_count: int = 8
@export var open_hour: float = 10.0
@export var close_hour: float = 22.0
@export var dine_in_enabled: bool = true
@export var delivery_enabled: bool = false
@export var delivery_cap: int = 4
## Kitchen stations: hard cap on simultaneously enabled menu dishes.
@export var menu_slots: int = 4
@export var purchase_price: float = 0.0
@export var menu: Array[MenuEntry] = []
@export var staff: Array[StaffMember] = []
@export var star_rating: float = 3.0
@export var sales_history: Array[float] = []

# --- Runtime-only (rebuilt each session) ---
var door_pos: Vector3 = Vector3.ZERO
var curb_pos: Vector3 = Vector3.ZERO
var tables_occupied: int = 0
## Citizens waiting for a table: [{citizen, arrived_minute}]
var dine_queue: Array[Dictionary] = []
## Orders waiting for a free cook slot (FoodOrder).
var cook_backlog: Array = []
## Orders currently on a cook slot: [{order, minutes_left}]
var cooking: Array[Dictionary] = []
## Seated guests eating: [{citizen, order, done_minute}]
var dining: Array[Dictionary] = []
## Fractional waiter serving capacity accumulated per minute.
var waiter_credits: float = 0.0
var today: Dictionary = {}
var active_deliveries: int = 0


func reset_today() -> void:
	today = {
		"sales": 0.0,
		"expenses": 0.0,
		"orders": 0,
		"guests": 0,
		"cancelled": 0,
		"queue_leaves": 0,
	}


func is_open(hour: float) -> bool:
	if open_hour == close_hour:
		return false
	if open_hour < close_hour:
		return hour >= open_hour and hour < close_hour
	return hour >= open_hour or hour < close_hour


func menu_entry_for(dish: StringName) -> MenuEntry:
	for entry: MenuEntry in menu:
		if entry.dish_id == dish and entry.enabled:
			return entry
	return null


func enabled_dish_count() -> int:
	var count: int = 0
	for entry: MenuEntry in menu:
		if entry.enabled:
			count += 1
	return count


func enabled_menu() -> Array[MenuEntry]:
	var result: Array[MenuEntry] = []
	for entry: MenuEntry in menu:
		if entry.enabled:
			result.append(entry)
	return result


func staff_on_shift(type_id: StringName, hour: float) -> int:
	var count: int = 0
	for member: StaffMember in staff:
		if member.type_id == type_id and member.on_shift(hour):
			count += 1
	return count


func staff_count(type_id: StringName) -> int:
	var count: int = 0
	for member: StaffMember in staff:
		if member.type_id == type_id:
			count += 1
	return count


func record_sale(amount: float) -> void:
	today["sales"] = float(today.get("sales", 0.0)) + amount
	today["orders"] = int(today.get("orders", 0)) + 1
