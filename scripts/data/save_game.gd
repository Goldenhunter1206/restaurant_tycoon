class_name SaveGame
extends Resource
## Serializable snapshot of a play session (format v6: headquarters +
## source-aware capabilities). In-flight orders are not saved — kitchens restart empty on
## load, and inventory lot reservations are cleared on restore.
## v4 saves load fine: supply fields default empty and SupplyManager seeds
## starter stock into any restaurant without an inventory.

@export var save_version: int = 6
@export var day: int = 1
@export var game_hours: float = 7.0
## Every competing company (player + rivals), each carrying its own finances,
## restaurants and — player only — recipe book. Empty means pre-v4 save;
## pre-v4 saves are not migrated and load as "incompatible".
@export var companies: Array[CompanyState] = []
@export var active_campaigns: Array[MarketingCampaign] = []
## Billboard sites (vacant + rented); regenerated from seed when empty.
@export var ad_placements: Array[AdPlacement] = []
## company_id -> district -> segment -> awareness (0-1).
@export var marketing_awareness: Dictionary = {}
@export var city_trends: Array[CityTrend] = []
@export var job_market: Array[JobCandidate] = []
@export var next_candidate_uid: int = 1
## citizen_id -> wealth (tastes/wages regenerate deterministically).
@export var citizen_wealth: Dictionary = {}
## World seed chosen in the New Game Wizard (drives AI determinism).
@export var world_seed: int = 0
@export var difficulty: StringName = &"medium"
## Persistent scenario/award capability sources; HQ sources are derived.
@export var capability_sources: Array[CapabilitySourceState] = []
## Supply chain (v5+). Per-restaurant stock rides inside companies via
## RestaurantState.inventory; the rest is manager-owned global state.
@export var warehouses: Array[WarehouseState] = []
@export var purchase_orders: Array[PurchaseOrder] = []
@export var transfer_orders: Array[TransferOrder] = []
@export var supplier_contracts: Array[SupplierContractState] = []
@export var supply_disruptions: Array[SupplyDisruption] = []
@export var supply_next_id: int = 1
