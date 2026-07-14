# Marketing

## Goal

Create an advertising system that lets companies expand awareness, target demographics, promote recipes or ingredients, position their brand, and compete directly with rivals. Marketing must alter demand through explainable reach and message fit, not simply multiply sales.

## Existing foundation

Demand already evaluates citizens, restaurant utility, location, price, taste, and intent. The minimap already supports Demand and Coverage layers. Economy supports recurring expenses and events. The Marketing screen currently routes to a placeholder, providing a clean UI insertion point.

## Data model

- `MarketingChannelDef`: flyer, billboard/poster, local event, radio/digital equivalent if desired, and citywide zeppelin; includes reach shape, duration, setup cost, recurring cost, frequency, and prerequisites.
- `MarketingMessage`: brand image, target demographics, promoted recipe/ingredient, claim type, named rival target, and intensity/budget.
- `MarketingCampaignState`: ID, company, restaurant scope or city scope, channel, placements, message, start/end, spend, current effectiveness, fatigue, and status.
- `AdPlacement`: world location or coverage region, rental term, owner, and occupancy.

Campaign definitions should be data-driven so cities can enable different media and pricing.

## Effect model

For each citizen or aggregated demographic cell, calculate:

`awareness gain = channel reach × exposure frequency × message fit × credibility × spend efficiency × novelty - fatigue`

Awareness affects whether a restaurant enters the citizen’s consideration set. It does not override affordability, travel distance, capacity, recipe appeal, or service quality. Claims such as “lowest price,” “best staff,” or “highest quality” derive credibility from actual reports. False or stale claims lose effectiveness and may create reputation or government risk.

Recipe or ingredient promotion can create a temporary city trend when exposure crosses a threshold. Competitor comparison campaigns gain strength when the claim is true but may provoke a response. Store awareness per company/restaurant at an aggregated demographic-zone level, with citizen-level values only for selected or active citizens.

## Player workflow

1. Choose local restaurant or citywide campaign.
2. Choose channel and, for billboards, placement on the map.
3. Choose target segments and brand image.
4. Select a truthful strength, promoted recipe/ingredient, or rival comparison.
5. Set duration and budget.
6. Preview reach, estimated fit, recurring cost, and uncertainty range.
7. Start, pause, revise, or stop the campaign.

The Marketing screen needs Active, Create, Placements, and Results tabs. Coverage overlays should preview incremental reach before purchase. Results show awareness, attributed visits, revenue, cost per acquired customer, segment response, fatigue, and any negative credibility effect.

## Integrations

- `DemandManager` adds awareness and campaign-fit terms to restaurant utility.
- `EconomyManager` charges setup and daily/quarterly spend and reports attributed revenue.
- `RecipeManager` supplies recipe and ingredient targets.
- Rival AI selects campaigns using the same previews with imperfect estimates.
- Headquarters upgrades unlock larger channels and simultaneous campaign capacity.
- Reports compare spend, reach, conversions, and rival share of voice.
- Government may regulate false claims, illegal placements, or nuisance advertising.

## Delivery phases

### Phase 1 — Awareness and local flyers

Implement awareness storage, one local channel, campaign lifecycle, costs, basic results, save/load, and AI hooks.

### Phase 2 — Billboards and map placement

Add rentable placements, coverage preview, geographic overlap, and competitor contention.

### Phase 3 — Message design

Add demographic images, strengths, credibility, recipe/ingredient promotion, fatigue, and campaign comparison.

### Phase 4 — Citywide channels and trends

Add headquarters-gated citywide advertising, city trends, rival comparison, government consequences, and polished world visuals.

## Acceptance criteria

- A correctly targeted campaign increases consideration and visits within its coverage region.
- A poorly targeted or false campaign can lose money or damage reputation.
- Marketing cannot create sales when affordability, capacity, or opening-hours constraints make service impossible.
- The coverage preview matches measured exposure within an agreed tolerance.
- Campaign attribution is visible by restaurant and demographic.
- Rivals can advertise, respond to player campaigns, and compete for placements.
- Campaign state and awareness persist across save/load without duplicating charges.

## Testing strategy

- Deterministic reach tests against fixed map positions.
- A/B demand simulations with campaign on/off.
- Credibility tests as prices, staff, or quality change during a campaign.
- Cost and recurrence tests across pause, stop, save, and load boundaries.
- Performance tests for awareness aggregation over all zones and companies.

## Risks and controls

- **Opaque demand changes:** surface contribution breakdowns in tooltips and reports.
- **Dominant spend strategy:** fatigue, diminishing returns, limited placements, segment saturation, and liquidity opportunity cost.
- **Attribution ambiguity:** use first/last-touch approximations consistently and label them as estimates.
- **World clutter:** only render nearby active placements and summarize citywide channels in the sky/news UI.

