extends SceneTree

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_initial_force_has_one_capital_guard()
	_test_group_capacity_follows_actual_strength()
	_test_group_reconciliation_preserves_indivisible_remnants()
	_test_capital_guard_never_receives_war_corridor()
	_test_recruitment_fills_current_group_before_creating_next()
	_test_peace_and_capital_attack_routes()
	_test_war_pair_shares_reversed_capital_corridor()
	_test_threat_weighted_corridor_allocation()
	_test_defender_holds_forward_owned_corridor_node()
	_test_defender_counterattacks_occupied_corridor_city()
	_test_corridor_survives_third_enemy_occupation()
	_test_group_skips_unreachable_coalition_enemy()
	_test_off_corridor_army_joins_nearest_corridor_node()
	_test_holding_army_exits_toward_nearest_corridor_join()
	_test_allied_capital_corridors_merge_before_assignment()
	_test_prewar_groups_assemble_and_unlock_declaration()
	_test_node_threat_follows_capital_corridor()
	_test_peace_pressure_has_only_four_components()
	_test_simulation_issues_group_route_orders()
	_test_defeated_group_retreats_back_along_corridor()
	_test_defeated_group_at_city_retreats_back_along_corridor()
	_test_battle_losses_accumulate_and_clear_on_peace()
	_finish()


func _base_state() -> GameState:
	var state := GameState.new()
	state.generate_grid_world(95101)
	state.armies.clear()
	for nation in state.nations:
		nation.battle_groups.clear()
		nation.next_battle_group_id = 0
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				a, b, GameState.DiplomaticRelation.NEUTRAL
			)
	return state


func _add_main_army(
	state: GameState,
	nation_id: int,
	city_id: int,
	size: int
) -> Army:
	var army := Army.new()
	army.id = state.armies.size() + 10000
	army.owner_nation = nation_id
	army.location_city = city_id
	army.move_from = city_id
	army.size = size
	army.max_size = size
	army.strategic_role = Army.StrategicRole.MAIN
	state.armies.append(army)
	return army


func _test_initial_force_has_one_capital_guard() -> void:
	var state := GameState.new()
	state.generate_grid_world(95101)
	for nation in state.nations:
		var guards: Array[BattleGroup] = []
		for group in nation.battle_groups:
			if group.role == BattleGroup.Role.CAPITAL_GUARD:
				guards.append(group)
		_check(guards.size() == 1, "每个国家必须恰有一支首都禁军")
		if guards.size() != 1:
			continue
		_check(
			SimplifiedWarAI.group_strength(state, guards[0])
				== BattleGroup.CAPITAL_GUARD_MANPOWER,
			"首都禁军必须为固定5万人编制"
		)


func _test_group_capacity_follows_actual_strength() -> void:
	var state := _base_state()
	var capital := state.nations[0].capital_city_id
	var guard := state.create_battle_group(0)
	guard.role = BattleGroup.Role.CAPITAL_GUARD
	var guard_army := _add_main_army(
		state, 0, capital, BattleGroup.CAPITAL_GUARD_MANPOWER
	)
	state.assign_army_to_battle_group(guard_army, guard.id)
	for _index in range(7):
		_add_main_army(state, 0, capital, 5000)
	SimplifiedWarAI.reconcile_groups(state, 0)
	var strengths: Array[int] = []
	for group in state.nations[0].battle_groups:
		if group.role == BattleGroup.Role.CAPITAL_GUARD:
			continue
		strengths.append(SimplifiedWarAI.group_strength(state, group))
	_check(
		strengths == [15000, 15000, 5000],
		"3.5万现役主力必须按1.5万、1.5万、0.5万切成三团，实际=%s" % [strengths]
	)
	_check(state._battle_group_structure_valid(), "1.5万总兵力上限后的战团结构必须合法")
	_check(
		SimplifiedWarAI.group_strength(state, guard)
			== BattleGroup.CAPITAL_GUARD_MANPOWER,
		"整理野战军团不得拆分或并入首都禁军"
	)


