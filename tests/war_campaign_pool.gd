extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(94140)
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(3, 1, GameState.DiplomaticRelation.WAR)
	var center_one := _owned_center(state, 1)
	var center_two := _owned_center(state, 2)
	var valid := center_one >= 0 and center_two >= 0
	var war_one := state.set_war_objective(0, 1, center_one, "战争池门禁一")
	var war_two := state.set_war_objective(0, 2, center_two, "战争池门禁二")
	state.set_war_objective(3, 1, center_one, "盟军加入", war_one)
	valid = valid and war_one >= 0 and war_two > war_one
	valid = valid and int(state.war_objective(0, 1).get("war_id", -1)) == war_one
	valid = valid and int(state.war_objective(3, 1).get("war_id", -1)) == war_one
	valid = valid and state.campaign_enemy_ids(0, war_one) == [1]
	valid = valid and state.campaign_enemy_ids(0, war_two) == [2]
	var plan := AdministrativeCampaignPlan.new()
	plan.center_city_id = center_one
	plan.mode = AdministrativeCampaignPlan.Mode.OFFENSE
	plan.war_id = war_one
	state.nations[0].administrative_campaign_plans[center_one] = plan
	var army := Army.new()
	army.id = 94140
	army.owner_nation = 0
	army.size = 15000
	army.max_size = 15000
	army.location_city = state.nations[0].capital_city_id
	army.campaign_war_id = war_one
	state.armies.append(army)
	plan.army_assignments[army.id] = center_one
	valid = valid and state.campaign_assignment_war(army.id) == war_one
	valid = valid and state.offensive_campaigns_for_war(0, war_one) == [plan]
	var combat_army_data: Dictionary = CombatLog._side_snapshot(
		[army] as Array[Army]
	)[0]
	var replay_army: Army = CombatLog._army_from_snapshot(combat_army_data)
	valid = valid and replay_army.campaign_war_id == war_one
	var snapshot := NativeSnapshotBuilder.build(state)
	var armies: Dictionary = snapshot["armies"]
	var nations: Dictionary = snapshot["nations"]
	valid = valid and (armies["campaign_war_id"] as PackedInt32Array)[-1] == war_one
	valid = valid and (nations["campaign_war_ids"] as PackedInt32Array)[-1] == war_one
	var simulation := Simulation.new()
	simulation.setup(state)
	simulation._set_coalition_war_objective(
		[0, 3] as Array[int],
		[1, 2] as Array[int],
		0,
		center_one,
		"合并集团战争",
	)
	var merged_war := int(state.war_objective(0, 1).get("war_id", -1))
	valid = valid and merged_war == mini(war_one, war_two)
	valid = valid and int(state.war_objective(0, 2).get("war_id", -1)) == merged_war
	valid = valid and int(state.war_objective(3, 1).get("war_id", -1)) == merged_war
	valid = valid and army.campaign_war_id == merged_war
	valid = valid and plan.war_id == merged_war
	for pair in [Vector2i(0, 1), Vector2i(0, 2)]:
		state.set_diplomatic_relation(
			pair.x, pair.y, GameState.DiplomaticRelation.NEUTRAL
		)
	valid = valid and army.campaign_war_id == -1
	valid = valid and state.offensive_campaigns_for_war(0, merged_war).is_empty()
	valid = valid and state.is_enemy(3, 1)
	state.set_diplomatic_relation(3, 1, GameState.DiplomaticRelation.NEUTRAL)
	simulation.free()
	var continuous_valid := _test_continuous_state_campaign()
	var capital_valid := _test_capital_emergency_transfer()
	var two_front_valid := _test_two_front_war_allocation()
	var stable_assignment_valid := _test_campaign_assignment_survives_order_failure()
	var atomic_peace_valid := _test_atomic_peace_releases_war_pool()
	valid = (
		continuous_valid
		and capital_valid
		and two_front_valid
		and stable_assignment_valid
		and atomic_peace_valid
		and valid
	)
	if valid:
		print("WAR_CAMPAIGN_POOL_OK wars=%d/%d" % [war_one, war_two])
		quit(0)
		return
	push_error(
		(
			"WAR_CAMPAIGN_POOL_FAILED wars=%d/%d continuous=%s capital=%s "
			+ "two_front=%s stable_assignment=%s atomic_peace=%s"
		)
		% [
			war_one, war_two, continuous_valid, capital_valid,
			two_front_valid, stable_assignment_valid, atomic_peace_valid,
		]
	)
	quit(1)


