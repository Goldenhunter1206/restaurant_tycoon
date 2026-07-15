extends Node
## Shared, explainable command gateway for player UI, managers, and rival AI.

signal command_executed(command_id: StringName, result: CommandResult, actor_context: Dictionary)
signal command_undone(undo_token: String, result: CommandResult)

const REVERSIBLE_COMMANDS: Array[StringName] = [
	&"restaurant.set_hours",
	&"restaurant.set_channels",
	&"delivery.set_cap",
	&"menu.set_entry",
	&"staff.set_schedule",
	&"furniture.set_repair_policy",
	&"operations.emergency_close",
]

var processed_commands: Dictionary = {}
var undo_records: Dictionary = {}
var daily_spend: Dictionary = {}
var _initialized: bool = false
var _staff: Variant = null


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_staff = get_node_or_null("/root/StaffManager")
	if _staff == null:
		push_error("BranchCommandRouter requires StaffManager.")
		return
	if not is_instance_valid(CompanyManager) or not is_instance_valid(RestaurantManager):
		push_error("BranchCommandRouter requires the domain managers.")
		return
	var save: SaveGame = CompanyManager.loaded_save
	if save != null:
		restore_from_save(save)


func describe(command_id: StringName) -> Dictionary:
	var descriptions: Dictionary = {
		&"inventory.reorder": _spec(&"inventory", "Reorder stock", false, 3, &"automatic"),
		&"inventory.set_policy": _spec(&"inventory", "Change reorder policy", true, 1, &"approval"),
		&"furniture.repair": _spec(&"maintenance", "Repair furniture", false, 6, &"automatic"),
		&"furniture.set_repair_policy": _spec(&"maintenance", "Change repair policy", true, 1, &"approval"),
		&"layout.apply_template": _spec(&"layout", "Apply approved layout", false, 24, &"approval"),
		&"layout.apply_draft": _spec(&"layout", "Apply interior layout", false, 24, &"approval"),
		&"layout.expand": _spec(&"layout", "Expand interior", false, 24, &"approval"),
		&"staff.hire": _spec(&"staffing", "Hire employee", false, 12, &"approval"),
		&"staff.fire": _spec(&"staffing", "End employment", false, 24, &"approval"),
		&"staff.transfer": _spec(&"staffing", "Transfer employee", false, 12, &"approval"),
		&"staff.promote": _spec(&"staffing", "Promote employee", false, 24, &"approval"),
		&"staff.train": _spec(&"training", "Enroll in training", false, 8, &"approval"),
		&"staff.set_schedule": _spec(&"schedules", "Change schedule", true, 2, &"automatic"),
		&"staff.bulk_schedule": _spec(&"schedules", "Apply schedule", false, 2, &"approval"),
		&"staff.save_schedule_template": _spec(&"schedules", "Save schedule template", false, 1, &"approval"),
		&"staff.apply_schedule_template": _spec(&"schedules", "Apply schedule template", false, 2, &"approval"),
		&"staff.set_contract": _spec(&"staffing", "Change contract policy", false, 12, &"approval"),
		&"restaurant.set_hours": _spec(&"hours", "Change opening hours", true, 6, &"approval"),
		&"restaurant.set_channels": _spec(&"channels", "Change service channels", true, 3, &"approval"),
		&"delivery.set_cap": _spec(&"delivery", "Change delivery cap", true, 3, &"automatic"),
		&"menu.set_entry": _spec(&"menu", "Change menu item", true, 12, &"approval"),
		&"marketing.start_local": _spec(&"marketing", "Start local campaign", false, 24, &"approval"),
		&"marketing.stop_local": _spec(&"marketing", "Stop local campaign", false, 1, &"automatic"),
		&"operations.emergency_close": _spec(&"emergency", "Pause branch service", true, 1, &"automatic"),
	}
	return descriptions.get(command_id, {})


