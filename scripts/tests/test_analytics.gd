extends SceneTree
## Headless entry point for the analytics reconciliation + determinism suite.
## Run: godot --headless --script res://scripts/tests/test_analytics.gd
## Exit code 0 = pass, 1 = fail.


func _initialize() -> void:
	var result: Dictionary = AnalyticsReconciliation.run()
	var failures: Array = result.get("failures", [])
	if bool(result.get("ok", false)):
		print("PASS test_analytics: %d checks OK" % int(result.get("checks", 0)))
		quit(0)
	else:
		printerr("FAIL test_analytics: %d of %d checks failed" % [failures.size(), int(result.get("checks", 0))])
		for f: String in failures:
			printerr("  - %s" % f)
		quit(1)
