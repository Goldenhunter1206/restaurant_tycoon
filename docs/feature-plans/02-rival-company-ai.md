# Rival Company AI

## Goal

Introduce economically credible rival restaurant companies that compete for locations, customers, staff, awards, and market position. Rivals should be legible, imperfect, and subject to the same constraints as the player.

## Prerequisite refactor

The current managers assume one global company. Before AI behavior, add `CompanyState` with company ID, name, brand, color/logo, cash, loan, reputation, recipe book, owned restaurants, headquarters progression, relationships, and ledgers. Migrate the player into company ID `player` and make restaurant ownership explicit.

Business operations should become commands such as `purchase_location(company_id, ...)`, `hire_candidate(company_id, ...)`, `set_menu_entry(company_id, ...)`, and `start_marketing(company_id, ...)`. Commands return structured success/failure results so both AI and UI receive the same validation.

## AI architecture

Use a layered planner:

- **Strategic planner:** runs daily or weekly and chooses expansion, market positioning, liquidity targets, and rival focus.
- **Tactical planner:** runs several times per day and adjusts staffing, hours, menus, prices, marketing, supply, and repairs.
- **Incident responder:** handles shortages, bankruptcy risk, attacks, inspections, or sudden demand spikes.
- **Execution queue:** adds reaction delay and prevents instant omniscient changes.

Each `CompetitorProfile` defines risk tolerance, ethics, preferred demographics, quality/price bias, expansion appetite, marketing style, operational skill, and planning noise. Difficulty adjusts forecast accuracy, search depth, and reaction delay—not cash cheats or hidden demand bonuses.

## Decision model

AI evaluates actions using expected utility:

`expected profit + strategic position + reputation gain - risk - liquidity cost - management load`

Forecasts should use only information the company could reasonably know: its own reports, visible rival branches, public rankings, customer observations, and paid research if added later. Maintain an AI decision journal containing considered actions, chosen action, predicted result, and actual result. This powers debugging and player-facing competitor news.

## Core behaviors

The first production AI must be able to:

- Evaluate and acquire viable restaurant locations.
- Choose target demographics and restaurant positioning.
- Hire staff, schedule shifts, and correct bottlenecks.
- Select recipes, quality, and price with a positive expected margin.
- Open/close channels and set operating hours.
- Launch and stop marketing.
- Maintain a cash reserve, take/repay loans, and sell or close failing locations.
- React to player encroachment and defend important territories.

Later integrations add suppliers, headquarters upgrades, managers, awards, and legal or criminal competition.

## Simulation scaling

Run full restaurant operations for on-screen or selected rivals. Off-screen branches may use aggregated hourly throughput based on the same capacity, demand, menu, and staffing formulas. Reconcile aggregate state when a branch becomes visible; never spawn retroactive outcomes that contradict its ledger.

## UI and player feedback

- Company overview with brand, reputation, branch count, known strengths, and recent moves.
- Map colors and influence overlays for rival coverage.
- Comparison graphs in Reports and Rankings.
- News feed entries for openings, closures, awards, campaigns, attacks, and bankruptcies.
- Explanations such as “Bella Napoli cut prices near Downtown” rather than raw AI scores.

## Delivery phases

### Phase 1 — Multi-company foundation

Create company state, ownership, per-company economy, shared commands, save migration, and two inert rival companies.

### Phase 2 — Operational AI

Enable location purchase, staffing, menus, pricing, hours, and solvency management. Test in accelerated headless simulations.

### Phase 3 — Market strategy

Add demographic positioning, competitive response, marketing, expansion plans, and branch closure decisions.

### Phase 4 — Personality and advanced systems

Add profile-driven behavior, headquarters progression, supplier strategy, awards, alliances/hostility, and underworld decisions.

## Acceptance criteria

- A rival can start from cash, open and operate a profitable restaurant without scripted steps.
- At least three profiles produce observably different strategies over repeated seeded simulations.
- Rivals can fail and go bankrupt under the same economy rules as the player.
- Every AI action is reproducible with a fixed seed and visible in a decision journal.
- The player can identify why a rival is gaining customers through reports and world overlays.
- Ten accelerated in-game years complete without runaway queues, invalid ownership, or unbounded memory growth.

## Testing strategy

- Unit tests for every shared company command and permission boundary.
- Seeded scenario tests for expansion, price wars, staffing recovery, and insolvency.
- Tournament simulations comparing profiles across city seeds.
- Anti-cheat assertions that AI cash, knowledge, and transactions use public APIs.
- Performance budgets for tactical decisions and aggregate branch simulation.

## Risks and controls

- **Manager refactor scope:** introduce company IDs behind compatibility wrappers before changing UI call sites.
- **AI thrashing:** cooldowns, switching costs, minimum commitment periods, and hysteresis for price/staff changes.
- **Unfair perception:** expose rival moves, avoid hidden bonuses, and use delayed/inexact knowledge.
- **Performance:** stagger planning ticks and use aggregated off-screen operations.