func preview(command_id: StringName, arguments: Dictionary,
		actor_context: Dictionary = {}) -> CommandResult:
	var spec: Dictionary = describe(command_id)
	if spec.is_empty():
		return CommandResult.fail(&"unknown_command", "That command is not supported.")
	var context_result: CommandResult = _validate_context(arguments, actor_context)
	if not context_result.ok:
		return _decorate(context_result, command_id, spec, arguments, actor_context)
	var estimated_cost: float = _estimate_cost(command_id, arguments, actor_context)
	var policy_result: CommandResult = _validate_policy(command_id, arguments, actor_context, spec, estimated_cost)
	if not policy_result.ok:
		return _decorate(policy_result, command_id, spec, arguments, actor_context, estimated_cost)
	var domain_result: CommandResult = _preview_domain(command_id, arguments, actor_context)
	return _decorate(domain_result, command_id, spec, arguments, actor_context, estimated_cost)


func execute(command_id: StringName, arguments: Dictionary, actor_context: Dictionary,
		idempotency_key: String) -> CommandResult:
	if idempotency_key.is_empty():
		return CommandResult.fail(&"idempotency_required", "A command idempotency key is required.")
	if processed_commands.has(idempotency_key):
		var duplicate: CommandResult = _result_from_dictionary(processed_commands[idempotency_key])
		duplicate.duplicate = true
		return duplicate
	var checked: CommandResult = preview(command_id, arguments, actor_context)
	checked.idempotency_key = idempotency_key
	if not checked.ok:
		return checked
	var company_id: StringName = StringName(actor_context.get("company_id", arguments.get("company_id", &"player")))
	var company: CompanyState = CompanyManager.company(company_id)
	var cash_before: float = company.cash if company != null else 0.0
	var inverse: Dictionary = _capture_inverse(command_id, arguments, actor_context)
	var result: CommandResult = _dispatch(command_id, arguments, actor_context)
	var cash_after: float = company.cash if company != null else cash_before
	result.actual_cost = maxf(0.0, cash_before - cash_after)
	result.estimated_cost = checked.estimated_cost
	result.explanation = checked.explanation if result.explanation.is_empty() else result.explanation
	result.permission_category = checked.permission_category
	result.idempotency_key = idempotency_key
	result.actor_kind = StringName(actor_context.get("kind", &"player"))
	result.actor_id = str(actor_context.get("id", ""))
	result.executed_at = GameClock.total_minutes()
	result.metadata["command_id"] = command_id
	result.metadata["arguments"] = arguments.duplicate(true)
	if result.ok and bool(describe(command_id).get("reversible", false)) and not inverse.is_empty():
		var token: String = "undo:%s" % idempotency_key
		inverse["token"] = token
		inverse["post_state"] = _capture_post_state(command_id, arguments)
		inverse["consumed"] = false
		undo_records[token] = inverse
		result.reversible = true
		result.undo_token = token
	if result.ok:
		_record_spend(company_id, StringName(describe(command_id).get("category", &"")), result.actual_cost)
	processed_commands[idempotency_key] = result.as_dictionary()
	command_executed.emit(command_id, result, actor_context)
	return result


func undo(undo_token: String, actor_context: Dictionary) -> CommandResult:
	if not undo_records.has(undo_token):
		return CommandResult.fail(&"undo_unavailable", "That action can no longer be undone.")
	var record: Dictionary = undo_records[undo_token]
	if bool(record.get("consumed", false)) or not _inverse_still_safe(record):
		return CommandResult.fail(&"undo_unsafe", "The branch changed after this action, so undo is no longer safe.")
	var command_id := StringName(record.get("command_id", &""))
	var inverse_arguments: Dictionary = record.get("inverse_arguments", {})
	var result: CommandResult = _dispatch(command_id, inverse_arguments, actor_context)
	if result.ok:
		record["consumed"] = true
		undo_records[undo_token] = record
		result.reversible = false
		result.undo_token = ""
		command_undone.emit(undo_token, result)
	return result


func can_undo(undo_token: String) -> bool:
	if not undo_records.has(undo_token):
		return false
	var record: Dictionary = undo_records[undo_token]
	return not bool(record.get("consumed", false)) and _inverse_still_safe(record)


func write_save(save: SaveGame) -> void:
	save.set("command_router_schema_version", 1)
	save.set("processed_command_ids", processed_commands.duplicate(true))
	save.set("command_undo_records", undo_records.duplicate(true))
	save.set("command_daily_spend", daily_spend.duplicate(true))


