class_name ChecklistService
extends RefCounted
## Pure civic-inspection checklist engine (feature 13). Every check queries
## LIVE restaurant/company state so findings always map to a concrete,
## currently-true fact and a corrective the player can act on. No autoload
## access — callers pass the restaurant plus a ctx Dictionary:
## {day:int, hour:float, now_minutes:int, civic:CompanyCivicState,
##  tax_ratio:float (paid/owed 14d, 1.0 = clean)}.
## Deliberately separate from the food-guide star track (RatingService):
## stars smooth 14-day dimensions, the law checks facts on visit day.

var _tuning: Callable = Callable()

## Static check registry per inspection kind. Severity: 1 minor, 2 serious,
## 3 critical. Evaluation lives in _evaluate() so rows stay data-only.
const CHECKS: Dictionary = {
	&"food_safety": [
		{"id": &"expired_stock", "label": "No expired stock in storage", "category": &"food", "severity": 3},
		{"id": &"stock_freshness", "label": "Ingredient freshness acceptable", "category": &"food", "severity": 1},
		{"id": &"supplier_traceability", "label": "Stock lots traceable to suppliers", "category": &"food", "severity": 1},
		{"id": &"kitchen_cleanliness", "label": "Kitchen and dining cleanliness", "category": &"safety", "severity": 2},
		{"id": &"equipment_condition", "label": "Equipment in safe condition", "category": &"safety", "severity": 2},
		{"id": &"food_handling_permit", "label": "Food handling permit current", "category": &"paperwork", "severity": 2},
	],
	&"labor": [
		{"id": &"staffing_coverage", "label": "Staff scheduled for open hours", "category": &"labor", "severity": 2},
		{"id": &"overworked_staff", "label": "No staff on excessive shifts", "category": &"labor", "severity": 2},
		{"id": &"injured_on_duty", "label": "No injured staff working", "category": &"labor", "severity": 3},
	],
	&"tax": [
		{"id": &"business_license", "label": "Business license current", "category": &"paperwork", "severity": 3},
		{"id": &"tax_ledger", "label": "Tax payments consistent with revenue", "category": &"paperwork", "severity": 2},
		{"id": &"outstanding_fines", "label": "No overdue fines", "category": &"paperwork", "severity": 1},
	],
}


func configure(tuning: Callable) -> void:
	_tuning = tuning


func checks_for(kind: StringName) -> Array:
	return CHECKS.get(kind, [])


## Runs every check for `kind` against live state. Deterministic for a given
## state — no RNG anywhere in the checklist.
func run_checklist(kind: StringName, rest, ctx: Dictionary) -> Array[Dictionary]:
	var findings: Array[Dictionary] = []
	for spec: Dictionary in checks_for(kind):
		var result: Dictionary = _evaluate(spec.get("id", &""), rest, ctx)
		findings.append({
			"check_id": spec.get("id", &""),
			"label": String(spec.get("label", "")),
			"category": spec.get("category", &""),
			"severity": int(spec.get("severity", 1)),
			"passed": bool(result.get("passed", true)),
			"detail": String(result.get("detail", "")),
			"corrective": String(result.get("corrective", "")),
			"needed": String(result.get("needed", "")),
		})
	return findings


## Score 0..100 (100 = spotless). Bias is corruption-bought leniency (or a
## rigged audit's harshness when negative); it bends the score inside a
## clamped band and can never turn a critical failure into a clean sheet.
func score_findings(findings: Array[Dictionary], bias: float) -> Dictionary:
	var penalty_per_severity: float = float(_knob("government.inspection.penalty_per_severity", 12.0))
	var bias_band: float = float(_knob("government.inspection.bias_band", 10.0))
	var score: float = 100.0
	var worst_severity: int = 0
	var failed: int = 0
	for row: Dictionary in findings:
		if bool(row.get("passed", true)):
			continue
		failed += 1
		var severity: int = int(row.get("severity", 1))
		worst_severity = maxi(worst_severity, severity)
		score -= penalty_per_severity * float(severity)
	score = clampf(score + clampf(bias, -1.0, 1.0) * bias_band, 0.0, 100.0)
	var grade: StringName = _grade_for(score, failed, worst_severity)
	return {"score": score, "grade": grade, "failed": failed, "worst_severity": worst_severity}


func _grade_for(score: float, failed: int, worst_severity: int) -> StringName:
	if failed == 0:
		return &"clean"
	var floors: Dictionary = _knob("government.inspection.grade_floors", {})
	var warning_floor: float = float(floors.get("warning", 55.0))
	var remediation_floor: float = float(floors.get("remediation", 40.0))
	var fine_floor: float = float(floors.get("fine", 25.0))
	# A critical failure can never grade better than remediation, bias or not.
	if score >= warning_floor:
		return &"remediation" if worst_severity >= 3 else &"warning"
	if score >= remediation_floor:
		return &"remediation"
	if score >= fine_floor:
		return &"fine"
	return &"closure"


