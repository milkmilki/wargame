extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_military_routes_only_include_live_war_orders()
	_test_route_style_preserves_posture_and_merge_state()
	_test_groups_assigned_to_same_war_share_corridor()
	if _failures.is_empty():
		print("MILITARY_MAP_MODE: 3 passed")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _base_state() -> GameState:
	var state := GameState.new()
	state.generate_grid_world(94621)
	for a in range(state.nations.size()):
		state.nations[a].battle_groups.clear()
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				a, b, GameState.DiplomaticRelation.NEUTRAL
			)
	return state


func _test_military_routes_only_include_live_war_orders() -> void:
	var state := _base_state()
	var attacker := state.create_battle_group(0)
	attacker.posture = BattleGroup.Posture.ATTACK
	attacker.target_nation = 1
	attacker.route = [0, 1] as Array[int]
	var peace_group := state.create_battle_group(0)
	peace_group.posture = BattleGroup.Posture.PEACE
	peace_group.route = [1, 0] as Array[int]
	_check(
		MapRenderer.military_route_records(state).is_empty(),
		"未交战国家的军团路线不得出现在军事地图"
	)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var routes := MapRenderer.military_route_records(state)
	_check(
		routes.size() == 1
			and int(routes[0].get("owner_nation", -1)) == 0
			and routes[0].get("city_path", []) == [0, 1],
		"军事地图必须只返回交战中的进攻或防守路线"
	)


func _test_route_style_preserves_posture_and_merge_state() -> void:
	var state := _base_state()
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var attack := state.create_battle_group(0)
	attack.posture = BattleGroup.Posture.ATTACK
	attack.target_nation = 1
	attack.route = [0, 1] as Array[int]
	attack.merge_group_owner = 2
	attack.merge_group_id = 4
	var defend := state.create_battle_group(1)
	defend.posture = BattleGroup.Posture.ATTACK
	defend.target_nation = 0
	defend.route = [1, 0] as Array[int]
	var routes := MapRenderer.military_route_records(state)
	_check(routes.size() == 2, "军事地图必须同时显示攻势和防守路线")
	var attack_record: Dictionary = routes[0]
	var defend_record: Dictionary = routes[1]
	_check(
		bool(attack_record.get("merged", false))
			and not bool(attack_record.get("dashed", false))
			and int(attack_record.get("posture", -1))
				== BattleGroup.Posture.ATTACK,
		"汇流进攻路线必须保留进攻语义和汇流标记"
	)
	_check(
		not bool(defend_record.get("dashed", false))
			and int(defend_record.get("posture", -1))
				== BattleGroup.Posture.ATTACK
			and str(attack_record.get("corridor_key", ""))
				== str(defend_record.get("corridor_key", "")),
		"交战双方的反向军团路线必须映射到同一条战争走廊"
	)


func _test_groups_assigned_to_same_war_share_corridor() -> void:
	var state := _base_state()
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	for lane in range(2):
		var group := state.create_battle_group(0)
		group.posture = BattleGroup.Posture.ATTACK
		group.target_nation = 1
		group.corridor_lane = -1
		group.route = [0, 1] as Array[int]
	var routes := MapRenderer.military_route_records(state)
	_check(
		routes.size() == 2
			and str(routes[0].get("corridor_key", ""))
				== str(routes[1].get("corridor_key", "")),
		"分配到同一战争方向的多个1.5万人军团必须共用同一条首都走廊"
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