func restore_from_save(save: SaveGame) -> void:
	var saved_processed: Variant = save.get("processed_command_ids")
	if saved_processed is Dictionary:
		processed_commands = saved_processed.duplicate(true)
	var saved_undo: Variant = save.get("command_undo_records")
	if saved_undo is Dictionary:
		undo_records = saved_undo.duplicate(true)
	var saved_spend: Variant = save.get("command_daily_spend")
	if saved_spend is Dictionary:
		daily_spend = saved_spend.duplicate(true)


func _spec(category: StringName, label: String, reversible: bool, cooldown_hours: int,
		permission_requirement: StringName) -> Dictionary:
	return {
		"category": category,
		"label": label,
		"estimated_cost": true,
		"reversible": reversible,
		"cooldown_hours": cooldown_hours,
		"permission_requirement": permission_requirement,
	}


func _validate_context(arguments: Dictionary, actor_context: Dictionary) -> CommandResult:
	var company_id: StringName = StringName(actor_context.get("company_id", arguments.get("company_id", &"player")))
	var company: CompanyState = CompanyManager.company(company_id)
	if company == null:
		return CommandResult.fail(&"unknown_company", "The acting company does not exist.")
	if arguments.has("building_id"):
		var rest: RestaurantState = RestaurantManager.by_building.get(int(arguments["building_id"]))
		if rest == null:
			return CommandResult.fail(&"unknown_branch", "That branch does not exist.")
		if rest.company_id != company_id:
			return CommandResult.fail(&"not_owner", "That branch belongs to another company.")
	return CommandResult.good(company)


func _validate_policy(command_id: StringName, arguments: Dictionary, actor_context: Dictionary,
		spec: Dictionary, estimated_cost: float) -> CommandResult:
	var policy: BranchPolicy = actor_context.get("policy")
	if policy == null:
		return CommandResult.good()
	var category: StringName = StringName(spec.get("category", &""))
	var authority: StringName = policy.authority_for(category)
	var actor_kind: StringName = StringName(actor_context.get("kind", &"player"))
	if actor_kind == &"manager":
		if authority == BranchPolicy.AUTHORITY_RECOMMEND:
			return CommandResult.fail(&"recommend_only", "Policy allows a recommendation, not execution.")
		if authority == BranchPolicy.AUTHORITY_APPROVAL and not bool(actor_context.get("approved", false)):
			return CommandResult.fail(&"approval_required", "This action needs player approval.")
	var company: CompanyState = CompanyManager.company(policy.company_id)
	if company != null and company.cash - estimated_cost < policy.cash_reserve:
		return CommandResult.fail(&"cash_reserve", "This would take cash below the policy reserve.")
	var budget: float = policy.budget_for(category)
	if budget > 0.0 and _spent_today(policy.company_id, category) + estimated_cost > budget:
		return CommandResult.fail(&"category_budget", "This would exceed today's %s budget." % String(category).replace("_", " "))
	if command_id == &"inventory.reorder":
		var supplier_id: StringName = StringName(arguments.get("supplier_id", &""))
		if supplier_id != &"" and not policy.allows_supplier(supplier_id):
			return CommandResult.fail(&"supplier_blocked", "That supplier is not on the branch allowlist.")
	if command_id == &"menu.set_entry":
		var price: float = float(arguments.get("price", 0.0))
		if price < policy.minimum_price or price > policy.maximum_price:
			return CommandResult.fail(&"price_guardrail", "The price is outside the approved range.")
		var quality: int = _quality_index(StringName(arguments.get("tier", &"med")))
		if quality < policy.minimum_quality_tier or quality > policy.maximum_quality_tier:
			return CommandResult.fail(&"quality_guardrail", "The quality tier is outside the approved range.")
	if command_id == &"staff.fire" and policy.is_staff_protected(int(arguments.get("staff_uid", -1))):
		return CommandResult.fail(&"protected_staff", "This employee is protected by policy.")
	if command_id == &"layout.apply_template" and not policy.allows_layout(
			StringName(arguments.get("template_id", &""))):
		return CommandResult.fail(&"layout_guardrail", "That layout is not an approved template.")
	return CommandResult.good()


