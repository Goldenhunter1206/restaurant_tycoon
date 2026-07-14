# Game UI/UX Menu Architecture

## Purpose

This document is the master information architecture for the game UI. It shows every existing screen, existing placeholder, and planned screen from app launch through city play and deep management submenus. It is intended as the handoff baseline for UX flows, wireframes, visual design, interaction prototypes, and UI production planning.

Detailed system behavior remains in the [feature implementation plans](../feature-plans/README.md). This document owns navigation, hierarchy, screen purpose, visible information, and transitions.

## Status legend

- **Existing:** implemented and functional now.
- **Partial:** implemented, but planned scope adds important tabs or flows.
- **Placeholder:** visible in the current UI but opens a “Coming soon” screen.
- **Planned:** not currently present.
- **Developer-only:** diagnostic UI; not part of the player-facing information architecture.

## Navigation principles

1. The city remains the home screen. Closing a management screen always returns to the same city camera and selection.
2. Top-level management areas have stable entry points in the bottom navigation or selected-entity action panel.
3. Restaurant-specific screens retain the selected restaurant and show a restaurant switcher when the company owns multiple branches.
4. Company-wide screens retain active filters when users move between related tabs.
5. Deep screens use a visible breadcrumb and Back action; Escape moves up one level, never unpredictably all the way to the city.
6. Destructive or expensive actions show the exact cost, consequence, and affected entity before confirmation.
7. Every locked feature explains its headquarters, scenario, city, or progression requirement and links to the relevant unlock screen.
8. Time behavior is explicit. Screens show one of: **time continues**, **local simulation paused**, or **game paused**.
9. Empty, loading, error, locked, unaffordable, and no-selection states are designed states, not missing content.
10. Player and rival information clearly distinguish known facts, estimates, and unknown values.

## Screen presentation types

| Type | Use | Time behavior | Exit behavior |
|---|---|---|---|
| Persistent HUD | Core city status and navigation | Continues | Always present in city mode |
| World overlay | Heatmaps, insights, routes, placement previews | Continues | Toggle or Escape |
| Management workspace | Recipes, staff, reports, marketing, suppliers | Continues by default; player can pause globally | Close/Back returns to city |
| Entity workspace | Restaurant interior, headquarters, warehouse, city hall | Continues; interior edit pauses local branch simulation | Back returns to prior world view |
| Blocking dialog | Confirmation, result, critical failure | Paused where outcome requires acknowledgement | Confirm/cancel |
| App shell screen | Title, new game, load, settings | No active simulation | Explicit navigation |

## Master navigation tree

```text
Application
├── Title Screen [Planned]
│   ├── Continue
│   ├── New Game
│   │   ├── Profile
│   │   ├── Mode: Campaign / Free Play / Challenge / Tutorial
│   │   ├── Company Identity
│   │   ├── City or Scenario
│   │   ├── Difficulty, Rivals, Seed, Optional Systems
│   │   └── Review & Start
│   ├── Load Game
│   ├── Settings
│   ├── Credits
│   └── Quit
├── Scenario Intro [Planned]
├── General Game Screen / City [Existing]
│   ├── Persistent HUD
│   │   ├── Top Company & Time Bar
│   │   ├── Left Objectives / Events / Insights / Inspector
│   │   ├── Right Restaurant Panel
│   │   ├── Bottom Money / Reputation / Feed / Summary
│   │   ├── Bottom Main Navigation
│   │   └── Delivery & Clock Status
│   ├── City Map & World Interaction
│   │   ├── Building / Citizen / Vehicle Inspector
│   │   ├── Minimap & Data Layers
│   │   ├── City Insights Overlay
│   │   ├── Restaurant Influence / Demand / Route Overlays
│   │   └── Placement / Purchase Context
│   ├── Restaurants
│   │   ├── Locations & Expansion [Existing]
│   │   ├── Branch Overview [Existing/Partial]
│   │   ├── Operations [Existing]
│   │   ├── Staff [Existing/Partial]
│   │   ├── Recipes & Menu [Existing/Partial]
│   │   ├── Marketing [Placeholder → Planned]
│   │   ├── Service & Deliveries [Existing/Partial]
│   │   ├── Suppliers & Inventory [Placeholder → Planned]
│   │   ├── Reports [Placeholder → Planned]
│   │   ├── Finances [Existing/Partial]
│   │   ├── Rating & Awards [Planned]
│   │   ├── Security & Incidents [Planned]
│   │   └── Visit / Edit Interior [Existing/Partial]
│   ├── Company Management
│   │   ├── Staff & Training [Existing/Partial]
│   │   ├── Company Recipe Book [Planned]
│   │   ├── Company Finances [Existing/Partial]
│   │   ├── Reports & Analytics [Placeholder → Planned]
│   │   ├── Rankings [Placeholder → Planned]
│   │   ├── Headquarters [Planned]
│   │   ├── Managers & Policies [Planned]
│   │   ├── Warehouses & Procurement [Planned]
│   │   ├── Awards & Competitions [Planned]
│   │   ├── Government Relations [Planned]
│   │   └── Underworld [Planned, optional]
│   ├── Rival Company / Rival Restaurant [Planned]
│   ├── Missions & Scenario Progress [Partial → Planned]
│   └── Pause Menu [Planned]
└── Scenario Results / Campaign Progress [Planned]
```

