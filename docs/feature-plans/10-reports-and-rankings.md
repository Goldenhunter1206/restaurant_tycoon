# Reports and Rankings

## Goal

Give players trustworthy, actionable explanations of performance over time and direct comparison with rival companies. Expand the current finance screen into a reporting platform while keeping quick operational summaries close to the map.

## Existing foundation

Economy stores daily ledgers and series; restaurants store sales/expense history and daily operational counters; the HUD shows profit, operations bottlenecks, demographics, and sparklines. The dedicated Reports and Rankings routes are placeholders. The main technical gap is a consistent historical metric pipeline across restaurants, recipes, staff, suppliers, marketing, rivals, awards, and incidents.

## Data architecture

- `MetricDef`: ID, label, unit, aggregation rule, supported dimensions, retention, and visibility requirements.
- `MetricSample`: time bucket, metric ID, value, and dimensions such as company, restaurant, district, recipe, demographic, employee, supplier, or campaign.
- `BusinessEvent`: timestamp, type, source IDs, monetary impact, tags, and explanation payload.
- `ReportQuery`: metric, time range, interval, filters, grouping, comparison, and derived calculation.
- `RankingDef`: metric/formula, eligible entities, evaluation interval, tie-breaker, visibility, and scenario score contribution.

Create `AnalyticsManager` to ingest events and close daily/weekly/quarterly buckets. Do not make UI scrape live managers to reconstruct history. Retain summarized older data so long campaigns do not grow saves without bound.

## Required reports

### Company dashboard

Revenue, expenses, profit, cash flow, loan, inventory value, market share, reputation, restaurant count, and trend explanations.

### Restaurant comparison

Sales, margin, guests, lost demand, table utilization, queue time, cook utilization, delivery performance, staffing cost, rent, maintenance, waste, marketing attribution, and demographic mix.

### Recipe performance

Units, revenue, ingredient cost, waste, margin, prep time, rating, demographic response, stockouts, and version comparison.

### Workforce

Payroll, productivity, service quality, absence, overtime, motivation, turnover, training cost, and skill development.

### Supply and marketing

Supplier cost/reliability/waste and campaign spend/reach/conversion/attributed profit.

### Competition

Known rival revenue/market-share estimates, branch growth, reputation, awards, advertising share of voice, and district strength. Unknown data should show estimates or “not known,” not omniscient exact values.

## Rankings

Provide city/company rankings for value, revenue, profit, market share, reputation, restaurant quality, delivery performance, recipe popularity, awards, and scenario score. Rankings update on a defined cadence and publish news when positions change materially. Campaigns select a subset for victory and scoring.

## UI

- Reports home with pinned KPIs, alerts, and explanation cards.
- Time range and interval controls.
- Filter/group controls with sensible presets.
- Line, bar, stacked, share, and table views; no chart type without a specific comparison purpose.
- Compare branch, recipe, employee, campaign, supplier, or company.
- Click a chart anomaly to open relevant events such as price changes, shortages, campaigns, staff loss, or sabotage.
- Export is optional; first ensure reports are readable in-game.

The Rankings screen should emphasize current placement, movement since last period, the leader’s known advantage, and the next attainable target.

## Integrations

Every major feature emits typed events and metric samples. `EconomyManager.transact()` remains the monetary source of truth and includes company/restaurant/source dimensions. AI reads reports through a restricted knowledge view. Managers use branch reports. Objectives and awards query finalized buckets rather than duplicating calculations.

## Delivery phases

### Phase 1 — Analytics pipeline

Add event journal, metric registry, daily buckets, company/restaurant dimensions, retention, save/load, and reconciliation with existing ledgers.

### Phase 2 — Core reports

Build company, finance, restaurant, operations, and recipe reports with filters and event annotations.

### Phase 3 — Rankings and rival comparison

Add rankings, market share, estimated rival data, movement news, and scenario hooks.

### Phase 4 — Extended feature reports

Add staff, supplier, inventory, marketing, award, crime, and government views as their source systems ship.

## Acceptance criteria

- Company profit exactly reconciles with ledger categories for every time bucket.
- Restaurant totals reconcile to company totals with an explicit corporate/unassigned category.
- A player can identify the primary causes of a profit change from linked events.
- Filters and comparisons return deterministic values across save/load.
- Rival reports never expose data outside the company’s knowledge rules.
- Rankings handle ties, closures, new companies, and bankruptcies predictably.
- Long accelerated sessions keep save size and query latency within budgets.

## Risks and controls

- **Metric inconsistency:** one registry, one finalized bucket pipeline, and reconciliation tests.
- **Save bloat:** rolling raw-event retention plus permanent aggregate buckets.
- **Dashboard overload:** presets, progressive detail, and actionable annotations.
- **Misleading attribution:** label estimates and document calculation methods in tooltips.