func _test_group_reconciliation_preserves_indivisible_remnants() -> void:
	var state := _base_state()
	var capital := state.nations[0].capital_city_id
	var remnants: Array[Army] = []
	for size in [10000, 10000, 10000]:
		remnants.append(_add_main_army(state, 0, capital, size))
	SimplifiedWarAI.reconcile_groups(state, 0)
	var assigned := true
	for army in remnants:
		assigned = assigned and army.battle_group_id >= 0
	_check(
		assigned and state._battle_group_structure_valid(),
		"不可拆分残编必须按实际装箱数保留军团归属，不能按总兵力向上取整后漏军"
	)


func _test_capital_guard_never_receives_war_corridor() -> void:
	var state := _base_state()
	var capital := state.nations[0].capital_city_id
	var guard := state.create_battle_group(0)
	guard.role = BattleGroup.Role.CAPITAL_GUARD
	var guard_army := _add_main_army(
		state, 0, capital, BattleGroup.CAPITAL_GUARD_MANPOWER
	)
	state.assign_army_to_battle_group(guard_army, guard.id)
	_add_main_army(state, 0, capital, 15000)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	SimplifiedWarAI.plan_nation(state, 0)
	var field_groups: Array[BattleGroup] = []
	for group in state.nations[0].battle_groups:
		if group.role == BattleGroup.Role.FIELD:
			field_groups.append(group)
	_check(
		guard.posture == BattleGroup.Posture.PEACE
			and guard.target_nation == -1
			and guard.target_city == capital
			and guard.route[-1] == capital,
		"首都禁军在战争中也只能驻守首都，不能获得军事走廊"
	)
	_check(
		field_groups.size() == 1
			and field_groups[0].posture == BattleGroup.Posture.ATTACK
			and field_groups[0].target_nation == 1,
		"只有野战军团可以分配到敌国首都走廊"
	)


func _test_recruitment_fills_current_group_before_creating_next() -> void:
	var state := _base_state()
	var group := state.create_battle_group(0)
	for size in [5000, 5000]:
		var army := _add_main_army(
			state, 0, state.nations[0].capital_city_id, size
		)
		state.assign_army_to_battle_group(army, group.id)
	var simulation := Simulation.new()
	simulation.setup(state)
	var next := simulation._next_battle_group_recruitment(0, true, true)
	_check(
		int(next.get("group_id", -1)) == group.id
			and not bool(next.get("create_group", false)),
		"当前野战军团未满1.5万人时不得提前创建下一军团"
	)
	var reinforcement := _add_main_army(
		state, 0, state.nations[0].capital_city_id, 5000
	)
	state.assign_army_to_battle_group(reinforcement, group.id)
	var after_full := simulation._next_battle_group_recruitment(0, true, true)
	_check(
		bool(after_full.get("create_group", false)),
		"只有已有野战军团满1.5万人后才能创建下一军团"
	)
	simulation.free()


func _test_peace_and_capital_attack_routes() -> void:
	var state := _base_state()
	var own_capital := state.nations[0].capital_city_id
	var start := state.land_cities_of(0)[-1].id
	_add_main_army(state, 0, start, 15000)
	SimplifiedWarAI.plan_nation(state, 0)
	var group := state.nations[0].battle_groups[0]
	_check(
		group.posture == BattleGroup.Posture.PEACE
			and group.target_city == own_capital
			and group.route[-1] == own_capital,
		"和平期主战军团必须返回本国首都"
	)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	SimplifiedWarAI.plan_nation(state, 0)
	var enemy_capital := state.nations[1].capital_city_id
	_check(
		group.posture == BattleGroup.Posture.ATTACK
			and group.target_nation == 1
			and group.target_city == enemy_capital
			and not group.route.is_empty()
			and group.route[-1] == enemy_capital,
		"无来袭路线时，进攻军团的唯一默认战略目标必须是敌国首都"
	)


