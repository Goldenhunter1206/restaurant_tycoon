# City and Content Breadth

## Goal

Evolve the single-city project into a reusable catalog of distinct cities that support campaign progression and free play. Each city should change strategy through geography, demographics, costs, traffic, labor, suppliers, regulations, events, and rival conditions—not merely reskin the same map.

## Existing foundation

The project already has a substantial 3D city, procedural/dressing scripts, building catalog, calibrated road graph, districts, citizens, traffic, parking, day/night, demand segments, and restaurant-property data. The priority is to separate city-specific data/assets from global simulation and formalize a repeatable city production pipeline.

## City package

Add `CityDef` with:

- Stable city ID, display name, country/region, scene path, preview, localization, and campaign order.
- Economy profile: starting year/time presentation, rent/property multipliers, wages, taxes, supplier prices, loan terms, and event probabilities.
- District definitions and target-demographic distributions.
- Population profile, schedules, transit usage, vehicle ownership, and tourist/event populations.
- Available restaurant, warehouse, headquarters, government, supplier, police, and attraction buildings.
- Road graph/navigation resources and world calibration.
- Supplier pool, labor market, marketing placements/channels, government policies, awards, and crime settings.
- Music/ambience/visual theme and localized names/dialogue pools.
- Scenario compatibility flags and performance budgets.

Runtime managers receive a city context during session bootstrap. Remove hard-coded district labels, citywide tuning, or resource paths from global managers incrementally.

## Strategic differentiation

Each city should have at least three material strategic characteristics. Examples:

- Dense expensive center with high foot traffic versus cheap car-dependent suburbs.
- Student-heavy demand and late-night hours versus affluent evening dining.
- Expensive high-quality suppliers versus unreliable low-cost logistics.
- Strict inspections and fast police response versus weak enforcement and higher crime.
- Scarce labor, high wages, or strong specialist candidates.
- Seasonal stadium/tourist events or transit disruptions.

City-specific content should use the shared demographic and economic vocabulary so reports and AI remain reusable. Add new mechanics only when they benefit multiple scenarios.

## Authoring pipeline

For each city:

1. Create/import the base scene and define world bounds/origin.
2. Build and validate road, sidewalk, pedestrian, parking, and service-route graphs.
3. Tag buildings with stable IDs, type, district, doors, curb points, capacity, ownership rules, and special functions.
4. Define population homes/jobs/attractions and verify daily route feasibility.
5. Define restaurant candidates, warehouse/HQ sites, suppliers, government, police, and marketing placements.
6. Apply visual dressing and city-specific assets.
7. Run spatial, navigation, economy, AI, and performance audits.
8. Tune free-play baseline before authoring campaign scenarios.

Create an editor-side city validator that checks duplicate IDs, missing anchors, disconnected routes, unreachable buildings, district coverage, required special buildings, invalid catalog references, and population/traffic budgets.

## Content scaling

Do not target ten cities immediately. Recommended sequence:

- **City 1:** current city, refactored into the package format and used as the baseline/tutorial city.
- **City 2:** same core art family but deliberately different geography/economy to validate data separation.
- **City 3:** stronger visual and regulatory variation to validate content extensibility.
- Expand toward the campaign target only after the three-city slice proves replayable.

Use shared modular building/prop libraries, material variants, procedural dressing profiles, localized signs, lighting/weather presets, and district composition recipes. Preserve a few bespoke landmarks and layouts per city for identity.

## Runtime and transitions

`SessionManager` loads one city scene, supplies `CityDef` to managers, initializes deterministic population/companies, and unloads all city-scoped state cleanly on return to menu or campaign transition. Autoload managers must expose `reset_session()` and never retain Node references from a previous city.

Campaign transitions may carry company/profile progression while city-specific restaurants, staff, rivals, and civic state follow scenario rules. Define this explicitly; do not copy the entire old city state by accident.

## Integrations

- Campaign/free play selects `CityDef` and scenario overlays.
- Save metadata stores city ID and validates content availability before load.
- AI location evaluation and strategy consume city features rather than city-specific code.
- Suppliers, government, marketing, awards, labor, and crime load city catalogs.
- Reports normalize currencies/units if localization ever changes presentation.
- Front end shows previews, strategic traits, unlocked state, best score, and performance warning if needed.

## Delivery phases

### Phase 1 — Extract current city

Create `CityDef`, city context, manager reset lifecycle, city-scoped paths/tuning, and package the existing scene without behavior regression.

### Phase 2 — Validation and tooling

Build city validator, ID/anchor audits, route tests, population/traffic budgets, and a free-play smoke scenario.

### Phase 3 — Second city proof

Produce a strategically distinct second city, eliminate remaining hard-coded assumptions, and test AI/economy balance.

### Phase 4 — Campaign content pipeline

Produce the third city, formalize art/dressing recipes, localization workflow, scenario authoring, and then scale the catalog.

## Acceptance criteria

- The same simulation managers can start, stop, and switch between two city packages in one app session without stale nodes or state.
- A city validator catches missing routes, duplicate building IDs, and required special-building omissions before play.
- The same seed and city definition create reproducible population/company initialization.
- Two cities demand measurably different viable strategies from geography and tuning, not hidden bonuses.
- AI can operate and complete a baseline scenario in every city.
- Save metadata rejects an unknown/incompatible city cleanly and explains the issue.
- Each city meets explicit frame, agent, route, memory, and load-time budgets.

## Risks and controls

- **Content cost:** prove modular reuse and the city validator before committing to a large city count.
- **Hard-coded assumptions:** extract current city first and use the second city as a systematic compatibility test.
- **Visual sameness:** combine shared kits with unique layout, landmark, lighting, signage, demographic, and economy profiles.
- **Balance explosion:** maintain city baseline simulations and scenario-specific overlays rather than one global tuning file.

