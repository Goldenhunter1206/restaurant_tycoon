extends SceneTree
## Dev-only headless test for the recipe system's deterministic core.
## Run: godot --headless --path . --script res://scripts/dev/test_recipe_scoring.gd
## Exits 0 when every assertion passes, 1 otherwise. No autoloads are running
## here, so only the pure catalog/scoring surface is exercised; save/load and
## demand integration are covered by runtime QA.

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var rm: Node = load("res://scripts/autoload/recipe_manager.gd").new()
	rm._load_catalogs()
	rm.reset_book()

	_test_catalogs(rm)
	_test_starters_valid(rm)
	_test_determinism(rm)
	_test_burger_reorder(rm)
	_test_segment_separation(rm)
	_test_serialize_roundtrip(rm)
	_test_versioning(rm)

	print("---")
	print("%d checks, %d failures" % [_checks, _failures])
	rm.free()
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s" % label)


func _test_catalogs(rm: Node) -> void:
	print("catalogs:")
	_check(rm.ingredients.size() == 40, "40 ingredients loaded (got %d)" % rm.ingredients.size())
	_check(rm.bases.size() == 6, "6 bases loaded (got %d)" % rm.bases.size())
	_check(rm.starter_recipes.size() == 4, "4 starter recipes loaded (got %d)" % rm.starter_recipes.size())
	_check(rm.is_recipe(&"margherita"), "legacy dish id 'margherita' resolves to a recipe")
	_check(rm.is_recipe(&"cheeseburger"), "legacy dish id 'cheeseburger' resolves to a recipe")
	_check(not rm.is_recipe(&"hotdog"), "'hotdog' stays a fixed dish")


func _test_starters_valid(rm: Node) -> void:
	print("starter validity:")
	for id: StringName in [&"margherita", &"pepperoni", &"classic_burger", &"cheeseburger"]:
		var rec: RecipeDef = rm.recipe(id)
		_check(rec != null, "%s exists in book" % id)
		if rec == null:
			continue
		_check(not rm.has_errors(rec), "%s has no validation errors" % id)
		_check(rec.cached_cost > 0.0, "%s cost cached (%.2f)" % [id, rec.cached_cost])
		_check(rec.cached_prep > 0.0, "%s prep cached (%.1f)" % [id, rec.cached_prep])


func _test_determinism(rm: Node) -> void:
	print("determinism:")
	var rec: RecipeDef = rm.recipe(&"pepperoni")
	rm.recalc(rec)
	var appeal_a: Dictionary = rec.cached_appeal.duplicate(true)
	var cost_a: float = rec.cached_cost
	rm.recalc(rec)
	_check(rec.cached_cost == cost_a, "recalc cost is stable")
	var same: bool = true
	for seg: StringName in appeal_a:
		if not is_equal_approx(float(appeal_a[seg]), float(rec.cached_appeal[seg])):
			same = false
	_check(same, "recalc per-segment appeal is stable")
	var s1: Dictionary = rm.score(rec)
	var s2: Dictionary = rm.score(rec)
	_check(is_equal_approx(float(s1["overall"]), float(s2["overall"])), "score() is deterministic")


func _test_burger_reorder(rm: Node) -> void:
	print("burger reorder:")
	var rec: RecipeDef = rm.recipe(&"cheeseburger").duplicate_recipe()
	rm.recalc(rec)
	var before: float = rec.cached_structure
	var qty_before: float = 0.0
	for c: RecipeComponent in rec.components:
		qty_before += c.quantity
	# Move the sauce from the bottom (index 0) to directly under the top bun.
	var sauce: RecipeComponent = null
	var top_index: int = 0
	for c: RecipeComponent in rec.components:
		top_index = maxi(top_index, c.stack_index)
		if c.role == &"sauce":
			sauce = c
	sauce.stack_index = top_index + 1
	rm.recalc(rec)
	var qty_after: float = 0.0
	for c: RecipeComponent in rec.components:
		qty_after += c.quantity
	_check(rec.cached_structure < before,
		"wet layer under top bun lowers structure (%.2f -> %.2f)" % [before, rec.cached_structure])
	_check(is_equal_approx(qty_before, qty_after), "reorder does not change quantities")