## A. App shell and session flow

### A1. Title Screen — Planned

**Screen ID:** `front.title`

**Primary actions:** Continue, New Game, Load Game, Settings, Credits, Quit.

**Content:** Game logo/key art, active profile, latest valid save summary, version, and non-blocking compatibility warning if the latest save cannot load.

**Continue card:** Company, city, mode/scenario, game date, real timestamp, thumbnail, and playtime. Continue is disabled with a reason when no valid save exists.

### A2. Profile Select — Planned

**Screen ID:** `front.profiles`

**Entries:** Existing profiles, Create Profile, Rename, Delete, Set Active.

**Profile detail:** Campaign progress, unlocked cities, medals/highscores, tutorial status, preferred company identity, and total playtime. Deleting a profile explicitly distinguishes profile progress from session saves.

### A3. New Game Wizard — Planned

**Screen ID:** `front.new_game`

The wizard keeps a visible stepper and a persistent summary panel.

1. **Mode:** Campaign, Free Play, Challenge, Tutorial.
2. **Company:** name, logo, color, optional avatar, preview on map pin/signage.
3. **Campaign/scenario or city:** preview image, strategic traits, enabled systems, prior score, estimated session length.
4. **Configuration:** difficulty, rival count/profiles, starting cash, seed, victory condition, optional crime/government systems where allowed.
5. **Review:** objectives, starting conditions, rivals, city modifiers, difficulty, and Start.

Campaign may skip configuration values fixed by the scenario. Back preserves entered values. Randomize only changes fields the player has not locked.

### A4. Load Game — Planned

**Screen ID:** `front.load_game`

**Tabs/filters:** All, Manual, Autosaves, Campaign, Free Play, Incompatible/Recovery.

**Save row:** name, company, city, mode/scenario, game date, real timestamp, playtime, thumbnail, version status.

**Actions:** Load, Rename, Duplicate, Delete, Recover Backup, Show Compatibility Details. Delete and overwrite require confirmation. Invalid saves remain visible with an explanation.

### A5. Settings — Planned

**Screen ID:** `front.settings`

**Tabs:**

- **Audio:** master, music, ambience, effects, UI, mute in background.
- **Graphics:** display, resolution, mode, frame cap, quality, shadows, crowd/traffic density.
- **Controls:** camera, edge scroll, zoom, shortcuts, rebinding, reset.
- **Gameplay:** pause-on-modal, autosave interval/count, tutorial prompts, confirmations, time-speed defaults.
- **Accessibility:** text scale, color-independent indicators, reduced motion, subtitle/tooltips, contrast, hold/toggle behavior.
- **Language:** interface and subtitle language where supported.

Display changes use Apply/Keep/Revert. Other settings apply immediately with Reset per tab.

### A6. Scenario Intro — Planned

**Screen ID:** `session.intro`

**Content:** city/scenario title, narrative briefing, three or fewer headline objectives, optional objectives, deadline, rivals, starting assets, special rules, and enabled/disabled systems.

**Actions:** Start, View Full Objectives, Back to Setup. Tutorial scenarios also show expected controls.

### A7. Pause Menu — Planned

**Screen ID:** `session.pause`

**Actions:** Resume, Save Game, Load Game, Settings, Restart Scenario, Return to Title, Quit. Restart and leave actions show unsaved-progress warnings. The current HUD quick-save action remains available but should use a recognizable save icon and confirmation toast.

### A8. Scenario Results — Planned

**Screen ID:** `session.results`

**Content:** success/failure, objective results, score breakdown, awards, company/branch/recipe highlights, rival comparison, unlocks, and campaign narrative.

**Actions:** Next City, Continue in Free Play if allowed, Retry, Save Result, Return to Title.

## B. General Game Screen / City

### B1. Overall layout — Existing