func _test_war_pair_shares_reversed_capital_corridor() -> void:
	var state := _base_state()
	var frontier: Edge = null
	for edge in state.edges:
		if (
			edge.max_manpower > 0
			and state.cities[edge.city_a].owner_nation
				!= state.cities[edge.city_b].owner_nation
		):
			frontier = edge
			break
	_check(frontier != null, "公共首都路线测试需要一条跨国道路")
	if frontier == null:
		return
	var nation_a := state.cities[frontier.city_a].owner_nation
	var nation_b := state.cities[frontier.city_b].owner_nation
	var army_a := _add_main_army(
		state, nation_a, frontier.city_a, 15000
	)
	_add_main_army(state, nation_b, frontier.city_b, 15000)
	state.set_diplomatic_relation(
		nation_a, nation_b, GameState.DiplomaticRelation.WAR
	)
	SimplifiedWarAI.plan_nation(state, nation_a)
	SimplifiedWarAI.plan_nation(state, nation_b)
	var group_a := state.nations[nation_a].battle_groups[0]
	var group_b := state.nations[nation_b].battle_groups[0]
	var reversed_b: Array[int] = group_b.route.duplicate()
	reversed_b.reverse()
	_check(
		group_a.posture == BattleGroup.Posture.ATTACK
			and group_b.posture == BattleGroup.Posture.ATTACK
			and group_a.route.size() >= 2
			and group_a.route[0] == state.nations[nation_a].capital_city_id
			and group_a.route[-1] == state.nations[nation_b].capital_city_id
			and group_a.route == reversed_b,
		"交战双方必须共用同一条首都到首都走廊，并从相反方向推进"
	)
	var simulation := Simulation.new()
	simulation.setup(state)
	var member_path := simulation._battle_group_member_path(army_a, group_a)
	var route_index := group_a.route.find(army_a.location_city)
	var follows_corridor := member_path == group_a.route.slice(route_index + 1)
	if route_index < 0:
		follows_corridor = false
		for path_index in range(member_path.size()):
			var join_index := group_a.route.find(member_path[path_index])
			if join_index < 0:
				continue
			follows_corridor = (
				member_path.slice(path_index + 1)
				== group_a.route.slice(join_index + 1)
			)
			break
	_check(
		follows_corridor,
		"军团从任意节点汇入公共走廊后必须沿正确方向推进"
	)
	simulation.free()


func _test_threat_weighted_corridor_allocation() -> void:
	var state := _base_state()
	var own_capital := state.nations[0].capital_city_id
	for _index in range(4):
		_add_main_army(state, 0, own_capital, 15000)
	for _index in range(2):
		_add_main_army(
			state, 1, state.nations[1].capital_city_id, 15000
		)
	_add_main_army(state, 2, state.nations[2].capital_city_id, 15000)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	state.set_war_objective(1, 0, own_capital, "测试北线威胁")
	state.set_war_objective(2, 0, own_capital, "测试南线威胁")
	SimplifiedWarAI.plan_nation(state, 1)
	SimplifiedWarAI.plan_nation(state, 2)
	SimplifiedWarAI.plan_nation(state, 0)
	var assigned := {1: 0, 2: 0}
	for group in state.nations[0].battle_groups:
		if group.role == BattleGroup.Role.FIELD and assigned.has(group.target_nation):
			assigned[group.target_nation] = int(assigned[group.target_nation]) + 1
	_check(
		int(assigned[1]) == 3 and int(assigned[2]) == 1,
		"四支守军面对3万与1.5万走廊威胁时必须按3:1分配，实际=%s" % [assigned]
	)