func _preview_domain(command_id: StringName, arguments: Dictionary,
		actor_context: Dictionary) -> CommandResult:
	var company_id: StringName = StringName(actor_context.get("company_id", arguments.get("company_id", &"player")))
	var building_id: int = int(arguments.get("building_id", -1))
	match command_id:
		&"inventory.reorder":
			if float(arguments.get("quantity", 0.0)) <= 0.0:
				return CommandResult.fail(&"bad_quantity", "Choose a positive reorder quantity.")
			if RecipeManager.ingredient(StringName(arguments.get("ingredient_id", &""))) == null:
				return CommandResult.fail(&"unknown_ingredient", "That ingredient does not exist.")
		&"inventory.set_policy":
			if not arguments.has("ingredient_id"):
				return CommandResult.fail(&"unknown_ingredient", "Choose an ingredient.")
		&"furniture.repair":
			var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
			if rest == null or rest.interior_layout == null:
				return CommandResult.fail(&"no_layout", "That branch has no editable interior.")
			var ids: Array[int] = []
			ids.assign(arguments.get("instance_ids", []))
			if ids.is_empty():
				return CommandResult.fail(&"nothing_to_repair", "Choose at least one furniture item.")
		&"layout.apply_template":
			if RestaurantManager.interior.template_for(StringName(arguments.get("template_id", &""))) == null:
				return CommandResult.fail(&"unknown_template", "That layout template does not exist.")
		&"layout.apply_draft":
			if not arguments.get("draft") is InteriorLayoutState:
				return CommandResult.fail(&"invalid_layout", "A valid interior layout draft is required.")
		&"staff.hire":
			var candidate_id: int = int(arguments.get("candidate_uid", -1))
			var found: bool = false
			for candidate: JobCandidate in _staff.candidates(company_id):
				if candidate.uid == candidate_id:
					found = true
					break
			if not found:
				return CommandResult.fail(&"candidate_gone", "That candidate is no longer available.")
		&"staff.fire", &"staff.set_schedule", &"staff.train", &"staff.promote", &"staff.set_contract":
			if _staff.staff_member(company_id, int(arguments.get("staff_uid", -1))) == null:
				return CommandResult.fail(&"unknown_staff", "That employee does not exist.")
		&"staff.transfer":
			if int(arguments.get("to_building_id", -1)) == building_id:
				return CommandResult.fail(&"same_branch", "Choose a different destination branch.")
		&"restaurant.set_hours":
			if is_equal_approx(float(arguments.get("open_hour", 0.0)), float(arguments.get("close_hour", 0.0))):
				return CommandResult.fail(&"invalid_hours", "Opening and closing time must differ.")
		&"delivery.set_cap":
			if int(arguments.get("cap", -1)) < 0:
				return CommandResult.fail(&"invalid_cap", "Delivery capacity cannot be negative.")
		&"marketing.start_local", &"marketing.stop_local":
			if not arguments.get("campaign") is MarketingCampaign:
				return CommandResult.fail(&"invalid_campaign", "A configured campaign is required.")
	return CommandResult.good()


