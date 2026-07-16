extends SceneTree
## Headless entry point for the feature 11 acceptance suite (ratings, awards,
## recipe competitions). Run:
##   godot --headless --path . --script res://scripts/tests/test_awards.gd
## Exit code 0 = pass, 1 = fail.


func _initialize() -> void:
	var result: Dictionary = AwardsReconciliation.run()
	var failures: Array = result.get("failures", [])
	if bool(result.get("ok", false)):
		print("PASS test_awards: %d checks OK" % int(result.get("checks", 0)))
		quit(0)
	else:
		printerr("FAIL test_awards: %d of %d checks failed" % [failures.size(), int(result.get("checks", 0))])
		for f: String in failures:
			printerr("  - %s" % f)
		quit(1)
