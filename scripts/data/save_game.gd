class_name SaveGame
extends Resource
## Serializable snapshot (v7: management, automation, and workforce).

@export var save_version: int = 7
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
@export var capability_sources: Array[CapabilitySourceState] = []
## Supply chain.
@export var warehouses: Array[WarehouseState] = []
@export var purchase_orders: Array[PurchaseOrder] = []
@export var transfer_orders: Array[TransferOrder] = []
@export var supplier_contracts: Array[SupplierContractState] = []
@export var supply_disruptions: Array[SupplyDisruption] = []
@export var supply_next_id: int = 1
## Workforce section.
@export var workforce_schema_version: int = 1
@export var schedule_templates: Dictionary = {}
@export var training_enrollments: Array[TrainingEnrollment] = []
@export var training_completion_keys: Dictionary = {}
@export var absence_log: Array[Dictionary] = []
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
