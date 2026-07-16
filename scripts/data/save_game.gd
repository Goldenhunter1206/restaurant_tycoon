class_name SaveGame
extends Resource
## Serializable snapshot (v13: government, mayor & police civic layer).

@export var save_version: int = 13
@export var day: int = 1
@export var game_hours: float = 7.0
## Every competing company carries its own finances, restaurants, and workforce.
@export var companies: Array[CompanyState] = []
@export var active_campaigns: Array[MarketingCampaign] = []
@export var ad_placements: Array[AdPlacement] = []
@export var marketing_awareness: Dictionary = {}
@export var city_trends: Array[CityTrend] = []
## Shared, time-limited labor market.
@export var job_market: Array[JobCandidate] = []
@export var next_candidate_uid: int = 1
@export var citizen_wealth: Dictionary = {}
@export var world_seed: int = 0
@export var difficulty: StringName = &"medium"
## Campaign/session state is intentionally separate from the durable player profile.
@export var session_schema_version: int = 0
@export var session_config: Dictionary = {}
@export var scenario_state: Dictionary = {}
@export var scenario_result: Dictionary = {}
@export var capability_sources: Array[CapabilitySourceState] = []
## Supply chain.
@export var warehouses: Array[WarehouseState] = []
@export var purchase_orders: Array[PurchaseOrder] = []
@export var transfer_orders: Array[TransferOrder] = []
@export var supplier_contracts: Array[SupplierContractState] = []
@export var supply_disruptions: Array[SupplyDisruption] = []
@export var supply_next_id: int = 1
## Workforce section.
@export var workforce_schema_version: int = 2
@export var schedule_templates: Dictionary = {}
@export var training_enrollments: Array[TrainingEnrollment] = []
@export var training_completion_keys: Dictionary = {}
@export var absence_log: Array[Dictionary] = []
@export var city_labor_events: Array[Dictionary] = []
@export var turnover_log: Array[Dictionary] = []
## Shared command router section.
@export var command_router_schema_version: int = 1
@export var processed_command_ids: Dictionary = {}
@export var command_undo_records: Dictionary = {}
@export var command_daily_spend: Dictionary = {}
## Management and automation section.
@export var management_schema_version: int = 1
@export var manager_assignments: Array[ManagerAssignment] = []
@export var branch_policies: Array[BranchPolicy] = []
@export var manager_policy_templates: Array[BranchPolicy] = []
@export var manager_approvals: Array[ManagerApproval] = []
@export var manager_decisions: Array[ManagerDecisionRecord] = []
@export var manager_escalations: Array[ManagerEscalation] = []
@export var manager_observations: Array[BranchObservationSnapshot] = []
@export var manager_processed_windows: Dictionary = {}
@export var manager_next_uid: int = 1
## Analytics / reporting section (v9).
@export var analytics_schema_version: int = 1
@export var analytics_daily: Array[Dictionary] = []
@export var analytics_weekly: Array[Dictionary] = []
@export var analytics_quarterly: Array[Dictionary] = []
@export var analytics_events: Array[Dictionary] = []
## Ratings / awards / competitions section (v10). Schema 0 = section absent
## (pre-v10 save re-written by a v10 build) — AwardsManager reseeds on restore.
@export var awards_schema_version: int = 0
@export var rating_states: Array[RestaurantRatingState] = []
@export var award_results: Array[AwardResult] = []
@export var award_claimed_keys: Dictionary = {}
@export var competitions: Array[CompetitionState] = []
@export var competition_next_uid: int = 1
## Crime & sabotage section (v12). Schema 0 = section absent — CrimeManager
## seeds security/heat states on restore (one code path also covers fresh
## games and new branches).
@export var crime_schema_version: int = 0
@export var crime_agents: Array[CriminalAgentState] = []
@export var crime_operations: Array[CrimeOperationState] = []
@export var crime_security_states: Array[SecurityState] = []
@export var crime_heat_states: Array[CompanyHeatState] = []
## {"intel": attacker->target->last_valid_day, "cooldowns": key->day}.
@export var crime_intel: Dictionary = {}
@export var crime_op_next_uid: int = 1
@export var crime_incident_next_uid: int = 1
## Government / civic section (v13). Schema 0 = section absent — the
## GovernmentManager seeds civic states, officials and starter permits on
## restore (one code path also covers fresh games and new companies).
@export var government_schema_version: int = 0
@export var civic_states: Array[CompanyCivicState] = []
@export var gov_officials: Array[OfficialState] = []
@export var gov_inspections: Array[InspectionState] = []
@export var police_stations: Array[PoliceStationState] = []
@export var development_projects: Array[DevelopmentProjectState] = []
@export var gov_next_uids: Dictionary = {}
