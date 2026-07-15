class_name MarketingCampaign
extends Resource
## One running ad campaign. Raises awareness (and offer utility) for citizens
## inside its coverage. Paid daily by the owning company; expires when
## days_left hits zero. All fields default inert so pre-existing v4 saves
## load unchanged.

@export var company_id: StringName = &"player"
@export var building_id: int = -1
## Legacy single target, kept for old saves. Use target_segments; segments()
## merges both.
@export var demographic: StringName = &""
@export var radius: float = 400.0
@export var utility_bonus: float = 0.15
@export var cost_per_day: float = 150.0
@export var days_left: int = 7

@export_group("Channel")
@export var channel_id: StringName = &"flyer"
## Rented AdPlacement site ids (billboard-style channels).
@export var placement_ids: Array[int] = []
## Spend multiplier 0.5-2.0 chosen at creation; scales cost and exposure.
@export var intensity: float = 1.0

@export_group("Message")
## Empty targets every demographic.
@export var target_segments: Array[StringName] = []
## Brand positioning line shown in previews, e.g. "Family night!".
@export var brand_image: String = ""
@export var promoted_recipe: StringName = &""
@export var promoted_ingredient: StringName = &""
## &"" | &"lowest_price" | &"best_staff" | &"highest_quality".
@export var claim: StringName = &""
## Company id of a named rival for comparison campaigns.
@export var rival_target: StringName = &""

@export_group("Progress")
@export var days_run: int = 0
## 0-1 saturation from repeated exposure; suppresses further gains.
@export var fatigue: float = 0.0
## novelty x (1 - fatigue), recomputed each daily tick.
@export var effectiveness: float = 1.0
## 0-1 truthfulness weight from real stats; 1.0 until claims are checked.
@export var credibility: float = 1.0
## Days the claim has been measurably false (government risk).
@export var false_claim_days: int = 0

@export_group("Attribution")
@export var attributed_visits: int = 0
@export var attributed_revenue: float = 0.0
## segment (StringName) -> visits (int), last-touch estimate.
@export var segment_visits: Dictionary = {}
@export var total_spend: float = 0.0


## Effective target list: new-style target_segments, falling back to the
## legacy single demographic. Empty means everyone.
func segments() -> Array[StringName]:
	if not target_segments.is_empty():
		return target_segments
	if demographic != &"":
		var single: Array[StringName] = [demographic]
		return single
	return []


## True when `segment` is inside this campaign's audience.
func targets_segment(segment: StringName) -> bool:
	var wanted: Array[StringName] = segments()
	return wanted.is_empty() or wanted.has(segment)
