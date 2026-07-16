class_name RivalIntel
extends RefCounted
## Player-facing view of a rival company built only from public information.
## Ground truth is filtered by visibility: KNOWN (visible in the world),
## ESTIMATED (noisy but stable guesses), UNKNOWN (hidden until a real
## intelligence source exists). Estimates are seeded per company per week so
## they don't jitter, and never reveal exact books.


## Branch count is public — the buildings are visible in the world.
static func branch_count(company: CompanyState) -> int:
	return company.restaurants.size()


static func districts(company: CompanyState) -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for rest: RestaurantState in company.restaurants:
		if not seen.has(rest.district):
			seen[rest.district] = true
			result.append(rest.district)
	return result


## Star ratings hang on the door — public.
static func avg_rating(company: CompanyState) -> float:
	if company.restaurants.is_empty():
		return company.reputation
	var total: float = 0.0
	for rest: RestaurantState in company.restaurants:
		total += rest.star_rating
	return total / float(company.restaurants.size())


## Menu prices are posted — public. Average across enabled entries.
static func avg_menu_price(company: CompanyState) -> float:
	var total: float = 0.0
	var count: int = 0
	for rest: RestaurantState in company.restaurants:
		for entry: MenuEntry in rest.enabled_menu():
			total += entry.price
			count += 1
	return total / float(count) if count > 0 else 0.0


## Campaigns are visible in the streets — "spotted".
static func spotted_campaigns(company: CompanyState) -> int:
	return MarketingManager.campaigns_for(company.id).size()


## Active exposure share vs everyone advertising. Exact for the player,
## blurred for rivals (you can see their ads, not their spend).
static func share_of_voice(company: CompanyState, exact: bool) -> float:
	var real: float = MarketingManager.share_of_voice(company.id)
	if exact:
		return real
	return clampf(real * _noise_factor(company, 0.3), 0.0, 1.0)


## Weekly revenue GUESS: real revenue blurred by stable per-company noise.
## Never exact; re-rolls once per in-game week.
static func estimated_revenue(company: CompanyState, days: int = 7) -> float:
	var actual: float = 0.0
	for rest: RestaurantState in company.restaurants:
		var count: int = mini(days, rest.sales_history.size())
		for i: int in count:
			actual += rest.sales_history[rest.sales_history.size() - 1 - i]
	return actual * _noise_factor(company, 0.25)


## Public composite used by the Rankings screen. Exact for the player,
## estimate-based for rivals.
static func score(company: CompanyState, exact: bool) -> float:
	var revenue: float = 0.0
	if exact:
		for rest: RestaurantState in company.restaurants:
			var count: int = mini(7, rest.sales_history.size())
			for i: int in count:
				revenue += rest.sales_history[rest.sales_history.size() - 1 - i]
	else:
		revenue = estimated_revenue(company)
	return float(company.restaurants.size()) * 1000.0 + company.reputation * 2000.0 + revenue


## Competition entries are sealed until the run is judged, then become public
## record. (A future espionage capability can unseal entries early.)
static func competition_entry_view(company: CompanyState, comp: CompetitionState) -> Dictionary:
	var entry: Dictionary = comp.entry_for(company.id)
	if entry.is_empty():
		return {}
	if comp.status == &"judged" or comp.status == &"closed":
		var recipe: RecipeDef = entry.get("recipe")
		return {
			"visibility": &"known",
			"recipe_name": recipe.display_name if recipe != null else "?",
			"recipe": recipe,
			"tier": entry.get("tier", &"med"),
		}
	return {"visibility": &"sealed", "recipe_name": "Sealed entry"}


## Stable multiplicative noise: seeded per company per in-game week.
static func _noise_factor(company: CompanyState, spread: float) -> float:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(company.id) ^ hash(GameClock.day / 7)
	return 1.0 + rng.randf_range(-spread, spread)