func _test_defender_holds_forward_owned_corridor_node() -> void:
	var state := _base_state()
	for edge in state.edges:
		edge.max_manpower = 0
	var corridor := [0, 1, 2, 3] as Array[int]
	for index in range(corridor.size() - 1):
		state.edge_of(corridor[index], corridor[index + 1]).max_manpower = 15000
	state.edge_of(2, 3).danger = 0.95
	state.edge_of(2, 3).allows_holding = true
	for city_id in corridor:
		state.cities[city_id].owner_nation = 0 if city_id < 3 else 1
		state.recognized_city_owners[city_id] = 0 if city_id < 3 else 1
	state.cities[0].fort_strength = 100
	state.cities[1].fort_strength = 30
	state.cities[2].fort_strength = 1
	state.nations[0].capital_city_id = 0
	state.nations[1].capital_city_id = 3
	var defender := _add_main_army(state, 0, 0, 15000)
	_add_main_army(state, 1, 3, 15000)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_war_objective(1, 0, 0, "测试防御据点")
	SimplifiedWarAI.plan_nation(state, 0)
	var group := state.nations[0].battle_groups[0]
	_check(
		group.posture == BattleGroup.Posture.DEFEND
			and group.target_nation == 1
			and group.target_city == 2
			and group.route == corridor,
		"防守方必须忽略后方高城防城市，部署到走廊最前沿的己控节点：target=%d route=%s"
			% [group.target_city, group.route]
	)
	defender.location_city = group.target_city
	defender.move_from = group.target_city
	var simulation := Simulation.new()
	simulation.setup(state)
	simulation._issue_battle_group_order(group)
	_check(
		group.defense_edge_to == 3
			and defender.state == Army.State.MOVING
			and defender.move_from == 2
			and defender.move_to == 3
			and defender.hold_target_progress > 0.0,
		"前线道路适合驻防时，防守军必须进入走廊边并在己方一侧驻防：edge=%d state=%d move=%d-%d"
			% [group.defense_edge_to, defender.state, defender.move_from, defender.move_to]
	)
	simulation.free()


func _test_defender_counterattacks_occupied_corridor_city() -> void:
	var state := _base_state()
	for edge in state.edges:
		edge.max_manpower = 0
	var corridor := [0, 1, 2, 3] as Array[int]
	for index in range(corridor.size() - 1):
		state.edge_of(corridor[index], corridor[index + 1]).max_manpower = 15000
	state.cities[0].owner_nation = 0
	state.cities[1].owner_nation = 0
	state.cities[2].owner_nation = 1
	state.cities[3].owner_nation = 1
	state.recognized_city_owners[2] = 0
	state.nations[0].capital_city_id = 0
	state.nations[1].capital_city_id = 3
	var defender := _add_main_army(state, 0, 1, 15000)
	_add_main_army(state, 1, 3, 15000)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_war_objective(1, 0, 0, "测试前线反攻")
	SimplifiedWarAI.plan_nation(state, 0)
	var group := state.nations[0].battle_groups[0]
	var simulation := Simulation.new()
	simulation.setup(state)
	simulation._issue_battle_group_order(group)
	_check(
		group.posture == BattleGroup.Posture.DEFEND
			and group.target_city == 2
			and group.defense_edge_to == -1
			and defender.state == Army.State.MOVING
			and defender.ai_action == ActionCandidate.Kind.ATTACK
			and defender.ai_target_city == 2,
		"防守走廊紧邻己方法理失地时，军团必须反攻该城而不是停在后方"
	)
	simulation.free()


func _test_defeated_group_retreats_back_along_corridor() -> void:
	var state := _base_state()
	state.nations[0].capital_city_id = 0
	var army := _add_main_army(state, 0, 2, 15000)
	var group := state.create_battle_group(0)
	state.assign_army_to_battle_group(army, group.id)
	group.posture = BattleGroup.Posture.ATTACK
	group.target_nation = 1
	group.target_city = 3
	group.route = [0, 1, 2, 3] as Array[int]
	army.location_city = 2
	army.move_from = 2
	army.move_to = 3
	army.move_progress = 0.4
	army.on_edge = true
	army.state = Army.State.FIGHTING
	state.edge_of(2, 3).passing_count += 1
	var simulation := Simulation.new()
	simulation.setup(state)
	simulation._retreat(army)
	_check(
		army.state == Army.State.RETREATING
			and army.move_to == 2
			and army.path == ([1, 0] as Array[int]),
		"走廊上的战败主战军必须掉头并沿本军团走廊一路撤回己方首都"
	)
	simulation.free()


