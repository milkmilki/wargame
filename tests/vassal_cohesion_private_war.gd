extends SceneTree

var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := _fixture()
	var state: GameState = fixture["state"]
	var root := int(fixture["root"])
	var attacker := int(fixture["attacker"])
	var defender := int(fixture["defender"])
	var outsider := int(fixture["outsider"])
	var direct_count := 0
	var system_count := 0
	for city in state.land_cities():
		var legal_owner := state.recognized_owner_of(city.id)
		if legal_owner in [root, attacker, defender]:
			system_count += 1
		if legal_owner == root:
			direct_count += 1
	var expected := float(direct_count) / float(system_count)
	_check(
		is_equal_approx(state.suzerainty_cohesion(attacker), expected),
		"凝聚力必须按宗主直辖法理陆城 / 宗藩体系法理陆城计算"
	)
	var occupied_city := state.land_cities_of(attacker)[0]
	var legal_before := state.recognized_owner_of(occupied_city.id)
	occupied_city.owner_nation = outsider
	state.ownership_revision += 1
	_check(
		state.recognized_owner_of(occupied_city.id) == legal_before
			and is_equal_approx(
				state.suzerainty_cohesion(attacker), expected
			),
		"临时控制权变化不得改变宗藩凝聚力"
	)
	occupied_city.owner_nation = attacker
	state.ownership_revision += 1
	var legal_snapshot := state.recognized_city_owners.duplicate()
	for city in state.land_cities():
		if state.recognized_owner_of(city.id) in [root, attacker, defender]:
			state.recognized_city_owners[city.id] = root
	state.recognized_city_owners[
		state.land_cities_of(attacker)[0].id
	] = attacker
	state.recognized_city_owners[
		state.land_cities_of(defender)[0].id
	] = defender
	state.ownership_revision += 1
	_check(
		state.suzerainty_cohesion(root)
			> GameState.VASSAL_PRIVATE_WAR_COHESION_THRESHOLD
			and not state.can_vassal_declare_private_war(attacker),
		"高凝聚力宗藩不得新开私人战争"
	)
	state.recognized_city_owners = legal_snapshot
	state.ownership_revision += 1

	_check(
		state.can_vassal_declare_private_war(attacker),
		"低于35%凝聚力时和平藩王应解锁私人战争"
	)
	_check(
		state.can_declare_private_war(attacker, defender),
		"低凝聚力藩王应能向同体系兄弟藩王宣战"
	)
	_check(
		state.is_same_suzerainty_system(attacker, defender),
		"兄弟藩王必须被识别为同一宗藩体系，而非普通盟友"
	)
	_check(
		not state.can_declare_private_war(attacker, root),
		"私人战争不得攻击自己的宗主根"
	)
	_check(
		DiplomacyAI.war_desire(
			state, attacker, defender, {}, true
		) > -INF,
		"私人战争必须复用普通战争评估，而非被宗藩盟约门禁直接拒绝"
	)
	var attacker_nation := state.nations[attacker]
	attacker_nation.ruler_archetype = RulerProfile.CONQUEROR
	attacker_nation.ruler_traits.clear()
	attacker_nation.treasury_gold = 1000000
	attacker_nation.manpower_pool = 1000000
	attacker_nation.granary_food = 1000000
	state.day = 20 * Simulation.DAYS_PER_YEAR
	var committed := {}
	for nation in state.nations:
		if nation.id not in [attacker, defender]:
			committed[nation.id] = true
	var ai_actions: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(
		state,
		ai_actions,
		committed,
		{},
		attacker,
		attacker + 1
	)
	var private_preparation := false
	for action in ai_actions:
		private_preparation = private_preparation or (
			int(action.get("kind", -1)) == DiplomacyAI.Action.PREPARE_WAR
			and int(action.get("a", -1)) == attacker
			and int(action.get("b", -1)) == defender
			and int(action.get("war_scope", -1))
				== GameState.WarScope.VASSAL_PRIVATE
		)
	_check(
		private_preparation,
		"低凝聚力时军事通行不得把接壤兄弟藩王从AI私战候选中删掉"
	)

	var simulation := Simulation.new()
	simulation.setup(state)
	var target_city := _border_target(state, attacker, defender)
	_check(target_city >= 0, "测试夹具必须存在相邻的兄弟藩王城市")
	var changed := simulation._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.DECLARE_WAR,
		"a": attacker,
		"b": defender,
		"objective_city": target_city,
		"objective_reason": "私人领土诉求",
		"war_scope": GameState.WarScope.VASSAL_PRIVATE,
		"mobilization_armies": 0,
		"reason": "低凝聚力藩王私人战争测试",
	}, {}, [])
	_check(changed, "合法私人宣战必须提交成功")
	_check(state.is_enemy(attacker, defender), "私人战争双方必须进入战争")
	_check(
		not state.is_enemy(root, defender)
			and not state.is_enemy(root, attacker),
		"私人战争不得把宗主拖入战争"
	)
	_check(
		state.is_private_war(attacker, defender),
		"私人战争目标必须保存 VASSAL_PRIVATE 作用域"
	)
	_check(
		int(state.diplomatic_history[-1].get("war_scope", -1))
			== GameState.WarScope.VASSAL_PRIVATE,
		"外交历史必须记录私人战争作用域"
	)
	simulation._normalize_alliance_wars()
	_check(
		not state.is_enemy(root, defender),
		"联盟战争归一化不得传播私人战争"
	)
	var capture := state.transfer_city_control(
		target_city,
		attacker,
		attacker,
		GameState.TerritoryStockDisposition.CAPTURE_SPOILS,
		"private_war_test_capture"
	)
	_check(bool(capture.get("changed", false)), "私人战争测试占领必须成功")
	state.day = DiplomacyAI.MIN_WAR_DAYS + 1
	var peace := simulation._make_coalition_peace(attacker, defender)
	_check(bool(peace.get("changed", false)), "私人战争必须能单独议和")
	_check(
		state.relation_between(attacker, defender)
			== GameState.DiplomaticRelation.NEUTRAL,
		"私人议和必须结束宣战藩王与目标国的战争"
	)
	_check(
		state.is_allied(root, attacker) and state.is_allied(root, defender),
		"私人议和不得改动宗主与其他藩王的宗藩盟约"
	)
	_check(
		state.recognized_owner_of(target_city) == attacker,
		("私人战争获胜领土必须确认给实际作战藩王（实控%d 法理%d 转移%d）"
			% [
				state.cities[target_city].owner_nation,
				state.recognized_owner_of(target_city),
				int(peace.get("territories_transferred", -1)),
			])
	)
	state.set_diplomatic_relation(
		attacker, defender, GameState.DiplomaticRelation.ALLIED
	)
	var prepare_action := {
		"objective_city": state.land_cities_of(defender)[0].id,
		"objective_reason": "作用域传递测试",
		"war_scope": GameState.WarScope.VASSAL_PRIVATE,
		"mobilization_armies": 0,
	}
	_check(
		simulation._start_war_preparation(attacker, defender, prepare_action)
			and state.nations[attacker].war_preparation_scope
				== GameState.WarScope.VASSAL_PRIVATE,
		"私人作用域必须随备战状态持久化"
	)
	simulation._clear_war_preparation(attacker)
	_check(
		state.can_declare_private_war(attacker, outsider),
		"低凝聚力藩王也应能向体系外中立国家发动私人战争"
	)
	var external_changed := simulation._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.DECLARE_WAR,
		"a": attacker,
		"b": outsider,
		"objective_city": -1,
		"objective_reason": "提交前目标失效",
		"war_scope": GameState.WarScope.VASSAL_PRIVATE,
		"mobilization_armies": 0,
		"reason": "无有效目标的作用域隔离测试",
	}, {}, [])
	_check(
		external_changed and state.is_private_war(attacker, outsider),
		"目标城失效不得让私人战争丢失双边作用域"
	)
	simulation._normalize_alliance_wars()
	_check(
		not state.is_enemy(root, outsider),
		"体系外私人战争也不得在联盟归一化时拖入宗主"
	)
	simulation.free()
	_finish()


