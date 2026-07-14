# Custom Pizza & Burger Workshop

## Goal

Replace the fixed-dish-only menu with a creative recipe system in which players compose both pizzas and burgers from ingredients, understand how different customer segments perceive them, set a production tier and price, and reuse successful recipes across restaurants. Preserve the current predefined dishes as starter recipes and keep non-customizable sides and desserts as catalog items.

## Existing foundation

`DishDef`, `QualityTier`, `MenuEntry`, `RestaurantManager`, `DemandManager`, and the Recipes & Menu screen already model prep time, popularity, ingredient cost, quality, price, margin, and menu capacity. The missing layer is player-authored composition. The current pizza and burger dish resources should migrate into immutable starter recipes; salads, hotdogs, and desserts remain fixed starter catalog items so existing saves remain valid.

## Player experience

The workshop begins with a product choice: **Pizza** or **Burger**. Both use the same ingredient catalog, costing, demographic feedback, recipe book, and menu-assignment workflow, but each has a purpose-built assembly interaction:

- **Pizza:** a top-down base where players place, distribute, rotate, and portion toppings and sauces across the surface.
- **Burger:** a side-on stack where players choose buns and drag ordered layers such as patties, cheese, vegetables, sauces, and extras between the top and bottom bun.

Players preview cost, prep time, structural/assembly warnings, and estimated appeal by customer segment. A recipe can be named, saved to the company recipe book, tested, edited into a new version, and assigned to restaurant menus. Exact appeal ranges remain partially uncertain until the recipe generates real sales, making experimentation useful without hiding the core rules.

## Data model

Add these Resource types:

- `IngredientDef`: ID, name, category, unit cost, prep-time modifier, quality, nutrition/spice/oil/novelty traits, compatible quality tiers, compatible product types, allowed assembly roles, model/icon, and per-demographic affinities.
- `RecipeBaseDef`: product type, dough/bun/base option, assembly mode, base cost, prep time, capacity requirements, and presentation rules.
- `RecipeComponent`: ingredient ID, assembly role, quantity, preparation choice, and product-specific placement data. Pizza components store normalized surface position, distribution radius, rotation, and scale; burger components store ordered stack index, thickness/portion, and optional sauce/spread coverage.
- `RecipeDef`: stable ID, owner company ID, name, product type, base ID, components, version, created day, cached cost/prep/appeal/assembly values, and unlock source.
- `RecipeBookState`: owned recipes, archived versions, starter recipes, and base-menu IDs.

Use normalized coordinates for pizza placement and an ordered semantic layer list for burgers so recipes are resolution independent. Cache derived values, but make components authoritative so balance patches can recalculate recipes. Do not encode burger stacks as arbitrary 3D transforms; the layer order must remain easy to validate, render, save, and use by AI.

## Simulation

Create `RecipeManager` to load ingredients, bases, and recipes; validate compositions; calculate costs; score recipes; clone/version recipes; and expose company recipe books. Recipe scoring should combine:

- Ingredient affinity for each demographic.
- Product-type and base affinity for each demographic.
- Pizza coverage and distribution; deliberate even or patterned placement can matter without pixel-perfect grading.
- Burger layer balance, ingredient order, height, sauce load, and structural integrity; a tall or unstable burger may look novel but reduce eating convenience and service consistency.
- Ingredient balance, conflicts, excess, novelty, and current city trends.
- Selected quality tier and cook consistency.
- Price utility, existing restaurant appeal, and marketing modifiers through `DemandManager`.

Pizza and burger assembly rules share cost, demographic, nutrition, quality, and novelty traits, but each product type owns its spatial/structural calculation. This avoids forcing burger design into a pizza-placement metaphor or duplicating the entire recipe system.

`RestaurantManager.make_order()` should resolve a recipe ID and snapshot its product type, base, components, cost, prep time, quality, and version onto the order. This prevents an in-progress order changing when the recipe is edited. Sales must record recipe ID and version for reporting.

## UI and controls

Split the existing Recipes & Menu screen into:

1. **Recipe book:** all, pizza, burger, starter, custom, archived, and competitor-discovered filters.
2. **Workshop:** product selector plus a pizza canvas or burger stack editor, shared ingredient browser, quantity/preparation controls, undo/redo, cost/prep summary, assembly warnings, and appeal preview.
3. **Base menu:** reusable company defaults.
4. **Restaurant menu:** current enable/quality/price controls and station capacity.