func _test_defeated_group_at_city_retreats_back_along_corridor() -> void:
	var state := _base_state()
	state.nations[0].capital_city_id = 0
	var army := _add_main_army(state, 0, 2, 15000)
	var group := state.create_battle_group(0)
	state.assign_army_to_battle_group(army, group.id)
	group.posture = BattleGroup.Posture.ATTACK
	group.target_nation = 1
	group.target_city = 3
	group.route = [0, 1, 2, 3] as Array[int]
	var simulation := Simulation.new()
	simulation.setup(state)
	simulation._start_morale_retreat_from_city(army, 2, 2)
	_check(
		army.state == Army.State.RETREATING
			and army.move_from == 2
			and army.move_to == 1
			and army.path == ([0] as Array[int]),
		"城市节点战败的主战军也必须沿走廊反向连续撤退，不能另寻捷径"
	)
	simulation.free()


func _test_corridor_survives_third_enemy_occupation() -> void:
	var state := _base_state()
	for edge in state.edges:
		edge.max_manpower = 0
	var corridor := [0, 8, 16, 24, 32, 40] as Array[int]
	for index in range(corridor.size() - 1):
		state.edge_of(corridor[index], corridor[index + 1]).max_manpower = 15000
	for city_id in corridor:
		state.cities[city_id].owner_nation = 0 if city_id <= 16 else 1
	state.nations[0].capital_city_id = corridor[0]
	state.nations[1].capital_city_id = corridor[-1]
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	_check(
		SimplifiedWarAI.shared_capital_route(state, 0, 1) == corridor,
		"第三方占领前测试夹具必须只有一条首都走廊"
	)
	state.cities[24].owner_nation = 2
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	var after_occupation := SimplifiedWarAI.build_war_corridors(state)
	_check(
		after_occupation.get(Vector2i(0, 1), [] as Array[int]) == corridor,
		"通道中段被共同敌国控制后，原交战双方的首都走廊不能消失"
	)
	var reverse: Array[int] = corridor.duplicate()
	reverse.reverse()
	_check(
		after_occupation.get(Vector2i(1, 0), [] as Array[int]) == reverse,
		"第三方占领后反向走廊仍须与正向走廊严格互逆"
	)


func _test_group_skips_unreachable_coalition_enemy() -> void:
	var state := _base_state()
	for edge in state.edges:
		edge.max_manpower = 0
	for road in [[0, 1], [1, 2], [0, 8], [8, 16], [16, 24]]:
		state.edge_of(int(road[0]), int(road[1])).max_manpower = 15000
	state.cities[0].owner_nation = 0
	state.cities[1].owner_nation = 0
	state.cities[2].owner_nation = 3
	state.cities[8].owner_nation = 0
	state.cities[16].owner_nation = 2
	state.cities[24].owner_nation = 1
	state.nations[0].capital_city_id = 0
	state.nations[1].capital_city_id = 24
	state.nations[3].capital_city_id = 2
	_add_main_army(state, 0, 0, 15000)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.WAR)
	SimplifiedWarAI.plan_nation(state, 0)
	var group := state.nations[0].battle_groups[0]
	_check(
		group.target_nation == 3
			and group.route == ([0, 1, 2] as Array[int]),
		"联盟战争军团必须跳过首都不可达的敌国，选择可执行的敌国走廊"
	)
	state.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.NEUTRAL)
	SimplifiedWarAI.plan_nation(state, 0)
	_check(
		group.posture == BattleGroup.Posture.PEACE
			and group.target_nation == -1
			and group.target_city == state.nations[0].capital_city_id
			and group.route[-1] == state.nations[0].capital_city_id,
		"所有敌方首都均不可达时必须清除空攻击命令并回防首都"
	)