func _border_target(state: GameState, attacker: int, defender: int) -> int:
	for city in state.land_cities_of(defender):
		for neighbor_id in state.neighbors(city.id):
			var edge := state.edge_of(city.id, neighbor_id)
			if (
				state.cities[neighbor_id].owner_nation == attacker
				and edge != null
				and edge.max_manpower > 0
			):
				return city.id
	return -1


func _fixture() -> Dictionary:
	var state := GameState.new()
	state.generate_grid_world(95001)
	var attacker := -1
	var defender := -1
	for edge in state.edges:
		var owner_a := state.cities[edge.city_a].owner_nation
		var owner_b := state.cities[edge.city_b].owner_nation
		if owner_a != owner_b:
			attacker = owner_a
			defender = owner_b
			break
	var remaining: Array[int] = []
	for nation in state.nations:
		if nation.id not in [attacker, defender]:
			remaining.append(nation.id)
	var root := remaining[0]
	var outsider := remaining[1]
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	state.suzerainty = {
		attacker: {
			"overlord_id": root,
			"tribute_rate": 0.2,
			"created_day": 0,
			"last_centralization_day": -1,
			"civil_war": false,
		},
		defender: {
			"overlord_id": root,
			"tribute_rate": 0.2,
			"created_day": 0,
			"last_centralization_day": -1,
			"civil_war": false,
		},
	}
	state.set_diplomatic_relation(root, attacker, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(root, defender, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(attacker, defender, GameState.DiplomaticRelation.ALLIED)
	state.ownership_revision += 1
	return {
		"state": state,
		"root": root,
		"attacker": attacker,
		"defender": defender,
		"outsider": outsider,
	}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("VASSAL_COHESION_PRIVATE_WAR_OK checks=", _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("VASSAL_COHESION_PRIVATE_WAR_FAIL: " + failure)
	quit(1)
