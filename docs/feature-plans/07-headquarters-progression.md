# Headquarters Progression

## Goal

Create a visible company headquarters that provides long-term progression, company-wide capacity, information, and unlocks. Headquarters growth should turn early hands-on restaurant management into a scalable chain-management game without making basic viability depend on arbitrary grind.

## Design principles

- Headquarters unlock new strategic tools; they do not simply add global percentage bonuses.
- Every upgrade has an operational purpose, recurring cost, and visible world/UI representation.
- Core restaurant operation remains available without a headquarters. Expansion systems such as advanced advertising, training, managers, analytics, warehouses, security, and underworld actions require departments or capacity.
- Progress is primarily economic and strategic, with campaign-specific restrictions layered on top.

## Data model

- `HeadquartersState`: company ID, building ID, tier, departments, capacity usage, staff, security, condition, active projects, and known intelligence.
- `HeadquartersTierDef`: tier, purchase/build requirements, upgrade cost/time, footprint/scene variant, base operating cost, department slots, and capability grants.
- `DepartmentDef`: ID, display data, prerequisites, construction cost/time, upkeep, capacity, capabilities, and world-room representation.
- `UpgradeProjectState`: source/target tier or department, start/end time, paid amount, paused state, and blockers.
- `CapabilityRegistry`: capability ID, source, current level/capacity, and consumers.

Suggested departments include Operations, Training, Marketing, Procurement, Analytics, Security, Legal/Government Relations, and—if enabled by the scenario—Underworld.

## Capability model

Features query capabilities rather than headquarters tier numbers. Examples:

- `marketing.local_campaigns`, `marketing.billboards`, `marketing.citywide`
- `staff.training_slots`, `management.branch_managers`
- `procurement.warehouse_count`, `analytics.report_depth`
- `security.guard_capacity`, `crime.crew_capacity`

This avoids scattering checks such as “HQ level >= 3” across UI and managers. Multiple sources may grant a capability, allowing scenarios, awards, or temporary events to modify access cleanly.

## Headquarters gameplay

Players acquire or construct one headquarters per city/company according to scenario rules. They choose when to upgrade and which departments to prioritize. Projects take time, may temporarily consume capacity, and add daily costs. Headquarters can employ specialized staff and becomes a strategic location for guards, managers, intelligence, or criminal crews.

The headquarters dashboard shows:

- Tier, departments, active projects, capability capacity, upkeep, and next unlocks.
- Company-wide alerts and manager summaries.
- Security, legal/government standing, and hostile threats.
- Central policies, base menu, supplier contracts, marketing portfolio, and research/training queues.

The world building should visibly change by tier or use modular additions. Selecting it opens the dashboard rather than a restaurant panel.

## Progression outline

### Tier 0 — Founder mode

No headquarters. The player operates restaurants manually with local hiring, pricing, and basic suppliers/marketing.

### Tier 1 — Office

Company dashboard, consolidated reports, local marketing coordination, basic procurement, and one department.

### Tier 2 — Regional headquarters

Staff training, guards/security, billboard coordination, additional departments, and branch-manager capacity.

### Tier 3 — Corporate center

Citywide marketing, advanced analytics, central recipes/base menu, strong automation, interior designer templates, and larger warehouse network.

### Higher or specialized progression

Scenario-dependent government relations, advanced security, intelligence, and underworld capacity. Prefer specialization branches over many linear tiers.

## Integrations

- Campaign scenarios can grant, restrict, or require capabilities.
- Managers consume management capacity; training consumes training slots.
- Marketing channels and campaign count use marketing capabilities.
- Warehouses/contracts use procurement capacity.
- Reports reveal more comparison detail through analytics.
- Crime and guards use separate underworld/security capacities.
- AI competitors choose headquarters investments based on profile and strategy.
- Save/load persists projects and recalculates capabilities from definitions.

## Delivery phases

### Phase 1 — Capability registry

Implement company capability queries, sources, limits, UI lock explanations, serialization, and developer inspection tools without changing gameplay access.

### Phase 2 — Headquarters property and tiers

Add acquisition, upgrade projects, upkeep, world representation, dashboard, and two initial tiers.

### Phase 3 — Departments

Add Operations, Training, Marketing, Procurement, and Analytics with real feature capacity and tradeoffs.

### Phase 4 — Security and specialization

Add security/legal/underworld departments, specialized branches, AI strategy, damage/defense, and campaign hooks.

## Acceptance criteria

- Features query capabilities through one registry and show the exact missing prerequisite.
- Upgrades cost money, take time, charge upkeep, survive save/load, and cannot complete twice.
- Different department choices create materially different company strategies.
- Losing or selling a headquarters disables new actions gracefully without corrupting active state.
- AI can select upgrades, respect capacity, and remain solvent.
- Old saves receive an explicit migration state rather than silently unlocking everything.

## Risks and controls

- **Artificial gating:** retain a useful basic version of core systems before headquarters unlocks advanced scale or automation.
- **Dependency cycles:** capabilities are passive facts; departments never call consuming systems directly.
- **Feature-plan coupling:** ship the registry early, but add departments only when their consuming feature is functional.
- **One optimal build:** upkeep, limited slots, scenario conditions, respec costs, and competitor pressure should support specialization.