func _test_off_corridor_army_joins_nearest_corridor_node() -> void:
	var state := _base_state()
	var nation_a := 0
	var nation_b := 1
	var army := _add_main_army(
		state, nation_a, state.nations[nation_a].capital_city_id, 15000
	)
	state.set_diplomatic_relation(
		nation_a, nation_b, GameState.DiplomaticRelation.WAR
	)
	SimplifiedWarAI.plan_nation(state, nation_a)
	var group := state.nations[nation_a].battle_groups[0]
	var start := -1
	var expected_cost := INF
	var capital_cost := INF
	for city in state.cities:
		if group.route.has(city.id):
			continue
		var costs: Array[float] = []
		for corridor_city in group.route:
			var path := Pathfinding.campaign_route(
				state, city.id, corridor_city, nation_a, nation_b
			)
			costs.append(
				_campaign_path_cost(state, city.id, path)
				if not path.is_empty() else INF
			)
		var best_cost: float = costs.min()
		var own_capital_index := group.route.find(
			state.nations[nation_a].capital_city_id
		)
		var candidate_capital_cost := costs[own_capital_index]
		if best_cost + 0.000001 < candidate_capital_cost:
			start = city.id
			expected_cost = best_cost
			capital_cost = candidate_capital_cost
			break
	_check(start >= 0, "最近走廊接入测试需要一个中段明显近于己方首都的城")
	if start < 0:
		return
	state.cities[start].owner_nation = nation_a
	army.location_city = start
	army.move_from = start
	var simulation := Simulation.new()
	simulation.setup(state)
	var member_path := simulation._battle_group_member_path(army, group)
	var join_offset := -1
	for path_index in range(member_path.size()):
		if group.route.has(member_path[path_index]):
			join_offset = path_index
			break
	var join_path: Array[int] = (
		member_path.slice(0, join_offset + 1)
		if join_offset >= 0 else [] as Array[int]
	)
	var actual_cost := _campaign_path_cost(state, start, join_path)
	var expected_path := join_path.duplicate()
	if join_offset >= 0:
		var join_route_index := group.route.find(member_path[join_offset])
		expected_path.append_array(group.route.slice(join_route_index + 1))
	_check(
		join_offset >= 0
			and is_equal_approx(actual_cost, expected_cost)
			and actual_cost < capital_cost,
		"走廊外军团必须接入最近可达节点，不能固定绕回己方首都"
	)
	_check(
		member_path == expected_path,
		"军团首次接入走廊后必须立即朝敌都推进，不能沿走廊退回首都再折返"
	)
	simulation.free()


func _campaign_path_cost(
	state: GameState,
	start: int,
	path: Array[int]
) -> float:
	var result := 0.0
	var from_city := start
	for to_city in path:
		var edge := state.edge_of(from_city, to_city)
		if edge == null:
			return INF
		result += (
			float(maxi(edge.distance, 1))
			* maxf(edge.travel_time_multiplier, 0.05)
			+ edge.danger * Pathfinding.DANGER_WEIGHT
		)
		from_city = to_city
	return result


func _test_holding_army_exits_toward_nearest_corridor_join() -> void:
	var state := _base_state()
	var group := BattleGroup.new()
	group.owner_nation = 0
	group.target_nation = 1
	group.posture = BattleGroup.Posture.ATTACK
	group.route = [8, 0, 1, 2, 3, 4] as Array[int]
	var army := Army.new()
	army.owner_nation = 0
	army.on_edge = true
	army.move_from = 8
	army.move_to = 9
	army.move_progress = 0.99
	var current_edge := state.edge_of(8, 9)
	var forward_join_edge := state.edge_of(9, 1)
	current_edge.distance = 100
	current_edge.danger = 0.0
	forward_join_edge.distance = 1
	forward_join_edge.danger = 0.0
	var simulation := Simulation.new()
	simulation.setup(state)
	_check(
		simulation._battle_group_attack_holding_endpoint(army, group) == 9,
		"道路驻军应按当前位置驶向最近接入点，不能固定退向已在线端点"
	)
	simulation.free()


