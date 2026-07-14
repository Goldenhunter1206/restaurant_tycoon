# Government, Mayor, and Police

## Goal

Create a civic simulation that evaluates restaurant compliance, responds to crime, awards prestige, influences city development, and gives companies lawful and corrupt ways to build relationships. Government actors must provide predictable rules and strategic leverage without becoming random punishment.

## Data model

- `GovernmentState`: city ID, departments, active policies, inspection schedules, police resources, development projects, and public events.
- `CompanyCivicState`: permits, official reputation, police reputation, mayor relationship/influence, violations, donations, evidence/heat, fines, and active closures.
- `OfficialDef/State`: mayor, food inspector, labor inspector, tax official, police commander; priorities, schedule, integrity, and authority.
- `InspectionDef/State`: trigger, target, checklist, notice, assigned official, visit time, findings, appeal deadline, and outcome.
- `PoliceUnitState`: station, readiness, strength, route, current incident, response ETA, and recovery.
- `DevelopmentProject`: proposed building/zone change, affected demand, sponsors, decision date, and result.

Keep official reputation separate from customer reputation and criminal heat. A company can be popular but poorly regarded by regulators.

## Inspections and compliance

Inspection checklists query real state:

- Food freshness, contamination, stock storage, and supplier traceability.
- Cleanliness, furniture condition, blocked paths, and safety.
- Staff schedules, health/absence, and scenario-specific labor rules.
- Permits, taxes/ledger consistency, and prior violations.

Inspections may be scheduled, triggered by complaints/incidents, or requested against a rival when credible evidence exists. Outcomes include warning, remediation deadline, fine, temporary closure, reputation change, or clean certificate. The player always receives findings and the exact corrective conditions.

## Mayor and influence

The mayor affects property pricing policy, permits, inspection priorities, awards, city events, and development projects. Companies can make declared donations, sponsor civic events, lobby for projects, or—if the scenario permits corruption—offer illicit payments with evidence risk. Influence changes probabilities or priorities within limits; it never directly overwrites objective simulation facts.

Development projects can change nearby demand by adding/removing attractions, transit, housing, industry, or entertainment. The player sees proposals early, expected district effects, competing company support, and the final rationale.

## Police

Police stations have finite response units. Crime incidents request the nearest available capable unit; route and traffic determine ETA. Police secure scenes, confront hostile agents abstractly, collect evidence, and may investigate or raid companies. Funding, city policy, company reputation, and current heat affect readiness and scrutiny, but response rules remain visible.

Companies can hire guards for immediate private defense and call police for detected incidents. False or abusive reports reduce official reputation. Raids may temporarily close a branch or headquarters and seize illegal resources when supported by evidence.

## UI and world presentation

- City Hall screen for permits, reputation, donations, lobbying, officials, development proposals, fines, appeals, and inspection history.
- Police/security overlay with station coverage and approximate response time.
- Inspection checklist and remediation tracker at each restaurant.
- Civic news for policy changes, awards, projects, raids, and public events.
- Officials and police can travel in the world when visible; off-screen actions use route-derived timing.

## Integrations

- Inventory/interiors/staff supply inspection facts.
- Awards use mayor/official visits and civic state.
- Crime supplies incidents, evidence, heat, and raids; security supplies guards.
- Marketing claims and placements can create violations.
- Economy records taxes, donations, fines, permits, sponsorships, and closure losses.
- City breadth defines local policies, official profiles, police resources, and development pools.
- AI companies lobby, comply, report rivals, and react to enforcement through the same commands.
- Reports distinguish legal expense, violations, civic influence, and crime losses.

## Delivery phases

### Phase 1 — Civic reputation and inspections

Add company civic state, one food/safety checklist, scheduled visits, warnings, remediation, fines, closure, appeals, and save/load.

### Phase 2 — Police response

Add stations/units, route ETA, incident dispatch, evidence collection, guards interaction, raids, and coverage UI.

### Phase 3 — Mayor and influence

Add donations, lobbying, awards scheduling, official profiles, corruption risk, and rival competition for influence.

### Phase 4 — City development and policy

Add proposals, transit/building changes, local regulations, public events, AI strategy, and campaign hooks.

## Acceptance criteria

- Every inspection finding maps to current restaurant state and a concrete corrective action.
- Correcting violations before the deadline prevents the documented escalation.
- Police response time reflects station availability, route distance, and traffic.
- Evidence and legal state persist across save/load and cannot resolve twice.
- Influence changes bounded decisions but cannot guarantee awards or erase proven severe violations.
- Development projects create measurable, reported demand/location effects.
- AI companies can comply, appeal, donate/lobby, call police, and receive penalties under the same rules.

## Risks and controls

- **Random punishment:** notice, visible checklists, deterministic findings, and appeal/remediation paths.
- **Corruption as dominant strategy:** diminishing influence, competing donations, evidence risk, upkeep, and integrity differences.
- **Police pathing cost:** full agents only for visible responses; route-time aggregation elsewhere.
- **Systemic snowballing:** civic actions consume money and attention, and influence decays over time.

