class_name MarketingChannelDef
extends Resource
## One advertising medium (flyer, billboard, zeppelin, ...). Loaded from
## data/marketing_channels/*.tres so cities can enable different media and
## pricing. Campaign state lives in MarketingCampaign; this is the catalog.

## &"local" reaches around one branch/placement; &"citywide" reaches all districts.
@export var id: StringName = &""
@export var display_name: String = ""
## UiAssets icon name, e.g. "megaphone".
@export var icon: String = "megaphone"
@export_multiline var blurb: String = ""
@export var scope: StringName = &"local"
## CapabilityRegistry id required to use this channel.
@export var required_capability: StringName = &"marketing.local_campaigns"
## &"radius" (around the branch), &"placement" (around a rented site),
## &"city" (every district).
@export var reach_shape: StringName = &"radius"
@export var base_radius: float = 450.0
## Awareness gain multiplier per exposure tick (0-1 scale).
@export_range(0.0, 1.0) var reach_weight: float = 0.3
## Exposures per day relative to a flyer (1.0).
@export var frequency: float = 1.0
@export var setup_cost: float = 0.0
@export var cost_per_day: float = 150.0
@export var min_days: int = 3
@export var max_days: int = 28
## Requires renting an AdPlacement site before launch.
@export var needs_placement: bool = false
## &"" | &"billboard" | &"zeppelin" — world prop shown while active.
@export var world_prop: StringName = &""
