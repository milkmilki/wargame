extends SceneTree
## 军事 AI 简化门禁：每个指挥单位只含一支独立主战军，攻势规模有界。

var _failures: Array[String] = []


func _init() -> void:
	_test_single_standard_battle_group()
	_test_generated_world_has_only_command_units()
	_test_campaign_bounds()
	_test_stable_campaign_plan_reuse()
	_test_defender_counteroffensive_transition()
	for failure in _failures:
		push_error("MILITARY_AI_SIMPLIFICATION_FAIL: " + failure)
	print("MILITARY_AI_SIMPLIFICATION_%s checks=5" % [
		"OK" if _failures.is_empty() else "FAILED",
	])
	quit(0 if _failures.is_empty() else 1)


func _test_single_standard_battle_group() -> void:
	var state := GameState.new()
	state.generate_grid_world(91001)
	var nation := state.nations[0]
	var group := nation.battle_groups[0]
	var members := state.battle_group_members(0, group.id)
	var standard_count := 0
	var nonstandard_count := 0
	for army in members:
		if army.max_size == GameState.INITIAL_HEAVY_ARMY_SIZE:
			standard_count += 1
		else:
			nonstandard_count += 1
	var extra_main := state.create_army(
		0,
		nation.capital_city_id,
		GameState.INITIAL_HEAVY_ARMY_SIZE,
		GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	var occupied_group_rejected := not state.assign_army_to_battle_group(
		extra_main, group.id
	)
	var nonstandard_rejected := state.create_army(
		0,
		nation.capital_city_id,
		5000,
		5000
	) == null
	state.armies.erase(extra_main)
	var understrength_main := state.create_army(
		0,
		nation.capital_city_id,
		5000,
		GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	_check(
		BattleGroup.MAX_ARMIES == 1
			and members.size() == 1
			and standard_count == 1
			and nonstandard_count == 0
			and occupied_group_rejected
			and nonstandard_rejected
			and understrength_main != null
			and understrength_main.max_size == GameState.INITIAL_HEAVY_ARMY_SIZE,
		"每个指挥单位只能包含一支15000编制主战军，非标准编制必须拒绝"
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


func _test_defender_counteroffensive_transition() -> void:
	var state := GameState.new()
	state.generate_grid_world(91005)
	state.armies.clear()
	state.battles.clear()
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	var attacker_id := 0
	var defender_id := 1
	var target_center := state.nations[defender_id].capital_city_id
	target_center = state.administrative_center_of(target_center)
	state.set_diplomatic_relation(
		attacker_id, defender_id, GameState.DiplomaticRelation.WAR
	)
	state.set_war_objective(
		attacker_id, defender_id, target_center, "防守转换测试"
	)
	var invader := state.create_army(
		attacker_id,
		state.nations[attacker_id].capital_city_id,
		GameState.INITIAL_HEAVY_ARMY_SIZE,
		GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	invader.location_city = target_center
	invader.move_from = target_center
	var defender_army := state.create_army(
		defender_id,
		state.nations[defender_id].capital_city_id,
		GameState.INITIAL_HEAVY_ARMY_SIZE,
		GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	var defender_reserve := state.create_army(
		defender_id,
		state.nations[defender_id].capital_city_id,
		GameState.INITIAL_HEAVY_ARMY_SIZE,
		GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	var stale_plan := AdministrativeCampaignPlan.new()
	stale_plan.center_city_id = state.administrative_center_of(
		state.nations[attacker_id].capital_city_id
	)
	stale_plan.army_assignments[defender_army.id] = stale_plan.center_city_id
	state.nations[defender_id].administrative_campaign_plans[
		stale_plan.center_city_id
	] = stale_plan
	state.nations[defender_id].campaign_objective_center_city = (
		stale_plan.center_city_id
	)
	defender_army.path = [stale_plan.center_city_id] as Array[int]
	defender_army.ai_target_city = stale_plan.center_city_id
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_campaign_offensive(defender_id)
	var defense_campaign := state.campaign_plan(defender_id, target_center)
	var stale_plan_suspended := (
		state.campaign_plan(defender_id, stale_plan.center_city_id) == null
		and defense_campaign != null
		and defense_campaign.mode == AdministrativeCampaignPlan.Mode.DEFENSE
		and defense_campaign.phase == AdministrativeCampaignPlan.Phase.SORTIE
		and defense_campaign.army_assignments.has(defender_army.id)
		and defense_campaign.army_assignments.has(defender_reserve.id)
	)
	invader.location_city = state.nations[attacker_id].capital_city_id
	invader.move_from = invader.location_city
	sim._manage_campaign_offensive(defender_id)
	var counteroffensive_created := false
	for center_value in state.nations[
		defender_id
	].administrative_campaign_plans:
		var campaign := state.campaign_plan(defender_id, int(center_value))
		if (
			campaign != null
			and campaign.mode == AdministrativeCampaignPlan.Mode.OFFENSE
		):
			counteroffensive_created = true
			break
	_check(
		stale_plan_suspended and counteroffensive_created,
		"目标州内仍有敌军时防守方不得反攻；敌军清空后才可转攻敌州"
	)
	sim.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
