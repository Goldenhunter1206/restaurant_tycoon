@tool
class_name InteriorFinishDef
extends Resource
## Room-wide finish choice (data/interior_finishes/*.tres): floor material,
## wall paint or background music. One of each kind is active per layout and
## contributes comfort, style and per-segment appeal to the evaluation.

@export var id: StringName = &""
@export var display_name: String = ""
## floor | wall | music
@export var kind: StringName = &"floor"
@export var price: float = 0.0
## Music has a running cost instead of a one-off price.
@export var daily_cost: float = 0.0
@export_range(0.0, 2.0) var comfort: float = 0.0
@export var style_tags: Array[StringName] = []
## segment id -> appeal bonus.
@export var segment_appeal: Dictionary = {}
## Floor kind: tile glb that replaces the room's floor tiles.
@export_file("*.glb") var tile_scene: String = ""
## Wall kind: albedo tint layered onto wall meshes.
@export var wall_tint: Color = Color.WHITE
## Floor kind: albedo tint applied to the swapped tiles (the tile textures
## are shared gradient atlases, so the tint carries the look).
@export var floor_tint: Color = Color.WHITE
