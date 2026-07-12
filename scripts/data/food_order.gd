class_name FoodOrder
extends RefCounted
## One customer order (dine-in or delivery) moving through the pipeline.
## All timing uses absolute game minutes (GameClock.total_minutes()).

enum State {
	PLACED,
	QUEUED,
	COOKING,
	READY,
	ASSIGNED,
	PICKED_UP,
	EN_ROUTE,
	SERVED,
	DELIVERED,
	CANCELLED,
}

var order_id: int = -1
var restaurant_id: int = -1
var citizen_id: int = -1
var dish_id: StringName = &""
var tier: StringName = &"med"
var price: float = 0.0
var ingredient_cost: float = 0.0
var prep_minutes: float = 10.0
## Consistency attr of the cook who prepared it; feeds service reputation.
var cook_consistency: float = 0.5
var placed_minute: int = 0
var state: int = State.PLACED
var is_delivery: bool = false
var target_door: Vector3 = Vector3.ZERO
var driver: Node = null


func state_name() -> String:
	return State.keys()[state]