func _test_campaign_assignment_survives_order_failure() -> bool:
	var state := GameState.new()
	state.generate_grid_world(94145)
	var attacker_id := 0
	var defender_id := 1
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	state.set_diplomatic_relation(
		attacker_id, defender_id, GameState.DiplomaticRelation.WAR
	)
	var center_id := _owned_center(state, defender_id)
	if center_id < 0:
		return false
	var war_id := state.set_war_objective(
		attacker_id, defender_id, center_id, "稳定州绑定门禁"
	)
	state.armies.clear()
	var plan := AdministrativeCampaignPlan.new()
	plan.center_city_id = center_id
	plan.mode = AdministrativeCampaignPlan.Mode.OFFENSE
	plan.war_id = war_id
	state.nations[attacker_id].administrative_campaign_plans[center_id] = plan
	var army := Army.new()
	army.id = 941450
	army.owner_nation = attacker_id
	army.size = 4500
	army.max_size = 15000
	army.location_city = state.nations[attacker_id].capital_city_id
	army.move_from = army.location_city
	army.state = Army.State.IDLE
	army.ai_target_city = -1
	army.campaign_war_id = war_id
	state.armies.append(army)
	plan.army_assignments[army.id] = center_id
	var simulation := Simulation.new()
	simulation.setup(state)
	var failed_order := ActionCandidate.make(
		ActionCandidate.Kind.REINFORCE,
		2000.0,
		"模拟异步提交失败",
		center_id,
	)
	var intent := AiCommandIntent.make(
		army, failed_order, 0, [] as Array[int], true
	)
	var committed_before := state.campaign_committed_manpower(
		attacker_id, center_id
	)
	simulation._commit_ordinary_ai_intent(intent)
	var committed_after := state.campaign_committed_manpower(
		attacker_id, center_id
	)
	var allocation := simulation.war_offensive_allocation(
		attacker_id, war_id
	)
	var fronts: Array = allocation["fronts"]
	var valid := (
		committed_before == army.size
		and committed_after == army.size
		and plan.army_assignments.has(army.id)
		and state.campaign_assignment_center(army.id) == center_id
		and fronts.size() == 1
		and int((fronts[0] as Dictionary)["committed_C"]) == army.size
		and int(allocation["war_pool_total"]) == army.size
		and int(allocation["war_pool_effective"]) == army.size
		and int(allocation["duplicate_assignments"]) == 0
	)
	simulation.free()
	return valid


func _test_atomic_peace_releases_war_pool() -> bool:
	var state := GameState.new()
	state.generate_grid_world(94144)
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var center_id := _owned_center(state, 1)
	if center_id < 0:
		return false
	var war_id := state.set_war_objective(0, 1, center_id, "原子议和战争池门禁")
	var plan := AdministrativeCampaignPlan.new()
	plan.center_city_id = center_id
	plan.mode = AdministrativeCampaignPlan.Mode.OFFENSE
	plan.war_id = war_id
	state.nations[0].administrative_campaign_plans[center_id] = plan
	var army := Army.new()
	army.id = 941440
	army.owner_nation = 0
	army.size = 15000
	army.max_size = 15000
	army.location_city = state.nations[0].capital_city_id
	army.move_from = army.location_city
	army.campaign_war_id = war_id
	state.armies.append(army)
	plan.army_assignments[army.id] = center_id
	var result := state.apply_territory_transaction(
		[] as Array[Dictionary],
		{},
		state.ownership_revision,
		null,
		[{
			"nation_a": 0,
			"nation_b": 1,
			"relation": GameState.DiplomaticRelation.NEUTRAL,
			"truce_days": GameState.DEFAULT_TRUCE_DAYS,
		}] as Array[Dictionary],
		state.diplomacy_revision,
	)
	return (
		bool(result.get("ok", false))
		and bool(result.get("diplomacy_changed", false))
		and not state.is_enemy(0, 1)
		and state.war_id_between(0, 1) == -1
		and army.campaign_war_id == -1
		and state.offensive_campaigns_for_war(0, war_id).is_empty()
	)


