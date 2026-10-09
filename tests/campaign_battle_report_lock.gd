extends SceneTree
## 州战役真实野战期间锁定调兵战报，战后才以实际幸存兵力补缺。

var _failures: Array[String] = []


func _init() -> void:
	_test_parallel_battles_hold_report_until_last_finish()
	_test_rear_camp_loss_waits_for_parallel_engagements()
	_test_administrative_end_preserves_other_engagement()
	_test_campaign_battle_blocks_ad_hoc_local_reinforcement()
	if _failures.is_empty():
		print("CAMPAIGN_BATTLE_REPORT_LOCK_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("CAMPAIGN_BATTLE_REPORT_LOCK_FAILED count=%d" % _failures.size())
	quit(1)


func _test_campaign_battle_blocks_ad_hoc_local_reinforcement() -> void:
	var fixture := _fixture(96121)
	if fixture.is_empty():
		_fail("无法构造邻近增援夹具")
		return
	var state: GameState = fixture["state"]
	var sim: Simulation = fixture["sim"]
	var attacker := int(fixture["attacker"])
	var defender := int(fixture["defender"])
	var war_id := int(fixture["war_id"])
	var center_id := int(fixture["center_id"])
	var front := state.create_campaign_front(
		war_id, [attacker] as Array[int], attacker,
		CoalitionCampaignFront.Mode.OFFENSE, center_id
	)
	var participant := _army(961300, attacker, center_id)
	participant.battle_group_id = 0
	_bind(participant, front, war_id, center_id)
	var enemy := _army(961301, defender, center_id)
	enemy.battle_group_id = 0
	var reserve := _army(961302, attacker, center_id)
	reserve.battle_group_id = 1
	state.armies.append_array([participant, enemy, reserve] as Array[Army])
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city = state.cities[center_id]
	battle.siege_attacker_nation = attacker
	battle.side_a.append(participant)
	battle.side_b.append(enemy)
	battle.side_b_defends_city = true
	_check(
		sim._nearby_main_reinforcement_candidates(
			battle, attacker, {}
		).is_empty(),
		"州战役野战不得从邻近城市抽取未绑定军队"
	)
	participant.campaign_front_id = -1
	participant.campaign_war_id = -1
	front.army_assignments.erase(participant.id)
	_check(
		sim._nearby_main_reinforcement_candidates(
			battle, attacker, {}
		).is_empty(),
		"没有州战役绑定的普通遭遇战也不得绕过统一分配"
	)
	sim.free()


func _test_parallel_battles_hold_report_until_last_finish() -> void:
	var fixture := _fixture(96122)
	if fixture.is_empty():
		_fail("无法构造并行野战夹具")
		return
	var state: GameState = fixture["state"]
	var sim: Simulation = fixture["sim"]
	var attacker := int(fixture["attacker"])
	var defender := int(fixture["defender"])
	var war_id := int(fixture["war_id"])
	var center_id := int(fixture["center_id"])
	var front := state.create_campaign_front(
		war_id, [attacker] as Array[int], attacker,
		CoalitionCampaignFront.Mode.OFFENSE, center_id
	)
	var armies: Array[Army] = []
	for index in range(2):
		var army := _army(961400 + index, attacker, center_id)
		_bind(army, front, war_id, center_id)
		army.state = Army.State.FIGHTING
		state.armies.append(army)
		armies.append(army)
	var enemies: Array[Army] = []
	for index in range(2):
		var army := _army(961410 + index, defender, center_id)
		army.state = Army.State.FIGHTING
		state.armies.append(army)
		enemies.append(army)
	var first := state.new_battle(Battle.Kind.FIELD)
	first.side_a.append(armies[0])
	first.side_b.append(enemies[0])
	var second := state.new_battle(Battle.Kind.FIELD)
	second.side_a.append(armies[1])
	second.side_b.append(enemies[1])
	sim._lock_campaign_reports_for_battle(first)
	sim._lock_campaign_reports_for_battle(second)
	first.finished = true
	sim._finish_campaign_reports_for_battle(first)
	_check(front.combat_report_locked,
		"同一战线尚有第二场野战时不得提前解锁战报")
	second.finished = true
	sim._finish_campaign_reports_for_battle(second)
	_check(not front.combat_report_locked,
		"同一战线最后一场野战结束后必须解锁战报")
	sim.free()


func _test_rear_camp_loss_waits_for_parallel_engagements() -> void:
	var fixtures = preload("res://tests/direct_center_camp.gd")
	var state := fixtures.fixture()
	var first := fixtures.army(state, 0, 2)
	var second := fixtures.army(state, 0, 2)
	var front := fixtures.front(state, [first, second])
	front.camp_city_id = 2
	var sim := Simulation.new()
	sim.setup(state)
	var battles: Array[Battle] = []
	for own in [first, second]:
		var enemy := fixtures.army(state, 1, 2)
		own.state = Army.State.FIGHTING
		enemy.state = Army.State.FIGHTING
		var battle := state.new_battle(Battle.Kind.FIELD)
		battle.side_a.append(own)
		battle.side_b.append(enemy)
		own.battle_id = battle.id
		enemy.battle_id = battle.id
		sim._lock_campaign_reports_for_battle(battle)
		battles.append(battle)
	state.cities[2].owner_nation = 1
	state.ownership_revision += 1
	sim._manage_administrative_campaign(front)
	_check(front.combat_report_locked and state.campaign_front(front.front_id) != null, "后方大营失守不得解除仍有并行野战的绑定")
	battles[0].finished = true
	sim._finish_campaign_reports_for_battle(battles[0])
	sim._manage_administrative_campaign(front)
	_check(front.combat_report_locked and state.campaign_front(front.front_id) != null, "第一场结束不能提前释放后方大营战线")
	battles[1].finished = true
	sim._finish_campaign_reports_for_battle(battles[1])
	sim._manage_administrative_campaign(front)
	_check(not front.combat_report_locked and state.campaign_front(front.front_id) == null, "最后一场结束才统一上报并释放拔营失败战线")
	_check(first.campaign_war_id == front.war_id and second.campaign_war_id == front.war_id, "后方大营失败仍保留双方败军的战争池")
	sim.free()


func _test_administrative_end_preserves_other_engagement() -> void:
	var fixture := _fixture(96123)
	if fixture.is_empty():
		_fail("无法构造行政结束战报夹具")
		return
	var state: GameState = fixture["state"]
	var sim: Simulation = fixture["sim"]
	var attacker := int(fixture["attacker"])
	var defender := int(fixture["defender"])
	var center_id := int(fixture["center_id"])
	var home_id := state.nations[attacker].capital_city_id
	var front := state.create_campaign_front(
		int(fixture["war_id"]), [attacker] as Array[int], attacker,
		CoalitionCampaignFront.Mode.OFFENSE, center_id
	)
	var reserve := _army(961520, attacker, home_id)
	state.armies.append(reserve)
	var battles: Array[Battle] = []
	for index in range(2):
		var army := _army(961500 + index, attacker, home_id)
		var enemy := _army(961510 + index, defender, center_id)
		_bind(army, front, front.war_id, center_id)
		state.armies.append_array([army, enemy])
		var battle := state.new_battle(Battle.Kind.FIELD)
		sim._enter_battle(battle, army, 1)
		sim._enter_battle(battle, enemy, 2)
		sim._lock_campaign_reports_for_battle(battle)
		battles.append(battle)
	sim._finish_battle_administratively(battles[0])
	sim._finish_campaign_reports_for_battle(null)
	_check(front.combat_report_locked and not battles[1].finished,
		"行政结束一场战斗不得结束另一场野战或提前解锁")
	_check(battles[0].winner_side == 0 and battles[0].side_a.is_empty()
		and battles[0].side_b.is_empty(), "行政结束不产生胜负且必须解除参战引用")
	sim._finish_battle_administratively(battles[1])
	sim._finish_campaign_reports_for_battle(null)
	_check(not front.combat_report_locked and front.reported_effective_manpower == 30000
		and front.combat_report_day == state.day,
		"最后一场行政结束后应以未被额外扣兵的实际兵力更新战报")
	_check(sim._coalition_campaign_wake_day == state.day + 1,
		"战报更新必须请求集团次日规划，而不是当天国家规划")
	sim._allocate_coalition_fronts(_component_for(state, front.war_id, attacker))
	_check(front.army_assignments.size() == 2, "行政结束当日不得立即补充战线绑定")
	state.day += 1
	sim._allocate_coalition_fronts(_component_for(state, front.war_id, attacker))
	_check(reserve.campaign_front_id == front.front_id, "行政结束次日应恢复按实际缺口补兵")
	sim.free()


func _fixture(seed: int) -> Dictionary:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(seed, 8, 48)
	state.armies.clear()
	state.battles.clear()
	state.clear_campaign_fronts()
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	var pair := Vector2i(-1, -1)
	for contact in state.territorial_border_pairs():
		var owner_a := state.cities[contact.x].owner_nation
		var owner_b := state.cities[contact.y].owner_nation
		if owner_a >= 0 and owner_b >= 0 and owner_a != owner_b:
			pair = Vector2i(owner_a, owner_b)
			break
	if pair.x < 0:
		return {}
	state.set_diplomatic_relation(
		pair.x, pair.y, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.war_id_between(pair.x, pair.y)
	var center_id := state.administrative_center_of(
		state.nations[pair.y].capital_city_id
	)
	state.cities[center_id].garrison_manpower = 0
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	return {
		"state": state,
		"sim": sim,
		"attacker": pair.x,
		"defender": pair.y,
		"war_id": war_id,
		"center_id": center_id,
	}


func _component_for(state: GameState, war_id: int, nation_id: int) -> Dictionary:
	for component in state.coalition_campaign_components(war_id):
		if (component["members"] as Array[int]).has(nation_id):
			return component
	return {}


func _bind(
	army: Army,
	front: CoalitionCampaignFront,
	war_id: int,
	target_city_id: int
) -> void:
	army.campaign_war_id = war_id
	army.campaign_front_id = front.front_id
	army.ai_target_city = target_city_id
	front.army_assignments[army.id] = target_city_id


func _army(id: int, owner_id: int, city_id: int) -> Army:
	var army := Army.new()
	army.id = id
	army.owner_nation = owner_id
	army.size = 15000
	army.max_size = 15000
	army.location_city = city_id
	army.move_from = city_id
	army.state = Army.State.IDLE
	army.morale = army.max_morale
	army.supply_ratio = 1.0
	return army


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