## Re-evaluates one check so fix_violation can prove the fact is corrected.
func check_passes_now(check_id: StringName, rest, ctx: Dictionary) -> bool:
	return bool(_evaluate(check_id, rest, ctx).get("passed", false))


func _evaluate(check_id: StringName, rest, ctx: Dictionary) -> Dictionary:
	match check_id:
		&"expired_stock":
			return _check_expired_stock(rest, ctx)
		&"stock_freshness":
			return _check_stock_freshness(rest, ctx)
		&"supplier_traceability":
			return _check_supplier_traceability(rest)
		&"kitchen_cleanliness":
			return _check_cleanliness(rest)
		&"equipment_condition":
			return _check_equipment(rest)
		&"food_handling_permit":
			return _check_permit(ctx, &"food_handling", "Food handling permit")
		&"staffing_coverage":
			return _check_staffing_coverage(rest)
		&"overworked_staff":
			return _check_overwork(rest)
		&"injured_on_duty":
			return _check_injuries(rest, ctx)
		&"business_license":
			return _check_permit(ctx, &"business_license", "Business license")
		&"tax_ledger":
			return _check_tax_ledger(ctx)
		&"outstanding_fines":
			return _check_outstanding_fines(ctx)
	return {"passed": true, "detail": "Not applicable"}


func _lots(rest) -> Array:
	if rest == null or rest.inventory == null:
		return []
	return rest.inventory.lots


func _check_expired_stock(rest, ctx: Dictionary) -> Dictionary:
	var now: int = int(ctx.get("now_minutes", 0))
	var expired: int = 0
	for lot in _lots(rest):
		if lot.is_expired(now) and lot.qty > 0.0:
			expired += 1
	if expired == 0:
		return {"passed": true, "detail": "No expired lots on hand"}
	return {
		"passed": false,
		"detail": "%d expired stock lot%s in storage" % [expired, "" if expired == 1 else "s"],
		"corrective": "Discard the expired stock lots",
		"needed": "0 expired lots on hand",
	}


func _check_stock_freshness(rest, ctx: Dictionary) -> Dictionary:
	var now: int = int(ctx.get("now_minutes", 0))
	var min_avg: float = float(_knob("government.inspection.min_avg_freshness", 0.35))
	var total: float = 0.0
	var count: int = 0
	for lot in _lots(rest):
		if lot.qty <= 0.0:
			continue
		total += lot.freshness(now)
		count += 1
	if count == 0:
		return {"passed": true, "detail": "No perishable stock on hand"}
	var avg: float = total / float(count)
	if avg >= min_avg:
		return {"passed": true, "detail": "Average freshness %d%%" % int(round(avg * 100.0))}
	return {
		"passed": false,
		"detail": "Average freshness %d%% (minimum %d%%)" % [int(round(avg * 100.0)), int(round(min_avg * 100.0))],
		"corrective": "Rotate out stale stock and reorder fresh ingredients",
		"needed": "Average freshness at or above %d%%" % int(round(min_avg * 100.0)),
	}


func _check_supplier_traceability(rest) -> Dictionary:
	var untraced: int = 0
	for lot in _lots(rest):
		if lot.qty > 0.0 and String(lot.supplier_id) == "":
			untraced += 1
	if untraced == 0:
		return {"passed": true, "detail": "All lots carry a supplier record"}
	return {
		"passed": false,
		"detail": "%d lot%s without supplier records" % [untraced, "" if untraced == 1 else "s"],
		"corrective": "Use up or discard untraceable stock; buy through suppliers",
		"needed": "Every stock lot traceable to a supplier",
	}


func _check_cleanliness(rest) -> Dictionary:
	var min_avg: float = float(_knob("government.inspection.min_avg_cleanliness", 0.55))
	var layout = rest.interior_layout if rest != null else null
	if layout == null or layout.placed.is_empty():
		return {"passed": true, "detail": "No furnishings to assess"}
	var total: float = 0.0
	for item in layout.placed:
		total += item.cleanliness
	var avg: float = total / float(layout.placed.size())
	if avg >= min_avg:
		return {"passed": true, "detail": "Cleanliness %d%%" % int(round(avg * 100.0))}
	return {
		"passed": false,
		"detail": "Cleanliness %d%% (minimum %d%%)" % [int(round(avg * 100.0)), int(round(min_avg * 100.0))],
		"corrective": "Clean the interior (repair crew or staff downtime)",
		"needed": "Average cleanliness at or above %d%%" % int(round(min_avg * 100.0)),
	}


