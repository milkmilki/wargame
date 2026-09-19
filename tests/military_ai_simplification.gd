extends SceneTree
## 军事 AI 简化门禁：每个指挥单位只含一支独立主战军，攻势规模有界，
## 友军沿既定道路移动时不使整份动态驻防计划失效。

var _failures: Array[String] = []


func _init() -> void:
	_test_single_heavy_battle_group()
	_test_generated_world_has_only_command_units()
	_test_campaign_bounds()
	_test_friendly_progress_signature()
	_test_stable_campaign_plan_reuse()
	for failure in _failures:
		push_error("MILITARY_AI_SIMPLIFICATION_FAIL: " + failure)
	print("MILITARY_AI_SIMPLIFICATION_%s checks=5" % [
		"OK" if _failures.is_empty() else "FAILED",
	])
	quit(0 if _failures.is_empty() else 1)


func _test_single_heavy_battle_group() -> void:
	var state := GameState.new()
	state.generate_grid_world(91001)
	var nation := state.nations[0]
	var group := nation.battle_groups[0]
	var members := state.battle_group_members(0, group.id)
	var heavy_count := 0
	var light_count := 0
	for army in members:
		if army.max_size >= GameState.INITIAL_HEAVY_ARMY_SIZE:
			heavy_count += 1
		else:
			light_count += 1
	var light := state.create_army(
		0,
		nation.capital_city_id,
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	var light_rejected := not state.assign_army_to_battle_group(
		light, group.id
	)
	light.max_size = 10000
	var nonstandard_rejected := not state.assign_army_to_battle_group(
		light, group.id
	)
	_check(
		BattleGroup.MAX_LIGHT_ARMIES == 0
			and BattleGroup.MAX_HEAVY_ARMIES == 1
			and members.size() == 1
			and heavy_count == 1
			and light_count == 0
			and light_rejected
			and nonstandard_rejected,
		"每个指挥单位必须且只能包含一支独立主战军，轻军不得加入"
	)


func _test_generated_world_has_only_command_units() -> void:
	var state := GameState.new()
	state.generate_grid_world(91004)
	var valid := true
	for nation in state.nations:
		var living_armies := 0
		for army in state.armies:
			if army.owner_nation != nation.id or army.size <= 0:
				continue
			living_armies += 1
			valid = (
				valid
				and army.is_main_battle_role()
				and army.battle_group_id >= 0
				and army.max_size == GameState.INITIAL_HEAVY_ARMY_SIZE
				and state.battle_group_members(
					nation.id, army.battle_group_id
				).size() == 1
			)
		valid = valid and living_armies == nation.battle_groups.size()
	_check(valid, "生成世界的每支主战军必须拥有独立指挥单位")


func _test_campaign_bounds() -> void:
	_check(
		Simulation.CAMPAIGN_MAX_PARALLEL_TARGETS == 2,
		"州战役必须限制为最多两个战术目标"
	)


func _test_friendly_progress_signature() -> void:
	var state := GameState.new()
	state.generate_grid_world(91002)
	state.uses_heightmap = true
	state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	var friendly: Army = null
	for army in state.armies:
		if army.owner_nation == 0:
			friendly = army
			break
	if friendly == null:
		_check(false, "驻防签名测试需要一支友军")
		return
	var neighbor := state.neighbors(friendly.location_city)[0]
	friendly.state = Army.State.MOVING
	friendly.on_edge = true
	friendly.move_from = friendly.location_city
	friendly.move_to = neighbor
	friendly.location_city = -1
	friendly.move_progress = 0.10
	var before_view := AiWorldView.build(state, 0)
	var before_plan := CityDefensePlan.prepare_evaluation(
		before_view,
		StrategicMapSnapshot.build(before_view),
		ThreatField.build(before_view)
	)
	friendly.move_progress = 0.20
	var after_view := AiWorldView.build(state, 0)
	var after_plan := CityDefensePlan.prepare_evaluation(
		after_view,
		StrategicMapSnapshot.build(after_view),
		ThreatField.build(after_view)
	)
	_check(
		before_plan.input_signature == after_plan.input_signature,
		"友军沿同一道路移动时不应使整份驻防动态计划缓存失效"
	)


func _test_stable_campaign_plan_reuse() -> void:
	var state := GameState.new()
	state.generate_grid_world(91003)
	var plan := AdministrativeCampaignPlan.new()
	plan.center_city_id = int(state.administrative_center_city_ids[0])
	plan.refresh_fingerprint(state)
	var reusable := plan.fingerprint_matches(state)
	state.ownership_revision += 1
	var invalidated := not plan.fingerprint_matches(state)
	_check(
		reusable and invalidated,
		"州战役计划应在版本不变时复用，领土变化后立即失效"
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
