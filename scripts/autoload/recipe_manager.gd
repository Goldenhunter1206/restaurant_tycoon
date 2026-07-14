extends Node
## Autoload: owns the ingredient/base/starter-recipe catalogs and the active
## company RecipeBookState. Validates, costs, scores, clones and versions
## recipes. Scoring is deterministic — same components always yield the same
## score. Registered before RestaurantManager, which resolves menu ids here.

signal book_changed

const INGREDIENT_DIR: String = "res://data/ingredients"
const BASE_DIR: String = "res://data/recipe_bases"
const STARTER_DIR: String = "res://data/recipes/starters"

const SEGMENTS: Array[StringName] = [&"teens", &"students", &"workers", &"families", &"seniors"]

## Per-segment tolerance before a trait starts to repel (0..1).
const TRAIT_TOLERANCE: Dictionary = {
	&"teens": {"spice": 0.85, "oil": 0.85, "novelty": 0.95},
	&"students": {"spice": 0.75, "oil": 0.80, "novelty": 0.90},
	&"workers": {"spice": 0.55, "oil": 0.65, "novelty": 0.70},
	&"families": {"spice": 0.35, "oil": 0.60, "novelty": 0.55},
	&"seniors": {"spice": 0.25, "oil": 0.50, "novelty": 0.45},
}

const TIER_TABLE: Array[Dictionary] = [
	{"tier": &"low", "name": "Budget", "cost_mult": 0.7, "quality": 0.25},
	{"tier": &"med", "name": "Standard", "cost_mult": 1.0, "quality": 0.55},
	{"tier": &"high", "name": "Premium", "cost_mult": 1.5, "quality": 0.9},
]

## Sales needed before predicted appeal is shown without an uncertainty band.
const CONFIDENCE_N: int = 60

const MAX_PIZZA_PORTIONS: float = 14.0
const MAX_BURGER_LAYERS: int = 8

var ingredients: Dictionary = {}
var bases: Dictionary = {}
var starter_recipes: Dictionary = {}
var book: RecipeBookState = RecipeBookState.new()

var _tier_cache: Dictionary = {}


func _ready() -> void:
	_load_catalogs()
	reset_book()


func _load_catalogs() -> void:
	ingredients.clear()
	bases.clear()
	starter_recipes.clear()
	for res: Resource in _load_dir(INGREDIENT_DIR):
		var ing: IngredientDef = res as IngredientDef
		if ing != null and ing.id != &"":
			ingredients[ing.id] = ing
	for res: Resource in _load_dir(BASE_DIR):
		var base_def: RecipeBaseDef = res as RecipeBaseDef
		if base_def != null and base_def.id != &"":
			bases[base_def.id] = base_def
	for res: Resource in _load_dir(STARTER_DIR):
		var rec: RecipeDef = res as RecipeDef
		if rec != null and rec.id != &"":
			rec.is_starter = true
			rec.unlock_source = &"starter"
			starter_recipes[rec.id] = rec


