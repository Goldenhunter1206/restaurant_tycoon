class_name InfluenceService
extends RefCounted
## Pure influence/corruption math (feature 13). Influence bends bounded
## decisions — award bias, inspection leniency, project priority — and NEVER
## overwrites objective sim facts. Every curve here is diminishing and capped
## so buying the city cannot become the dominant strategy: repeat donations
## flatten (half-life), donation-bought reputation has a hard ceiling, bribes
## carry evidence risk that grows with the amount, and influence decays daily.

var donation_reputation_per_1k: float = 0.03
var reputation_cap_from_donations: float = 0.35
var influence_decay_per_day: float = 0.5
var diminishing_half_life: float = 5000.0
var bribe_base_success: float = 0.35
var bribe_evidence_risk: float = 0.25
var award_bias_max: float = 0.15


## tuning = Callable(path: String, fallback) -> Variant.
func configure(tuning: Callable) -> void:
	donation_reputation_per_1k = float(tuning.call(
		"government.influence.donation_reputation_per_1k", donation_reputation_per_1k))
	reputation_cap_from_donations = float(tuning.call(
		"government.influence.reputation_cap_from_donations", reputation_cap_from_donations))
	influence_decay_per_day = float(tuning.call(
		"government.influence.influence_decay_per_day", influence_decay_per_day))
	diminishing_half_life = float(tuning.call(
		"government.influence.diminishing_half_life", diminishing_half_life))
	bribe_base_success = float(tuning.call(
		"government.influence.bribe_base_success", bribe_base_success))
	bribe_evidence_risk = float(tuning.call(
		"government.influence.bribe_evidence_risk", bribe_evidence_risk))
	award_bias_max = float(tuning.call(
		"government.influence.award_bias_max", award_bias_max))


## Diminishing factor for the NEXT dollar given prior lifetime donations.
func diminishing_factor(donations_total: float) -> float:
	return diminishing_half_life / (diminishing_half_life + maxf(donations_total, 0.0))


## What a declared donation/sponsorship buys: bounded reputation + influence.
## Reputation from money can never push past 0.5 + reputation_cap (earn the
## rest with clean inspections).
func donation_effect(amount: float, donations_total: float, official_reputation: float) -> Dictionary:
	var scale: float = diminishing_factor(donations_total)
	var rep_ceiling: float = 0.5 + reputation_cap_from_donations
	var rep_gain: float = amount / 1000.0 * donation_reputation_per_1k * scale
	rep_gain = maxf(0.0, minf(rep_gain, rep_ceiling - official_reputation))
	return {
		"reputation_gain": rep_gain,
		"influence_gain": amount / 100.0 * scale,
		"relationship_gain": clampf(amount / 8000.0 * scale, 0.0, 0.15),
	}


## Chance a bribe lands: money helps with diminishing returns, integrity
## resists hard. Always leaves both failure and success possible.
func bribe_success(amount: float, integrity: float) -> float:
	var money_pull: float = amount / (amount + diminishing_half_life)
	return clampf(bribe_base_success + money_pull * 0.5 - clampf(integrity, 0.0, 1.0) * 0.45, 0.02, 0.9)


## Chance the payment leaves a trail. Upright officials and big envelopes are
## both more likely to surface.
func evidence_risk(amount: float, integrity: float) -> float:
	return clampf(bribe_evidence_risk + clampf(integrity, 0.0, 1.0) * 0.15 + amount / 20000.0, 0.05, 0.7)


## Bounded award-jury nudge from influence + mayor goodwill. Can tilt a close
## race; can never manufacture a win (AwardEvaluator clamps scores after it).
func award_bias(influence: float, mayor_relationship: float) -> float:
	var bias: float = influence / 400.0 * 0.1 + maxf(mayor_relationship, 0.0) * 0.08
	return clampf(bias, 0.0, award_bias_max)


## Daily fade of bought goodwill.
func decay(civic: CompanyCivicState) -> void:
	civic.influence = maxf(0.0, civic.influence - influence_decay_per_day)
	civic.mayor_relationship = move_toward(civic.mayor_relationship, 0.0, 0.002)
