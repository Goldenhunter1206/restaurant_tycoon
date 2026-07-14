extends Node
## Marketing campaigns: a paid demand-utility boost for citizens near a
## branch. One system shared by the player's Marketing screen and the rival
## AI — both go through start_campaign() and pay the same daily cost.

signal campaigns_changed

var campaigns: Array[MarketingCampaign] = []

var _initialized: bool = false


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	# Daily charge/expiry runs inside each company's ledger day.
	EconomyManager.daily_cost_providers.append(_charge_daily)
	if CompanyManager.loaded_save != null:
		for campaign: MarketingCampaign in CompanyManager.loaded_save.active_campaigns:
			campaigns.append(campaign)


func start_campaign(campaign: MarketingCampaign) -> CommandResult:
	var company: CompanyState = CompanyManager.company(campaign.company_id)
	if company == null:
		return CommandResult.fail(&"unknown_company", "No company '%s'." % campaign.company_id)
	var rest: RestaurantState = RestaurantManager.by_building.get(campaign.building_id)
	if rest == null or rest.company_id != campaign.company_id:
		return CommandResult.fail(&"not_owner", "That branch isn't owned by the company.")
	for existing: MarketingCampaign in campaigns:
		if existing.company_id == campaign.company_id and existing.building_id == campaign.building_id:
			return CommandResult.fail(&"already_running", "A campaign is already running for this branch.")
	if not company.can_afford(campaign.cost_per_day):
		return CommandResult.fail(&"insufficient_cash", "First day costs $%.0f." % campaign.cost_per_day)
	company.transact(&"marketing", -campaign.cost_per_day)
	campaigns.append(campaign)
	campaigns_changed.emit()
	return CommandResult.good(campaign)


func stop_campaign(campaign: MarketingCampaign) -> void:
	if campaigns.has(campaign):
		campaigns.erase(campaign)
		campaigns_changed.emit()


func campaigns_for(company_id: StringName) -> Array[MarketingCampaign]:
	var result: Array[MarketingCampaign] = []
	for campaign: MarketingCampaign in campaigns:
		if campaign.company_id == company_id:
			result.append(campaign)
	return result


## Extra offer utility when the citizen at `origin` sits inside a campaign
## radius of `rest` and matches the campaign's target demographic.
func bonus_for(rest: RestaurantState, demographic: StringName, origin: Vector3) -> float:
	if campaigns.is_empty():
		return 0.0
	var best: float = 0.0
	for campaign: MarketingCampaign in campaigns:
		if campaign.building_id != rest.building_id:
			continue
		if origin.distance_to(rest.door_pos) > campaign.radius:
			continue
		if campaign.demographic != &"" and campaign.demographic != demographic:
			continue
		best = maxf(best, campaign.utility_bonus)
	return best


## Registered with EconomyManager.daily_cost_providers — runs once per
## company on day rollover, before that company's ledger closes.
func _charge_daily(company: CompanyState, _day: int) -> void:
	var changed: bool = false
	for i: int in range(campaigns.size() - 1, -1, -1):
		var campaign: MarketingCampaign = campaigns[i]
		if campaign.company_id != company.id:
			continue
		campaign.days_left -= 1
		var branch_gone: bool = not RestaurantManager.by_building.has(campaign.building_id)
		if campaign.days_left <= 0 or branch_gone or not company.can_afford(campaign.cost_per_day):
			campaigns.remove_at(i)
			changed = true
			continue
		company.transact(&"marketing", -campaign.cost_per_day)
	if changed:
		campaigns_changed.emit()
