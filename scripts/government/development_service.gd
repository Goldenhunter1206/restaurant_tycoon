class_name DevelopmentService
extends RefCounted
## Pure city-development math (feature 13). Proposals collect lobbying
## support, get decided on a seeded roll (support helps with diminishing
## returns, never guarantees), and once BUILT shift district demand inside a
## clamped band. Touches no autoloads.

var decision_days: int = 14
var support_cost_base: float = 1500.0
var demand_uplift_max: float = 0.25
var base_approval: float = 0.45


## tuning = Callable(path: String, fallback) -> Variant.
func configure(tuning: Callable) -> void:
	decision_days = int(tuning.call("government.development.decision_days", decision_days))
	support_cost_base = float(tuning.call("government.development.support_cost_base", support_cost_base))
	demand_uplift_max = float(tuning.call("government.development.demand_uplift_max", demand_uplift_max))
	base_approval = float(tuning.call("government.development.base_approval", base_approval))


## What the proposal would do — for the Development tab's expected-effects card.
func expected_effect(def: DevelopmentProjectDef, district: String) -> Dictionary:
	return {
		"district": district,
		"demand_delta": clampf(def.demand_delta, -demand_uplift_max, demand_uplift_max),
		"demographics": def.demographic_shift.duplicate(true),
		"kind": def.kind,
	}


## Approval chance: civic support helps with diminishing returns and mayoral
## goodwill of the top sponsor tips the scale slightly. Bounded 0.15..0.9 —
## money can tilt the council, not own it.
func approval_chance(def: DevelopmentProjectDef, support_total: float,
		top_sponsor_mayor_relationship: float) -> float:
	var reference: float = maxf(def.support_cost_base, support_cost_base)
	var support_pull: float = support_total / (support_total + reference * 2.0) * 0.4
	var mayor_pull: float = clampf(top_sponsor_mayor_relationship, -0.5, 0.5) * 0.15
	return clampf(base_approval + support_pull + mayor_pull, 0.15, 0.9)


func decide(def: DevelopmentProjectDef, project: DevelopmentProjectState,
		top_sponsor_mayor_relationship: float, rng: RandomNumberGenerator) -> bool:
	var chance: float = approval_chance(def, project.support_total(), top_sponsor_mayor_relationship)
	return rng.randf() < chance


## District demand term for one BUILT project (clamped band).
func built_bonus(def: DevelopmentProjectDef) -> float:
	return clampf(def.demand_delta, -demand_uplift_max, demand_uplift_max)