**Screen ID:** `game.city`

The city is the primary workspace. Management screens layer above it and return to the same camera position and selection.

```text
┌──────────────── Top company/time/speed bar ────────────────┐
│ Objectives / events                     Restaurant panel   │
│ City insights / inspector               Minimap / status   │
│                                                           │
│                     3D CITY WORLD                          │
│                                                           │
│ Money + reputation | Messages/news | Today | Delivery/time│
└──────────────────── Bottom navigation ─────────────────────┘
```

### B2. Top company and time bar — Existing

**Visible information:** company badge/name, company level proxy, cash, current profit, date, quarter, and game-speed buttons.

**Speed actions:** Pause, Normal, Fast, Ultra. Active speed uses selected state, not color alone.

**Planned additions:** current city/scenario breadcrumb, autosave/saving state, critical alert indicator, and optional company switch only in developer/spectator tools—not normal play.

### B3. Left objective stack — Existing/Partial

**Current panels:**

- Objectives with progress bars for cash, restaurants, reputation, and deliveries.
- Next meal-rush timing and current restaurant hours.
- Upcoming Events showing festival, rent review, and inspection events.
- City Insights toggle.
- Selected entity Inspector.

**Planned expansion:**

- Objective groups: Primary, Optional, Accepted Missions.
- Deadline/maintain-duration states and reward previews.
- Mission inbox entry with Accept/Decline.
- Pinned alerts chosen from operations, stock, staff, incidents, inspections, and competitions.
- Collapse/reorder behavior to protect world visibility.

### B4. Center world viewport — Existing

**Primary actions:** pan, orbit/rotate where supported, zoom, select building/citizen/vehicle, follow/center, and enter restaurant interior.

**Selection result:** selected entity is highlighted; Inspector shows known attributes and contextual actions.

**Planned context actions by entity:**

- Own restaurant: Manage, Visit, Edit Interior, View Report, Security.
- Available location: Sign Lease, Center, District Info.
- Rival restaurant: Public Profile, Compare, Challenge, Report Violation, Underworld Actions if enabled.
- Headquarters: Open Headquarters.
- Warehouse: Open Warehouse.
- City Hall/police/supplier: open respective civic/procurement screen.
- Billboard/ad site: Rent Placement or View Owner.

### B5. Entity Inspector — Existing/Partial

**Current inspected types:** citizen, building, restaurant, vehicle, delivery vehicle, employer/home/job relationships, shift, money/wage, likes, district, destination/order, and thought/goal.

**Current contextual actions:** Manage owned restaurant and Sign Lease where eligible.

**Planned states:** known/estimated/unknown data, rival ownership, civic status, active campaign exposure, incident involvement, supply shipment, and direct navigation to relevant report.

### B6. City Insights Overlay — Existing/Partial

**Current purpose:** reveal citizen restaurant intent and selected-citizen thinking.

**Planned layers:** demand, customer journeys, unmet demand, competitor influence, advertising reach, delivery/service routes, supplier routes, police response, crime risk, property opportunity, and development proposals.

Only one analytical family should dominate at once. Layer legend, metric date/range, and Clear All remain visible.

### B7. Minimap and map layers — Existing/Partial

**Current controls:** zoom in/out, center on selected restaurant, and radio-select City, Demand, Coverage, Routes, or Zoning.

**Current legends:** demand heat, restaurant delivery reach, live delivery routes, and zoning colors.

**Planned layers:** company influence, rival branches, ad placements, supplier/warehouse coverage, civic/police coverage, inspections/incidents, awards, and development proposals. Layer availability follows context and permissions.

### B8. Right restaurant panel — Existing/Partial

**Screen ID:** `game.restaurant_panel`

**Header:** district name, minimap, restaurant switcher, restaurant name, reputation stars currently derived from global reputation, open/closed status, opening hours.

**Tabs:**

- **Overview — Existing:** five-segment customer profile, rent/ownership, traffic estimate, sales, profit, guests/tables, deliveries, and 10-day sales sparkline.
- **Operations — Existing:** dining occupancy/queue, oldest wait, cooking capacity/backlog, active deliveries/drivers, inbound citizens, and a recommended bottleneck action.
- **Rating — Planned:** restaurant-specific stars, food/service/atmosphere/cleanliness/value dimensions, inspection history, next-star blockers, and awards.
- **Alerts — Planned:** stockouts, staff absence, maintenance, campaign, inspection, security, and manager escalations.

**Restaurant action grid:** Build, Staff, Recipes, Marketing, Deliveries, Suppliers, Reports, Finances, Visit. Details appear in section D.

