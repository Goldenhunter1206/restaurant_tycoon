extends SceneTree
## Headless entrypoint for the ManagersAutomationRegression suite (a static
## RefCounted covering command metadata, policy guardrails, assignment cooldown,
## staff bounds/midnight shift, training boundary, and seed-resource existence).
## This wrapper makes that suite runnable via the project's test convention.
## Run: godot --headless --script res://scripts/tests/test_managers_regression.gd

func _initialize() -> void:
	var result: Dictionary = ManagersAutomationRegression.run()
	var failures: Array = result.get("failures", [])
	if bool(result.get("ok", false)):
		print("PASS test_managers_regression: %d checks OK" % int(result.get("checks", 0)))
		quit(0)
	else:
		printerr("FAIL test_managers_regression: %d failure(s)" % failures.size())
		for message: Variant in failures:
			printerr("  FAIL: %s" % str(message))
		quit(1)
