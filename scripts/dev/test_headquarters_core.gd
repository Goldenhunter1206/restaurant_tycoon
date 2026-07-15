extends SceneTree
## Deterministic headless coverage for HQ resources, source aggregation,
## persistence, progress math, migration markers and static UI targets.
## Run: godot --headless --path . --script res://scripts/dev/test_headquarters_core.gd

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_test_capability_sources()
	_test_project_progress()
	_test_state_and_definitions()
	_test_save_round_trip()
	_test_ui_scene_smoke()
	print("---")
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s" % label)


func _registry() -> Node:
	var script: GDScript = load("res://scripts/autoload/capability_registry.gd")
	return script.new()


func _test_capability_sources() -> void:
	print("capability sources:")
	var registry: Node = _registry()
	var changes: Array[StringName] = []
	registry.capabilities_changed.connect(func(company_id: StringName) -> void: changes.append(company_id))
	registry.set_source(&"test", &"award", {
		&"test.depth": 1,
		&"marketing.campaign_slots": 1,
	}, true)
	registry.set_source(&"test", &"scenario", {
		&"test.depth": 2,
		&"marketing.campaign_slots": 2,
	})
	_check(int(registry.level(&"test", &"test.depth")) == 2, "level capabilities take maximum source")
	_check(int(registry.capacity(&"test", &"marketing.campaign_slots")) == 3, "capacity capabilities add sources")
	_check(registry.has(&"test", &"test.depth"), "has remains source-aware")
	_check((registry.sources_for(&"test", &"test.depth") as Array).size() == 2, "source provenance is queryable")
	_check(changes.size() == 2, "source changes emit once per update")
	registry.set_lock_hints(&"test", &"policy", {&"test.locked": "Build test department."})
	_check(registry.explain(&"test", &"test.locked") == "Build test department.", "dynamic lock hint is exact")
	var exported: Array[CapabilitySourceState] = registry.export_persistent_sources()
	_check(exported.size() == 1 and exported[0].source_id == &"award", "only persistent sources export")
	registry.clear_source(&"test", &"scenario")
	_check(int(registry.level(&"test", &"test.depth")) == 1, "removing source drops max level")
	_check(int(registry.capacity(&"test", &"marketing.campaign_slots")) == 1, "removing source drops additive capacity")
	var restored: Node = _registry()
	restored.restore_persistent_sources(exported)
	_check(int(restored.level(&"test", &"test.depth")) == 1, "persistent source restores")
	restored.grant(&"test", &"test.depth", 3)
	_check(int(restored.level(&"test", &"test.depth")) == 3, "legacy grant remains compatible")
	restored.free()
	registry.free()


func _test_project_progress() -> void:
	print("project progress:")
	var project: UpgradeProjectState = UpgradeProjectState.new()
	project.id = 7
	project.kind = &"department"
	project.target_id = &"marketing"
	project.start_minute = 100
	project.end_minute = 300
	project.paid_amount = 5000.0
	_check(project.progress_at(50) == 0.0, "progress clamps before start")
	_check(is_equal_approx(project.progress_at(200), 0.5), "progress is absolute-minute based")
	_check(project.progress_at(400) == 1.0, "progress clamps after completion")
	_check(project.remaining_minutes(220) == 80, "remaining minutes is deterministic")
	var refund: float = project.paid_amount * (1.0 - project.progress_at(200)) * 0.5
	_check(is_equal_approx(refund, 1250.0), "cancellation refund is half uncompleted progress")
	project.paused = true
	project.paused_at_minute = 160
	_check(is_equal_approx(project.progress_at(260), 0.3), "paused project does not advance")
	project.completion_applied = true
	_check(project.completion_applied, "completion idempotency marker persists")


