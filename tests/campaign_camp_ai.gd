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
	var plan := AdministrativeCampaignPlan.new()
	plan.mode = AdministrativeCampaignPlan.Mode.OFFENSE
	plan.war_id = war_id
	plan.opponent_nation_id = defender_id
	plan.center_city_id = center_id
	for army in attackers:
		plan.army_assignments[army.id] = center_id
	state.nations[attacker_id].administrative_campaign_plans[center_id] = plan
	var sim := Simulation.new()
	sim.setup(state)

	_check(
		state.campaign_minimum_launch_requirement(attacker_id, center_id) == 27000,
		"最低出发兵力必须等于虚拟守军G加州内有效敌军V"
	)
	sim._manage_administrative_campaign(
		attacker_id, center_id, null, null, defender_id, war_id
	)
	entry_id = int(plan.tactical_target_city_ids[0])
	staging_id = plan.staging_city_id
	_check(plan.phase == AdministrativeCampaignPlan.Phase.ASSEMBLE, "未到齐时必须继续集结")
	_check(staging_id >= 0, "计划必须记录真实入口集结点")
	_check(_all_assigned_to(plan, attackers, staging_id), "集结阶段所有战区军必须前往同一集结点")

	for army in attackers:
		_place_idle(army, staging_id)
	sim._manage_administrative_campaign(
		attacker_id, center_id, null, null, defender_id, war_id
	)
	_check(plan.phase == AdministrativeCampaignPlan.Phase.BREAK_IN, "到场C达到G+V后必须进入破口")
	_check(_all_assigned_to(plan, attackers, entry_id), "破口时全军必须攻击同一入口府")
	defender.size = 30000
	sim._manage_administrative_campaign(
		attacker_id, center_id, null, null, defender_id, war_id
	)
	_check(plan.phase == AdministrativeCampaignPlan.Phase.BREAK_IN, "发动后V上升不得退回集结")

	defender.size = 12000
	state.cities[entry_id].owner_nation = attacker_id
	state.ownership_revision += 1
	for army in attackers:
		_place_idle(army, entry_id)
	sim._manage_administrative_campaign(
		attacker_id, center_id, null, null, defender_id, war_id
	)
	_check(plan.phase == AdministrativeCampaignPlan.Phase.RAID_FU, "入口府易手后必须建立大营并分遣占府")
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
	plan.army_assignments[reinforcement.id] = center_id
	sim._manage_administrative_campaign(
		attacker_id, center_id, null, null, defender_id, war_id
	)
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
		sim._manage_administrative_campaign(
			attacker_id, center_id, null, null, defender_id, war_id
		)
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
	# Put the relief force at the camp boundary as if movement resolution had
	# just delivered it; the defense planner must target the camp and wake the
	# attacker immediately, independent of the next ten-day turn.
	var sortie_origin := entry_id
	_place_idle(defender, sortie_origin)
	for index in range(8):
		state.armies.append(_army(941460 + index, defender_id, sortie_origin, 15000))
	sim._manage_administrative_defense(defender_id, center_id, null, null)
	var defense_plan := state.campaign_plan(defender_id, center_id)
	_check(
		sim._ai_forced_nations.has(attacker_id),
		"防守军攻击大营后必须强制进攻方在下一日重算（阶段%s，目标%s）" % [
			str(defense_plan.phase if defense_plan != null else -1),
			str(defense_plan.army_assignments if defense_plan != null else {}),
		]
	)
	for army in attackers + [reinforcement]:
		_place_idle(army, int(plan.army_assignments.get(army.id, entry_id)))
	sim._manage_administrative_campaign(
		attacker_id, center_id, null, null, defender_id, war_id
	)
	_check(plan.phase == AdministrativeCampaignPlan.Phase.RECALL_CAMP, "大营受威胁时必须进入全军回援")
	for army in attackers + [reinforcement]:
		_check(int(plan.army_assignments.get(army.id, -1)) == entry_id, "回援阶段所有空闲分遣军必须转向大营")

	state.cities[entry_id].owner_nation = defender_id
	state.ownership_revision += 1
	sim._manage_administrative_campaign(
		attacker_id, center_id, null, null, defender_id, war_id
	)
	_check(plan.camp_city_id == -1, "大营失守后必须清除大营状态")
	_check(plan.failed_until_day == state.day + 60, "大营失守后必须进入60天失败冷却")

	var nations: Dictionary = NativeSnapshotBuilder.build(state)["nations"]
	var plan_index := (nations["campaign_centers"] as PackedInt32Array).find(center_id)
	_check(plan_index >= 0, "原生快照必须包含州计划")
	if plan_index >= 0:
		_check(
			int((nations["campaign_staging_city_ids"] as PackedInt32Array)[plan_index])
				== plan.staging_city_id,
			"原生快照必须记录集结点"
		)
		_check(
			int((nations["campaign_camp_city_ids"] as PackedInt32Array)[plan_index])
				== plan.camp_city_id,
			"原生快照必须记录大营"
		)
	sim.free()
	_finish()


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
	plan: AdministrativeCampaignPlan,
	armies: Array[Army],
	city_id: int
) -> bool:
	for army in armies:
		if int(plan.army_assignments.get(army.id, -1)) != city_id:
			return false
	return true


func _assigned_manpower(
	plan: AdministrativeCampaignPlan,
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
