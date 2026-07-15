class_name ManagersAutomationRegression
extends RefCounted
## Deterministic smoke/regression coverage for the policy, command metadata, and
## persistent workforce primitives. Run with ManagersAutomationRegression.run().

const POLICY_PATHS: Array[String] = [
	"res://data/management/policies/conservative.tres",
	"res://data/management/policies/growth.tres",
	"res://data/management/policies/premium.tres",
	"res://data/management/policies/value.tres",
	"res://data/management/policies/delivery_first.tres",
	"res://data/management/policies/custom.tres",
]
const TRAINING_PATHS: Array[String] = [
	"res://data/training_programs/customer_care.tres",
	"res://data/training_programs/kitchen_mastery.tres",
	"res://data/training_programs/safe_delivery.tres",
	"res://data/training_programs/stock_control.tres",
	"res://data/training_programs/hygiene_standard.tres",
	"res://data/training_programs/leadership.tres",
]


static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_command_metadata(failures)
	_test_policy_guardrails_and_copy(failures)
	_test_assignment_cooldown(failures)
	_test_staff_bounds_and_midnight_shift(failures)
	_test_training_boundary(failures)
	_test_seed_resources(failures)
	return {
		"ok": failures.is_empty(),
		"checks": 24,
		"failures": failures,
	}


static func _test_command_metadata(failures: Array[String]) -> void:
	var result := CommandResult.good({"changed": true})
	result.estimated_cost = 42.5
	result.actual_cost = 40.0
	result.explanation = "Policy check passed."
	result.permission_category = &"automatic"
	result.reversible = true
	result.undo_token = "undo:test"
	result.idempotency_key = "command:test"
	result.actor_kind = &"manager"
	result.actor_id = "manager:7"
	result.executed_at = 120
	result.metadata = {"category": &"inventory"}
	var saved := result.as_dictionary()
	var restored := CommandResult.new()
	restored.ok = bool(saved.get("ok", false))
	restored.code = StringName(saved.get("code", &"ok"))
	restored.message = str(saved.get("message", ""))
	restored.payload = saved.get("payload")
	restored.with_command_metadata(saved)
	_expect(restored.ok, "Command success did not round-trip.", failures)
	_expect(is_equal_approx(restored.actual_cost, 40.0), "Actual cost did not round-trip.", failures)
	_expect(restored.idempotency_key == "command:test", "Idempotency metadata was lost.", failures)
	_expect(restored.reversible and restored.undo_token == "undo:test",
		"Undo metadata did not round-trip.", failures)


static func _test_policy_guardrails_and_copy(failures: Array[String]) -> void:
	var policy := BranchPolicy.new()
	policy.uid = "template:test"
	policy.template_version = 3
	policy.authority_by_category = {&"inventory": BranchPolicy.AUTHORITY_AUTOMATIC}
	policy.daily_budget_by_category = {&"inventory": 500.0}
	policy.supplier_allowlist = [&"supplier_a"]
	policy.protected_staff_uids = [7]
	policy.approved_layout_templates = [&"classic_trattoria"]
	_expect(policy.authority_for(&"inventory") == BranchPolicy.AUTHORITY_AUTOMATIC,
		"Policy authority lookup failed.", failures)
	_expect(is_equal_approx(policy.budget_for(&"inventory"), 500.0),
		"Policy budget lookup failed.", failures)
	_expect(policy.allows_supplier(&"supplier_a") and not policy.allows_supplier(&"supplier_b"),
		"Supplier allowlist failed.", failures)
	_expect(policy.is_staff_protected(7), "Protected staff guardrail failed.", failures)
	_expect(policy.allows_layout(&"classic_trattoria") and not policy.allows_layout(&"unknown"),
		"Layout template guardrail failed.", failures)
	var copy := policy.copy_for_branch("policy:branch:12", 12, 4)
	copy.daily_budget_by_category[&"inventory"] = 250.0
	_expect(copy.uid == "policy:branch:12" and copy.branch_building_id == 12,
		"Branch policy copy identity failed.", failures)
	_expect(is_equal_approx(policy.budget_for(&"inventory"), 500.0),
		"Branch policy copy mutated its template.", failures)


static func _test_assignment_cooldown(failures: Array[String]) -> void:
	var assignment := ManagerAssignment.new()
	assignment.set_cooldown(&"menu", 48)
	_expect(assignment.cooldown_until(&"menu") == 48, "Manager cooldown was not recorded.", failures)
	assignment.paused_reason = "Headquarters capacity unavailable."
	_expect(assignment.is_paused(), "Assignment pause state was not reported.", failures)


static func _test_staff_bounds_and_midnight_shift(failures: Array[String]) -> void:
	var member := StaffMember.new()
	member.shift_start = 20.0
	member.shift_hours = 8.0
	member.hourly_wage = 20.0
	member.competencies = {&"service": 1.0}
	member.energy = 1.0
	member.fatigue = 0.0
	member.health = 1.0
	member.motivation = 1.0
	member.satisfaction = 1.0
	member.stress = 0.0
	_expect(member.on_shift(23.0) and member.on_shift(2.0) and not member.on_shift(10.0),
		"Schedule crossing midnight failed.", failures)
	_expect(is_equal_approx(member.daily_pay(), 160.0), "Payroll calculation failed.", failures)
	var strong_effect := member.operational_effect(&"service")
	member.energy = 0.0
	member.fatigue = 1.0
	member.health = 0.0
	member.motivation = 0.0
	member.satisfaction = 0.0
	member.stress = 1.0
	var tired_effect := member.operational_effect(&"service")
	_expect(strong_effect > tired_effect, "Condition did not bound operational skill.", failures)
	_expect(strong_effect <= 1.25 and tired_effect >= 0.25,
		"Operational effect exceeded its safety bounds.", failures)


static func _test_training_boundary(failures: Array[String]) -> void:
	var enrollment := TrainingEnrollment.new()
	enrollment.status = &"active"
	enrollment.started_window = 10
	enrollment.completes_window = 34
	enrollment.completion_applied = false
	_expect(enrollment.is_active(20), "Active training was not detected.", failures)
	_expect(not enrollment.ready_to_complete(33), "Training completed before its horizon.", failures)
	_expect(enrollment.ready_to_complete(34), "Training did not complete at its horizon.", failures)
	enrollment.completion_applied = true
	_expect(not enrollment.ready_to_complete(35), "Training completion was not exactly once.", failures)


static func _test_seed_resources(failures: Array[String]) -> void:
	for path: String in POLICY_PATHS:
		_expect(ResourceLoader.exists(path), "Missing policy resource: %s" % path, failures)
		if ResourceLoader.exists(path):
			_expect(load(path) is BranchPolicy, "Invalid policy resource: %s" % path, failures)
	for path: String in TRAINING_PATHS:
		_expect(ResourceLoader.exists(path), "Missing training resource: %s" % path, failures)
		if ResourceLoader.exists(path):
			_expect(load(path) is TrainingProgramDef, "Invalid training resource: %s" % path, failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
