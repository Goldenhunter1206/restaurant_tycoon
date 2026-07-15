@tool
class_name InteriorTemplateDef
extends Resource
## Designer layout preset (data/interior_templates/*.tres): a complete
## furniture arrangement plus finishes, applied wholesale to a restaurant.
## The furniture itself is charged at catalog prices on commit; the template
## adds a one-off design fee. Rivals use these headlessly for their branches.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var blurb: String = ""
## One-off designer fee on top of the furniture cost.
@export var design_fee: float = 0.0
## CapabilityRegistry gate; empty = always available.
@export var prereq_cap: StringName = &""
@export var style: StringName = &""
@export var floor_finish: StringName = &"floor_checker"
@export var wall_finish: StringName = &"wall_cream"
@export var music: StringName = &"music_none"
## Placements: [{def_id, cell: Vector2i, rotation, variant}].
@export var items: Array[Dictionary] = []


## Materializes the template as a fresh layout (kitchen zone matches the
## base room; expansion not required unless cells exceed the base grid).
func build_layout() -> InteriorLayoutState:
	var layout: InteriorLayoutState = InteriorLayoutState.new()
	layout.kitchen_rects = [Rect2i(0, 0, 22, 3)] as Array[Rect2i]
	layout.floor_finish = floor_finish
	layout.wall_finish = wall_finish
	layout.music = music
	for row: Dictionary in items:
		layout.add(
			StringName(row.get("def_id", &"")),
			row.get("cell", Vector2i.ZERO),
			int(row.get("rotation", 0)),
			StringName(row.get("variant", &"")))
	return layout
