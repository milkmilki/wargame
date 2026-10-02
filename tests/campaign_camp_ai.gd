extends SceneTree

var _failures: Array[String] = []
var _checks: int = 0


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(94145)
	var context := _attack_context(state)
	_check(not context.is_empty(), "夹具必须找到可从陆路或本地渡口进入的大州")
	if context.is_empty():
		_finish()
		return
	var center_id := int(context["center"])
	var entry_id := int(context["entry"])
	var staging_id := int(context["staging"])
	var attacker_id := int(context["attacker"])
	var defender_id := int(context["defender"])
	_neutralize_diplomacy(state)
	state.set_diplomatic_relation(
		attacker_id, defender_id, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.set_war_objective(
		attacker_id, defender_id, center_id, "集结大营门禁"
	)
	for city in state.cities:
		if (
			city.politically_active
			and state.administrative_center_of(city.id) != center_id
		):
			city.owner_nation = attacker_id
	for member_id in state.administrative_members(center_id):
		state.cities[member_id].owner_nation = defender_id
	state.cities[staging_id].owner_nation = attacker_id
	state.cities[center_id].garrison_manpower = 15000
	state.armies.clear()
	state.battles.clear()
	var defender := _army(941450, defender_id, center_id, 12000)
	state.armies.append(defender)
	var attackers: Array[Army] = []
	for index in range(6):
		var location := staging_id if index == 0 else state.nations[attacker_id].capital_city_id
		var army := _army(941451 + index, attacker_id, location, 15000)
		army.campaign_war_id = war_id
		state.armies.append(army)
		attackers.append(army)
	state.ownership_revision += 1
	state.refresh_derived()
	var plan := CoalitionCampaignFront.new()
	plan.mode = CoalitionCampaignFront.Mode.OFFENSE
	plan.war_id = war_id
	plan.center_city_id = center_id
	for army in attackers:
		plan.army_assignments[army.id] = center_id
	state.register_campaign_front(plan, [attacker_id] as Array[int], attacker_id)
	var sim := Simulation.new()
	sim.setup(state)

	_check(
		state.campaign_minimum_launch_requirement(attacker_id, center_id) == 27000,
		"最低出发兵力必须等于虚拟守军G加州内有效敌军V"
	)
	sim._manage_administrative_campaign(plan)
	entry_id = int(plan.tactical_target_city_ids[0])
	staging_id = plan.staging_city_id
	_check(plan.phase == CoalitionCampaignFront.Phase.ASSEMBLE, "未到齐时必须继续集结")
	_check(staging_id >= 0, "计划必须记录真实入口集结点")
	_check(plan.camp_city_id == -1, "普通入口府战役不得提前建立后方大营")
	_check(_all_assigned_to(plan, attackers, staging_id), "集结阶段所有战区军必须前往同一集结点")

	for army in attackers:
		_place_idle(army, staging_id)
	sim._manage_administrative_campaign(plan)
	_check(plan.phase == CoalitionCampaignFront.Phase.BREAK_IN, "到场C达到G+V后必须进入破口")
	_check(_all_assigned_to(plan, attackers, entry_id), "破口时全军必须攻击同一入口府")
	defender.size = 30000
	sim._manage_administrative_campaign(plan)
	_check(plan.phase == CoalitionCampaignFront.Phase.BREAK_IN, "发动后V上升不得退回集结")

	defender.size = 12000
	state.cities[entry_id].owner_nation = attacker_id
	# Keep this fixture below the current center-assault requirement so it
	# continues to exercise detachment creation rather than the ready-camp path.
	state.cities[center_id].garrison_manpower = 60000
	state.ownership_revision += 1
	for army in attackers:
		_place_idle(army, entry_id)
	sim._manage_administrative_campaign(plan)
	_check(plan.phase == CoalitionCampaignFront.Phase.RAID_FU, "入口府易手后必须建立大营并分遣占府")
	_check(plan.camp_city_id == entry_id, "入口府必须成为大营")
	_check(plan.tactical_target_city_ids.size() <= 2, "同时最多只能有两个属府目标")
	_check(
		_assigned_manpower(plan, attackers, plan.camp_city_id) >= 30000,
		"六军破口后大营必须按总有效C的三分之一留守（大营%d，分配%s）" % [
			plan.camp_city_id, str(plan.army_assignments),
		]
	)

	var reinforcement := _army(
		941457, attacker_id, state.nations[attacker_id].capital_city_id, 15000
	)
	reinforcement.campaign_war_id = war_id
	state.armies.append(reinforcement)
	plan.army_assignments[reinforcement.id] = entry_id
	sim._manage_administrative_campaign(plan)
	_check(int(plan.army_assignments.get(reinforcement.id, -1)) == entry_id, "新增援军必须默认前往大营")

	if not plan.tactical_target_city_ids.is_empty():
		var captured_target := int(plan.tactical_target_city_ids[0])
		var group_ids: Array[int] = []
		for army in attackers:
			if int(plan.army_assignments.get(army.id, -1)) == captured_target:
				group_ids.append(army.id)
				_place_idle(army, captured_target)
		state.cities[captured_target].owner_nation = attacker_id
		state.ownership_revision += 1
		sim._manage_administrative_campaign(plan)
		if not group_ids.is_empty():
			var next_target := int(plan.army_assignments.get(group_ids[0], -1))
			for army_id in group_ids:
				_check(
					int(plan.army_assignments.get(army_id, -1)) == next_target,
					"同一分遣队完成目标后必须整组转向下一府"
				)

	_check(
		sim._defense_sortie_target_city(defender_id, center_id) == entry_id,
		"已有大营时防守出击必须瞄准大营而非属府分遣队"
	)
	# Defense must assemble at its real receiving point before launching.
	# Keep a direct legal sortie corridor for this camp-recall fixture.
	state._add_edge(center_id, entry_id)
	var sortie_origin := center_id
	_place_idle(defender, sortie_origin)
	for index in range(8):
		state.armies.append(_army(941460 + index, defender_id, sortie_origin, 15000))
	for _cycle in range(3):
		sim._manage_coalition_campaigns()
		state.day += Simulation.AI_DECISION_INTERVAL_DAYS
	var defense_plan := state.campaign_front_for(defender_id, center_id)
	_check(
		sim._coalition_campaign_wake_day <= state.day,
		"防守军攻击大营后必须强制进攻方在下一日重算（阶段%s，目标%s）" % [
			str(defense_plan.phase if defense_plan != null else -1),
			str(defense_plan.army_assignments if defense_plan != null else {}),
		]
	)
	for army in attackers + [reinforcement]:
		_place_idle(army, int(plan.army_assignments.get(army.id, entry_id)))
	# Arrival at the camp, rather than an attack intention alone, is the
	# existing trigger for recalling detachments.
	_place_idle(defender, entry_id)
	sim._manage_administrative_campaign(plan)
	_check(plan.phase == CoalitionCampaignFront.Phase.RECALL_CAMP, "大营受威胁时必须进入全军回援")
	for army in attackers + [reinforcement]:
		_check(int(plan.army_assignments.get(army.id, -1)) == entry_id, "回援阶段所有空闲分遣军必须转向大营")

	state.cities[entry_id].owner_nation = defender_id
	state.ownership_revision += 1
	sim._manage_administrative_campaign(plan)
	_check(plan.camp_city_id == -1, "大营失守后必须清除大营状态")
	_check(state.campaign_front(plan.front_id) == null, "大营失守后必须释放旧战线")
	_check(state.campaign_offensive_cooldown_until(plan.war_id, plan.participant_nation_ids) == state.day + 60,
		"大营失守后集团新进攻线必须进入60天失败冷却")

	var fronts: Dictionary = NativeSnapshotBuilder.build(state)["campaign_fronts"]
	var plan_index := (fronts["front_ids"] as PackedInt32Array).find(plan.front_id)
	_check(plan_index < 0, "原生快照不得保留已释放的失败州计划")
	sim.free()
	_test_blocked_fu_fallback(false, 4)
	_test_blocked_fu_fallback(true, 4)
	_test_blocked_fu_fallback(false, 1)
	_test_ready_camp_bypasses_remaining_fu()
	_test_two_hop_camp_assault()
	_test_camp_threat_requires_battle()
	_test_hold_camp_reinforcement_advance()
	_test_cleanup_releases_when_fu_unreachable()
	_finish()


func _test_camp_threat_requires_battle() -> void:
	var state := GameState.new()
	state.generate_grid_world(95213)
	var context := _attack_context(state)
	_check(not context.is_empty(), "威胁判定夹具必须找到大州")
	if context.is_empty():
		return
	var center_id := int(context["center"])
	var entry_id := int(context["entry"])
	var staging_id := int(context["staging"])
	var attacker_id := int(context["attacker"])
	var defender_id := int(context["defender"])
	_neutralize_diplomacy(state)
	state.set_diplomatic_relation(
		attacker_id, defender_id, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.set_war_objective(
		attacker_id, defender_id, center_id, "大营威胁判定门禁"
	)
	for city in state.cities:
		if (
			city.politically_active
			and state.administrative_center_of(city.id) != center_id
		):
			city.owner_nation = attacker_id
	for member_id in state.administrative_members(center_id):
		state.cities[member_id].owner_nation = defender_id
	state.cities[entry_id].owner_nation = attacker_id
	state.cities[center_id].garrison_manpower = 60000
	state.armies.clear()
	state.battles.clear()
	state.ownership_revision += 1
	state.refresh_derived()
	var attackers: Array[Army] = []
	for index in range(4):
		var army := _army(952120 + index, attacker_id, entry_id, 15000)
		army.campaign_war_id = war_id
		state.armies.append(army)
		attackers.append(army)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	var plan := CoalitionCampaignFront.new()
	plan.mode = CoalitionCampaignFront.Mode.OFFENSE
	plan.war_id = war_id
	plan.center_city_id = center_id
	plan.camp_city_id = entry_id
	plan.phase = CoalitionCampaignFront.Phase.RAID_FU
	plan.tactical_target_city_ids = [center_id] as Array[int]
	for army in attackers:
		plan.army_assignments[army.id] = entry_id
	state.register_campaign_front(plan, [attacker_id] as Array[int], attacker_id)
	# 敌军只是把大营设为行军目标（意图），人还在邻城，没有开战：不得回防。
	var intending := _army(952124, defender_id, staging_id, 15000)
	intending.ai_target_city = entry_id
	state.armies.append(intending)
	_check(
		not sim._campaign_camp_threatened(attacker_id, entry_id),
		"敌军仅把大营设为行军目标时不得判定为威胁"
	)
	sim._manage_administrative_campaign(plan)
	_check(
		plan.phase != CoalitionCampaignFront.Phase.RECALL_CAMP,
		"敌军仅有攻营意图时战线不得进入全军回援（阶段%s）" % str(plan.phase)
	)
	# 敌军真的进入大营城内时才触发全军回援。
	_place_idle(intending, entry_id)
	_check(
		sim._campaign_camp_threatened(attacker_id, entry_id),
		"敌军进入大营城内后必须判定为威胁"
	)
	sim._manage_administrative_campaign(plan)
	_check(
		plan.phase == CoalitionCampaignFront.Phase.RECALL_CAMP,
		"大营真正开战后战线必须进入全军回援（阶段%s）" % str(plan.phase)
	)
	sim.free()


func _test_hold_camp_reinforcement_advance() -> void:
	var state := GameState.new()
	state.generate_grid_world(94145)
	var context := _attack_context(state)
	_check(not context.is_empty(), "驻营援军夹具必须找到大州")
	if context.is_empty():
		return
	var center_id := int(context["center"])
	var entry_id := int(context["entry"])
	var attacker_id := int(context["attacker"])
	var defender_id := int(context["defender"])
	_neutralize_diplomacy(state)
	state.set_diplomatic_relation(
		attacker_id, defender_id, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.set_war_objective(
		attacker_id, defender_id, center_id, "驻营援军门禁"
	)
	for city in state.cities:
		if (
			city.politically_active
			and state.administrative_center_of(city.id) != center_id
		):
			city.owner_nation = attacker_id
	for member_id in state.administrative_members(center_id):
		state.cities[member_id].owner_nation = attacker_id
	state.cities[center_id].owner_nation = defender_id
	state.cities[center_id].garrison_manpower = 60000
	state.armies.clear()
	state.battles.clear()
	state.ownership_revision += 1
	state.refresh_derived()
	var camp_force: Array[Army] = []
	for index in range(3):
		var army := _army(962001 + index, attacker_id, entry_id, 15000)
		army.campaign_war_id = war_id
		state.armies.append(army)
		camp_force.append(army)
	var reinforcement := _army(
		962004, attacker_id, state.nations[attacker_id].capital_city_id, 15000
	)
	reinforcement.campaign_war_id = war_id
	state.armies.append(reinforcement)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	var plan := CoalitionCampaignFront.new()
	plan.mode = CoalitionCampaignFront.Mode.OFFENSE
	plan.war_id = war_id
	plan.center_city_id = center_id
	plan.camp_city_id = entry_id
	plan.phase = CoalitionCampaignFront.Phase.HOLD_CAMP
	plan.staging_city_id = int(
		DiplomacyAI.war_staging_cities_for_objective(
			state, attacker_id, entry_id
		)[0]
	)
	for army in camp_force:
		plan.army_assignments[army.id] = entry_id
	state.register_campaign_front(plan, [attacker_id] as Array[int], attacker_id)
	var component: Dictionary = {}
	for candidate in state.coalition_campaign_components(war_id):
		if (candidate["members"] as Array[int]).has(attacker_id):
			component = candidate
			break
	_check(not component.is_empty(), "驻营援军夹具必须找到战争连通分量")
	if component.is_empty():
		sim.free()
		return
	sim._plan_coalition_component(component, [] as Array[int], {})
	_check(
		reinforcement.campaign_front_id == plan.front_id,
		"分配器必须把空闲援军编入战线"
	)
	_check(
		reinforcement.ai_target_city == entry_id,
		"驻营阶段新援军必须被派往大营（实际 ai_target=%d）"
			% reinforcement.ai_target_city
	)
	_place_idle(reinforcement, entry_id)
	sim._manage_administrative_campaign(plan)
	_check(
		plan.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER,
		"援军抵达大营后必须发动第二波（阶段%d）" % plan.phase
	)
	sim.free()


func _test_cleanup_releases_when_fu_unreachable() -> void:
	var state := GameState.new()
	state.generate_grid_world(94145)
	var context := _attack_context(state)
	_check(not context.is_empty(), "肃清收尾夹具必须找到大州")
	if context.is_empty():
		return
	var center_id := int(context["center"])
	var entry_id := int(context["entry"])
	var attacker_id := int(context["attacker"])
	var defender_id := int(context["defender"])
	var neutral_id := -1
	for nation in state.nations:
		if nation.id not in [attacker_id, defender_id]:
			neutral_id = nation.id
			break
	_neutralize_diplomacy(state)
	state.set_diplomatic_relation(
		attacker_id, defender_id, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.set_war_objective(
		attacker_id, defender_id, center_id, "肃清收尾门禁"
	)
	for city in state.cities:
		if (
			city.politically_active
			and state.administrative_center_of(city.id) != center_id
		):
			city.owner_nation = attacker_id
	var members: Array[int] = state.administrative_members(center_id)
	for member_id in members:
		state.cities[member_id].owner_nation = attacker_id
	# 一个被中立领土包围的不可达属府，一个留有己方边境邻居的可达属府。
	var locked_fu := -1
	for member_id in members:
		if member_id in [center_id, entry_id]:
			continue
		var adjacent_center := false
		var adjacent_entry := false
		for neighbor_id in state.neighbors(member_id):
			if neighbor_id == center_id:
				adjacent_center = true
			if neighbor_id == entry_id:
				adjacent_entry = true
		if not adjacent_center and not adjacent_entry:
			locked_fu = member_id
			break
	state.cities[locked_fu].owner_nation = defender_id
	for neighbor_id in state.neighbors(locked_fu):
		if neighbor_id != center_id and neighbor_id != entry_id:
			state.cities[neighbor_id].owner_nation = neutral_id
	var reachable_fu := -1
	for member_id in members:
		if member_id in [center_id, entry_id, locked_fu]:
			continue
		for neighbor_id in state.neighbors(member_id):
			if state.administrative_center_of(neighbor_id) != center_id:
				reachable_fu = member_id
				break
		if reachable_fu >= 0:
			break
	state.cities[reachable_fu].owner_nation = defender_id
	state.armies.clear()
	state.battles.clear()
	state.ownership_revision += 1
	state.refresh_derived()
	for index in range(3):
		var army := _army(962101 + index, attacker_id, center_id, 15000)
		army.campaign_war_id = war_id
		state.armies.append(army)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	var plan := CoalitionCampaignFront.new()
	plan.mode = CoalitionCampaignFront.Mode.OFFENSE
	plan.war_id = war_id
	plan.center_city_id = center_id
	plan.camp_city_id = entry_id
	plan.phase = CoalitionCampaignFront.Phase.CLEANUP
	plan.tactical_target_city_ids = [center_id] as Array[int]
	for army in state.armies:
		plan.army_assignments[army.id] = center_id
	state.register_campaign_front(plan, [attacker_id] as Array[int], attacker_id)
	sim._manage_administrative_campaign(plan)
	_check(
		state.campaign_front(plan.front_id) != null,
		"尚有可达敌方属府时肃清战线必须继续存在"
	)
	_check(
		plan.tactical_target_city_ids.has(reachable_fu),
		"可达敌方属府必须被列为肃清目标（目标=%s）"
			% str(plan.tactical_target_city_ids)
	)
	state.cities[reachable_fu].owner_nation = attacker_id
	state.ownership_revision += 1
	sim._manage_administrative_campaign(plan)
	_check(
		state.campaign_front(plan.front_id) == null,
		"剩余敌方属府全部不可达时必须当场释放战线"
	)
	for army in state.armies:
		_check(
			army.campaign_front_id == -1,
			"战线释放后全部军队必须解绑"
		)
	var component: Dictionary = {}
	for candidate in state.coalition_campaign_components(war_id):
		if (candidate["members"] as Array[int]).has(attacker_id):
			component = candidate
			break
	if not component.is_empty():
		_check(
			not sim._component_objective_is_valid(
				center_id,
				component["enemy_ids"] as Array[int],
				component["members"] as Array[int],
				{}
			),
			"已夺取州治不得再成为合法战线目标"
		)
	sim.free()


func _attack_context(state: GameState) -> Dictionary:
	var centers: Array[int] = []
	for center_value in state.administrative_center_city_ids:
		centers.append(int(center_value))
	centers.sort_custom(func(a: int, b: int) -> bool:
		return state.administrative_members(a).size() > state.administrative_members(b).size()
	)
	for center_id in centers:
		if state.administrative_members(center_id).size() < 6:
			continue
		var defender_id := state.cities[center_id].owner_nation
		for member_id in state.administrative_members(center_id):
			if member_id == center_id:
				continue
			for neighbor_id in state.neighbors(member_id):
				if state.administrative_center_of(neighbor_id) == center_id:
					continue
				var attacker_id := state.cities[neighbor_id].owner_nation
				if attacker_id >= 0 and attacker_id != defender_id:
					return {
						"center": center_id,
						"entry": member_id,
						"staging": neighbor_id,
						"attacker": attacker_id,
						"defender": defender_id,
					}
	return {}


func _neutralize_diplomacy(state: GameState) -> void:
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)


func _test_blocked_fu_fallback(
	unreachable_frontier: bool,
	army_count: int
) -> void:
	var state := GameState.new()
	state.generate_grid_world(95200 + (1 if unreachable_frontier else 0))
	var context := _attack_context(state)
	_check(not context.is_empty(), "阻断府夹具必须找到大州")
	if context.is_empty():
		return
	var center_id := int(context["center"])
	var camp_id := int(context["entry"])
	var attacker_id := int(context["attacker"])
	var defender_id := int(context["defender"])
	var other_fu: Array[int] = []
	for member_id in state.administrative_members(center_id):
		if member_id not in [center_id, camp_id]:
			other_fu.append(member_id)
	_check(other_fu.size() >= 2, "阻断府夹具至少需要三个府")
	if other_fu.size() < 2:
		return
	var target_id := other_fu[0]
	var isolated_staging_id := other_fu[1]
	_neutralize_diplomacy(state)
	state.set_diplomatic_relation(
		attacker_id, defender_id, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.set_war_objective(
		attacker_id, defender_id, center_id, "州治阻断府回归"
	)
	for city in state.cities:
		city.owner_nation = attacker_id
	for member_id in state.administrative_members(center_id):
		state.cities[member_id].owner_nation = attacker_id
	state.cities[center_id].owner_nation = defender_id
	state.cities[target_id].owner_nation = defender_id
	state.cities[center_id].garrison_manpower = 15000
	state.armies.clear()
	state.battles.clear()
	var attackers: Array[Army] = []
	for index in range(army_count):
		var army := _army(95210 + index, attacker_id, camp_id, 15000)
		army.campaign_war_id = war_id
		state.armies.append(army)
		attackers.append(army)
	state.ownership_revision += 1
	state.refresh_derived()
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	for edge in state.edges:
		if (
			edge.city_a in [target_id, isolated_staging_id]
			or edge.city_b in [target_id, isolated_staging_id]
		):
			edge.max_manpower = 0
	_enable_edge(state, camp_id, center_id)
	_enable_edge(state, center_id, target_id)
	if unreachable_frontier:
		_enable_edge(state, center_id, isolated_staging_id)
		_enable_edge(state, target_id, isolated_staging_id)
	state.road_network_revision += 1
	var plan := CoalitionCampaignFront.new()
	plan.mode = CoalitionCampaignFront.Mode.OFFENSE
	plan.phase = CoalitionCampaignFront.Phase.RAID_FU
	plan.war_id = war_id
	plan.center_city_id = center_id
	plan.camp_city_id = camp_id
	for army in attackers:
		plan.army_assignments[army.id] = camp_id
	state.register_campaign_front(plan, [attacker_id] as Array[int], attacker_id)
	sim._manage_administrative_campaign(plan)
	var label := "不可达前沿府" if unreachable_frontier else "无前沿府"
	if army_count >= 4:
		_check(
			plan.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER,
			"%s且C满足R+V时必须改攻州治，不能卡在占府阶段" % label
		)
		_check(
			_all_assigned_to(plan, attackers, center_id),
			"%s降级攻州治时全部战区军必须直接向州治进军" % label
		)
	else:
		_check(
			plan.phase == CoalitionCampaignFront.Phase.HOLD_CAMP,
			"%s且C不足R+V时必须驻营等待" % label
		)
		_check(
			_all_assigned_to(plan, attackers, camp_id),
			"%s驻营等待时不得误派军队强攻州治" % label
		)
	sim.free()


func _test_ready_camp_bypasses_remaining_fu() -> void:
	var state := GameState.new()
	state.generate_grid_world(95209)
	var context := _attack_context(state)
	_check(not context.is_empty(), "营内主力攻州治夹具必须找到大州")
	if context.is_empty():
		return
	var center_id := int(context["center"])
	var camp_id := int(context["entry"])
	var staging_id := int(context["staging"])
	var attacker_id := int(context["attacker"])
	var defender_id := int(context["defender"])
	_neutralize_diplomacy(state)
	state.set_diplomatic_relation(
		attacker_id, defender_id, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.set_war_objective(
		attacker_id, defender_id, center_id, "营内主力转攻州治"
	)
	for city in state.cities:
		if not city.is_dock:
			city.owner_nation = attacker_id
	for member_id in state.administrative_members(center_id):
		state.cities[member_id].owner_nation = defender_id
	state.cities[camp_id].owner_nation = attacker_id
	state.cities[center_id].garrison_manpower = 15000
	# This case exercises a ready camp bypassing remaining Fu, not an attack
	# through hostile intermediate cities. Give it a legal center approach.
	_enable_edge(state, camp_id, center_id)
	state.road_network_revision += 1
	state.armies.clear()
	state.battles.clear()
	var attackers: Array[Army] = []
	for index in range(4):
		var army := _army(952090 + index, attacker_id, camp_id, 15000)
		army.campaign_war_id = war_id
		state.armies.append(army)
		attackers.append(army)
	var defeated_detachment := _army(952094, attacker_id, camp_id, 3000)
	defeated_detachment.campaign_war_id = war_id
	defeated_detachment.state = Army.State.RECOVERING
	defeated_detachment.morale = 0.0
	state.armies.append(defeated_detachment)
	state.ownership_revision += 1
	state.refresh_derived()
	var attacker_bloc := state.alliance_bloc(attacker_id)
	var plan := CoalitionCampaignFront.new()
	plan.mode = CoalitionCampaignFront.Mode.OFFENSE
	plan.phase = CoalitionCampaignFront.Phase.RAID_FU
	plan.war_id = war_id
	plan.center_city_id = center_id
	plan.camp_city_id = camp_id
	for army in attackers:
		plan.army_assignments[army.id] = camp_id
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	var frontier_targets := sim._zhou_enemy_fu_targets(
		attacker_id, center_id, attacker_bloc, true
	)
	_check(not frontier_targets.is_empty(), "夹具必须保留可达的敌方前沿府")
	if frontier_targets.is_empty():
		sim.free()
		return
	plan.tactical_target_city_ids = [frontier_targets[0]] as Array[int]
	plan.army_assignments[defeated_detachment.id] = frontier_targets[0]
	state.register_campaign_front(plan, [attacker_id] as Array[int], attacker_id)
	var requirement := (
		state.campaign_siege_requirement(attacker_id, center_id)
		+ state.campaign_reinforcement_threat(attacker_id, center_id)
	)
	_check(requirement <= 60000, "夹具中营内实际C必须满足当前R+V")
	sim._manage_administrative_campaign(plan)
	_check(
		plan.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER,
		"营内实际C满足R+V时必须跳过剩余属府并转攻州治"
	)
	_check(
		plan.tactical_target_city_ids == [center_id],
		"转攻州治后不得保留属府分遣目标"
	)
	_check(
		int(plan.army_assignments.get(defeated_detachment.id, -1)) == center_id,
		"恢复中的败退分遣队也必须清除旧属府绑定并改为追随州治主力"
	)
	for army in attackers:
		_place_idle(army, staging_id)
	sim._manage_administrative_campaign(plan)
	_check(
		plan.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER,
		"州治进攻发动后不得因大营到场C下降而退回分遣占府"
	)
	_check(
		plan.tactical_target_city_ids == [center_id],
		"已发动的州治进攻必须继续以州治为唯一目标"
	)
	sim.free()


func _test_two_hop_camp_assault() -> void:
	var state := GameState.new()
	state.generate_grid_world(95202)
	var center_id := -1
	var camp_id := -1
	var middle_id := -1
	for center_value in state.administrative_center_city_ids:
		var candidate_center := int(center_value)
		var members := state.administrative_members(candidate_center)
		for candidate_camp in members:
			if candidate_camp == candidate_center:
				continue
			for candidate_middle in members:
				if candidate_middle in [candidate_center, candidate_camp]:
					continue
				if (
					state.edge_of(candidate_camp, candidate_middle) != null
					and state.edge_of(candidate_middle, candidate_center) != null
					and state.edge_of(candidate_camp, candidate_center) == null
				):
					center_id = candidate_center
					camp_id = candidate_camp
					middle_id = candidate_middle
					break
			if center_id >= 0:
				break
		if center_id >= 0:
			break
	_check(center_id >= 0, "两跳大营夹具必须找到府—府—州治链")
	if center_id < 0:
		return
	var attacker_id := 0
	var defender_id := 1
	_neutralize_diplomacy(state)
	state.set_diplomatic_relation(
		attacker_id, defender_id, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.set_war_objective(
		attacker_id, defender_id, center_id, "两跳大营攻州治门禁"
	)
	for city in state.cities:
		if not city.is_dock:
			city.owner_nation = attacker_id
	for member_id in state.administrative_members(center_id):
		state.cities[member_id].owner_nation = attacker_id
	state.cities[center_id].owner_nation = defender_id
	state.cities[center_id].garrison_manpower = 15000
	for edge in state.edges:
		if (
			edge.city_a in [camp_id, center_id]
			or edge.city_b in [camp_id, center_id]
		):
			edge.max_manpower = 0
	_enable_edge(state, camp_id, middle_id)
	_enable_edge(state, middle_id, center_id)
	state.road_network_revision += 1
	state.armies.clear()
	state.battles.clear()
	var attackers: Array[Army] = []
	for index in range(4):
		var army := _army(95300 + index, attacker_id, camp_id, 15000)
		army.campaign_war_id = war_id
		state.armies.append(army)
		attackers.append(army)
	var plan := CoalitionCampaignFront.new()
	plan.mode = CoalitionCampaignFront.Mode.OFFENSE
	plan.phase = CoalitionCampaignFront.Phase.RAID_FU
	plan.war_id = war_id
	plan.center_city_id = center_id
	plan.camp_city_id = camp_id
	for army in attackers:
		plan.army_assignments[army.id] = camp_id
	state.register_campaign_front(plan, [attacker_id] as Array[int], attacker_id)
	state.ownership_revision += 1
	state.refresh_derived()
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim._manage_administrative_campaign(plan)
	_check(
		plan.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER,
		"清府后大营距州治两跳时必须进入攻州治阶段"
	)
	for army in attackers:
		_check(
			army.ai_target_city == center_id
			and army.move_from == camp_id
			and army.move_to == middle_id
			and army.path == [center_id],
			"两跳攻州治必须先走中间府并保留州治为最终路径"
		)
	var crossed_middle := false
	var reached_center := false
	for _day in range(120):
		sim._advance_day()
		for army in state.armies:
			if army.owner_nation != attacker_id or army.size <= 0:
				continue
			crossed_middle = crossed_middle or (
				army.location_city == middle_id
				or army.move_from == middle_id
			)
		for battle in state.battles:
			if battle.city != null and battle.city.id == center_id:
				reached_center = true
		reached_center = reached_center or (
			state.cities[center_id].owner_nation == attacker_id
		)
		if reached_center:
			break
	_check(crossed_middle, "两跳攻州治军队必须实际经过中间府")
	_check(reached_center, "两跳攻州治必须实际抵达州治并进入战斗或占领")
	sim.free()


func _enable_edge(state: GameState, city_a: int, city_b: int) -> void:
	var edge := state.edge_of(city_a, city_b)
	if edge == null:
		state._add_edge(city_a, city_b)
		edge = state.edge_of(city_a, city_b)
	edge.kind = Edge.Kind.LAND
	edge.max_manpower = 45000
	edge.base_max_manpower = 45000


func _army(id: int, owner_id: int, city_id: int, size: int) -> Army:
	var army := Army.new()
	army.id = id
	army.owner_nation = owner_id
	army.size = size
	army.max_size = 15000
	army.location_city = city_id
	army.move_from = city_id
	army.state = Army.State.IDLE
	army.morale = army.max_morale
	army.supply_ratio = 1.0
	return army


func _place_idle(army: Army, city_id: int) -> void:
	army.location_city = city_id
	army.move_from = city_id
	army.move_to = -1
	army.on_edge = false
	army.state = Army.State.IDLE
	army.path.clear()
	army.ai_target_city = -1


func _all_assigned_to(
	plan: CoalitionCampaignFront,
	armies: Array[Army],
	city_id: int
) -> bool:
	for army in armies:
		if int(plan.army_assignments.get(army.id, -1)) != city_id:
			return false
	return true


func _assigned_manpower(
	plan: CoalitionCampaignFront,
	armies: Array[Army],
	city_id: int
) -> int:
	var result := 0
	for army in armies:
		if int(plan.army_assignments.get(army.id, -1)) == city_id:
			result += army.size
	return result


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		push_error("CAMPAIGN_CAMP_AI_FAIL: " + failure)
	print("CAMPAIGN_CAMP_AI_%s checks=%d" % [
		"OK" if _failures.is_empty() else "FAILED", _checks,
	])
	quit(0 if _failures.is_empty() else 1)
