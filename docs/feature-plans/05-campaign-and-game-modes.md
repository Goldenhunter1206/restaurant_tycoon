# Campaign and Game Modes

## Goal

Add a structured product loop around the simulation: new-game setup, tutorial, a multi-city campaign with authored objectives and deadlines, configurable free play, scenario completion, scoring, failure, and progression between cities.

## Existing foundation

The game has a clock, economy events, four generic objective progress types, messages, bankruptcy, and a single main city. These are useful primitives, but objectives currently have no scenario lifecycle, rewards, failure conditions, branching, or city transition.

## Data model

- `GameSessionConfig`: mode, seed, city ID, difficulty, company identity, starting resources, rivals, enabled systems, and victory rules.
- `CampaignDef`: campaign ID, chapters/cities, narrative metadata, unlock rules, persistent rewards, and completion scoring.
- `ScenarioDef`: city ID, intro, starting state, rivals, required/optional objectives, time limit, scripted events, restrictions, success/failure outcomes, and next scenario.
- `ObjectiveDef`: ID, text, metric, operator, target, filters, deadline, visibility, reward, failure consequence, and prerequisites.
- `ScenarioState`: active objectives, progress snapshots, accepted side missions, elapsed time, score, completion state, and event flags.
- `PlayerProfileState`: completed scenarios, medals/scores, unlocked cities/content, tutorial state, and preferences.

Definitions should be resources or JSON validated at startup. Objective metrics should come from a registry rather than a hard-coded match statement in the panel.

## Scenario runtime

Create `ScenarioManager` as the authority for session initialization, objective evaluation, event scheduling, completion, failure, and transitions. It subscribes to simulation signals and also performs a low-frequency reconciliation pass so missed events cannot permanently stall progress.

Support objective forms such as:

- Reach or maintain cash, profit, reputation, market share, restaurant count, or awards.
- Serve a demographic, sell a recipe category, hit quality or delivery targets.
- Defeat/survive a rival, own a district, complete a recipe competition.
- Finish before a deadline or maintain a condition for several days.
- Optional missions delivered through the news/message system with explicit accept/decline and rewards.

Objectives need `hidden`, `revealed`, `active`, `completed`, `failed`, and `expired` states. Completion should freeze a result snapshot before offering continue/free-play/next-city choices.

## Game modes

### Campaign

Authored sequence of city scenarios with increasing complexity, recurring rivals, controlled feature introductions, narrative messages, and persistent score/unlocks.

### Free play

Player selects city, seed, starting cash, rival count/difficulty, economy difficulty, victory condition or endless play, and optional crime/government systems.

### Tutorial

Contextual task chain that teaches camera, buying a location, menu pricing, staff schedules, opening hours, operations, reports, and later systems. Tutorial steps must observe actions rather than seize control, and offer skip/reset.

### Challenge scenarios

Short data-driven setups for delivery-only, luxury dining, turnaround, price war, supply disruption, or crime-heavy play. These also serve as regression fixtures.

## Front-end flow

`Title → Continue / New Game / Load / Settings → Mode → Company setup → City/scenario setup → Intro → Play → Results → Next city or menu`

Company setup includes name, logo, color, and optional avatar. Scenario selection shows unlocked state, expected duration, enabled systems, rivals, objectives, and prior score.

## Integration requirements

- Save slots distinguish profile progress from individual session saves.
- City loading uses a city catalog and session bootstrap rather than a hard-coded main scene.
- AI profiles and starting assets come from scenario definitions.
- Reports and rankings produce scenario score components.
- Feature plans can register objective metrics and tutorial actions without modifying scenario core.
- Bankruptcy, hostile takeover, deadlines, or story events can trigger failure consistently.

## Delivery phases

### Phase 1 — Session bootstrap and objective registry

Create session config, scenario manager, extensible metrics, rewards/failure, and migrate current objectives into one sandbox scenario.

### Phase 2 — New-game and results flow

Build company setup, free-play configuration, scenario intro/results, restart, and return-to-menu.

### Phase 3 — Tutorial and side missions

Add action-observing tutorial steps, contextual help, optional timed missions, and reward/consequence handling.

### Phase 4 — Campaign content

Author the first three-city campaign slice, validate progression, then expand only after playtesting difficulty and save transitions.

## Acceptance criteria

- A scenario can initialize the city, companies, economy, objectives, and restrictions entirely from data.
- Success, failure, restart, save/load, and next-city transition preserve correct state.
- New objective metrics can be registered without editing the objectives panel.
- Free-play settings produce reproducible sessions with the same seed.
- Tutorial steps recognize already-completed actions and never deadlock after save/load.
- Results explain score sources and record campaign/profile progress once only.

## Testing strategy

- Fast deterministic scenarios for every objective operator and lifecycle state.
- Save/load at intro, mid-objective, deadline, results, and transition boundaries.
- Automated completion of the tutorial through command APIs.
- Campaign progression tests that prevent double rewards and locked-city bypasses.
- Content validation for unknown city, rival, objective, reward, and event IDs.

## Risks and controls

- **Content before framework stability:** ship a small vertical campaign slice before authoring all cities.
- **Objective deadlocks:** reconciliation queries, debug progress explanations, and scenario validation.
- **Feature gating complexity:** central capability flags supplied by session and headquarters state.
- **Long-session migrations:** version scenario state independently from general save data.