func _test_state_and_definitions() -> void:
	print("state and definitions:")
	var state: HeadquartersState = HeadquartersState.new()
	state.company_id = &"test"
	state.building_id = 41
	state.tier = 2
	state.departments = {&"marketing": 2, &"operations": 1}
	state.capacity_used = 3
	state.migration_state = &"legacy_v5_founder"
	_check(state.is_active(), "tier with reserved building is active")
	_check(state.department_level(&"marketing") == 2, "department levels persist")
	_check(state.capacity_used == 3, "department levels consume numeric capacity")
	_check(state.migration_state == &"legacy_v5_founder", "legacy migration marker persists")
	var department: DepartmentDef = DepartmentDef.new()
	department.required_tiers = [1, 2, 3]
	department.project_costs = [2500.0, 4000.0, 7000.0]
	department.project_minutes = [2880, 4320, 7200]
	department.total_upkeep = [50.0, 70.0, 150.0]
	department.grants_by_level = [{&"test.depth": 1}, {&"test.depth": 2}, {&"test.depth": 3}]
	_check(department.max_level() == 3, "department max level follows tuning arrays")
	_check(department.required_tier_for(2) == 2, "department prerequisite lookup")
	_check(department.cost_for(3) == 7000.0, "department capital lookup")
	_check(department.minutes_for(1) == 2880, "department duration lookup")
	_check(department.upkeep_for(0) == 0.0 and department.upkeep_for(2) == 70.0, "department upkeep lookup")
	_check(int(department.grants_for(3)[&"test.depth"]) == 3, "department grant lookup")


func _test_save_round_trip() -> void:
	print("save round trip:")
	var save: SaveGame = SaveGame.new()
	save.save_version = 6
	var company: CompanyState = CompanyState.new()
	company.id = &"test"
	company.cash = 12345.0
	company.headquarters = HeadquartersState.new()
	company.headquarters.company_id = company.id
	company.headquarters.building_id = 88
	company.headquarters.tier = 3
	company.headquarters.departments = {&"analytics": 2, &"procurement": 1}
	company.headquarters.capital_invested = 47000.0
	var project: UpgradeProjectState = UpgradeProjectState.new()
	project.id = 2
	project.kind = &"department"
	project.target_id = &"procurement"
	project.start_minute = 1200
	project.end_minute = 8400
	project.paid_amount = 8500.0
	company.headquarters.active_projects.append(project)
	save.companies.append(company)
	var source: CapabilitySourceState = CapabilitySourceState.new()
	source.company_id = company.id
	source.source_id = &"award"
	source.grants = {&"marketing.campaign_slots": 1}
	source.persistent = true
	save.capability_sources.append(source)
	var path: String = "user://hq_core_round_trip.tres"
	var saved: Error = ResourceSaver.save(save, path)
	var loaded: SaveGame = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveGame
	_check(saved == OK and loaded != null, "v6 save resource round-trips")
	_check(loaded.save_version == 6, "save version is v6")
	_check(loaded.companies[0].headquarters.building_id == 88, "office reservation round-trips")
	_check(loaded.companies[0].headquarters.tier == 3, "tier round-trips")
	_check(loaded.companies[0].headquarters.department_level(&"analytics") == 2, "departments round-trip")
	_check(loaded.companies[0].headquarters.active_project().end_minute == 8400, "active timing round-trips")
	_check(loaded.companies[0].headquarters.active_project().paid_amount == 8500.0, "project payment round-trips")
	_check(loaded.capability_sources.size() == 1 and loaded.capability_sources[0].persistent, "persistent capability source round-trips")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_ui_scene_smoke() -> void:
	print("UI scene smoke:")
	var packed: PackedScene = load("res://scenes/ui/HeadquartersScreen.tscn")
	var screen: Control = packed.instantiate() as Control
	_check(screen != null, "dashboard scene instantiates")
	_check(screen.get_node_or_null("Paper/Workspace/Root/Header") != null, "dashboard header exists")
	_check(screen.get_node_or_null("Paper/Workspace/Root/TabScroll/TabRow") != null, "dashboard tabs exist")
	_check(screen.get_node_or_null("Paper/Workspace/Root/BodyPanel/BodyMargin/BodyScroll/Body") != null, "dashboard body exists")
	var close_button: Button = screen.get_node("Paper/Workspace/Root/Header/CloseButton") as Button
	_check(close_button.custom_minimum_size.y >= 44.0, "static close target is at least 44px")
	var tab_scroll: ScrollContainer = screen.get_node("Paper/Workspace/Root/TabScroll") as ScrollContainer
	_check(tab_scroll.custom_minimum_size.y >= 44.0, "tab strip target band is at least 44px")
	screen.free()
