extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(94146)
	_neutralize_diplomacy(state)
	var context := _prewar_context(state)
	_check(not context.is_empty(), "夹具必须存在合法战前集结方向")
	if context.is_empty():
		_finish()
		return
	var center_id := int(context["center"])
	var entry_id := int(context["entry"])
	var staging_id := int(context["staging"])
	for member_id in state.administrative_members(center_id):
		state.cities[member_id].owner_nation = 1
	var normalized_staging := DiplomacyAI.war_staging_cities_for_objective(
		state, 0, entry_id
	)
	_check(
		normalized_staging.has(staging_id),
		"统一目标州归属后原入口外集结点仍必须合法（候选%s，预期%d）" % [
			str(normalized_staging), staging_id,
		]
	)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.ALLIED)
	state.cities[center_id].garrison_manpower = 15000
	state.armies.clear()
	state.battles.clear()
	state.armies.append(_army(941460, 1, center_id, 12000))
	state.armies.append(_army(941461, 2, center_id, 15000))
	state.armies.append(_army(941462, 3, center_id, 14000))
	var attacker_armies: Array[Army] = []
	for index in range(3):
		var army := _army(941470 + index, 0, staging_id, 15000)
		state.armies.append(army)
		attacker_armies.append(army)
	var nation := state.nations[0]
	nation.war_preparation_target_nation = 1
	nation.war_preparation_objective_city = entry_id
	nation.war_preparation_objective_center_city = center_id
	nation.war_preparation_staging_city_id = staging_id
	nation.war_preparation_started_day = state.day
	for army in attacker_armies:
		nation.war_preparation_army_ids.append(army.id)

	_check(
		state.campaign_prewar_reinforcement_threat(0, 1, center_id) == 27000,
		"战前V必须包含目标国及其防御联盟军，不得计入中立第三方"
	)
	state.armies[0].state = Army.State.FIGHTING
	_check(
		state.campaign_prewar_reinforcement_threat(0, 1, center_id) == 27000,
		"已在州内交战的有效守军仍是宣战后的V，战前预览不得漏算"
	)
	state.armies[0].state = Army.State.IDLE
	_check(
		state.campaign_prewar_launch_requirement(0, 1, center_id) == 42000,
		"有属府州的战前门槛必须等于G加战前V"
	)
	_check(
		DiplomacyAI.required_assault_troops(state, 0, entry_id) == 42000,
		"360天尽力宣战门槛必须沿用战前G/V预览，不得退回敌对关系查询"
	)
	_check(
		DiplomacyAI.war_preparation_arrived_troops(state, 0) == 45000,
		"只统计备战池中实际到达集结点的有效兵力"
	)
	var original_members := state.administrative_members(center_id)
	var original_centers := {}
	for member_id in original_members:
		original_centers[member_id] = state.administrative_center_by_city[member_id]
		if member_id != center_id:
			state.administrative_center_by_city[member_id] = member_id
	var singleton_r := state.campaign_siege_requirement(0, center_id)
	_check(
		state.campaign_prewar_launch_requirement(0, 1, center_id)
			== singleton_r + 27000,
		"无属府州的战前门槛必须使用当前R加战前V"
	)
	for member_id in original_members:
		state.administrative_center_by_city[member_id] = int(
			original_centers[member_id]
		)
	_check(
		DiplomacyAI.war_preparation_ready(state, 0),
		"到场C达到G+V时不得再等待固定30天"
	)
	var refresh_actions: Array[Dictionary] = []
	var refresh_committed := {}
	nation.war_preparation_objective_center_city = -1
	nation.war_preparation_staging_city_id = center_id
	DiplomacyAI._collect_existing_war_preparation(
		state, 0, refresh_actions, refresh_committed
	)
	_check(
		refresh_actions.size() == 1
		and int(refresh_actions[0].get("kind", -1))
			== DiplomacyAI.Action.RETARGET_WAR_PREPARATION
		and int(refresh_actions[0].get("objective_city", -1)) == entry_id,
		"州域或道路变化后必须保留目标并重新冻结合法集结点"
	)
	nation.war_preparation_objective_center_city = center_id
	nation.war_preparation_staging_city_id = staging_id
	attacker_armies[-1].state = Army.State.RECOVERING
	_check(
		DiplomacyAI.war_preparation_arrived_troops(state, 0) == 30000
		and not DiplomacyAI.war_preparation_ready(state, 0),
		"恢复军不得计入战前到场C"
	)

	var snapshot: Dictionary = NativeSnapshotBuilder.build(state)["nations"]
	_check(
		(snapshot["war_preparation_staging_city"] as PackedInt32Array)[0]
			== staging_id,
		"原生快照必须记录备战集结点"
	)
	_check(
		(snapshot["war_preparation_army_ids"] as PackedInt32Array).size()
			== attacker_armies.size(),
		"原生快照必须记录备战军队池"
	)

	nation.war_preparation_army_ids.clear()
	nation.war_preparation_staging_city_id = -1
	for army in attacker_armies:
		army.state = Army.State.IDLE
	var spare := _army(941473, 0, staging_id, 15000)
	var recovering := _army(941474, 0, staging_id, 15000)
	recovering.state = Army.State.RECOVERING
	var war_bound := _army(941475, 0, staging_id, 15000)
	war_bound.campaign_war_id = 99
	state.armies.append(spare)
	state.armies.append(recovering)
	state.armies.append(war_bound)
	var sim := Simulation.new()
	sim.setup(state)
	_check(
		sim._start_war_preparation(0, 1, {
			"objective_city": entry_id,
			"objective_center_city": center_id,
			"objective_reason": "战前集结门禁",
			"mobilization_armies": 0,
		}),
		"开始备战时必须固定同一合法集结点"
	)
	sim._manage_war_preparation_assembly(0)
	_check(
		nation.war_preparation_staging_city_id == staging_id,
		"备战调兵必须沿用开始备战时冻结的集结点"
	)
	_check(
		nation.war_preparation_army_ids.size() == 3,
		"备战池只应抽到已承诺兵力满足G+V，不得集结全国军队"
	)
	_check(
		not nation.war_preparation_army_ids.has(recovering.id)
		and not nation.war_preparation_army_ids.has(war_bound.id),
		"恢复军和其他战争池军不得被备战集结征用"
	)
	var released_moving: Army = attacker_armies[0]
	released_moving.state = Army.State.MOVING
	released_moving.on_edge = true
	released_moving.move_from = staging_id
	released_moving.move_to = entry_id
	released_moving.location_city = -1
	released_moving.path = [center_id] as Array[int]
	released_moving.ai_target_city = center_id
	released_moving.ai_order_reason = "战前集结：取消路径门禁"
	sim._clear_war_preparation(0)
	sim._clear_ai_command_collection()
	_check(
		nation.war_preparation_army_ids.is_empty()
		and nation.war_preparation_staging_city_id == -1,
		"取消备战必须释放军队池和集结点"
	)
	_check(
		released_moving.state == Army.State.MOVING
		and released_moving.on_edge
		and released_moving.path.is_empty()
		and released_moving.ai_target_city == -1,
		"取消备战的在途军必须走完当前道路段后停止，不得继续完整旧路径"
	)
	state.day = DiplomacyAI.MIN_NEUTRAL_DAYS
	for army in attacker_armies + [spare]:
		army.state = Army.State.IDLE
		army.campaign_war_id = -1
		army.location_city = staging_id
		army.move_from = staging_id
		army.move_to = -1
		army.on_edge = false
		army.path.clear()
		army.ai_target_city = -1
	sim._start_war_preparation(0, 1, {
		"objective_city": entry_id,
		"objective_center_city": center_id,
		"objective_reason": "宣战移交门禁",
		"mobilization_armies": 0,
	})
	sim._manage_war_preparation_assembly(0)
	var best_effort_excluded_id := int(nation.war_preparation_army_ids[-1])
	for army in state.armies:
		if army.id == best_effort_excluded_id:
			army.state = Army.State.RECOVERING
			break
	var prepared_ids := sim._war_preparation_arrived_army_ids(0)
	_check(
		prepared_ids.size() == 2
		and DiplomacyAI.war_preparation_arrived_troops(state, 0)
			>= ceili(
				float(state.campaign_prewar_launch_requirement(0, 1, center_id))
				* DiplomacyAI.WAR_PREPARATION_BEST_EFFORT_RATIO
			)
		and not DiplomacyAI.war_preparation_ready(state, 0),
		"360天兜底夹具必须处于半数以上但未达到完整需求的状态"
	)
	var declared := sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.DECLARE_WAR,
		"a": 0,
		"b": 1,
		"objective_city": entry_id,
		"objective_center_city": center_id,
		"objective_reason": "宣战移交门禁",
		"mobilization_armies": 0,
		"reason": "集结完成后宣战",
	})
	var plan := state.campaign_plan(0, center_id)
	var war_id := state.war_id_between(0, 1)
	_check(declared and war_id >= 0 and plan != null, "集结完成后必须成功创建正式战争与州计划")
	_check(
		plan != null
		and plan.phase == AdministrativeCampaignPlan.Phase.BREAK_IN
		and plan.staging_city_id == staging_id
		and plan.tactical_target_city_ids == [entry_id],
		"宣战当日（包括360天尽力宣战）必须继承入口与集结点并直接进入BREAK_IN（phase=%s staging=%s targets=%s entry=%d C=%d need=%d assignments=%s）" % [
			str(plan.phase if plan != null else -1),
			str(plan.staging_city_id if plan != null else -1),
			str(plan.tactical_target_city_ids if plan != null else []),
			entry_id,
			state.campaign_committed_manpower(0, center_id),
			state.campaign_minimum_launch_requirement(0, center_id),
			str(plan.army_assignments if plan != null else {}),
		]
	)
	for army_id in prepared_ids:
		var prepared_army: Army = state.armies.filter(
			func(army: Army) -> bool: return army.id == army_id
		)[0]
		_check(
			prepared_army.campaign_war_id == war_id
			and plan.army_assignments.has(army_id),
			"到场备战军必须原地转入正式战争池且不经过三军重分配"
		)
	_check(
		nation.war_preparation_army_ids.is_empty()
		and nation.war_preparation_target_nation == -1,
		"宣战移交后必须清空备战状态"
	)
	sim.free()
	_test_preparation_uses_remaining_unplanned_army()
	_finish()


