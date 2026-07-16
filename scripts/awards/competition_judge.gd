class_name CompetitionJudge
extends RefCounted
## Pure deterministic competition judging. AwardsManager supplies a recipe
## scorer Callable(recipe, tier, segments) -> 0..1 and an rng maker
## Callable(company_id) -> RandomNumberGenerator seeded from the frozen
## seed_day, so a judged CompetitionState reproduces bit-identically from its
## stored entries. Every scoring component lands in the results rows.


func judge(comp: CompetitionState, def: CompetitionDef, recipe_scorer: Callable, rng_for: Callable) -> void:
	var w_recipe: float = float(def.judging.get("recipe", 0.6))
	var w_comply: float = float(def.judging.get("compliance", 0.25))
	var w_novelty: float = float(def.judging.get("novelty", 0.15))
	var noise_range: float = float(def.judging.get("noise_range", 0.05))
	var rows: Array[Dictionary] = []
	for entry: Dictionary in comp.entries:
		var recipe: RecipeDef = entry.get("recipe")
		if recipe == null:
			continue
		var tier: StringName = StringName(entry.get("tier", &"med"))
		var company_id: StringName = StringName(entry.get("company_id", &""))
		var recipe_score: float = clampf(float(recipe_scorer.call(recipe, tier, def.target_demographics)), 0.0, 1.0)
		var comply: Dictionary = compliance(recipe, def)
		var novelty: float = novelty_of(recipe, comp.entries)
		var rng: RandomNumberGenerator = rng_for.call(company_id)
		var noise: float = rng.randf_range(-noise_range, noise_range)
		rows.append({
			"company_id": company_id,
			"recipe_name": recipe.display_name,
			"tier": tier,
			"recipe_score": recipe_score,
			"compliance": float(comply["score"]),
			"compliance_notes": comply["notes"],
			"novelty": novelty,
			"noise": noise,
			"noise_range": noise_range,
			"total": w_recipe * recipe_score + w_comply * float(comply["score"]) + w_novelty * novelty + noise,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a["total"]) - float(b["total"])) > 0.000001:
			return float(a["total"]) > float(b["total"])
		return hash(String(a["company_id"])) < hash(String(b["company_id"])))
	for i: int in rows.size():
		rows[i]["rank"] = i + 1
	comp.results = rows
	comp.winner_company_id = StringName(rows[0]["company_id"]) if not rows.is_empty() else &""


## Constraint compliance: every check listed in notes; score = passed fraction.
func compliance(recipe: RecipeDef, def: CompetitionDef) -> Dictionary:
	var notes: Array[Dictionary] = []
	if def.product_type != &"":
		notes.append({"check": &"product_type", "passed": recipe.product_type == def.product_type})
	var rules: Dictionary = def.constraints
	if rules.has("max_cost"):
		notes.append({"check": &"max_cost", "passed": recipe.cached_cost <= float(rules["max_cost"])})
	if rules.has("max_price"):
		var price: float = recipe.suggested_price if recipe.suggested_price > 0.0 else recipe.cached_cost * 2.0
		notes.append({"check": &"max_price", "passed": price <= float(rules["max_price"])})
	if rules.has("min_components"):
		notes.append({"check": &"min_components", "passed": recipe.components.size() >= int(rules["min_components"])})
	if rules.has("max_components"):
		notes.append({"check": &"max_components", "passed": recipe.components.size() <= int(rules["max_components"])})
	if rules.has("require_ingredient"):
		var wanted: StringName = StringName(String(rules["require_ingredient"]))
		var found: bool = false
		for component: RecipeComponent in recipe.components:
			if component.ingredient_id == wanted:
				found = true
				break
		notes.append({"check": &"require_ingredient", "passed": found})
	if notes.is_empty():
		return {"score": 1.0, "notes": notes}
	var passed: int = 0
	for note: Dictionary in notes:
		if bool(note["passed"]):
			passed += 1
	return {"score": float(passed) / notes.size(), "notes": notes}


## Ingredient-set distinctiveness vs the other entries (1 - max Jaccard).
func novelty_of(recipe: RecipeDef, entries: Array[Dictionary]) -> float:
	var own: Dictionary = _ingredient_set(recipe)
	var max_similarity: float = 0.0
	var others: int = 0
	for entry: Dictionary in entries:
		var other: RecipeDef = entry.get("recipe")
		if other == null or other == recipe:
			continue
		others += 1
		max_similarity = maxf(max_similarity, _jaccard(own, _ingredient_set(other)))
	if others == 0:
		return 0.5
	return clampf(1.0 - max_similarity, 0.0, 1.0)


func _ingredient_set(recipe: RecipeDef) -> Dictionary:
	var out: Dictionary = {}
	for component: RecipeComponent in recipe.components:
		out[component.ingredient_id] = true
	return out


func _jaccard(a: Dictionary, b: Dictionary) -> float:
	if a.is_empty() and b.is_empty():
		return 1.0
	var overlap: int = 0
	for key: StringName in a:
		if b.has(key):
			overlap += 1
	var union_size: int = a.size() + b.size() - overlap
	return float(overlap) / union_size if union_size > 0 else 0.0
