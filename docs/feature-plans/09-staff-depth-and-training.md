# Staff Depth and Training

## Goal

Turn employees from mostly static attributes and schedules into persistent people whose skill, health, motivation, fatigue, pay, experience, and development affect operations. Add the roles needed by the expanded simulation while keeping staffing understandable at chain scale.

## Existing foundation

`StaffMember`, `StaffTypeDef`, job candidates, hiring/firing, wages, shifts, staff attributes, and the schedule UI already exist. Current roles are cook, waiter, and driver. Extend these resources and flows rather than introducing a parallel workforce system.

## Data model

Extend `StaffMember` with:

- Experience and skill values by competency.
- Health, energy/fatigue, motivation, loyalty, stress, and satisfaction.
- Traits, training history, tenure, attendance, injuries/absence, and performance history.
- Contract terms, desired wage, raises, warnings, and manager relationship.
- Home/location and commute tolerance if citizen integration remains affordable.

Extend `StaffTypeDef` with role responsibilities, skill weights, legal schedule limits, uniform/visual data, progression curves, and station eligibility.

Add `TrainingProgramDef` and `TrainingEnrollment`: cost, duration, capacity, targeted competencies, health/motivation effect, work-efficiency penalty during training, prerequisites, and completion result.

New legitimate roles should include runner/stock worker, cleaner or cleaning contractor, and branch manager. Guards belong to the security feature but reuse workforce conventions. Avoid adding a role until it performs a real simulation task.

## Staff simulation

- Experience grows through successful task execution with diminishing returns.
- Skill affects speed, quality consistency, waste, customer handling, driving, management, or procurement according to role.
- Fatigue accumulates during shifts and from overtime; recovery occurs off shift.
- Motivation responds to wage fairness, workload, success, manager style, training, injuries, and branch condition.
- Health affects absence and vulnerability to hostile actions; routine operation should not create punishing random sickness.
- Low satisfaction increases lateness, mistakes, wage demands, and resignation probability with advance warning.
- Staff can transfer between restaurants subject to commute, schedule, and role constraints.

Use daily or shift-boundary updates for slow-changing values. Do not tick every psychological variable every frame.

## Labor market

Candidates are shared across companies and remain available for a limited time. Rivals can hire them. Market supply varies by city, role, wage climate, reputation, and campaign events. Candidate information may be imperfect until interviewed or assessed. Hiring requires a signing cost/time only if it creates meaningful planning; avoid delay for its own sake.

## Scheduling and work rules

Upgrade the current timeline to support reusable shift templates, coverage overlays, availability, overtime, breaks if required by tuning, and demand forecasts. The screen should show projected capacity by hour for kitchen, service, delivery, cleaning, and management. Conflicts must explain whether the cause is availability, maximum hours, training, transfer, or absence.

## Player-facing UI

- Roster cards with role, shift, pay, core skills, energy, motivation, and current status.
- Detailed employee view with trait explanations, history, goals, training, and performance.
- Candidate comparison and filters.
- Training queue and headquarters capacity.
- Pay review, transfer, promote/role-change, discipline, and dismissal actions.
- Schedule forecast showing demand versus staffed capacity.

Use trends and clear thresholds rather than requiring constant monitoring of many bars. Managers can handle routine raises, replacement hiring, and schedule maintenance within policy.

## Integrations

- Restaurant throughput and service quality derive from on-shift employee skills and condition.
- Interiors provide real stations, path load, and cleanliness tasks.
- Suppliers introduce runner/procurement work and waste effects.
- Headquarters supplies training capacity and manager slots.
- Awards inspect service and staff quality.
- Crime/government can cause injury, intimidation, inspections, or labor consequences with strong counterplay.
- Reports track turnover, payroll, absence, training return, productivity, and satisfaction.
- Save migration initializes new values from existing attributes and tenure-safe defaults.

## Delivery phases

### Phase 1 — Persistent condition

Add experience, fatigue, motivation, satisfaction, daily updates, UI summaries, save migration, and operational effects with conservative tuning.

### Phase 2 — Training and progression

Add programs, headquarters slots, enrollment, skill growth, performance history, and promotion/role prerequisites.

### Phase 3 — Labor market and roles

Add shared candidate competition, runner, cleaner/contractor, manager, transfers, resignations, and richer schedules.

### Phase 4 — Advanced management

Add employee goals, interviews, policy automation, city labor events, AI workforce strategy, and detailed analytics.

## Acceptance criteria

- Staff condition changes at deterministic shift/day boundaries and survives all time speeds.
- Better-trained staff improve the correct operational outcomes without bypassing capacity constraints.
- Excessive schedules create visible fatigue and recover after rest.
- Wage, workload, manager quality, and branch success affect motivation in explainable ways.
- Training costs time/capacity and produces the promised improvement exactly once.
- Rival hiring makes the candidate market competitive without stealing already contracted staff silently.
- The player can staff several branches using templates and manager policies without editing every shift individually.

## Testing strategy

- Seeded multi-week workforce simulations across schedule patterns.
- Boundary tests for shift wraparound, training during shifts, transfer, firing, and absence.
- Attribute-to-throughput tests for each role.
- Payroll reconciliation and save/load tests.
- Stress tests with the maximum planned staff count and accelerated time.

## Risks and controls

- **Too many meters:** surface a small summary and explain underlying factors on demand.
- **Death spirals:** warnings, gradual degradation, temporary staff/contractors, and manager recovery actions.
- **Balance volatility:** cap individual modifiers and make capacity/station constraints dominant.
- **Schedule micromanagement:** templates, forecasts, bulk actions, and delegation ship alongside depth.