func _owned_center(state: GameState, owner_id: int) -> int:
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		if state.cities[center_id].owner_nation == owner_id:
			return center_id
	return -1


func _test_continuous_state_campaign() -> bool:
	var state := GameState.new()
	state.generate_grid_world(94141)
	var chain := _administrative_center_chain(state)
	if chain.size() < 3:
		return false
	var attacker_id := 0
	var defender_id := 1
	var neutral_id := 2
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	for city in state.cities:
		if not city.is_dock:
			city.owner_nation = neutral_id
			state.recognized_city_owners[city.id] = neutral_id
	for member_id in state.administrative_members(chain[0]):
		state.cities[member_id].owner_nation = attacker_id
		state.recognized_city_owners[member_id] = attacker_id
	for center_id in [chain[1], chain[2]]:
		for member_id in state.administrative_members(center_id):
			state.cities[member_id].owner_nation = defender_id
			state.recognized_city_owners[member_id] = defender_id
	state.nations[attacker_id].capital_city_id = chain[0]
	state.nations[defender_id].capital_city_id = chain[2]
	state.armies.clear()
	state.battles.clear()
	state.set_diplomatic_relation(
		attacker_id, defender_id, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.set_war_objective(
		attacker_id, defender_id, chain[1], "连续州战役门禁"
	)
	var army := Army.new()
	army.id = 94141
	army.owner_nation = attacker_id
	army.size = 15000
	army.max_size = 15000
	army.location_city = chain[0]
	army.move_from = chain[0]
	army.state = Army.State.IDLE
	state.armies.append(army)
	state.ownership_revision += 1
	state.refresh_derived()
	var simulation := Simulation.new()
	simulation.setup(state)
	simulation._manage_campaign_offensive(
		attacker_id, null, null, {"wars": [defender_id]}
	)
	var first_plans := state.offensive_campaigns_for_war(attacker_id, war_id)
	var first_plan: AdministrativeCampaignPlan = (
		first_plans[0] if not first_plans.is_empty() else null
	)
	var valid := first_plan != null and first_plan.center_city_id == chain[1]
	state.cities[chain[1]].owner_nation = attacker_id
	state.ownership_revision += 1
	simulation._manage_campaign_offensive(
		attacker_id, null, null, {"wars": [defender_id]}
	)
	valid = valid and first_plan.center_city_id == chain[1]
	for member_id in state.administrative_members(chain[1]):
		state.cities[member_id].owner_nation = attacker_id
	state.ownership_revision += 1
	simulation._manage_campaign_offensive(
		attacker_id, null, null, {"wars": [defender_id]}
	)
	var second_plans := state.offensive_campaigns_for_war(attacker_id, war_id)
	var second_plan: AdministrativeCampaignPlan = (
		second_plans[0] if not second_plans.is_empty() else null
	)
	valid = (
		valid
		and second_plan != null
		and second_plan.center_city_id == chain[2]
		and army.campaign_war_id == war_id
	)
	simulation.free()
	return valid


func _test_two_front_war_allocation() -> bool:
	var state := GameState.new()
	state.generate_grid_world(94144)
	var chain := _administrative_center_chain(state)
	if chain.size() < 3:
		return false
	var attacker_id := 0
	var defender_id := 1
	var neutral_id := 2
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	for city in state.cities:
		if not city.is_dock:
			city.owner_nation = neutral_id
			state.recognized_city_owners[city.id] = neutral_id
	for member_id in state.administrative_members(chain[1]):
		state.cities[member_id].owner_nation = attacker_id
		state.recognized_city_owners[member_id] = attacker_id
	for center_id in [chain[0], chain[2]]:
		for member_id in state.administrative_members(center_id):
			state.cities[member_id].owner_nation = defender_id
			state.recognized_city_owners[member_id] = defender_id
	state.nations[attacker_id].capital_city_id = chain[1]
	state.nations[defender_id].capital_city_id = chain[2]
	state.armies.clear()
	state.battles.clear()
	state.set_diplomatic_relation(
		attacker_id, defender_id, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.set_war_objective(
		attacker_id, defender_id, chain[0], "双州战线门禁"
	)
	for index in range(5):
		var army := Army.new()
		army.id = 941440 + index
		army.owner_nation = attacker_id
		army.size = 15000
		army.max_size = 15000
		army.location_city = chain[1]
		army.move_from = chain[1]
		army.state = Army.State.IDLE
		state.armies.append(army)
	state.ownership_revision += 1
	state.refresh_derived()
	var simulation := Simulation.new()
	simulation.setup(state)
	var context := {"wars": [defender_id]}
	simulation._manage_campaign_offensive(attacker_id, null, null, context)
	var first_cycle := state.offensive_campaigns_for_war(attacker_id, war_id)
	var assigned_first_cycle := 0
	for plan in first_cycle:
		assigned_first_cycle += plan.army_assignments.size()
	var valid := first_cycle.size() == 1 and assigned_first_cycle == 3
	var sixth_army := Army.new()
	sixth_army.id = 941445
	sixth_army.owner_nation = attacker_id
	sixth_army.size = 15000
	sixth_army.max_size = 15000
	sixth_army.location_city = chain[1]
	sixth_army.move_from = chain[1]
	sixth_army.state = Army.State.IDLE
	state.armies.append(sixth_army)
	simulation._manage_campaign_offensive(attacker_id, null, null, context)
	var second_cycle := state.offensive_campaigns_for_war(attacker_id, war_id)
	var assigned_ids := {}
	var assigned_second_cycle := 0
	for plan in second_cycle:
		assigned_second_cycle += plan.army_assignments.size()
		for army_id_value in plan.army_assignments:
			assigned_ids[int(army_id_value)] = true
	valid = (
		valid
		and second_cycle.size() == 2
		and assigned_second_cycle == 6
		and assigned_ids.size() == 6
	)
	for army in state.armies:
		if army.owner_nation == attacker_id:
			valid = valid and army.campaign_war_id == war_id
	sixth_army.state = Army.State.RECOVERING
	simulation._manage_campaign_offensive(attacker_id, null, null, context)
	valid = valid and state.offensive_campaigns_for_war(
		attacker_id, war_id
	).size() == 2
	var cooling_plan := state.offensive_campaigns_for_war(
		attacker_id, war_id
	)[0]
	cooling_plan.had_forces = true
	for army in state.armies:
		if cooling_plan.army_assignments.has(army.id):
			army.size = 0
	var replacement := Army.new()
	replacement.id = 941446
	replacement.owner_nation = attacker_id
	replacement.size = 15000
	replacement.max_size = 15000
	replacement.location_city = chain[1]
	replacement.move_from = chain[1]
	replacement.state = Army.State.IDLE
	state.armies.append(replacement)
	simulation._manage_campaign_offensive(attacker_id, null, null, context)
	valid = (
		valid
		and cooling_plan.failed_until_day == state.day + 60
		and not cooling_plan.army_assignments.has(replacement.id)
	)
	var extra_center := -1
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		if not state.nations[attacker_id].administrative_campaign_plans.has(center_id):
			extra_center = center_id
			break
	if extra_center >= 0:
		var extra_plan := AdministrativeCampaignPlan.new()
		extra_plan.center_city_id = extra_center
		extra_plan.mode = AdministrativeCampaignPlan.Mode.OFFENSE
		extra_plan.war_id = war_id
		state.nations[attacker_id].administrative_campaign_plans[extra_center] = extra_plan
		simulation._sanitize_offensive_campaigns(attacker_id)
		valid = valid and state.offensive_campaigns_for_war(
			attacker_id, war_id
		).size() == 2
	simulation.free()
	return valid


func _administrative_center_chain(state: GameState) -> Array[int]:
	var adjacency := {}
	for center_value in state.administrative_center_city_ids:
		adjacency[int(center_value)] = {}
	for pair in state.territorial_border_pairs():
		var center_a := state.administrative_center_of(pair.x)
		var center_b := state.administrative_center_of(pair.y)
		if center_a < 0 or center_b < 0 or center_a == center_b:
			continue
		(adjacency[center_a] as Dictionary)[center_b] = true
		(adjacency[center_b] as Dictionary)[center_a] = true
	var centers: Array[int] = []
	for center_value in adjacency:
		centers.append(int(center_value))
	EquivariantOrder.sort_city_ids(centers, state, 0)
	for middle in centers:
		var neighbors: Array[int] = []
		for neighbor_value in (adjacency[middle] as Dictionary):
			neighbors.append(int(neighbor_value))
		EquivariantOrder.sort_city_ids(neighbors, state, 0, middle)
		if neighbors.size() >= 2:
			return [neighbors[0], middle, neighbors[1]] as Array[int]
	return [] as Array[int]


func _test_capital_emergency_transfer() -> bool:
	var state := GameState.new()
	state.generate_grid_world(94142)
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	var defender_id := 0
	var first_enemy := 1
	var second_enemy := 2
	var capital_center := state.administrative_center_of(
		state.nations[defender_id].capital_city_id
	)
	var first_target := _owned_center(state, first_enemy)
	state.set_diplomatic_relation(
		defender_id, first_enemy, GameState.DiplomaticRelation.WAR
	)
	var first_war := state.set_war_objective(
		defender_id, first_enemy, first_target, "首都调兵原战争"
	)
	state.set_diplomatic_relation(
		second_enemy, defender_id, GameState.DiplomaticRelation.WAR
	)
	var defense_war := state.set_war_objective(
		second_enemy, defender_id, capital_center, "首都调兵防御战争"
	)
	state.armies.clear()
	state.battles.clear()
	var reserve := Army.new()
	reserve.id = 94142
	reserve.owner_nation = defender_id
	reserve.size = 15000
	reserve.max_size = 15000
	reserve.location_city = capital_center
	reserve.move_from = capital_center
	reserve.campaign_war_id = first_war
	state.armies.append(reserve)
	var offensive := AdministrativeCampaignPlan.new()
	offensive.center_city_id = first_target
	offensive.mode = AdministrativeCampaignPlan.Mode.OFFENSE
	offensive.war_id = first_war
	offensive.army_assignments[reserve.id] = first_target
	state.nations[defender_id].administrative_campaign_plans[first_target] = offensive
	var invader := Army.new()
	invader.id = 94143
	invader.owner_nation = second_enemy
	invader.size = 15000
	invader.max_size = 15000
	invader.location_city = capital_center
	invader.move_from = capital_center
	state.armies.append(invader)
	var simulation := Simulation.new()
	simulation.setup(state)
	simulation._manage_campaign_offensive(
		defender_id,
		null,
		null,
		{"wars": [first_enemy, second_enemy]},
	)
	var defense_plan := state.campaign_plan(defender_id, capital_center)
	var valid := (
		defense_plan != null
		and defense_plan.mode == AdministrativeCampaignPlan.Mode.DEFENSE
		and defense_plan.war_id == defense_war
		and reserve.campaign_war_id == defense_war
		and reserve.defensive_deployment_until_day >= state.day + 60
		and not offensive.army_assignments.has(reserve.id)
	)
	simulation.free()
	return valid
