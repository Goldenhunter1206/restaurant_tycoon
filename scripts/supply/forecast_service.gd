class_name ForecastService
extends RefCounted
## Consumption smoothing and demand-aware days-of-cover projection. Pure math,
## no autoload access — SupplyManager feeds it the demand multiplier it derives
## from menu size, active marketing campaigns and city events.

const WARN_DAYS: float = 2.0
const CRITICAL_DAYS: float = 1.0


## Exponential moving average of daily consumption.
func ewma(previous: float, today: float, alpha: float) -> float:
	return lerpf(previous, today, alpha)


## Projected daily use once a demand multiplier (1.0 = normal, >1 = campaign
## or event spike) is applied.
func projected_daily_use(base_daily_use: float, demand_mult: float) -> float:
	return base_daily_use * maxf(demand_mult, 0.0)


## Days the current stock lasts at the projected burn rate (INF if idle).
func days_of_cover(available: float, projected_daily_use: float) -> float:
	if projected_daily_use <= 0.001:
		return INF
	return available / projected_daily_use


## Build forecast warnings for one inventory.
## rows: [{ingredient_id, available, base_use}]; demand_mult applies to all;
## boosted: {ingredient_id: extra_mult} for campaign-promoted ingredients.
## Returns [{ingredient_id, severity, days, reason}] worst-first.
func warnings(rows: Array[Dictionary], demand_mult: float,
		boosted: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in rows:
		var ing: StringName = row["ingredient_id"]
		var mult: float = demand_mult * float(boosted.get(ing, 1.0))
		var use: float = projected_daily_use(float(row["base_use"]), mult)
		var cover: float = days_of_cover(float(row["available"]), use)
		if cover >= WARN_DAYS:
			continue
		var severity: StringName = &"critical" if cover < CRITICAL_DAYS else &"warning"
		var reason: String = "%.1f days of cover" % cover
		if float(boosted.get(ing, 1.0)) > 1.0:
			reason += " — campaign demand"
		elif demand_mult > 1.05:
			reason += " — raised demand"
		out.append({
			"ingredient_id": ing,
			"severity": severity,
			"days": cover,
			"reason": reason,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["days"]) < float(b["days"]))
	return out
