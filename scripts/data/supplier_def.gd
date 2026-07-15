class_name SupplierDef
extends Resource
## One wholesale supplier in the city catalog. Loaded from
## data/suppliers/*.tres — drop a file in, no code changes. Live negotiation
## state (relationship, service history) lives in SupplierContractState.

@export var id: StringName = &""
@export var display_name: String = ""
## UiAssets icon name shown on comparison cards.
@export var icon: String = "basket"
@export_multiline var blurb: String = ""
## Ingredient categories this supplier carries (&"sauce" &"cheese" &"veg"
## &"meat" &"extra"). Union with `catalog`.
@export var categories: Array[StringName] = []
## Explicit extra ingredient ids carried on top of `categories`. A supplier
## with both lists empty carries everything.
@export var catalog: Array[StringName] = []
## Multiplies IngredientDef.unit_cost for purchase pricing.
@export var price_mult: float = 1.0
## Quality of delivered lots, 0..1.
@export_range(0.0, 1.0) var base_quality: float = 0.5
## Chance a placed order confirms and arrives on time, 0..1.
@export_range(0.0, 1.0) var reliability: float = 0.9
## Game minutes from confirmation to arrival (1 day = 1440).
@export var lead_time_minutes: int = 1440
## Flat fee charged per delivered shipment.
@export var delivery_fee: float = 25.0
## Orders below this value are rejected.
@export var min_order_value: float = 0.0
## kind -> daily chance while healthy (&"outage" &"price_spike" &"delay"), phase 4.
@export var disruption_profile: Dictionary = {}


func carries(ingredient_id: StringName, category: StringName) -> bool:
	if catalog.has(ingredient_id):
		return true
	if not categories.is_empty():
		return categories.has(category)
	# No category filter: explicit-catalog-only supplier, or carries-all.
	return catalog.is_empty()