### B9. Bottom information band — Existing/Partial

**Current clusters:**

- Cash, bank loan, and reputation stars.
- Messages/News feed tabs with timestamped entries.
- Today’s sales, expenses, and profit.

**Planned additions:**

- Inbox tab for mission offers, inspection notices, manager approvals, competition invitations, extortion, and critical incidents.
- Filterable notification center with unread state and jump-to-entity action.
- Cash-flow forecast and next major scheduled payment tooltip.

### B10. Bottom main navigation — Existing/Partial

**Current actions:** Quick Save, City Map, Restaurants, Staff, Recipes, Finances, Rankings.

**Planned structure:** retain these primary entries. Headquarters becomes a world entity plus optional shortcut once acquired. Reports may remain restaurant-panel and headquarters entries rather than overcrowding the bottom navigation. The active destination must show selected state.

### B11. Delivery and clock status — Existing

Shows active scooter, car, and walker delivery counts plus the current clock. Clicking the delivery cluster should open the selected restaurant’s Service & Deliveries screen; clicking the clock opens/pins the time controls on smaller layouts.

## C. Main navigation workspaces

### C1. Restaurants / Locations & Expansion — Existing/Partial

**Screen ID:** `manage.restaurants`

**Current sections:**

- Your restaurants: owned/rented state, rent, View, and Buy Out.
- Locations for lease: district, signing fee, daily rent, and Sign Lease.

**Planned tabs:**

1. **Portfolio:** every branch with status, district, ownership, profit, rating, manager, alerts, and quick actions.
2. **Available Locations:** current lease list plus filters, map selection, demand profile, competitor proximity, and cost forecast.
3. **Property Detail:** traffic/demographics, rent/value, floor area/expansion potential, supply access, delivery access, permits, and forecast.
4. **Expansion Projects:** restaurant expansions, headquarters, and warehouses under construction.

**Primary flows:** compare → view on map → sign lease/purchase → name restaurant → choose starter layout/menu → open setup checklist.

### C2. Staff — Existing/Partial

**Screen ID:** `manage.staff`

**Current tabs:**

- **Schedule:** employee timelines, shifts, fire action, and daily payroll.
- **Job Market:** candidates, attributes/wage, and Hire.

**Planned tabs/subscreens:**

1. **Roster:** sortable staff cards by restaurant, role, status, motivation, energy, skill, and pay.
2. **Schedule:** 24-hour demand/capacity forecast, reusable templates, coverage warnings, overtime/availability, and bulk actions.
3. **Job Market:** candidate filters, compare tray, interview/assessment, offer terms, and rival-interest indicator where known.
4. **Employee Detail:** role, contract, skills, traits, health, fatigue, motivation, satisfaction, history, current task, goals.
5. **Training:** available programs, headquarters slots, queue, cost/duration, expected outcome, enrollment.
6. **Transfers & Promotion:** restaurant transfer, role qualification, promotion, and schedule impact.
7. **Policies:** wage bands, replacement hiring, overtime, training, manager authority.

### C3. Recipes — Existing/Partial

**Screen ID:** `manage.recipes`

**Current screen:** fixed dishes with enabled checkbox, prep time, quality tier, price, profit/day, kitchen-station capacity, and Add Station.

**Planned tabs:**

1. **Recipe Book:** All, Pizza, Burger, Starter, Custom, Archived, Competitor-discovered; sort by sales, margin, appeal, date.
2. **Workshop:** choose Pizza or Burger, then open product-specific assembly editor.
3. **Base Menu:** company-wide default recipes, quality, suggested price, and branch rollout.
4. **Restaurant Menu:** current enable/quality/price/station controls, local overrides, ingredient availability, and demand fit.
5. **Performance:** sales, margin, waste, demographic response, version comparison.
6. **Competitions:** active prompt, deadline, frozen entry, participants, and results.

**Pizza Workshop:** top-down base, ingredient browser, topping placement, portion/distribution, component list, undo/redo, cost/prep/appeal, save/test.

**Burger Workshop:** side-on bun-to-bun stack, ingredient browser, ordered layers, drag reorder, portion/preparation, height/structure meter, cost/prep/appeal, save/test.

### C4. Finances — Existing/Partial

**Screen ID:** `manage.finances`

**Current tabs:**

- **Overview:** cash, income/expenses/profit today, 14-day profit, loan amount, Borrow, Repay.
- **Categories:** Today/Last 7 Days, income/expense ledger categories and subtotals.
- **Restaurants:** ownership/rent and current sales/expenses/profit per branch.