Support mouse and keyboard placement/reordering, accessible color-independent ingredient markers, confirmation before destructive edits, and a one-click “duplicate as new recipe” flow. Switching product type after ingredients have been added requires confirmation and creates a converted copy only when compatible ingredients can be mapped safely. The interior view should visualize authored pizzas and burgers using assembled ingredient layers where assets exist and the current dish-model fallback otherwise.

### Pizza editor layout

- Center: top-down dough canvas with selectable size/base.
- Left: ingredient categories, search, compatibility filters, and preparation variants.
- Right: component list, quantity, cost/prep/appeal summary, demographic preview, and warnings.
- Toolbar: undo/redo, distribute, clear, duplicate, save version, and test recipe.

### Burger editor layout

- Center: side-on stack between selected bottom and top buns.
- Left: compatible buns, patties/proteins, cheese, vegetables, sauces, and extras.
- Right: ordered layer list, portion/preparation controls, height/structure meter, cost/prep/appeal summary, demographic preview, and warnings.
- Direct manipulation: drag to insert or reorder a layer; repeated ingredients remain separate editable layers or can be grouped for quantity changes.

## Integration requirements

- `DemandManager` consumes recipe appeal instead of only fixed dish taste weights.
- Marketing can promote a product type, recipe, or ingredient.
- AI competitors use the same recipe evaluator with imperfect search budgets and valid pizza/burger assembly operators.
- Supplier inventory derives required ingredients from projected recipe demand.
- Interior/kitchen capacity recognizes pizza and burger preparation stations or shared stations according to `RecipeBaseDef`.
- Reports track unit sales, margin, waste, demographic appeal, product type, and recipe version.
- Recipe competitions accept a frozen pizza or burger recipe version as an entry according to competition rules.
- Saves serialize product-specific components and retain missing-ingredient placeholders if content is removed.

## Delivery phases

### Phase 1 — Data and compatibility

Implement ingredient, base, and recipe resources; migrate the existing pizza and burger dishes into starter recipes; add deterministic product-specific scoring tests; and preserve current menus through automatic conversion.

### Phase 2 — Pizza and burger workshop MVP

Build pizza and burger creation, naming, validation, save, clone, delete/archive, and menu assignment. Ship 35–45 reusable ingredients across dough/buns, sauces, cheeses, vegetables, meats/proteins, and extras before expanding toward PC2-scale breadth.

### Phase 3 — Demand and analytics

Connect demographic scoring, observed sales, recipe profitability, trends, product-type comparisons, and report explanations.

### Phase 4 — World and competitive integration

Add food visuals, AI recipe creation, marketing hooks, supplier consumption, product-specific station requirements, and recipe competitions.

## Acceptance criteria

- A player can create, save, edit, duplicate, archive, and sell both a custom pizza and a custom burger.
- Moving or changing an ingredient produces deterministic, understandable changes to cost and appeal.
- Reordering burger layers changes the rendered stack and any applicable balance/structure score without changing ingredient quantities.
- Pizza surface placement and burger layer ordering both persist exactly across save/load.
- Two recipes aimed at different segments produce measurably different demand under controlled conditions.
- Editing a recipe never mutates existing orders or historical reports.
- AI companies can create valid pizzas and burgers and price them profitably.
- Custom recipes persist across saves and migrate safely when ingredient or base catalogs change.

## Risks and controls

- **Combinatorial balance:** use shared trait-based scoring plus product-specific assembly rules and automated recipe fuzz tests rather than hand-tuning every combination.
- **UI complexity:** progressive disclosure; the default view shows cost and overall appeal, while advanced panels explain segment-level scoring.
- **Optimal-recipe convergence:** city trends, competitor pressure, ingredient prices, product-type preferences, and diminishing returns should keep multiple compositions viable.
- **Burger rendering complexity:** render from semantic layer anchors with thickness rules, not physics; cap visual height and collapse repeated layers where needed for distant views.
- **Asset burden:** reuse ingredients across pizzas and burgers, start with category-level visual fallbacks, and add bespoke ingredient meshes incrementally.

## Out of scope for the first release

User-generated asset imports, online recipe sharing, physics-based burger stacking, custom dough/bun mesh sculpting, sandwiches/wraps/tacos, and procedural ingredient mesh generation.
