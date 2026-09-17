extends SceneTree
## 六指挥单位与兵力制攻势门槛的集中回归。

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := GameState.new()
	state.generate_world(86420, 4, 48)
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	var nation_id := 0
	var nation := state.nations[nation_id]
	while nation.battle_groups.size() < BattleGroup.MAX_COMMAND_UNITS:
		var group := state.create_battle_group(nation_id)
		_check(group != null, "six_command_slots_available")
		if group == null:
			break
	for group in nation.battle_groups:
		if state.battle_group_members(nation_id, group.id).is_empty():
			var command_army := state._spawn_conjured_army(
				nation_id,
				nation.capital_city_id,
				GameState.INITIAL_HEAVY_ARMY_SIZE,
				Army.StrategicRole.MAIN
			)
			_check(
				state.assign_army_to_battle_group(command_army, group.id),
				"command_slot_has_aggregate_army"
			)
	_check(
		nation.battle_groups.size() == 6
		and state.create_battle_group(nation_id) == null,
		"seventh_command_rejected"
	)

	var target_city := _first_enemy_border_city(state, nation_id)
	if target_city >= 0:
		state.set_diplomatic_relation(
			nation_id,
			state.cities[target_city].owner_nation,
			GameState.DiplomaticRelation.WAR
		)
	_check(target_city >= 0, "enemy_target_exists")
	if target_city >= 0:
		var demand := simulation._campaign_target_group_demand(
			nation_id, target_city
		)
		_check(
			not demand.has("command_units")
			and not demand.has("groups")
			and not demand.has("is_decisive"),
			"target_demand_contains_only_force_thresholds"
		)
		var expected_staged := int(ceil(
			float(demand.get("required_manpower", 0))
				* Simulation.CAMPAIGN_TARGET_COMMIT_RATIO
				* Simulation.CAMPAIGN_STAGED_TROOP_RATIO
		))
		var plan := CampaignAllocationPlan.new()
		plan.assigned_target_ids.append(target_city)
		plan.target_demands[target_city] = demand
		nation.campaign_preparation_plan = plan
		_check(
			simulation._campaign_minimum_staged_troops(
				nation_id, target_city
			) == maxi(expected_staged, 1),
			"launch_requires_real_staged_manpower"
		)

	var main_army := _first_main_army(state, nation_id)
	_check(main_army != null, "main_command_army_exists")
	if main_army != null:
		nation.manpower_pool = maxi(nation.manpower_pool, 100000)
		nation.treasury_gold = maxi(nation.treasury_gold, 100000)
		var ordered_groups: Array[BattleGroup] = nation.battle_groups.duplicate()
		ordered_groups.sort_custom(func(a: BattleGroup, b: BattleGroup) -> bool:
			return a.id < b.id
		)
		var recruitment := simulation._next_battle_group_recruitment(nation_id)
		_check(
			int(recruitment.get("expand_army_id", -1)) >= 0
			and int(recruitment.get("group_id", -1)) == ordered_groups[0].id
			and not bool(recruitment.get("create_group", false)),
			"seventh_legion_cycles_to_command_one"
		)
		var expanded_army := _army_by_id(
			state, int(recruitment.get("expand_army_id", -1))
		)
		_check(expanded_army != null, "expand_target_exists")
		if expanded_army != null:
			var army_count_before := state.armies.size()
			var size_before := expanded_army.size
			var capacity_before := expanded_army.max_size
			var manpower_before := nation.manpower_pool
			var gold_before := nation.treasury_gold
			var expansion_cost := GameState.formation_creation_gold_cost(
				GameState.INITIAL_HEAVY_ARMY_SIZE
			)
			var expanded := simulation._try_create_force_recruitment(
				nation_id,
				nation,
				recruitment,
				GameState.INITIAL_HEAVY_ARMY_SIZE,
				false,
				false
			)
			_check(
				expanded
				and state.armies.size() == army_count_before
				and expanded_army.size
					== size_before + GameState.INITIAL_HEAVY_ARMY_SIZE
				and expanded_army.max_size
					== capacity_before + GameState.INITIAL_HEAVY_ARMY_SIZE
				and nation.manpower_pool
					== manpower_before - GameState.INITIAL_HEAVY_ARMY_SIZE
				and nation.treasury_gold == gold_before - expansion_cost,
				"expansion_reuses_entity_and_pays_resources"
			)
			var next_recruitment := simulation._next_battle_group_recruitment(
				nation_id
			)
			_check(
				int(next_recruitment.get("group_id", -1))
					== ordered_groups[1].id,
				"eighth_legion_cycles_to_command_two"
			)

	var army_count_before_merge := state.armies.size()
	var capacity_before_merge := _main_capacity(state, nation_id)
	var overflow := state._spawn_conjured_army(
		nation_id,
		nation.capital_city_id,
		GameState.INITIAL_HEAVY_ARMY_SIZE,
		Army.StrategicRole.MAIN
	)
	var merged_command := state.assign_or_merge_main_army(overflow)
	_check(
		merged_command != null
		and not state.armies.has(overflow)
		and state.armies.size() == army_count_before_merge
		and _main_capacity(state, nation_id)
			== capacity_before_merge + GameState.INITIAL_HEAVY_ARMY_SIZE,
		"overflow_main_army_merges_into_existing_command"
	)
	_test_revoke_vassal_merges_command_units()
	_test_adjacent_main_command_reinforces_battle()

	if not _failures.is_empty():
		for failure in _failures:
			push_error("COMMAND_UNIT_OFFENSIVE_FAIL: " + failure)
		quit(1)
		return
	print("COMMAND_UNIT_OFFENSIVE_OK")
	simulation.free()
	quit(0)


