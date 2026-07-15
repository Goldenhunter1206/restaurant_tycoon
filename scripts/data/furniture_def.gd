@tool
class_name FurnitureDef
extends Resource
## Catalog definition of one placeable interior item (data/furniture/*.tres).
## Purely descriptive: footprints are in whole grid cells (1 m), anchors in
## local cell offsets at rotation 0. All gameplay numbers live here so the
## layout evaluation never needs the 3D scene.

## Stable catalog id, e.g. &"table_bistro".
@export var id: StringName = &""
@export var display_name: String = ""
## seating | kitchen | service | decor | entertainment | utility
@export var category: StringName = &"seating"
## Placement restriction: any | kitchen | dining.
@export var placement_zone: StringName = &"any"
## UiAssets icon shown on the catalog tile.
@export var icon: StringName = &"dining"
@export_multiline var blurb: String = ""

@export_group("Economy")
@export var price: float = 100.0
## Fraction of price refunded at full durability; scales with condition.
@export_range(0.0, 1.0) var resale_factor: float = 0.5
## Daily upkeep while placed and enabled.
@export var maintenance_cost: float = 0.0
## CapabilityRegistry gate; empty = always available.
@export var prereq_cap: StringName = &""

@export_group("Footprint")
## Cells occupied at rotation 0 (x = width, z = depth).
@export var footprint_w: int = 1
@export var footprint_d: int = 1
## Blocking items occupy nav cells; non-blocking (rugs, ceiling lights) don't.
@export var blocks_walk: bool = true
## Wall-mounted: must touch a wall cell, renders at mount_y.
@export var is_wall_item: bool = false
## Vertical offset for mounted/counter-top meshes (0 = on floor).
@export var mount_y: float = 0.0

@export_group("Capacity")
## Guests seated when paired with a table (chairs/stools/sofa seats).
@export var seats: int = 0
## True for tables: adjacent seating pairs with it to create dining capacity.
@export var is_table: bool = false
## Cook stations contributed (ovens).
@export var cook_slots: int = 0
## Prep speed bonus weight (prep tables, counters near ovens).
@export var throughput: float = 0.0
## Delivery/pickup bag slots contributed (pickup counters).
@export var pickup_slots: int = 0
## Enabled-menu-dish capacity contributed (shelves, prep space).
@export var menu_capacity: int = 0
## Queue guests handled (barriers/host stands extend the waiting line).
@export var queue_capacity: int = 0

@export_group("Atmosphere")
@export_range(0.0, 5.0) var comfort: float = 0.0
@export_range(0.0, 5.0) var entertainment: float = 0.0
## Positive keeps the room cleaner (sinks), negative dirties it faster (ovens).
@export_range(-2.0, 2.0) var cleanliness_impact: float = 0.0
## Style identity, e.g. [&"classic"] — coherence raises appeal.
@export var style_tags: Array[StringName] = []
## Flat per-segment appeal bonus: segment id -> float.
@export var segment_appeal: Dictionary = {}

@export_group("Condition")
@export var durability_max: float = 100.0
## Durability lost per guest/cook use.
@export var wear_per_use: float = 0.05

@export_group("Visuals")
## Default model (res://RestaurantAssets/...glb).
@export_file("*.glb") var scene_path: String = ""
## Colorway variants: variant id (StringName) -> glb path. Cycled by "recolor".
@export var variant_scenes: Dictionary = {}
## Optional base mesh rendered under the main model (e.g. counter under a
## coffee machine); main model then sits at mount_y.
@export_file("*.glb") var base_scene: String = ""


func footprint_cells(rotation: int) -> Vector2i:
	## Occupied cell extents after rotation (90/270 swap width and depth).
	if rotation % 180 == 90:
		return Vector2i(footprint_d, footprint_w)
	return Vector2i(footprint_w, footprint_d)


func scene_for_variant(variant: StringName) -> String:
	if variant != &"" and variant_scenes.has(variant):
		return String(variant_scenes[variant])
	return scene_path


func variant_ids() -> Array[StringName]:
	var ids: Array[StringName] = [&""]
	for key: Variant in variant_scenes.keys():
		ids.append(StringName(key))
	return ids
