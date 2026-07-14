# Crime and Sabotage

## Goal

Implement an optional underworld strategy layer inspired by Pizza Connection 2: companies can pressure or disrupt rivals through escalating illegal actions, while targets can gather warnings, hire protection, recover, and involve authorities. The system must create calculated risk and counterplay rather than unavoidable random punishment.

## Product and scenario policy

Crime is a scenario capability and can be disabled in free play. Campaigns introduce it only after the legal economy is established. Actions are stylized tycoon-game abstractions; avoid graphic presentation. Every hostile effect has advance information where plausible, a defense, a duration or repair path, evidence risk, and an economic opportunity cost.

## Data model

- `CrimeActionDef`: ID, tier, target types, prerequisite capability/crew, cost, preparation time, execution duration, success formula, effects, evidence, heat, cooldown, and countermeasures.
- `CriminalAgentState`: UID, company, role, skill, loyalty, health/readiness, equipment tier, current assignment, and incarceration/recovery state.
- `CrimeOperationState`: action, attacker, target, agents, plan, phase, start/ETA, discovered state, evidence, outcome, and cancellation rules.
- `SecurityState`: guards, equipment, alert level, vulnerabilities, recent incidents, and protection coverage.
- `CompanyHeatState`: police heat, known evidence, official reputation, outstanding extortion, and investigation status.

Roles may include courier, punk/contact, enforcer, and gangster/advanced crew, unlocked through headquarters capabilities. Do not reuse ordinary staff invisibly; recruitment and capacity must be explicit.

## Action ladder

### Pressure and nuisance

Extortion demands, protests/punks, graffiti, rumor campaigns, staff bribery, minor theft, or stink disruption. These are cheaper, temporary, and carry lower evidence risk.

### Operational sabotage

Pest/contamination incidents, supply disruption, equipment damage, targeted staff intimidation, and forced closure through planted violations. Effects interact with inventory, cleanliness, maintenance, staffing, and inspections.

### Violent escalation

Property attack, guard conflict, kidnapping/forced recruitment abstraction, and bombing/demolition only in scenarios that enable the highest tier. These require major preparation, create strong police response and reputation consequences, and offer obvious warnings/counterplay.

## Resolution model

Operations progress through planning, travel, infiltration/confrontation, effect, escape, and investigation. Resolution uses attacker skill, target security, route/time, intelligence, alert level, and limited seeded uncertainty. World agents may visualize nearby operations, while distant operations use the same aggregated timing and probabilities.

Evidence and heat matter independently of success. A successful operation may still expose the attacker later. Failed operations can injure/lose agents, reveal intent, or create retaliation. The target receives an incident report distinguishing known facts from suspicions.

## Defense and recovery

- Guards, security upgrades, surveillance/intelligence, and alert policies.
- Police call/automatic response according to government relations and distance.
- Insurance or emergency funds where enabled.
- Repair, pest control, decontamination, temporary staff, and public-relations recovery.
- Counterintelligence to detect bribery and planned attacks.
- Negotiation or payment for extortion with explicit consequences.

## UI

The headquarters Underworld department shows crew, capacity, heat, available actions, target intelligence, expected effect range, cost, evidence risk, travel time, and known defenses. Confirmation must state likely collateral consequences. Security views show threats, coverage, guard assignments, alerts, and incident history. News avoids revealing attackers unless evidence supports it.

## Integrations

- Headquarters gates crew types and operation capacity.
- Government/police handles response, evidence, raids, fines, closure, and incarceration.
- Interiors and inventory provide concrete sabotage targets and recovery tasks.
- Staff supplies bribery, intimidation, injury, loyalty, and guard roles.
- Reports show incident loss, defense spending, suspected attackers, and heat.
- AI personality/ethics controls criminal appetite and retaliation.
- Campaigns can prohibit, require, or narratively constrain actions.
- Save/load freezes deterministic operation seeds and prevents repeated resolution.

## Delivery phases

### Phase 1 — Security and incident framework

Create operation lifecycle, security state, evidence/heat, incident reports, cooldowns, save/load, and non-hostile test operations.

### Phase 2 — Nuisance actions

Add extortion, graffiti/protest, rumor, basic staff bribery, guards, detection, and temporary recoverable effects.

### Phase 3 — Operational sabotage

Add pests, supply disruption, equipment damage, planted violations, investigations, insurance/recovery, and AI use.

### Phase 4 — High-tier conflict

Add advanced crews, property attacks, kidnapping abstraction, demolition, strong police response, and scenario-specific balancing.

## Acceptance criteria

- Every action shows prerequisites, cost, possible effect, risk, and known countermeasures before confirmation.
- Targets have at least one proactive and one reactive counterplay path.
- Operations resolve deterministically from their stored seed across save/load.
- Evidence, attribution, success, and heat are separate outcomes.
- Effects appear in operations and finance reports and expire or can be repaired.
- AI follows the same costs, capacity, evidence, and enforcement rules.
- Disabling crime removes actions and incidents without breaking campaigns not requiring them.

## Risks and controls

- **Arbitrary-feeling losses:** warnings, bounded effects, incident explanations, insurance/recovery, and difficulty controls.
- **Snowballing:** rising heat, expensive crews, retaliation risk, diminishing target impact, and government counterforce.
- **Feature complexity:** ship nuisance and security before irreversible high-tier actions.
- **Tone mismatch:** stylized presentation, optional mode, and no graphic detail.

