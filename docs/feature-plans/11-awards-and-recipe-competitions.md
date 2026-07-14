# Awards and Recipe Competitions

## Goal

Add external evaluation and competitive prestige goals beyond cash. Restaurants can earn quality stars and periodic awards; companies can challenge rivals in timed recipe competitions aimed at specific demographics or constraints.

## Data model

- `RestaurantRatingState`: restaurant ID, current score by dimension, awarded stars, inspection history, warnings, and eligibility.
- `AwardDef`: ID, category, cadence, eligibility, score formula, evaluator, reward, tie-breakers, and presentation.
- `AwardResult`: period, nominees, scores, winner, explanation, reward, and disputed/invalid state.
- `CompetitionDef`: target demographic, ingredient/theme constraints, entry deadline, judging time, entry fee, reward, and reputation impact.
- `CompetitionState`: participants, frozen recipe-version entries, status, scores, winner, and event log.

## Restaurant evaluation

Evaluate separate dimensions:

- Food quality and recipe fit.
- Service quality and wait time.
- Atmosphere, comfort, style, music, and crowding.
- Cleanliness, furniture condition, and safety.
- Value relative to target demographics.
- Consistency over a minimum observation window.

Publish the score breakdown and “next star” blockers. Stars should require sustained quality and an inspection, not appear instantly from a transient score. Severe degradation can trigger warnings and later star loss. Global company reputation must remain distinct from restaurant-specific stars.

## Inspections and awards

The mayor or an independent food guide periodically visits eligible restaurants. Inspections use sampled real operations plus current condition. Government influence may change visit timing or leniency within narrow, visible bounds but cannot fabricate a top rating from a failing branch.

Periodic awards might include Best Premium Restaurant, Best Value, Best Service, Best Delivery, Most Popular Recipe, Cleanest Restaurant, and Best Newcomer. Limit active categories per scenario to avoid meaningless trophy spam. Rewards may include reputation, cash, marketing reach, campaign score, or a temporary trend.

## Recipe competitions

A company challenges rivals or enters a scheduled city competition. The prompt defines a demographic and optional ingredient, cost, size, or quality constraint. Each participant submits a frozen recipe version before the deadline. Judging combines recipe score, constraint compliance, novelty, and limited randomness disclosed as a judging range. Results show every scoring component.

Competitions run alongside normal play, appear in upcoming events, and support AI entries. Winning grants a medal/reputation and may create a recipe trend. Competitor entries become inspectable only according to knowledge/espionage rules.

## UI

- Restaurant rating panel with stars, dimension bars, inspection history, and prioritized improvement guidance.
- Awards calendar, eligibility, current leaders/estimates, past winners, and rewards.
- Competition inbox, accept/challenge flow, countdown, recipe submission, locked-entry confirmation, results podium, and score breakdown.
- Restaurant and recipe screens display earned awards with period and city.

## Integrations

- Interiors supply atmosphere, comfort, condition, cleanliness, and capacity.
- Staff supplies service consistency, skill, and motivation.
- Recipes supply food/demographic scores and frozen versions.
- Reports provide observation windows and rankings.
- Government schedules inspections and mayor involvement.
- Marketing may promote legitimate awards; false award claims lose credibility.
- Campaign objectives can require stars, awards, medals, or competition wins.
- AI decides whether to enter based on expected score, cost, and strategic value.

## Delivery phases

### Phase 1 — Restaurant ratings

Create dimension scoring, daily history, star thresholds, player explanations, and migration from global reputation display.

### Phase 2 — Inspections and awards

Add visits, warnings/star changes, a small award catalog, quarterly evaluation, rewards, and news.

### Phase 3 — Recipe competitions

Add invitations/challenges, frozen entries, judging, AI participation, results, and campaign hooks.

### Phase 4 — Advanced ecosystem

Add city-specific evaluators, sponsorship/marketing, richer ceremonies, historical records, and government influence.

## Acceptance criteria

- Two restaurants owned by one company can hold different star ratings for explainable reasons.
- Ratings use sustained operational samples and cannot be raised solely by opening the panel or reloading.
- Every award result can reproduce its score from finalized metrics.
- Recipe edits after submission never mutate a competition entry.
- AI enters valid recipes and can win under the same scoring rules.
- Rewards, reputation, and campaign score apply once and survive save/load.

## Risks and controls

- **Opaque prestige:** show formulas as labeled dimensions and concrete improvement blockers.
- **Rich-get-richer loop:** category diversity, newcomer/value awards, entry costs, and diminishing reputation gains.
- **Save scumming:** deterministic judging seed fixed when the competition starts.
- **Award spam:** limited calendar, meaningful eligibility, and archived history.

