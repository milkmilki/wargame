extends SceneTree
## 强攻受挫门禁：
## C1 — 途中野战败北必须触发撤营重整（与州治城下败北同一路径），不再添油。
## C2 — 走廊断裂连续两个决策日无法对州治下达进攻令时，退回驻营重整。

var _failures: Array[String] = []
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_field_rout_regroups_assault()
	_test_stalled_assault_falls_back()
	_test_blocked_fu_does_not_restart_unready_assault(false)
	_test_blocked_fu_does_not_restart_unready_assault(true)
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


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		push_error("CAMPAIGN_ASSAULT_FALLBACK_FAIL: " + failure)
	print("CAMPAIGN_ASSAULT_FALLBACK_%s checks=%d" % [
		"OK" if _failures.is_empty() else "FAILED", _checks,
	])
	quit(0 if _failures.is_empty() else 1)


## C1：强攻途中的野战败北 → 撤营重整，败军回大营。
func _test_field_rout_regroups_assault() -> void:
	var state := GameState.new()
	state.generate_grid_world(94145)
	var context := _attack_context(state)
	_check(not context.is_empty(), "野战败北夹具必须找到大州")
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
		attacker_id, defender_id, center_id, "野战败北重整门禁"
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
	var losers: Array[Army] = []
	for index in range(2):
		var army := _army(963001 + index, attacker_id, entry_id, 15000)
		army.campaign_war_id = war_id
		state.armies.append(army)
		losers.append(army)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	var plan := CoalitionCampaignFront.new()
	plan.mode = CoalitionCampaignFront.Mode.OFFENSE
	plan.war_id = war_id
	plan.center_city_id = center_id
	plan.camp_city_id = entry_id
	plan.phase = CoalitionCampaignFront.Phase.ASSAULT_CENTER
	plan.tactical_target_city_ids = [center_id] as Array[int]
	for army in losers:
		plan.army_assignments[army.id] = center_id
	state.register_campaign_front(plan, [attacker_id] as Array[int], attacker_id)
	var winner := _army(963010, defender_id, center_id, 10000)
	var battle := state.new_battle(Battle.Kind.FIELD)
	battle.side_a = [winner]
	battle.side_b = [losers[0]]
	battle.winner_side = 1
	sim._finish_field_battle(battle)
	_check(
		plan.phase == CoalitionCampaignFront.Phase.HOLD_CAMP,
		"强攻途中野战败北后战线必须回到驻营重整（阶段%d）" % plan.phase
	)
	for army in losers:
		_check(
			int(plan.army_assignments.get(army.id, -1)) == entry_id,
			"重整后全部编制必须改绑大营"
		)
	_check(
		losers[0].state == Army.State.RECOVERING
			and losers[0].location_city == entry_id,
		"大营内败军必须就地进入恢复（状态%d 位置%d）"
			% [losers[0].state, losers[0].location_city]
	)
	_check(losers[0].size == 3000, "败军必须承受野战溃散损耗（实际%d）" % losers[0].size)
	_check(
		plan.assault_stalled_days == 0,
		"重整必须清零强攻停滞计数"
	)
	sim.free()


