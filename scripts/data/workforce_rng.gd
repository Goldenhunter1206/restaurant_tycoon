class_name WorkforceRng
extends RefCounted
## Deterministic RNG factory for slow/random workforce processes — resignations,
## labor-market generation and contention, and city labor events. Every stream is
## seeded from the world seed + a domain tag + the sim day + caller keys, so a
## given save reproduces identically on reload and stays identical at all time
## speeds. Distinct domains keep unrelated streams from correlating.
## Usage: var rng := WorkforceRng.make(&"resign", day, [building_id, uid])
##
## GameSetup is reached through the tree rather than the autoload global so this
## helper also compiles under `godot --headless --script` (which skips autoloads).

static func make(domain: StringName, day: int, keys: Array = []) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var key := "%d:%s:%d" % [_world_seed(), domain, day]
	for part: Variant in keys:
		key += ":" + str(part)
	rng.seed = hash(key)
	return rng


static func _world_seed() -> int:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var setup: Node = (loop as SceneTree).root.get_node_or_null("/root/GameSetup")
		if setup != null:
			return int(setup.get("world_seed"))
	return 0