**Planned tabs:**

1. **Overview:** current content plus cash forecast and alerts.
2. **Profit & Loss:** time range, company/restaurant comparison, category drilldown.
3. **Cash Flow:** operating, investing, financing, scheduled payments.
4. **Balance Sheet:** cash, property, inventory, debt, company value.
5. **Restaurants:** current branch comparison with deeper cost attribution.
6. **Loans & Property:** loan terms/history, repayment plan, leases, buyouts, property values.
7. **Transaction Detail:** filterable ledger with source entity and jump action.

### C5. Rankings — Placeholder → Planned

**Screen ID:** `manage.rankings`

**Tabs:** Companies, Restaurants, Recipes, Delivery, Awards, Scenario Score, History.

**Ranking row:** rank, movement, entity, known score/value, trend, primary known strength, and compare action. Unknown rival data is marked estimated. Filters select city, district, period, and ranking metric.

## D. Restaurant action workspaces

Every restaurant-specific workspace includes restaurant switcher, restaurant status, unsaved-change protection where relevant, and “View in City.”

### D1. Build — Existing/Partial

Opens Locations & Expansion. When invoked from a selected restaurant, default to its Property Detail/Expansion view rather than the generic lease list.

### D2. Staff — Existing/Partial

Opens Staff filtered to the selected restaurant. Tabs: Roster, Schedule, Job Market, Training, Transfers, Policies.

### D3. Recipes & Menu — Existing/Partial

Opens Restaurant Menu for the selected branch, with links to Recipe Book and Workshop. Unsaved custom-recipe edits remain in the workshop draft, not in the live menu.

### D4. Marketing — Placeholder → Planned

**Screen ID:** `manage.marketing`

**Tabs:**

1. **Overview:** active spend, awareness, attributed visits/revenue, alerts, and campaign calendar.
2. **Active Campaigns:** campaign cards, scope, channel, target, message, spend, effectiveness, fatigue, pause/stop/edit.
3. **Create Campaign:** restaurant/city scope → channel → placement → audience/image → claim/recipe/ingredient/rival → budget/duration → review/start.
4. **Placements:** billboard/map inventory, reach preview, price, occupancy, rental end.
5. **Audience & Brand:** customer segments, awareness, brand image, known strengths/credible claims.
6. **Results:** reach, frequency, conversions, attributed profit, cost per customer, segment response, credibility, comparison.

Campaign creation uses a stepper with a persistent live map preview and cost summary.

### D5. Service & Deliveries — Existing/Partial

**Screen ID:** `manage.delivery`

**Current sections:** dine-in toggle, online delivery toggle, maximum simultaneous delivery orders, opening/closing hours, and live cooks/waiters/drivers/tables/deliveries summary.

**Planned tabs:**

1. **Channels & Hours:** current controls plus channel profitability and staffing warnings.
2. **Live Orders:** queued, cooking, ready, assigned, en route, completed/cancelled; order detail and route.
3. **Drivers & Fleet:** on-shift drivers, status, vehicle/type, capacity, performance, assignments.
4. **Delivery Area:** map coverage, maximum range, average ETA, excluded zones, demand forecast.
5. **Performance:** completion time, cancellations, late rate, margin, driver utilization.

### D6. Suppliers & Inventory — Placeholder → Planned

**Screen ID:** `manage.suppliers`

**Tabs:**

1. **Overview:** stock health, days of cover, inbound shipments, waste, shortages, urgent actions.
2. **Inventory:** ingredient, quantity, reserved, quality/freshness, days remaining, storage, source, value.
3. **Suppliers:** compare price, quality, reliability, lead time, fee, catalog; contract detail and select/replace.
4. **Purchase Orders:** draft, confirmed, shipped, delayed, received, cancelled; order detail and ETA.
5. **Warehouses:** owned/rented sites, capacity, assigned restaurants, inventory, routes, upgrades.
6. **Transfers:** source/destination, contents, status, vehicle/ETA, delay reason.
7. **Policies:** reorder point, target stock, preferred supplier, quality minimum, substitutions, emergency purchase behavior.
8. **Waste & Reliability:** spoilage, stockouts, lost sales, supplier performance.

### D7. Reports — Placeholder → Planned

**Screen ID:** `manage.reports`

**Home:** pinned KPIs, period selector, alert/explanation cards, saved report presets.

**Report families:** Company, Restaurants, Operations, Recipes, Workforce, Supply, Marketing, Competition, Incidents/Government.

**Common controls:** date range, interval, filters, group by, compare, chart/table toggle, event annotations, jump to source. Clicking an anomaly opens the events that explain it.