func _check_equipment(rest) -> Dictionary:
	var min_durability: float = float(_knob("government.inspection.min_equipment_durability", 30.0))
	var layout = rest.interior_layout if rest != null else null
	if layout == null or layout.placed.is_empty():
		return {"passed": true, "detail": "No equipment to assess"}
	var worst: float = 100.0
	var failing: int = 0
	for item in layout.placed:
		worst = minf(worst, item.durability)
		if item.durability < min_durability:
			failing += 1
	if failing == 0:
		return {"passed": true, "detail": "All equipment above %d%% condition" % int(min_durability)}
	return {
		"passed": false,
		"detail": "%d item%s below %d%% durability (worst %d%%)" % [failing, "" if failing == 1 else "s", int(min_durability), int(worst)],
		"corrective": "Repair or replace worn furniture and equipment",
		"needed": "Every placed item at or above %d%% durability" % int(min_durability),
	}


func _check_permit(ctx: Dictionary, permit_id: StringName, label: String) -> Dictionary:
	var civic = ctx.get("civic")
	var day: int = int(ctx.get("day", 0))
	if civic != null and civic.has_active_permit(permit_id, day):
		return {"passed": true, "detail": "%s active" % label}
	return {
		"passed": false,
		"detail": "%s missing or lapsed" % label,
		"corrective": "Renew the permit at City Hall",
		"needed": "%s active on inspection day" % label,
	}


func _check_staffing_coverage(rest) -> Dictionary:
	if rest == null or rest.staff.is_empty():
		return {
			"passed": false,
			"detail": "No staff employed at this branch",
			"corrective": "Hire staff and schedule them for opening hours",
			"needed": "At least one staff member on shift during open hours",
		}
	var probe_hour: float = clampf(rest.open_hour + 1.0, 0.0, 23.0)
	var on_shift: int = 0
	for member in rest.staff:
		if member.on_shift(probe_hour):
			on_shift += 1
	if on_shift > 0:
		return {"passed": true, "detail": "%d staff cover opening hours" % on_shift}
	return {
		"passed": false,
		"detail": "No staff scheduled at %02d:00" % int(probe_hour),
		"corrective": "Adjust shifts to cover opening hours",
		"needed": "At least one staff member on shift during open hours",
	}


func _check_overwork(rest) -> Dictionary:
	var max_hours: float = float(_knob("government.inspection.max_shift_hours", 12.0))
	var over: int = 0
	if rest != null:
		for member in rest.staff:
			if member.shift_hours > max_hours:
				over += 1
	if over == 0:
		return {"passed": true, "detail": "All shifts within %d hours" % int(max_hours)}
	return {
		"passed": false,
		"detail": "%d staff on shifts over %d hours" % [over, int(max_hours)],
		"corrective": "Shorten shifts in the schedule planner",
		"needed": "No shift longer than %d hours" % int(max_hours),
	}


func _check_injuries(rest, ctx: Dictionary) -> Dictionary:
	var day: int = int(ctx.get("day", 0))
	var working_injured: int = 0
	if rest != null:
		for member in rest.staff:
			if member.is_injured(day) and not member.is_absent(day):
				working_injured += 1
	if working_injured == 0:
		return {"passed": true, "detail": "No injured staff on duty"}
	return {
		"passed": false,
		"detail": "%d injured staff still working" % working_injured,
		"corrective": "Send injured staff on leave until recovered",
		"needed": "No injured staff on active duty",
	}


func _check_tax_ledger(ctx: Dictionary) -> Dictionary:
	var threshold: float = float(_knob("government.tax.audit_threshold", 0.2))
	var ratio: float = float(ctx.get("tax_ratio", 1.0))
	if ratio >= 1.0 - threshold:
		return {"passed": true, "detail": "Tax ledger consistent"}
	return {
		"passed": false,
		"detail": "Tax shortfall of %d%% against recorded revenue" % int(round((1.0 - ratio) * 100.0)),
		"corrective": "Settle outstanding tax with the city",
		"needed": "Tax paid within %d%% of the assessed amount" % int(round(threshold * 100.0)),
	}


func _check_outstanding_fines(ctx: Dictionary) -> Dictionary:
	var civic = ctx.get("civic")
	var day: int = int(ctx.get("day", 0))
	var overdue: int = 0
	if civic != null:
		for row: Dictionary in civic.unpaid_fines():
			if day > int(row.get("appeal_deadline_day", 0)):
				overdue += 1
	if overdue == 0:
		return {"passed": true, "detail": "No overdue fines"}
	return {
		"passed": false,
		"detail": "%d fine%s past the payment deadline" % [overdue, "" if overdue == 1 else "s"],
		"corrective": "Pay outstanding fines at City Hall",
		"needed": "No fines past their deadline",
	}


func _knob(path: String, fallback: Variant) -> Variant:
	if _tuning.is_valid():
		return _tuning.call(path, fallback)
	return fallback
