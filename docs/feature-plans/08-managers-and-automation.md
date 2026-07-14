# Managers and Automation

## Goal

Allow growing chains to delegate repetitive branch operation without removing strategic control. Managers should execute explicit player policies, have measurable competence, make explainable mistakes, and use the same business commands available to the player and rival AI.

## Existing foundation

Restaurants already expose operational bottlenecks, staff rosters, schedules, menu settings, opening hours, delivery caps, daily results, and finance data. These become manager observations and actions. The feature depends on deeper staff progression and headquarters management capacity, but a limited manager prototype can precede both.

## Data model

- Extend `StaffMember` or create `ManagerAssignment` with manager UID, restaurant ID, authority level, start date, salary, and performance history.
- `BranchPolicy`: goal weights, cash budget, reserve threshold, staffing targets, schedule template, pricing bounds, allowed quality tiers, menu rules, inventory/waste targets, repair threshold, marketing allowance, delivery policy, and escalation preferences.
- `AutomationRule`: trigger metric/operator/value, cooldown, permitted command, limits, and enabled state.
- `ManagerDecisionRecord`: timestamp, observation, chosen command, expected result, actual result, cost, and explanation.
- `Escalation`: severity, evidence, recommended action, deadline, and player response.

Policies are versioned resources/state so they can be copied between restaurants and saved as company templates.

## Manager loop

At scheduled decision windows, a manager:

1. Reads only branch reports, forecasts, and company policy.
2. Identifies deviations such as understaffing, low stock, poor margins, congestion, wear, or excess waste.
3. Generates allowed actions within authority and budget.
4. Scores actions using manager skills and policy priorities.
5. Executes through shared command APIs after validation.
6. Records the decision and escalates anything outside authority.

Manager quality affects forecast error, reaction time, candidate evaluation, scheduling efficiency, and probability of choosing a near-best action. It must not directly multiply restaurant output.

## Player controls

The manager screen should offer:

- Assignment and salary/contract information.
- High-level goals: profit, growth, quality, reputation, stability, or delivery service.
- Guardrails: minimum cash reserve, price range, maximum daily spend, approved suppliers, no-firing list, minimum quality, and actions requiring approval.
- Policies for staffing, schedules, ordering, repairs, menu changes, and local marketing.
- “Recommend only,” “ask approval,” and “automatic” authority modes by category.
- Decision timeline with plain-language explanations and undo/override where safe.
- Alerts for unresolved issues and manager performance against targets.

Provide presets such as Conservative, Growth, Premium, Value, Delivery-first, and Custom. Copying a policy across branches should remain easy, but local overrides must be visible.

## Supported automation

Initial release:

- Reorder stock within supplier and budget policy.
- Repair/replace furniture below condition thresholds.
- Maintain approved staff counts and schedule templates.
- Adjust delivery cap and opening hours from demand windows.
- Escalate price/menu suggestions without changing them automatically.

Later releases:

- Controlled pricing and quality adjustments.
- Candidate hiring/firing, training enrollment, local marketing, layout template application, and emergency responses.

## Integrations

- Headquarters provides manager slots and policy sophistication.
- Staff depth provides manager skills, motivation, fatigue, training, and retention.
- Reports provide observations and performance evaluation.
- Suppliers, interiors, marketing, and recipes expose commands with permission metadata.
- Rival AI may use the same policy engine for individual branches while retaining a strategic company planner.
- Scenario restrictions can force manual play or cap authority.

## Delivery phases

### Phase 1 — Policy and audit foundation

Create policies, command permission metadata, dry-run recommendations, decision records, and a “recommend only” assistant for one restaurant.

### Phase 2 — Safe automation

Automate inventory reorder, repair, delivery cap, and schedule-template maintenance with budgets and cooldowns.

### Phase 3 — Manager employees

Add manager hiring, skill effects, headquarters capacity, salary, evaluation, reassignment, and training.

### Phase 4 — Advanced delegation

Add pricing/menu/marketing authority, approval inbox, multi-branch templates, AI reuse, and emergency management.

## Acceptance criteria

- Every automated action is legal through the same command used by manual UI.
- The player can explain what changed, why, when, and how much it cost from the audit log.
- Guardrails prevent spending below reserve, out-of-range pricing, unauthorized firing, and unapproved suppliers.
- “Recommend only” produces useful suggestions without mutating state.
- Better managers improve decision quality and response without hidden output bonuses.
- Policy and pending approvals persist across save/load without repeating commands.
- A ten-restaurant chain can operate for several game days without constant manual correction under a sensible preset.

## Risks and controls

- **Loss of agency:** granular authority levels, approvals, clear logs, and instant pause/disable.
- **Oscillation:** cooldowns, hysteresis, minimum commitment periods, and switching costs.
- **Cross-feature breakage:** commands advertise validation, cost estimate, reversibility, and permission requirements.
- **Invisible failure:** managers must escalate blockers instead of silently retrying forever.