### D8. Finances — Existing/Partial

Opens Finances filtered to the selected restaurant and defaults to its branch detail. Company-wide navigation remains available.

### D9. Visit / Interior — Existing/Partial

**Screen ID:** `restaurant.interior`

**Current mode:** full-screen restaurant interior, Back to City, restaurant title, orbit/zoom camera, and live visual operations.

**Planned top-level modes:**

1. **Observe:** live customers, staff, queue, cooking, tables, pickups, deliveries; select actor/station for status.
2. **Edit Interior:** local simulation paused, furniture catalog, ghost placement, move/rotate/duplicate/sell, undo/redo, budget, validation.
3. **Evaluate:** seats, kitchen slots, queue capacity, flow, condition, cleanliness, style, demographic appeal, warnings.
4. **Heatmaps:** congestion, staff travel, cleanliness, customer sentiment, station utilization.
5. **Templates/Designer:** apply, save, duplicate, or share company layout templates; preview total price and changed objects.
6. **Expansion:** current footprint, expansion options, construction cost/time, capacity gain.

**Furniture catalog:** Seating, Kitchen, Service, Queue, Decoration, Entertainment, Utilities, Floors/Walls, Stored/Owned.

### D10. Rating & Awards — Planned

**Screen ID:** `restaurant.rating`

**Tabs:** Rating Summary, Dimension Detail, Inspections, Awards, Improvement Plan, History.

Shows restaurant-specific stars and food, service, atmosphere, cleanliness, and value. “Next star” lists blockers and sustained observation requirements. Inspection results link directly to corrective screens.

### D11. Security & Incidents — Planned

**Screen ID:** `restaurant.security`

**Tabs:** Security Coverage, Guards, Alerts, Incidents, Recovery, Police/Insurance.

Shows known vulnerabilities, alert level, guard assignment, response ETA, active effects, evidence/known attacker confidence, repair/remediation, and financial loss.

## E. Company entities and strategic workspaces

### E1. Headquarters — Planned

**Screen ID:** `company.headquarters`

**Tabs:**

1. **Overview:** tier, departments, upkeep, capacity, active projects, company alerts, next unlocks.
2. **Departments:** Operations, Training, Marketing, Procurement, Analytics, Security, Legal/Government, Underworld where enabled.
3. **Upgrades:** tier/department tree, prerequisites, cost, build time, capability comparison.
4. **Managers & Policies:** manager capacity, assignments, company templates, approval inbox.
5. **Training:** programs, slots, queue, outcomes.
6. **Procurement:** contracts, warehouse network, company policies.
7. **Analytics:** company dashboards and intelligence level.
8. **Security:** headquarters guards, threats, incidents, defense upgrades.
9. **Government Relations:** civic standing, donations/lobbying, permits, violations.
10. **Underworld:** crew and operations when enabled.

### E2. Managers & Automation — Planned

**Screen ID:** `company.managers`

**Tabs:** Assignments, Policy Templates, Approval Inbox, Decisions, Performance, Escalations.

**Branch manager detail:** goals, authority by category, spending limit, cash reserve, staffing/schedule policy, inventory, repairs, price/menu authority, marketing authority, decision timeline, and performance versus target.

Every automated change shows what changed, why, cost, expected result, actual result, and whether it can be overridden.

### E3. Warehouse — Planned

**Screen ID:** `company.warehouse`

**Tabs:** Overview, Inventory, Inbound Orders, Restaurant Transfers, Assigned Restaurants, Vehicles/Routes, Upgrades, Policies, Costs & Waste.

World selection opens the selected warehouse. Company procurement opens a network view across all warehouses.

### E4. Awards & Competitions — Planned

**Screen ID:** `company.awards`

**Tabs:** Calendar, Eligibility, Restaurant Awards, Recipe Competitions, Active Entry, Results, History/Trophy Case.

Competition flow: invitation/challenge → prompt and constraints → participants → choose/create recipe → validate/freeze version → submit → countdown → judging/results → rewards.

### E5. Rival Company — Planned

**Screen ID:** `competition.rival`

**Tabs:** Public Profile, Known Branches, Market Position, Known Campaigns, Recent Moves, Comparison, Relationship/Actions.

Actions may include View Branch, Compare Report, Challenge to Competition, Respond with Marketing, Report Violation, Negotiate Extortion, or Underworld Targeting according to enabled systems and knowledge.

Exact private finances, recipes, staffing, or plans are never shown without a valid intelligence source.

## F. Civic and underworld workspaces

