# Pizza Connection 2 Feature-Parity Plans

This folder turns the feature-gap audit into implementation-ready plans. Each document describes the intended player experience, data model, runtime systems, UI, delivery phases, acceptance criteria, risks, and dependencies. The plans extend the existing restaurant, demand, economy, delivery, citizen, traffic, and UI architecture instead of replacing it.

For the complete existing-plus-planned navigation hierarchy and screen requirements, see the [Game UI/UX Menu Architecture](../ui-ux/game-ui-menu-architecture.md).

## Plan index

1. [Custom pizza & burger workshop](01-custom-recipe-workshop.md)
2. [Rival company AI](02-rival-company-ai.md)
3. [Marketing](03-marketing.md)
4. [Editable restaurant interiors](04-editable-restaurant-interiors.md)
5. [Campaign and game modes](05-campaign-and-game-modes.md)
6. [Suppliers, inventory, and warehouses](06-suppliers-inventory-warehouses.md)
7. [Headquarters progression](07-headquarters-progression.md)
8. [Managers and automation](08-managers-and-automation.md)
9. [Staff depth and training](09-staff-depth-and-training.md)
10. [Reports and rankings](10-reports-and-rankings.md)
11. [Awards and recipe competitions](11-awards-and-recipe-competitions.md)
12. [Crime and sabotage](12-crime-and-sabotage.md)
13. [Government, mayor, and police](13-government-mayor-and-police.md)
14. [City and content breadth](14-city-and-content-breadth.md)
15. [Save system and front end](15-save-system-and-frontend.md)

## Shared architectural rules

All features should follow these rules so that they compose cleanly:

- Persistent domain objects use stable string or integer IDs; Node references are runtime-only and are never the authoritative save state.
- Player and AI companies use the same command APIs for buying, hiring, pricing, advertising, and hostile actions. Difficulty may change planning quality and reaction delay, not economic rules.
- Simulation belongs in autoload managers and Resource-based state objects. Scenes visualize state and accept input; they do not own business truth.
- Definitions such as ingredients, furniture, campaigns, suppliers, cities, upgrades, and crime actions are data-driven resources or JSON catalogs.
- Every monetary action routes through `EconomyManager.transact()` with a new ledger category where required.
- Long-running systems advance from `GameClock` ticks and publish typed signals. Avoid independent timers for business simulation.
- Every new feature supplies save serialization, migration behavior, finance/reporting hooks, AI hooks, and deterministic test seams in its first production release.
- Expensive citizen-level effects may be aggregated when off-screen, but player-visible outcomes must remain explainable through reports and tooltips.

## Recommended delivery sequence

### Foundation milestone

Create shared `CompanyState`, company IDs, command results, per-company ledgers, versioned save sections, and a lightweight simulation event journal. Today several systems assume a single global player; rival AI, rankings, campaign scoring, marketing, and crime all depend on removing that assumption carefully.

### Milestone A — Competitive restaurant game

Deliver custom recipes, rival AI, and marketing. This establishes the defining loop: create an offer, position it for a demographic, and compete for customers.

### Milestone B — Physical restaurant depth

Deliver editable interiors plus suppliers, inventory, and warehouses. Capacity, atmosphere, production, ingredient quality, and logistics become visible operational choices.

### Milestone C — Progression and delegation

Deliver headquarters upgrades, managers, automation, and deeper staff development. These systems prevent a growing chain from turning into repetitive micromanagement.

### Milestone D — Evaluation and long-term goals

Deliver reports, rankings, awards, and recipe competitions. Players gain clear feedback, comparative goals, and reasons to optimize beyond cash.

### Milestone E — Underworld simulation

Deliver crime/sabotage and government/police together. Shipping only attacks without counterplay, evidence, enforcement, or reputation would create arbitrary losses.

### Milestone F — Product structure and content

Deliver campaign/free play, expanded cities, multiple saves, new-game setup, tutorial, options, and progression presentation. Build campaign content after the reusable scenario and city-data systems exist.

## Cross-feature definition of done

A feature is complete only when:

1. It creates a meaningful decision with at least two viable strategies.
2. Its outcomes are visible in the world or UI and attributable in reports.
3. AI companies can use or respond to it where applicable.
4. It survives save/load and older saves migrate safely.
5. It has deterministic simulation tests and at least one end-to-end gameplay test.
6. It has tuning data outside hard-coded UI logic.
7. It performs acceptably with the target number of citizens, restaurants, and competitors.