func _first_enemy_border_city(state: GameState, nation_id: int) -> int:
	for city in state.cities:
		if (
			city.is_dock
			or city.owner_nation < 0
			or city.owner_nation == nation_id
		):
			continue
		for neighbor in state.neighbors(city.id):
			if state.cities[neighbor].owner_nation == nation_id:
				return city.id
	return -1


func _first_main_army(state: GameState, nation_id: int) -> Army:
	for army in state.armies:
		if army.owner_nation == nation_id and army.is_main_battle_role():
			return army
	return null


func _army_by_id(state: GameState, army_id: int) -> Army:
	for army in state.armies:
		if army.id == army_id:
			return army
	return null


func _main_capacity(state: GameState, nation_id: int) -> int:
	var total := 0
	for army in state.armies:
		if army.owner_nation == nation_id and army.is_main_battle_role():
			total += army.max_size
	return total


func _test_revoke_vassal_merges_command_units() -> void:
	var state := GameState.new()
	state.generate_grid_world(86421)
	state.armies.clear()
	for nation in state.nations:
		nation.battle_groups.clear()
		nation.next_battle_group_id = 0
	var overlord_id := 0
	var subject_id := 1
	state.suzerainty[subject_id] = {
		"overlord_id": overlord_id,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": state.day,
		"last_centralization_day": -1,
		"civil_war": false,
	}
	for nation_id in [overlord_id, subject_id]:
		for command_index in range(BattleGroup.MAX_COMMAND_UNITS):
			var group := state.create_battle_group(nation_id)
			var army := state._spawn_conjured_army(
				nation_id,
				state.nations[nation_id].capital_city_id,
				GameState.INITIAL_HEAVY_ARMY_SIZE,
				Army.StrategicRole.MAIN
			)
			_check(
				group != null
				and state.assign_army_to_battle_group(army, group.id),
				"revocation_fixture_command_created_%d_%d"
					% [nation_id, command_index]
			)
	var expected_capacity := (
		BattleGroup.MAX_COMMAND_UNITS
		* 2
		* GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	var revoked := state.revoke_vassal(subject_id)
	_check(
		revoked
		and state.nations[overlord_id].battle_groups.size()
			== BattleGroup.MAX_COMMAND_UNITS
		and _main_capacity(state, overlord_id) == expected_capacity
		and state._battle_group_structure_valid(),
		"revocation_merges_twelve_commands_into_six_pools"
	)


func _test_adjacent_main_command_reinforces_battle() -> void:
	var state := GameState.new()
	state.generate_grid_world(86422)
	state.armies.clear()
	for nation in state.nations:
		nation.battle_groups.clear()
		nation.next_battle_group_id = 0
	var target_city := 9
	var reserve_city := 8
	var attacker_city := 10
	state.cities[target_city].owner_nation = 0
	state.cities[reserve_city].owner_nation = 0
	state.cities[attacker_city].owner_nation = 1
	state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	var defender_group := state.create_battle_group(0)
	var reserve_group := state.create_battle_group(0)
	var attacker_group := state.create_battle_group(1)
	var defender := state.create_army(0, target_city, 5000, 15000)
	var reserve := state.create_army(0, reserve_city, 15000, 15000)
	var attacker := state.create_army(1, attacker_city, 15000, 15000)
	state.assign_army_to_battle_group(defender, defender_group.id)
	state.assign_army_to_battle_group(reserve, reserve_group.id)
	state.assign_army_to_battle_group(attacker, attacker_group.id)
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city = state.cities[target_city]
	battle.edge = state.edge_of(target_city, attacker_city)
	battle.has_garrison = true
	battle.side_a.append(attacker)
	battle.side_b.append(defender)
	for participant in [attacker, defender]:
		participant.state = Army.State.FIGHTING
		participant.battle_id = battle.id
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation._resolve_nearby_main_battle_reinforcements()
	_check(
		reserve.state == Army.State.MOVING
			and reserve.ai_target_city == target_city
			and reserve.ai_order_reason.contains("邻近战场"),
		"adjacent_idle_main_command_reinforces_outmatched_siege"
	)
	simulation.free()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
