class_name DishDef
extends Resource
## Static definition of a sellable dish. New dishes are added by dropping a
## .tres file into data/dishes/ — no code changes needed.

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = &"pizza"
@export var base_prep_minutes: float = 12.0
@export var popularity: float = 1.0
@export var suggested_price: float = 9.0
@export var tiers: Array[QualityTier] = []


func tier_by_id(tier_id: StringName) -> QualityTier:
	for t: QualityTier in tiers:
		if t.tier == tier_id:
			return t
	return tiers[0] if not tiers.is_empty() else null