func _test_allied_capital_corridors_merge_before_assignment() -> void:
	var state := _base_state()
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	var corridors := SimplifiedWarAI.build_war_corridors(state)
	var route_0: Array[int] = corridors.get(Vector2i(0, 2), [])
	var route_1: Array[int] = corridors.get(Vector2i(1, 2), [])
	var reverse_0: Array[int] = corridors.get(Vector2i(2, 0), [])
	var reverse_1: Array[int] = corridors.get(Vector2i(2, 1), [])
	var expected_reverse_0: Array[int] = route_0.duplicate()
	expected_reverse_0.reverse()
	var expected_reverse_1: Array[int] = route_1.duplicate()
	expected_reverse_1.reverse()
	var common_suffix := false
	for index_0 in range(1, route_0.size()):
		var index_1 := route_1.find(route_0[index_0])
		if index_1 <= 0:
			continue
		if (
			route_0.size() - index_0 >= 2
			and route_0.slice(index_0) == route_1.slice(index_1)
		):
			common_suffix = true
			break
	_check(
		route_0.size() >= 2
			and route_1.size() >= 2
			and route_0[0] == state.nations[0].capital_city_id
			and route_1[0] == state.nations[1].capital_city_id
			and route_0[-1] == state.nations[2].capital_city_id
			and route_1[-1] == state.nations[2].capital_city_id
			and common_suffix,
		"两跳内的盟军首都走廊必须保留各自起点并共享通往敌都的下游"
	)
	_check(
		reverse_0 == expected_reverse_0
			and reverse_1 == expected_reverse_1,
		"盟军走廊汇流完成后，必须再同步生成敌方使用的严格反向路线"
	)


func _test_prewar_groups_assemble_and_unlock_declaration() -> void:
	var state := _base_state()
	state.uses_heightmap = true
	var frontier: Edge = null
	for edge in state.edges:
		if (
			edge.max_manpower > 0
			and state.cities[edge.city_a].owner_nation
				!= state.cities[edge.city_b].owner_nation
		):
			frontier = edge
			break
	_check(frontier != null, "备战测试需要一条跨国可通行边")
	if frontier == null:
		return
	var attacker_id := state.cities[frontier.city_a].owner_nation
	var defender_id := state.cities[frontier.city_b].owner_nation
	var nation := state.nations[attacker_id]
	var army := _add_main_army(
		state, attacker_id, nation.capital_city_id, 15000
	)
	nation.war_preparation_target_nation = defender_id
	nation.war_preparation_objective_city = frontier.city_b
	nation.war_preparation_started_day = 0
	SimplifiedWarAI.plan_nation(state, attacker_id)
	var group := state.battle_group_by_id(attacker_id, army.battle_group_id)
	var staging := DiplomacyAI.staging_cities_for_objective(
		state, attacker_id, frontier.city_b
	)
	_check(
		group != null
			and group.posture == BattleGroup.Posture.RECOVER
			and group.target_nation == defender_id
			and staging.has(group.target_city),
		"和平中的备战军团必须向目标边境集结，不能继续执行返都命令"
	)
	if group == null or not staging.has(group.target_city):
		return
	army.location_city = group.target_city
	army.move_from = group.target_city
	army.move_to = -1
	army.on_edge = false
	army.state = Army.State.IDLE
	state.day = DiplomacyAI.WAR_PREPARATION_MIN_DAYS
	_check(
		DiplomacyAI.war_preparation_ready(state, attacker_id),
		"简化军团已到边境后必须直接完成备战，不得依赖已删除的旧战役计划"
	)


func _test_node_threat_follows_capital_corridor() -> void:
	var state := _base_state()
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var defender_capital := state.nations[1].capital_city_id
	for size in [15000, 15000]:
		var group := state.create_battle_group(0)
		var army := _add_main_army(state, 0, state.nations[0].capital_city_id, size)
		state.assign_army_to_battle_group(army, group.id)
		group.posture = BattleGroup.Posture.ATTACK
		group.target_nation = 1
		group.target_city = defender_capital
		group.route = SimplifiedWarAI.shared_capital_route(state, 0, 1)
	var threats := SimplifiedWarAI.node_threats(state, 1)
	var total_threat := 0
	for value in threats.values():
		total_threat += int(value)
	_check(total_threat == 30000, "NodeThreat 必须累计经过边境节点的来袭集团兵力")