func _dispatch(command_id: StringName, arguments: Dictionary,
		actor_context: Dictionary) -> CommandResult:
	var company_id: StringName = StringName(actor_context.get("company_id", arguments.get("company_id", &"player")))
	var building_id: int = int(arguments.get("building_id", -1))
	match command_id:
		&"inventory.reorder":
			var supplier_id: StringName = StringName(arguments.get("supplier_id", &""))
			if supplier_id == &"":
				return SupplyManager.manual_restock_cmd(company_id, building_id,
					StringName(arguments.get("ingredient_id", &"")), float(arguments.get("quantity", 0.0)))
			var lines: Array[Dictionary] = [{
				"ingredient_id": StringName(arguments.get("ingredient_id", &"")),
				"qty": ceilf(float(arguments.get("quantity", 0.0))),
			}]
			return SupplyManager.place_purchase_order_cmd(
				company_id, supplier_id, &"restaurant", building_id, lines)
		&"inventory.set_policy":
			return SupplyManager.set_reorder_policy_cmd(company_id, building_id,
				StringName(arguments.get("ingredient_id", &"")), arguments.get("fields", {}))
		&"furniture.repair":
			var ids: Array[int] = []
			ids.assign(arguments.get("instance_ids", []))
			return RestaurantManager.repair_furniture_cmd(company_id, building_id, ids)
		&"furniture.set_repair_policy":
			return RestaurantManager.set_repair_policy_cmd(company_id, building_id,
				StringName(arguments.get("policy", &"manual")), float(arguments.get("threshold", 0.35)))
		&"layout.apply_template":
			return RestaurantManager.apply_template_cmd(company_id, building_id,
				StringName(arguments.get("template_id", &"")))
		&"layout.apply_draft":
			var layout_draft: InteriorLayoutState = arguments.get("draft")
			return RestaurantManager.edit_interior(building_id, layout_draft)
		&"layout.expand":
			return RestaurantManager.expand_interior_cmd(company_id, building_id)
		&"staff.hire":
			return _staff.hire_candidate_cmd(company_id, building_id,
				int(arguments.get("candidate_uid", -1)), arguments.get("offer", {}))
		&"staff.fire":
			return _staff.fire_staff_cmd(company_id, building_id, int(arguments.get("staff_uid", -1)))
		&"staff.transfer":
			return _staff.transfer_staff_cmd(company_id, building_id,
				int(arguments.get("to_building_id", -1)), int(arguments.get("staff_uid", -1)))
		&"staff.promote":
			return _staff.promote_staff_cmd(company_id, building_id,
				int(arguments.get("staff_uid", -1)), StringName(arguments.get("new_role_id", &"")),
				float(arguments.get("hourly_wage", 0.0)))
		&"staff.train":
			return _staff.enroll_training_cmd(company_id, building_id,
				int(arguments.get("staff_uid", -1)), StringName(arguments.get("program_id", &"")))
		&"staff.set_schedule":
			return _staff.set_schedule_cmd(company_id, building_id,
				int(arguments.get("staff_uid", -1)), float(arguments.get("start", 10.0)),
				float(arguments.get("hours", 8.0)), int(arguments.get("weekday", -1)))
		&"staff.bulk_schedule":
			var assignments: Array[Dictionary] = []
			assignments.assign(arguments.get("assignments", []))
			return _staff.bulk_schedule_cmd(company_id, building_id, assignments)
		&"staff.save_schedule_template":
			var template_assignments: Array[Dictionary] = []
			template_assignments.assign(arguments.get("assignments", []))
			_staff.save_schedule_template(company_id,
				String(arguments.get("template_id", "standard")), {
					"display_name": String(arguments.get("display_name", "Standard Week")),
					"version": int(arguments.get("version", 1)),
					"assignments": template_assignments,
				})
			return CommandResult.good()
		&"staff.apply_schedule_template":
			return _staff.apply_schedule_template_cmd(company_id, building_id,
				String(arguments.get("template_id", "standard")))
		&"staff.set_contract":
			return _staff.set_contract_cmd(company_id, building_id,
				int(arguments.get("staff_uid", -1)),
				StringName(arguments.get("contract_type", &"permanent")),
				float(arguments.get("hourly_wage", 0.0)),
				bool(arguments.get("overtime_allowed", false)),
				float(arguments.get("maximum_overtime_hours", 0.0)))
		&"restaurant.set_hours":
			return RestaurantManager.set_hours_cmd(company_id, building_id,
				float(arguments.get("open_hour", 10.0)), float(arguments.get("close_hour", 22.0)))
		&"restaurant.set_channels":
			return RestaurantManager.set_channels_cmd(company_id, building_id,
				bool(arguments.get("dine_in", true)), bool(arguments.get("delivery", true)))
		&"delivery.set_cap":
			return RestaurantManager.set_delivery_cap_cmd(company_id, building_id, int(arguments.get("cap", 0)))
		&"menu.set_entry":
			return RestaurantManager.set_menu_entry_cmd(company_id, building_id,
				StringName(arguments.get("dish_id", &"")), float(arguments.get("price", 1.0)),
				StringName(arguments.get("tier", &"med")), bool(arguments.get("enabled", true)))
		&"marketing.start_local":
			var campaign: MarketingCampaign = arguments.get("campaign")
			return MarketingManager.start_campaign(campaign)
		&"marketing.stop_local":
			var stopped_campaign: MarketingCampaign = arguments.get("campaign")
			MarketingManager.stop_campaign(stopped_campaign)
			return CommandResult.good(stopped_campaign)
		&"operations.emergency_close":
			return RestaurantManager.set_channels_cmd(company_id, building_id, false, false)
	return CommandResult.fail(&"unknown_command", "That command is not supported.")


