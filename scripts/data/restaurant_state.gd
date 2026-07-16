class_name RestaurantState
extends Resource
## Full state of one company-owned restaurant (player or AI rival). Exported
## fields are persisted by the save system; the rest is runtime-only and
## rebuilt on load.

@export var building_id: int = -1
## Owning company (CompanyManager id); every branch belongs to exactly one.
@export var company_id: StringName = &"player"
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
## Cash paid at acquisition (signing fee since save v2).
@export var purchase_price: float = 0.0
## Full buyout price captured at signing; paying it stops rent permanently.
@export var property_value: float = 0.0
@export var owned_outright: bool = false
@export var menu: Array[MenuEntry] = []
## Per-recipe lifetime sales, keyed "recipe_id@version" ->
## {units: int, revenue: float, cost: float, by_segment: {segment: int}}.
@export var recipe_sales: Dictionary = {}
@export var staff: Array[StaffMember] = []
@export var star_rating: float = 3.0
## Furniture layout of the interior (save v4 additive; null on legacy saves
## and regenerated as the classic default layout on load).
@export var interior_layout: InteriorLayoutState = null
## Ingredient stock lots (save v5 additive; null = seeded on first access).
@export var inventory: InventoryState = null
## Manager auto-repair: &"off" or &"auto" (repairs below repair_threshold).
@export var repair_policy: StringName = &"off"
@export_range(0.0, 1.0) var repair_threshold: float = 0.4
## Timed forced closure (crime raids/violations, save v11 additive): the
## branch serves nothing while GameClock.day < closed_until_day.
@export var closed_until_day: int = 0
@export var sales_history: Array[float] = []
## Daily expense totals, parallel to sales_history.
@export var expense_history: Array[float] = []

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
# Derived from the interior layout on load/commit (never saved):
## Physical cook stations; caps concurrent cooking together with staff.
var cook_station_cap: int = 4
## Per-segment appeal deltas fed into demand scoring.
var interior_appeal: Dictionary = {}
var interior_comfort: float = 0.0
## Service-speed multiplier from layout flow (crowding, walk distances).
var interior_throughput_mod: float = 1.0


## Returns the owning CompanyState. Typed loosely on purpose: a hard
## RestaurantState <-> CompanyState type cycle breaks cold headless script
## loads (CompanyState.restaurants already references this class).
func company() -> Resource:
	return CompanyManager.company(company_id)


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
	# Timed forced closure from a raid/violation (feature 12) overrides hours.
	if closed_until_day > 0 and GameClock.day < closed_until_day:
		return false
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
		if member.type_id == type_id and member.on_shift(hour) and not member.is_absent(GameClock.day):
			count += 1
	return count


func staff_count(type_id: StringName) -> int:
	var count: int = 0
	for member: StaffMember in staff:
		if member.type_id == type_id:
			count += 1
	return count


func record_recipe_sale(recipe_id: StringName, version: int, price: float, cost: float, segment: StringName) -> void:
	if recipe_id == &"":
		return
	var key: String = "%s@%d" % [recipe_id, version]
	var row: Dictionary = recipe_sales.get(key, {"units": 0, "revenue": 0.0, "cost": 0.0, "by_segment": {}})
	row["units"] = int(row["units"]) + 1
	row["revenue"] = float(row["revenue"]) + price
	row["cost"] = float(row["cost"]) + cost
	if segment != &"":
		var seg_counts: Dictionary = row["by_segment"]
		seg_counts[segment] = int(seg_counts.get(segment, 0)) + 1
	recipe_sales[key] = row


func record_sale(amount: float) -> void:
	today["sales"] = float(today.get("sales", 0.0)) + amount
	today["orders"] = int(today.get("orders", 0)) + 1