### F1. City Hall / Government — Planned

**Screen ID:** `city.government`

**Tabs:**

1. **Overview:** city policies, official contacts, civic/company standing, active deadlines.
2. **Permits & Compliance:** permits, certificates, violations, remediation, appeals.
3. **Inspections:** scheduled/completed visits, checklist, findings, deadlines, assigned official.
4. **Mayor & Influence:** declared donations, civic sponsorship, lobbying, relationship, competing influence.
5. **Development:** proposed buildings/transit/zoning changes, expected district effects, support/oppose.
6. **Police:** stations, coverage, approximate response time, company standing, active investigations.
7. **Fines & Legal:** fines, closures, appeals, evidence, payment history.

### F2. Underworld — Planned, optional

**Screen ID:** `company.underworld`

**Tabs:** Crew, Available Actions, Target Intelligence, Active Operations, Heat & Evidence, Extortion, History.

Operation flow: choose action → target → crew → approach/timing → review cost/effect/risk/countermeasures → confirm → track phases → incident/result.

High-impact actions require stronger confirmation and clearly state possible failure, attribution, police response, company reputation damage, and target recovery options.

### F3. Police / Incident response — Planned

**Screen ID:** `city.police_incident`

Opened from an active incident or Police tab. Shows location, type, known threat, unit availability, route/ETA, guards present, evidence status, and company actions such as Call Police, Raise Alert, Evacuate/Close, or Begin Recovery.

## G. Missions, messaging, and guidance

### G1. Notification center — Planned expansion

Extends current Messages/News with tabs: All, Inbox, Operations, Economy, Competition, Civic, Security.

Each item has timestamp, severity, source, concise explanation, affected entity, primary action, secondary dismiss/archive, and read state. Similar low-priority events group rather than flood the feed.

### G2. Mission Offer — Planned

**Screen ID:** `scenario.mission_offer`

Shows issuer, goal, deadline, constraints, reward, failure consequence, and Accept/Decline. Accepted missions appear in Objectives and notification center. Expired offers remain in history.

### G3. Tutorial Coach — Planned

Non-blocking coach card with current goal, short instruction, optional Why?, Show Me camera focus, Skip Step, and Exit Tutorial. It observes normal actions; it does not replace production UI with special tutorial-only controls.

### G4. Critical state dialogs

- Bankruptcy warning and bankruptcy result.
- Scenario completed/failed.
- Restaurant forced closure.
- Save corruption/recovery.
- Destructive action confirmation.
- Feature/system disabled by scenario.

Dialogs state cause, consequence, available recovery, and where to go next.

## H. Required common states for every workspace

Design each major screen in these states where applicable:

1. **Default populated.**
2. **No selection:** explain what must be selected and offer a route to it.
3. **Empty:** no restaurants/staff/recipes/campaigns/orders/etc.; one clear primary action.
4. **Locked:** prerequisite, cost/progress, and link to unlock source.
5. **Unaffordable or capacity full:** exact shortfall and alternatives.
6. **Loading/recalculating:** preserve layout; avoid flashing empty state.
7. **Warning:** operation allowed but consequence explained.
8. **Error:** retain user input where possible and give corrective action.
9. **Read-only:** result/history/rival estimate with edit actions removed explicitly.
10. **Unsaved draft:** dirty marker, Save/Discard/Cancel on exit.
11. **Concurrent change:** restaurant/company state changed while screen was open; refresh with a non-destructive explanation.

## I. Shared components designers should define

- Company/restaurant/city switcher.
- Entity breadcrumb and Back/Close controls.
- KPI chip with value, trend, tooltip, and alert state.
- Filter bar, period selector, group-by, compare tray.
- Timeline/shift editor.
- Progress/objective row.
- Candidate/employee card.
- Recipe card and ingredient tile.
- Pizza canvas and burger stack layer.
- Restaurant/location/warehouse comparison row.
- Campaign card and placement marker.
- Inventory row with freshness and inbound state.
- Report chart shell and event annotation.
- Ranking row with movement.
- Upgrade/capability node with prerequisite state.
- Policy control with Recommend/Approval/Automatic modes.
- Incident card with evidence confidence and recovery action.
- Confirmation dialog with cost/consequence block.
- Toast, alert banner, inbox item, and grouped notification.
- Locked-state panel and empty-state call to action.

## J. Critical end-to-end UX flows

### J1. Open the first restaurant

City/Restaurants → Available Locations → compare property → view on map → Sign Lease → name branch → starter setup checklist → Recipes/Menu → Staff/Schedule → Channels & Hours → Open.