func _estimate_cost(command_id: StringName, arguments: Dictionary,
		_actor_context: Dictionary) -> float:
	var building_id: int = int(arguments.get("building_id", -1))
	match command_id:
		&"inventory.reorder":
			return maxf(0.0, float(arguments.get("estimated_unit_cost", 10.0)) * ceilf(
				float(arguments.get("quantity", 0.0))))
		&"furniture.repair":
			var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
			if rest == null or rest.interior_layout == null:
				return 0.0
			var total: float = 0.0
			var ids: Array[int] = []
			ids.assign(arguments.get("instance_ids", []))
			for instance_id: int in ids:
				var item: PlacedFurnitureState = rest.interior_layout.find(instance_id)
				if item == null:
					continue
				var definition: FurnitureDef = RestaurantManager.interior.def_for(item.def_id)
				if definition != null:
					total += definition.price * 0.3 * (1.0 - item.durability / definition.durability_max) + 5.0
			return total
		&"layout.apply_draft":
			var draft_rest: RestaurantState = RestaurantManager.by_building.get(building_id)
			var layout_draft: InteriorLayoutState = arguments.get("draft")
			if draft_rest == null or layout_draft == null:
				return 0.0
			var draft_difference: Dictionary = RestaurantManager.interior.price_diff(draft_rest.interior_layout, layout_draft)
			return maxf(0.0, float(draft_difference.get("net", 0.0)))
		&"layout.apply_template":
			var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
			var template: InteriorTemplateDef = RestaurantManager.interior.template_for(
				StringName(arguments.get("template_id", &"")))
			if rest == null or template == null:
				return 0.0
			var draft: InteriorLayoutState = template.build_layout()
			var difference: Dictionary = RestaurantManager.interior.price_diff(rest.interior_layout, draft)
			return maxf(0.0, float(difference.get("net", 0.0)) + template.design_fee)
		&"staff.train":
			var program: TrainingProgramDef = _staff.training_programs.get(
				StringName(arguments.get("program_id", &"")))
			return program.cost if program != null else 0.0
		&"marketing.start_local":
			return maxf(0.0, float(arguments.get("exact_cost", 0.0)))
	return maxf(0.0, float(arguments.get("estimated_cost", 0.0)))


func _decorate(result: CommandResult, command_id: StringName, spec: Dictionary,
		arguments: Dictionary, actor_context: Dictionary, estimated_cost: float = 0.0) -> CommandResult:
	result.estimated_cost = estimated_cost
	result.explanation = _explanation(command_id, arguments, result)
	var policy: BranchPolicy = actor_context.get("policy")
	result.permission_category = policy.authority_for(StringName(spec.get("category", &""))) if policy != null 		else StringName(spec.get("permission_requirement", &"recommend"))
	result.reversible = bool(spec.get("reversible", false)) and result.ok
	result.actor_kind = StringName(actor_context.get("kind", &"player"))
	result.actor_id = str(actor_context.get("id", ""))
	result.metadata["command_id"] = command_id
	result.metadata["category"] = spec.get("category", &"")
	result.metadata["cooldown_hours"] = int(spec.get("cooldown_hours", 0))
	return result


func _explanation(command_id: StringName, arguments: Dictionary, result: CommandResult) -> String:
	if not result.ok:
		return result.message
	var label := str(describe(command_id).get("label", "Apply change"))
	var branch_id := int(arguments.get("building_id", -1))
	return "%s at branch %d after policy and budget checks." % [label, branch_id] if branch_id >= 0 		else "%s after policy and budget checks." % label


