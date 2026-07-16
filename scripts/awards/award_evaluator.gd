class_name AwardEvaluator
extends RefCounted
## Pure quarterly award scoring. AwardsManager builds one nominee row per
## eligible branch — {company_id, building_id, name, opened_day, stars,
## delivery_enabled, dims: {dim: 0..100}, metrics: {metric: float}} — and this
## class normalizes every scoring component across the field, weights them per
## AwardDef, breaks ties deterministically, and emits an AwardResult whose
## stored breakdown reproduces the winning score exactly.


func eligible(def: AwardDef, nominee: Dictionary, day: int) -> bool:
	var rules: Dictionary = def.eligibility
	var age: int = day - int(nominee.get("opened_day", 1))
	if age < int(rules.get("min_age_days", 0)):
		return false
	if rules.has("max_age_days") and age > int(rules["max_age_days"]):
		return false
	if float(nominee.get("stars", 0.0)) < float(rules.get("min_stars", 0.0)):
		return false
	if bool(rules.get("requires_delivery", false)) and not bool(nominee.get("delivery_enabled", false)):
		return false
	var metrics: Dictionary = nominee.get("metrics", {})
	if float(metrics.get(&"guests", 0.0)) < float(rules.get("min_guests", 0.0)):
		return false
	return true


## Score all nominees for one award; null when the field is empty.
func evaluate(def: AwardDef, nominees: Array[Dictionary], period: int, period_label: String, day: int) -> AwardResult:
	if nominees.is_empty():
		return null
	var lo: Dictionary = {}
	var hi: Dictionary = {}
	for nominee: Dictionary in nominees:
		for comp: Variant in def.scoring:
			var value: float = component_value(nominee, StringName(comp))
			lo[comp] = minf(float(lo.get(comp, value)), value)
			hi[comp] = maxf(float(hi.get(comp, value)), value)
	var rows: Array[Dictionary] = []
	for nominee: Dictionary in nominees:
		var score: float = 0.0
		var breakdown: Dictionary = {}
		for comp: Variant in def.scoring:
			var raw: float = component_value(nominee, StringName(comp))
			var span: float = float(hi[comp]) - float(lo[comp])
			var norm: float = 0.5 if span < 0.0001 else (raw - float(lo[comp])) / span
			var weight: float = float(def.scoring[comp])
			breakdown[StringName(comp)] = {"raw": raw, "normalized": norm, "weight": weight}
			score += weight * norm
		rows.append({
			"company_id": StringName(nominee.get("company_id", &"")),
			"building_id": int(nominee.get("building_id", -1)),
			"name": String(nominee.get("name", "")),
			"score": score,
			"breakdown": breakdown,
			"tiebreak": component_value(nominee, def.tiebreak_metric),
			"opened_day": int(nominee.get("opened_day", 1)),
		})
	rows.sort_custom(_row_compare.bind(def.id, period))
	var winner: Dictionary = rows[0]
	var result: AwardResult = AwardResult.new()
	result.award_id = def.id
	result.display_name = def.display_name
	result.kind = &"award"
	result.period = period
	result.period_label = period_label
	result.day = day
	result.winner_company_id = StringName(winner["company_id"])
	result.winner_building_id = int(winner["building_id"])
	result.winner_name = String(winner["name"])
	var nominee_rows: Array[Dictionary] = []
	for row: Dictionary in rows:
		nominee_rows.append(row)
	result.nominees = nominee_rows
	result.explanation = _explain(winner)
	result.reward = {
		"cash": def.reward_cash,
		"reputation": def.reward_reputation,
		"trend_days": def.reward_trend_days,
	}
	return result


## Components resolve against rating dims first, then quarter metrics.
func component_value(nominee: Dictionary, comp: StringName) -> float:
	var dims: Dictionary = nominee.get("dims", {})
	if dims.has(comp):
		return float(dims[comp])
	var metrics: Dictionary = nominee.get("metrics", {})
	return float(metrics.get(comp, 0.0))


## Score desc -> tiebreak metric desc -> older branch -> deterministic hash.
func _row_compare(a: Dictionary, b: Dictionary, award_id: StringName, period: int) -> bool:
	if absf(float(a["score"]) - float(b["score"])) > 0.0001:
		return float(a["score"]) > float(b["score"])
	if absf(float(a["tiebreak"]) - float(b["tiebreak"])) > 0.0001:
		return float(a["tiebreak"]) > float(b["tiebreak"])
	if int(a["opened_day"]) != int(b["opened_day"]):
		return int(a["opened_day"]) < int(b["opened_day"])
	var salt: String = "%s@%d" % [award_id, period]
	return hash(salt + str(a["building_id"])) < hash(salt + str(b["building_id"]))


func _explain(winner: Dictionary) -> String:
	var parts: PackedStringArray = []
	var breakdown: Dictionary = winner["breakdown"]
	for comp: StringName in breakdown:
		var row: Dictionary = breakdown[comp]
		parts.append("%s %.0f (x%.2f)" % [String(comp).capitalize(), float(row["raw"]), float(row["weight"])])
	return "%s won on %s." % [String(winner["name"]), ", ".join(parts)]