func _neutralize_diplomacy(state: GameState) -> void:
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)


func _test_preparation_uses_remaining_unplanned_army() -> void:
	var state := GameState.new()
	state.generate_grid_world(94149)
	_neutralize_diplomacy(state)
	var context := _prewar_context(state)
	_check(not context.is_empty(), "剩余预备军夹具必须存在合法集结方向")
	if context.is_empty():
		return
	var center_id := int(context["center"])
	var entry_id := int(context["entry"])
	var staging_id := int(context["staging"])
	for member_id in state.administrative_members(center_id):
		state.cities[member_id].owner_nation = 1
	state.armies.clear()
	state.battles.clear()
	var existing_war_reserve := _army(941490, 0, staging_id, 15000)
	var preparation_reserve := _army(941491, 0, staging_id, 15000)
	state.armies.append(existing_war_reserve)
	state.armies.append(preparation_reserve)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	_check(
		sim._start_war_preparation(0, 1, {
			"objective_city": entry_id,
			"objective_center_city": center_id,
			"objective_reason": "剩余预备军门禁",
			"mobilization_armies": 0,
		}),
		"剩余预备军夹具必须成功开始备战"
	)
	# 模拟同一规划周期中，现有战争分配器已经优先预留了一军。
	sim._ai_planned_armies[existing_war_reserve.id] = true
	sim._manage_war_preparation_assembly(0)
	_check(
		state.nations[0].war_preparation_army_ids
			== [preparation_reserve.id],
		"现有战争优先规划后，备战必须继续抽调本轮剩余的空闲预备军"
	)
	_check(
		DiplomacyAI.war_preparation_arrived_troops(state, 0)
			== preparation_reserve.size,
		"剩余预备军已经位于集结点时必须立即计入到场C"
	)
	sim.free()


func _prewar_context(state: GameState) -> Dictionary:
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		if state.cities[center_id].owner_nation != 1:
			continue
		for member_id in state.administrative_members(center_id):
			if member_id == center_id:
				continue
			for neighbor_id in state.neighbors(member_id):
				var edge := state.edge_of(member_id, neighbor_id)
				if (
					state.administrative_center_of(neighbor_id) != center_id
					and state.cities[neighbor_id].owner_nation == 0
					and edge != null
					and edge.max_manpower > 0
				):
					return {
						"center": center_id,
						"entry": member_id,
						"staging": neighbor_id,
					}
	return {}


func _army(id: int, owner_id: int, city_id: int, size: int) -> Army:
	var army := Army.new()
	army.id = id
	army.owner_nation = owner_id
	army.location_city = city_id
	army.move_from = city_id
	army.size = size
	army.max_size = 15000
	army.state = Army.State.IDLE
	army.morale = army.max_morale
	army.supply_ratio = 1.0
	return army


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		push_error("PREWAR_ASSEMBLY_FAIL: " + failure)
	print("PREWAR_ASSEMBLY_%s" % (
		"OK" if _failures.is_empty() else "FAILED"
	))
	quit(0 if _failures.is_empty() else 1)