func _load_dir(dir_path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for file: String in dir.get_files():
		if file.ends_with(".tres") or file.ends_with(".res"):
			var res: Resource = load(dir_path + "/" + file)
			if res != null:
				out.append(res)
	return out


## Fresh book for a new game: starters cloned in so edits never touch .tres.
func reset_book() -> void:
	book = RecipeBookState.new()
	for id: StringName in starter_recipes:
		var starter: RecipeDef = starter_recipes[id]
		var copy: RecipeDef = starter.duplicate_recipe()
		recalc(copy)
		book.recipes.append(copy)
		# New restaurants open selling pizza (matches pre-recipe behavior).
		if copy.product_type == &"pizza":
			book.base_menu_ids.append(copy.id)
	_tier_cache.clear()


# ---------------------------------------------------------------- lookups

func ingredient(id: StringName) -> IngredientDef:
	return ingredients.get(id)


func base(id: StringName) -> RecipeBaseDef:
	return bases.get(id)


func is_recipe(id: StringName) -> bool:
	return recipe(id) != null


func recipe(id: StringName) -> RecipeDef:
	for rec: RecipeDef in book.recipes:
		if rec.id == id:
			return rec
	for rec: RecipeDef in book.archived:
		if rec.id == id:
			return rec
	return starter_recipes.get(id)


func live_recipes() -> Array[RecipeDef]:
	var out: Array[RecipeDef] = []
	for rec: RecipeDef in book.recipes:
		if not rec.archived:
			out.append(rec)
	return out


## The shared starter catalog every rival can cook, independent of the
## player's book state (recipe() resolves these ids via its starter
## fallback, so rival menus survive player archiving).
func rival_recipe_pool() -> Array[RecipeDef]:
	var out: Array[RecipeDef] = []
	for id: StringName in starter_recipes:
		out.append(starter_recipes[id])
	return out


func category_for(id: StringName) -> StringName:
	var rec: RecipeDef = recipe(id)
	return rec.product_type if rec != null else &""


## Quality tiers for a recipe, derived from its cost. Mirrors the dish
## low/med/high convention so MenuEntry.tier keeps working unchanged.
func tiers_for(id: StringName) -> Array[QualityTier]:
	var rec: RecipeDef = recipe(id)
	if rec == null:
		return []
	var key: String = "%s@%d" % [id, rec.version]
	if _tier_cache.has(key):
		return _tier_cache[key]
	var tiers: Array[QualityTier] = []
	for row: Dictionary in TIER_TABLE:
		var t: QualityTier = QualityTier.new()
		t.tier = row["tier"]
		t.display_name = row["name"]
		t.ingredient_cost = snappedf(rec.cached_cost * float(row["cost_mult"]), 0.01)
		t.quality_score = float(row["quality"])
		tiers.append(t)
	_tier_cache[key] = tiers
	return tiers


func suggested_price_for(rec: RecipeDef) -> float:
	if rec.suggested_price > 0.0:
		return rec.suggested_price
	return maxf(1.0, snappedf(rec.cached_cost * 3.0, 0.5))


func tier_for(id: StringName, tier_id: StringName) -> QualityTier:
	var tiers: Array[QualityTier] = tiers_for(id)
	for t: QualityTier in tiers:
		if t.tier == tier_id:
			return t
	return tiers[0] if not tiers.is_empty() else null


# ---------------------------------------------------------------- lifecycle

func new_draft(product_type: StringName, base_id: StringName) -> RecipeDef:
	var rec: RecipeDef = RecipeDef.new()
	rec.product_type = product_type
	rec.base_id = base_id
	rec.display_name = "New %s" % ("Pizza" if product_type == &"pizza" else "Burger")
	rec.created_day = GameClock.day
	recalc(rec)
	return rec


## Persist a draft into the book. New recipes get a uid; edits to an existing
## live recipe freeze the old version into the archive and bump version.
func save_recipe(rec: RecipeDef) -> StringName:
	recalc(rec)
	if rec.id == &"":
		rec.id = StringName("rcp_%06d" % book.next_recipe_uid)
		book.next_recipe_uid += 1
		rec.version = 1
		book.recipes.append(rec)
	else:
		var existing: RecipeDef = null
		for r: RecipeDef in book.recipes:
			if r.id == rec.id:
				existing = r
				break
		if existing != null and existing != rec:
			var frozen: RecipeDef = existing.duplicate_recipe()
			frozen.archived = true
			book.archived.append(frozen)
			rec.version = existing.version + 1
			book.recipes[book.recipes.find(existing)] = rec
		elif existing == null:
			book.recipes.append(rec)
	_tier_cache.clear()
	book_changed.emit()
	return rec.id


func clone_as_new(rec: RecipeDef) -> RecipeDef:
	var copy: RecipeDef = rec.duplicate_recipe()
	copy.id = &""
	copy.version = 1
	copy.is_starter = false
	copy.unlock_source = &"custom"
	copy.archived = false
	copy.display_name = "%s Copy" % rec.display_name
	return copy


func archive(rec: RecipeDef) -> void:
	rec.archived = true
	book_changed.emit()


func unarchive(rec: RecipeDef) -> void:
	rec.archived = false
	book_changed.emit()


# ---------------------------------------------------------------- persistence

func export_book() -> RecipeBookState:
	return book


func load_book(state: RecipeBookState) -> void:
	if state == null:
		reset_book()
	else:
		book = state
		_ensure_starters()
		for rec: RecipeDef in book.recipes:
			recalc(rec)
	_tier_cache.clear()
	book_changed.emit()


func _ensure_starters() -> void:
	for id: StringName in starter_recipes:
		var found: bool = false
		for rec: RecipeDef in book.recipes:
			if rec.id == id:
				found = true
				break
		if not found:
			var copy: RecipeDef = (starter_recipes[id] as RecipeDef).duplicate_recipe()
			recalc(copy)
			book.recipes.append(copy)


# ---------------------------------------------------------------- validation

## Returns [{severity: "error"|"warning", code: StringName, msg: String}].
func validate(rec: RecipeDef) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var base_def: RecipeBaseDef = base(rec.base_id)
	if base_def == null:
		issues.append({"severity": "error", "code": &"missing_base", "msg": "No base selected."})
	elif base_def.product_type != rec.product_type:
		issues.append({"severity": "error", "code": &"base_mismatch", "msg": "Base does not fit this product type."})
	if rec.components.is_empty():
		issues.append({"severity": "error", "code": &"empty", "msg": "Add at least one ingredient."})
	var sauce_count: float = 0.0
	var portions: float = 0.0
	for c: RecipeComponent in rec.components:
		var ing: IngredientDef = ingredient(c.ingredient_id)
		if ing == null:
			issues.append({"severity": "warning", "code": &"missing_ingredient",
				"msg": "Ingredient '%s' is no longer available." % c.ingredient_id})
			continue
		if not ing.allows_product(rec.product_type):
			issues.append({"severity": "error", "code": &"bad_product",
				"msg": "%s cannot be used on a %s." % [ing.display_name, rec.product_type]})
		if not ing.allows_role(c.role):
			issues.append({"severity": "error", "code": &"bad_role",
				"msg": "%s cannot be used as %s." % [ing.display_name, c.role]})
		portions += c.quantity
		if c.role == &"sauce" or c.role == &"spread":
			sauce_count += c.quantity
	if sauce_count > 2.0:
		issues.append({"severity": "warning", "code": &"too_much_sauce",
			"msg": "Heavy sauce load — messy to eat and slow to plate."})
	if rec.product_type == &"pizza" and portions > MAX_PIZZA_PORTIONS:
		issues.append({"severity": "warning", "code": &"overloaded",
			"msg": "Overloaded pizza — toppings won't cook evenly."})
	if rec.product_type == &"burger":
		if rec.components.size() > MAX_BURGER_LAYERS:
			issues.append({"severity": "warning", "code": &"tall_stack",
				"msg": "Tall stack — slower to plate at rush."})
		var wet: StringName = _wet_top_layer(rec)
		if wet != &"":
			issues.append({"severity": "warning", "code": &"wet_top",
				"msg": "Wet layer right under the top bun — soggy bun."})
	return issues


func has_errors(rec: RecipeDef) -> bool:
	for issue: Dictionary in validate(rec):
		if String(issue["severity"]) == "error":
			return true
	return false


# ---------------------------------------------------------------- scoring

## Recompute all cached derived values from components (authoritative data).
func recalc(rec: RecipeDef) -> void:
	var base_def: RecipeBaseDef = base(rec.base_id)
	var cost: float = base_def.base_cost if base_def != null else 0.0
	var prep: float = base_def.base_prep_minutes if base_def != null else 8.0
	for c: RecipeComponent in rec.components:
		var ing: IngredientDef = ingredient(c.ingredient_id)
		if ing == null:
			continue  # missing ingredient stays in the array but adds nothing
		cost += ing.unit_cost * c.quantity
		prep += ing.prep_mod * c.quantity
	rec.cached_cost = snappedf(cost, 0.01)
	rec.cached_prep = snappedf(prep, 0.1)
	rec.cached_structure = _structure_score(rec) if rec.product_type == &"burger" else 1.0
	var appeal: Dictionary = {}
	for segment: StringName in SEGMENTS:
		appeal[segment] = _segment_score(rec, segment)
	rec.cached_appeal = appeal


## Deterministic per-segment appeal, 0..1.
func _segment_score(rec: RecipeDef, segment: StringName) -> float:
	var base_def: RecipeBaseDef = base(rec.base_id)
	var portions: float = 0.0
	var aff_sum: float = 0.0
	var spice_sum: float = 0.0
	var oil_sum: float = 0.0
	var novelty_sum: float = 0.0
	var quality_sum: float = 0.0
	var sauce_qty: float = 0.0
	for c: RecipeComponent in rec.components:
		var ing: IngredientDef = ingredient(c.ingredient_id)
		if ing == null:
			continue
		portions += c.quantity
		aff_sum += ing.affinity_for(segment) * c.quantity
		spice_sum += ing.spice * c.quantity
		oil_sum += ing.oil * c.quantity
		novelty_sum += ing.novelty * c.quantity
		quality_sum += ing.quality * c.quantity
		if c.role == &"sauce" or c.role == &"spread":
			sauce_qty += c.quantity
	if portions <= 0.0:
		return 0.0
	var aff: float = aff_sum / portions
	var avg_spice: float = spice_sum / portions
	var avg_oil: float = oil_sum / portions
	var avg_novelty: float = novelty_sum / portions
	var avg_quality: float = quality_sum / portions
	var tol: Dictionary = TRAIT_TOLERANCE.get(segment, {})
	var penalty: float = 0.0
	penalty += maxf(0.0, avg_spice - float(tol.get("spice", 0.6))) * 0.8
	penalty += maxf(0.0, avg_oil - float(tol.get("oil", 0.7))) * 0.5
	penalty += maxf(0.0, avg_novelty - float(tol.get("novelty", 0.7))) * 0.5
	penalty += maxf(0.0, sauce_qty - 2.0) * 0.12
	var base_aff: float = base_def.affinity_for(segment) if base_def != null else 0.0
	var score: float = 0.5 + aff * 0.35 + base_aff * 0.12 + (avg_quality - 0.5) * 0.15
	if rec.product_type == &"pizza":
		score += (_pizza_spatial_score(rec) - 0.5) * 0.25
		if portions > MAX_PIZZA_PORTIONS:
			penalty += (portions - MAX_PIZZA_PORTIONS) * 0.03
	else:
		score += (_structure_score(rec) - 0.7) * 0.35
	return clampf(score - penalty, 0.0, 1.0)


## Analytic coverage + evenness of topping placement on the unit disc, 0..1.
func _pizza_spatial_score(rec: RecipeDef) -> float:
	var toppings: Array[RecipeComponent] = []
	for c: RecipeComponent in rec.components:
		if c.role == &"topping" or c.role == &"cheese":
			toppings.append(c)
	if toppings.is_empty():
		return 0.5
	var covered: float = 0.0
	var centroid: Vector2 = Vector2.ZERO
	var weight: float = 0.0
	for c: RecipeComponent in toppings:
		covered += c.quantity * (0.07 + c.radius * 0.18) * c.scale
		centroid += c.pos * c.quantity
		weight += c.quantity
	centroid /= weight
	var coverage: float = clampf(covered, 0.0, 1.0)
	if covered > 1.2:
		coverage = maxf(0.0, 1.0 - (covered - 1.2) * 0.5)  # overcrowding
	var evenness: float = 1.0 - clampf(centroid.distance_to(Vector2(0.5, 0.5)) * 2.5, 0.0, 1.0)
	return clampf(coverage * 0.6 + evenness * 0.4, 0.0, 1.0)


## Burger stability, 0..1 (1 = stable). Order-sensitive: reordering layers
## changes the score at constant quantities.
func _structure_score(rec: RecipeDef) -> float:
	if rec.components.is_empty():
		return 1.0
	var stack: Array[RecipeComponent] = rec.sorted_stack()
	var height: float = 0.0
	var sauce_load: float = 0.0
	var penalty: float = 0.0
	for c: RecipeComponent in stack:
		height += c.thickness * c.quantity
		if c.role == &"sauce" or c.role == &"spread":
			sauce_load += c.quantity
	if stack.size() > 6:
		penalty += float(stack.size() - 6) * 0.08
	if height > 7.0:
		penalty += (height - 7.0) * 0.05
	if sauce_load > 2.0:
		penalty += (sauce_load - 2.0) * 0.1
	if _wet_top_layer(rec) != &"":
		penalty += 0.12
	var patty_index: int = -1
	for i: int in stack.size():
		if stack[i].role == &"patty":
			patty_index = i
			break
	if patty_index > 1:
		penalty += float(patty_index - 1) * 0.06  # patty floating high = unstable
	return clampf(1.0 - penalty, 0.0, 1.0)


## Returns the ingredient id of a wet layer directly under the top bun, or &"".
func _wet_top_layer(rec: RecipeDef) -> StringName:
	var stack: Array[RecipeComponent] = rec.sorted_stack()
	if stack.is_empty():
		return &""
	var top: RecipeComponent = stack[stack.size() - 1]
	if top.role == &"sauce" or top.role == &"spread":
		return top.ingredient_id
	return &""


## Full score payload for UI: per-segment, overall (unweighted), structure,
## and uncertainty (shrinks as real sales accumulate).
func score(rec: RecipeDef, tier_id: StringName = &"med") -> Dictionary:
	recalc(rec)
	var by_segment: Dictionary = {}
	var total: float = 0.0
	var tier_bonus: float = _tier_bonus(tier_id)
	for segment: StringName in SEGMENTS:
		var s: float = clampf(float(rec.cached_appeal.get(segment, 0.0)) + tier_bonus, 0.0, 1.0)
		by_segment[segment] = s
		total += s
	return {
		"by_segment": by_segment,
		"overall": total / float(SEGMENTS.size()),
		"structure": rec.cached_structure,
		"uncertainty": uncertainty_for(rec.id),
	}


func segment_appeal(id: StringName, tier_id: StringName, segment: StringName) -> float:
	var rec: RecipeDef = recipe(id)
	if rec == null:
		return 0.0
	return clampf(float(rec.cached_appeal.get(segment, 0.0)) + _tier_bonus(tier_id), 0.0, 1.0)


## Blend per-segment appeal by the customer profile around a building.
func overall_appeal(id: StringName, tier_id: StringName, building_id: int) -> float:
	var profile: Dictionary = DemandManager.customer_profile(building_id)
	if profile.is_empty():
		var rec: RecipeDef = recipe(id)
		if rec == null:
			return 0.0
		var total: float = 0.0
		for segment: StringName in SEGMENTS:
			total += segment_appeal(id, tier_id, segment)
		return total / float(SEGMENTS.size())
	var blended: float = 0.0
	for segment: StringName in SEGMENTS:
		blended += segment_appeal(id, tier_id, segment) * float(profile.get(segment, 0.0))
	return blended


func _tier_bonus(tier_id: StringName) -> float:
	for row: Dictionary in TIER_TABLE:
		if row["tier"] == tier_id:
			return (float(row["quality"]) - 0.55) * 0.2
	return 0.0


func uncertainty_for(id: StringName) -> float:
	return clampf(1.0 - float(observed_units(id)) / float(CONFIDENCE_N), 0.0, 1.0)


## Total units sold of a recipe (all versions) across all owned restaurants.
func observed_units(id: StringName) -> int:
	var units: int = 0
	var prefix: String = "%s@" % id
	for rest: RestaurantState in RestaurantManager.owned:
		for key: String in rest.recipe_sales:
			if key.begins_with(prefix):
				units += int(rest.recipe_sales[key].get("units", 0))
	return units


## Company-wide roll-up for the Performance tab: units, revenue, cost, and
## per-segment unit counts, summed across restaurants for one recipe version
## (or all versions when version == 0).
func company_stats(id: StringName, version: int = 0) -> Dictionary:
	var out: Dictionary = {"units": 0, "revenue": 0.0, "cost": 0.0, "by_segment": {}}
	var match_key: String = "%s@%d" % [id, version]
	var prefix: String = "%s@" % id
	for rest: RestaurantState in RestaurantManager.owned:
		for key: String in rest.recipe_sales:
			if (version > 0 and key != match_key) or (version == 0 and not key.begins_with(prefix)):
				continue
			var row: Dictionary = rest.recipe_sales[key]
			out["units"] += int(row.get("units", 0))
			out["revenue"] += float(row.get("revenue", 0.0))
			out["cost"] += float(row.get("cost", 0.0))
			var seg_counts: Dictionary = row.get("by_segment", {})
			for segment: StringName in seg_counts:
				out["by_segment"][segment] = int(out["by_segment"].get(segment, 0)) + int(seg_counts[segment])
	return out