func _test_segment_separation(rm: Node) -> void:
	print("segment separation:")
	# Spicy pizza aimed at teens/students.
	var spicy: RecipeDef = RecipeDef.new()
	spicy.product_type = &"pizza"
	spicy.base_id = &"deep_dish"
	spicy.components.append(_pizza_comp(&"hot_sauce", &"sauce", 1.0))
	spicy.components.append(_pizza_comp(&"cheddar", &"cheese", 1.5))
	spicy.components.append(_pizza_comp(&"jalapeno", &"topping", 3.0))
	spicy.components.append(_pizza_comp(&"pepperoni", &"topping", 3.0))
	rm.recalc(spicy)
	# Mild classic aimed at families/seniors.
	var mild: RecipeDef = RecipeDef.new()
	mild.product_type = &"pizza"
	mild.base_id = &"classic_crust"
	mild.components.append(_pizza_comp(&"tomato_sauce", &"sauce", 1.0))
	mild.components.append(_pizza_comp(&"mozzarella", &"cheese", 2.0))
	mild.components.append(_pizza_comp(&"tomato", &"topping", 2.0))
	mild.components.append(_pizza_comp(&"mushroom", &"topping", 2.0))
	rm.recalc(mild)
	var spicy_teens: float = float(spicy.cached_appeal[&"teens"])
	var spicy_seniors: float = float(spicy.cached_appeal[&"seniors"])
	var mild_teens: float = float(mild.cached_appeal[&"teens"])
	var mild_seniors: float = float(mild.cached_appeal[&"seniors"])
	_check(spicy_teens > spicy_seniors,
		"spicy: teens %.2f > seniors %.2f" % [spicy_teens, spicy_seniors])
	_check(mild_seniors > spicy_seniors,
		"seniors prefer mild %.2f over spicy %.2f" % [mild_seniors, spicy_seniors])
	_check(spicy_teens > mild_teens,
		"teens prefer spicy %.2f over mild %.2f" % [spicy_teens, mild_teens])


func _test_serialize_roundtrip(rm: Node) -> void:
	print("serialize roundtrip:")
	var rec: RecipeDef = rm.recipe(&"margherita").duplicate_recipe()
	rec.components[2].pos = Vector2(0.3121, 0.6817)
	rec.components[2].radius = 0.4242
	var path: String = "user://_test_recipe_roundtrip.tres"
	var err: Error = ResourceSaver.save(rec, path)
	_check(err == OK, "recipe saves to .tres")
	var loaded: RecipeDef = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded != null, "recipe loads back")
	if loaded != null:
		_check(loaded.components[2].pos == rec.components[2].pos,
			"normalized pizza pos survives exactly")
		_check(is_equal_approx(loaded.components[2].radius, 0.4242), "radius survives exactly")
		_check(loaded.components.size() == rec.components.size(), "component count survives")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_versioning(rm: Node) -> void:
	print("versioning:")
	var draft: RecipeDef = RecipeDef.new()
	draft.product_type = &"burger"
	draft.base_id = &"brioche_bun"
	draft.display_name = "Test Stack"
	var patty: RecipeComponent = RecipeComponent.new()
	patty.ingredient_id = &"beef_patty"
	patty.role = &"patty"
	patty.stack_index = 0
	patty.thickness = 1.6
	draft.components.append(patty)
	var id: StringName = rm.save_recipe(draft)
	_check(String(id).begins_with("rcp_"), "custom recipe gets a rcp_ uid (%s)" % id)
	_check(rm.recipe(id).version == 1, "new recipe starts at version 1")
	var edited: RecipeDef = rm.recipe(id).duplicate_recipe()
	var cheese: RecipeComponent = RecipeComponent.new()
	cheese.ingredient_id = &"cheddar"
	cheese.role = &"cheese"
	cheese.stack_index = 1
	cheese.thickness = 0.3
	edited.components.append(cheese)
	rm.save_recipe(edited)
	_check(rm.recipe(id).version == 2, "editing bumps version to 2")
	_check(rm.book.archived.size() == 1, "old version frozen into archive")
	_check(rm.book.archived[0].components.size() == 1, "archived version keeps old components")
	var copy: RecipeDef = rm.clone_as_new(rm.recipe(id))
	_check(copy.id == &"" and copy.components.size() == 2, "clone is a fresh unsaved draft")


func _pizza_comp(ing: StringName, role: StringName, qty: float) -> RecipeComponent:
	var c: RecipeComponent = RecipeComponent.new()
	c.ingredient_id = ing
	c.role = role
	c.quantity = qty
	c.pos = Vector2(0.5, 0.5)
	c.radius = 0.6
	return c