func _capture_inverse(command_id: StringName, arguments: Dictionary,
		actor_context: Dictionary) -> Dictionary:
	if not REVERSIBLE_COMMANDS.has(command_id):
		return {}
	var building_id: int = int(arguments.get("building_id", -1))
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null:
		return {}
	var inverse_arguments: Dictionary = {"building_id": building_id}
	match command_id:
		&"restaurant.set_hours":
			inverse_arguments.merge({"open_hour": rest.open_hour, "close_hour": rest.close_hour})
		&"restaurant.set_channels", &"operations.emergency_close":
			inverse_arguments.merge({"dine_in": rest.dine_in_enabled, "delivery": rest.delivery_enabled})
			command_id = &"restaurant.set_channels"
		&"delivery.set_cap":
			inverse_arguments["cap"] = rest.delivery_cap
		&"furniture.set_repair_policy":
			inverse_arguments.merge({"policy": rest.repair_policy, "threshold": rest.repair_threshold})
		&"staff.set_schedule":
			var member: StaffMember = _staff.staff_member(
				StringName(actor_context.get("company_id", rest.company_id)), int(arguments.get("staff_uid", -1)))
			if member == null:
				return {}
			inverse_arguments.merge({
				"staff_uid": member.uid,
				"start": member.shift_start,
				"hours": member.shift_hours,
				"weekday": int(arguments.get("weekday", -1)),
			})
		&"menu.set_entry":
			var entry: MenuEntry = rest.menu_entry_for(StringName(arguments.get("dish_id", &"")))
			if entry == null:
				return {}
			inverse_arguments.merge({
				"dish_id": entry.dish_id,
				"price": entry.price,
				"tier": entry.tier,
				"enabled": entry.enabled,
			})
	return {
		"command_id": command_id,
		"inverse_arguments": inverse_arguments,
		"company_id": rest.company_id,
		"created_window": int(GameClock.total_minutes() / 60),
	}


func _capture_post_state(command_id: StringName, arguments: Dictionary) -> Dictionary:
	var state := arguments.duplicate(true)
	state["command_id"] = command_id
	return state


func _inverse_still_safe(record: Dictionary) -> bool:
	var state: Dictionary = record.get("post_state", {})
	var command_id := StringName(state.get("command_id", record.get("command_id", &"")))
	var building_id: int = int(state.get("building_id", -1))
	var rest: RestaurantState = RestaurantManager.by_building.get(building_id)
	if rest == null:
		return false
	match command_id:
		&"restaurant.set_hours":
			return is_equal_approx(rest.open_hour, float(state.get("open_hour", rest.open_hour))) 				and is_equal_approx(rest.close_hour, float(state.get("close_hour", rest.close_hour)))
		&"restaurant.set_channels":
			return rest.dine_in_enabled == bool(state.get("dine_in", rest.dine_in_enabled)) 				and rest.delivery_enabled == bool(state.get("delivery", rest.delivery_enabled))
		&"operations.emergency_close":
			return not rest.dine_in_enabled and not rest.delivery_enabled
		&"delivery.set_cap":
			return rest.delivery_cap == int(state.get("cap", rest.delivery_cap))
		&"furniture.set_repair_policy":
			return rest.repair_policy == StringName(state.get("policy", rest.repair_policy))
		&"staff.set_schedule":
			var member: StaffMember = _staff.staff_member(rest.company_id, int(state.get("staff_uid", -1)))
			return member != null and is_equal_approx(member.shift_start, float(state.get("start", member.shift_start))) 				and is_equal_approx(member.shift_hours, float(state.get("hours", member.shift_hours)))
		&"menu.set_entry":
			var entry: MenuEntry = rest.menu_entry_for(StringName(state.get("dish_id", &"")))
			return entry != null and is_equal_approx(entry.price, float(state.get("price", entry.price))) 				and entry.tier == StringName(state.get("tier", entry.tier)) 				and entry.enabled == bool(state.get("enabled", entry.enabled))
	return false


func _quality_index(tier: StringName) -> int:
	match tier:
		&"low":
			return 0
		&"high":
			return 2
	return 1


func _spent_today(company_id: StringName, category: StringName) -> float:
	return float(daily_spend.get(_spend_key(company_id, category), 0.0))


func _record_spend(company_id: StringName, category: StringName, amount: float) -> void:
	var key := _spend_key(company_id, category)
	daily_spend[key] = float(daily_spend.get(key, 0.0)) + maxf(0.0, amount)


func _spend_key(company_id: StringName, category: StringName) -> String:
	return "%d:%s:%s" % [GameClock.day, company_id, category]


func _result_from_dictionary(values: Dictionary) -> CommandResult:
	var result := CommandResult.new()
	result.ok = bool(values.get("ok", false))
	result.code = StringName(values.get("code", &"ok"))
	result.message = str(values.get("message", ""))
	result.payload = values.get("payload")
	result.with_command_metadata(values)
	return result