func _test_peace_pressure_has_only_four_components() -> void:
	var state := _base_state()
	var defender_capital := state.nations[0].capital_city_id
	var attacker_capital := state.nations[1].capital_city_id
	var defender_group := state.create_battle_group(0)
	state.assign_army_to_battle_group(
		_add_main_army(state, 0, defender_capital, 15000),
		defender_group.id
	)
	var attacker_group := state.create_battle_group(1)
	state.assign_army_to_battle_group(
		_add_main_army(state, 1, attacker_capital, 15000),
		attacker_group.id
	)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.nations[0].war_initial_military_strength[1] = 100000
	state.nations[0].war_military_losses[1] = 50000
	state.day = state.relation_since(0, 1) + 360
	attacker_group.posture = BattleGroup.Posture.ATTACK
	attacker_group.target_nation = 0
	attacker_group.target_city = defender_capital
	attacker_group.route = SimplifiedWarAI.route_to_city(
		state, attacker_group, defender_capital
	)
	var pressure := DiplomacyAI.peace_willingness_breakdown(state, 0, 1)
	var component_sum := (
		float(pressure["military_loss"])
		+ float(pressure["capital_threat"])
		+ float(pressure["uncovered_threat"])
		+ float(pressure["war_duration"])
	)
	_check(
		is_equal_approx(float(pressure["military_loss"]), 30.0),
		"损失开战军力一半必须产生30点 MilitaryLoss"
	)
	_check(
		is_equal_approx(float(pressure["war_duration"]), 5.0),
		"战争每持续一年必须产生5点 WarDuration"
	)
	_check(
		is_equal_approx(float(pressure["score"]), minf(component_sum, 100.0)),
		"PeacePressure 必须且只能是四项压力之和并限制在0到100"
	)


func _test_simulation_issues_group_route_orders() -> void:
	var state := _base_state()
	var army := _add_main_army(
		state, 0, state.nations[0].capital_city_id, 15000
	)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var simulation := Simulation.new()
	simulation.setup(state)
	simulation._run_simplified_war_ai(false)
	var group := state.battle_group_by_id(0, army.battle_group_id)
	_check(
		group != null
			and group.target_city == state.nations[1].capital_city_id
			and army.state == Army.State.MOVING
			and army.ai_target_city == state.nations[1].capital_city_id,
		"Simulation 必须把军团的敌首都路线提交为真实移动命令"
	)
	simulation.free()


func _test_battle_losses_accumulate_and_clear_on_peace() -> void:
	var state := _base_state()
	var army_a := _add_main_army(
		state, 0, state.nations[0].capital_city_id, 10000
	)
	var army_b := _add_main_army(
		state, 1, state.nations[1].capital_city_id, 10000
	)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var battle := Battle.new()
	battle.side_a = [army_a] as Array[Army]
	battle.side_b = [army_b] as Array[Army]
	var simulation := Simulation.new()
	simulation.setup(state)
	var before := simulation._battle_strength_by_nation(battle)
	army_a.size -= 2500
	simulation._record_battle_losses(
		before, battle, [0] as Array[int], [1] as Array[int]
	)
	_check(
		int(state.nations[0].war_military_losses[1]) == 2500,
		"真实战斗伤亡必须累计，后续补员不得冲销 MilitaryLoss"
	)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	_check(
		not state.nations[0].war_military_losses.has(1)
			and not state.nations[0].war_initial_military_strength.has(1),
		"停战后必须清除该战争的损失和开战兵力快照"
	)
	simulation.free()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("SIMPLIFIED_WAR_AI_OK checks=", _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("SIMPLIFIED_WAR_AI_FAIL: " + failure)
	quit(1)