func _test_blocked_fu_does_not_restart_unready_assault(route_open: bool) -> void:
	var state := GameState.new()
	state.generate_grid_world(94145)
	var context := _attack_context(state)
	_check(not context.is_empty(), "驻营循环夹具必须找到大州")
	if context.is_empty():
		return
	var center_id := int(context["center"])
	var camp_id := int(context["entry"])
	var rear_id := int(context["staging"])
	var attacker_id := int(context["attacker"])
	var defender_id := int(context["defender"])
	_neutralize_diplomacy(state)
	state.set_diplomatic_relation(attacker_id, defender_id, GameState.DiplomaticRelation.WAR)
	var war_id := state.set_war_objective(attacker_id, defender_id, center_id, "驻营循环门禁")
	for city in state.cities:
		city.owner_nation = attacker_id
	var blocked_fu := -1
	for member_id in state.administrative_members(center_id):
		if member_id not in [center_id, camp_id]:
			blocked_fu = member_id
			break
	state.cities[center_id].owner_nation = defender_id
	state.cities[center_id].garrison_manpower = 60000
	state.cities[blocked_fu].owner_nation = defender_id
	# The remaining Fu has no legal approach. The center route is separately
	# opened in the regroup case, so waiting cannot be attributed to that route.
	for edge in state.edges:
		if edge.city_a in [blocked_fu, center_id] or edge.city_b in [blocked_fu, center_id]:
			edge.max_manpower = 0
	if route_open:
		state._add_edge(camp_id, center_id)
		var center_edge := state.edge_of(camp_id, center_id)
		center_edge.kind = Edge.Kind.LAND
		center_edge.max_manpower = 50000
		center_edge.base_max_manpower = 50000
	state.road_network_revision += 1
	state.ownership_revision += 1
	state.armies.clear()
	state.battles.clear()
	var armies: Array[Army] = []
	for index in range(6):
		var army := _army(964000 + index, attacker_id, camp_id if index < 2 else rear_id, 15000)
		army.campaign_war_id = war_id
		state.armies.append(army)
		armies.append(army)
	var plan := CoalitionCampaignFront.new()
	plan.mode = CoalitionCampaignFront.Mode.OFFENSE
	plan.war_id = war_id
	plan.center_city_id = center_id
	plan.camp_city_id = camp_id
	plan.phase = CoalitionCampaignFront.Phase.HOLD_CAMP if route_open else CoalitionCampaignFront.Phase.RAID_FU
	for army in armies:
		plan.army_assignments[army.id] = camp_id
	state.register_campaign_front(plan, [attacker_id] as Array[int], attacker_id)
	state.refresh_derived()
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	var requirement := state.campaign_siege_requirement(attacker_id, center_id)
	_check(requirement > 30000 and requirement <= 90000, "夹具要求营内3万不足而全州9万足够：%d" % requirement)
	for cycle in range(9):
		sim._manage_administrative_campaign(plan)
		_check(plan.phase == CoalitionCampaignFront.Phase.HOLD_CAMP,
			"%s第%d轮不得虚假发动州治进攻（阶段%d）" % ["援军未到营" if route_open else "州治断路", cycle, plan.phase])
		state.day += Simulation.AI_DECISION_INTERVAL_DAYS
	if route_open:
		for army in armies:
			_place_idle(army, camp_id)
		sim._manage_administrative_campaign(plan)
		_check(plan.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER, "集结完成且道路畅通后必须正常发动下一波")
	else:
		for army in armies:
			_place_idle(army, camp_id)
		sim._manage_administrative_campaign(plan)
		_check(plan.phase == CoalitionCampaignFront.Phase.HOLD_CAMP, "全部到营也不能对断路州治虚假发动")
		state._add_edge(camp_id, center_id)
		var reopened_edge := state.edge_of(camp_id, center_id)
		reopened_edge.kind = Edge.Kind.LAND
		reopened_edge.max_manpower = 50000
		reopened_edge.base_max_manpower = 50000
		state.road_network_revision += 1
		sim._manage_administrative_campaign(plan)
		_check(plan.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER, "道路恢复后必须重新发动而非永久驻营")
	for army in armies:
		_check(army.ai_target_city == center_id and army.on_edge, "真正发动后军队必须执行州治进攻命令")
	for _cycle in range(3):
		sim._manage_administrative_campaign(plan)
		_check(plan.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER, "已离营向州治行军时不得因营内兵力下降回退")
	sim.free()


## C2：走廊断裂连续两个决策日无法下达进攻令 → 回驻营重整。
func _test_stalled_assault_falls_back() -> void:
	var state := GameState.new()
	state.generate_grid_world(94145)
	var context := _attack_context(state)
	_check(not context.is_empty(), "强攻停滞夹具必须找到大州")
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
		attacker_id, defender_id, center_id, "强攻停滞门禁"
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
	# 一条与我方接壤的走廊属府：军队在这里可以向州治直接下达进攻令。
	var launch_city := -1
	for neighbor_id in state.neighbors(center_id):
		if (
			state.administrative_center_of(neighbor_id) == center_id
			and neighbor_id != center_id
		):
			launch_city = neighbor_id
			break
	state.cities[launch_city].owner_nation = attacker_id
	state.ownership_revision += 1
	var survivor := _army(963101, attacker_id, launch_city, 15000)
	survivor.campaign_war_id = war_id
	state.armies.append(survivor)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	var plan := CoalitionCampaignFront.new()
	plan.mode = CoalitionCampaignFront.Mode.OFFENSE
	plan.war_id = war_id
	plan.center_city_id = center_id
	plan.camp_city_id = entry_id
	plan.phase = CoalitionCampaignFront.Phase.ASSAULT_CENTER
	plan.tactical_target_city_ids = [center_id] as Array[int]
	plan.army_assignments[survivor.id] = center_id
	state.register_campaign_front(plan, [attacker_id] as Array[int], attacker_id)
	sim._manage_administrative_campaign(plan)
	_check(
		plan.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER
			and survivor.ai_target_city == center_id,
		"走廊畅通时必须继续强攻且不累计停滞（阶段%d 目标%d）"
			% [plan.phase, survivor.ai_target_city]
	)
	_check(
		plan.assault_stalled_days == 0,
		"能下令时停滞计数必须保持为零（实际%d）" % plan.assault_stalled_days
	)
	# 走廊属府被敌方夺回：从此没有任何己方城市与州治接壤。
	state.cities[launch_city].owner_nation = defender_id
	state.ownership_revision += 1
	_place_idle(survivor, entry_id)
	sim._manage_administrative_campaign(plan)
	_check(
		plan.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER
			and plan.assault_stalled_days == 1,
		"走廊断裂第一轮必须保持强攻并累计停滞（阶段%d 计数%d）"
			% [plan.phase, plan.assault_stalled_days]
	)
	sim._manage_administrative_campaign(plan)
	_check(
		plan.phase == CoalitionCampaignFront.Phase.HOLD_CAMP,
		"连续两轮无法下令后必须退回驻营重整（阶段%d）" % plan.phase
	)
	_check(
		plan.assault_stalled_days == 0,
		"回退后停滞计数必须清零（实际%d）" % plan.assault_stalled_days
	)
	sim.free()