### J2. Create and sell a custom pizza or burger

Recipes → Recipe Book → New Recipe → Pizza or Burger → assemble → validate appeal/cost → name/save → Restaurant Menu → enable/set quality/price → resolve ingredient/station warnings → publish.

### J3. Resolve an operations bottleneck

Restaurant Panel → Operations → bottleneck evidence → recommended action → filtered Staff/Recipes/Delivery/Interior/Suppliers screen → change → return to Operations → verify result.

### J4. Launch marketing

Restaurant Panel → Marketing → Create Campaign → scope/channel → placement → audience/message → budget/duration → review → Start → Active Campaign → Results.

### J5. Fix a stockout

Alert/Operations → Suppliers & Inventory → affected ingredient → inbound/policy/supplier detail → emergency buy, substitute, expedite, or disable recipe → confirm cost → monitor shipment.

### J6. Edit the restaurant interior

Visit → Edit Interior → choose catalog item → place/validate → evaluate flow/appeal → save layout → resume local simulation → Observe/Operations.

### J7. Delegate a branch

Headquarters → Managers & Policies → assign manager → choose preset → set authority/guardrails → review predicted actions → activate → Approval Inbox/Decisions.

### J8. Enter a recipe competition

Inbox/Awards → competition prompt → accept → open Recipe Book/Workshop → create or choose eligible pizza/burger → freeze version → submit → track countdown → results/reward.

### J9. Respond to an inspection

Inbox/Restaurant Alert → inspection findings → remediation checklist → jump to Inventory/Interior/Staff/Permits → correct → request reinspection or await deadline → result.

### J10. Respond to sabotage

Incident alert → Security & Incidents → known effect/evidence → close/call police/dispatch guards/recover → City Police Incident → repair/remediate → report loss and outcome.

### J11. Finish a scenario and move cities

Objectives complete → Results → score/awards/unlocks → Save Result → Next City → briefing/company carryover → Start.

## K. Time, modal, and back-stack rules

- Opening ordinary management screens does not pause by default.
- Global Pause pauses business simulation and remains visible in the top bar.
- Interior Edit pauses that restaurant’s local operations and clearly marks it; global time may continue.
- Blocking scenario results, bankruptcy, save recovery, and destructive confirmation pause the game.
- Escape closes transient popups first, then goes back one navigation level, then opens Pause from the city.
- Returning from a linked corrective screen restores the prior screen, tab, filters, selected entity, and scroll position.
- Switching restaurants with a dirty draft requires Save/Discard/Cancel.

## L. Accessibility and input requirements

- All primary navigation and management actions are keyboard accessible with visible focus.
- Color is never the only carrier for profit/loss, quality, freshness, risk, rank movement, or alert severity.
- Text scale must not obscure critical actions; complex tables support row stacking or scrolling.
- Charts provide values in tooltips and an accessible table view.
- Drag interactions—pizza toppings, burger layers, shifts, furniture—also have select/move/reorder button or keyboard alternatives.
- Reduced motion disables hover scaling, large modal transitions, and animated map pulses while retaining state changes.
- Destructive confirmations default focus to Cancel.
- Tooltips explain formulas in plain language and distinguish exact values from estimates.

## M. Responsive desktop priorities

The current composition is desktop-first and information dense. Design first for the project’s target desktop resolution, then define compact behavior:

- Right restaurant panel collapses to a drawer.
- Left objectives/events collapse to alert badges/cards.
- Bottom information band becomes tabbed.
- Bottom navigation retains labels where possible; overflow is explicit, not icon-only ambiguity.
- Management workspaces use a single content column plus optional inspector drawer at narrow widths.
- The city viewport never becomes completely obscured by non-blocking panels.

## N. Developer-only UI

`dev_inspector.gd` and development lineup/audit scenes are not player-facing menus. Keep diagnostic controls visually and structurally separate from production navigation, gated by development builds or explicit debug settings.

## O. Design deliverables recommended per screen

For each screen or workspace, the UI/UX team should produce:

1. Sitemap position and entry/exit paths.
2. Default, empty, locked, warning, error, and narrow-layout wireframes.
3. Primary task flow and destructive-action flow.
4. Component inventory and reusable component references.
5. Keyboard/focus order and drag alternative.
6. Time behavior and back-stack behavior.
7. Data ownership: exact, estimated, or unknown.
8. Copy deck for titles, labels, tooltips, validation, confirmations, and empty states.
9. Prototype for any high-risk interaction: pizza placement, burger stacking, furniture editing, shift scheduling, campaign creation, report filtering, or policy automation.

