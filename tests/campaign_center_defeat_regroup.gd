extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(95320)
	var chain := _two_hop_campaign_chain(state)
	_check(not chain.is_empty(), "夹具必须找到大营—中间府—州治两跳链")
	if chain.is_empty():
		_finish()
		return
	var center_id := int(chain["center"])
	var camp_id := int(chain["camp"])
	var middle_id := int(chain["middle"])
	var attacker_id := 0
	var defender_id := 1
	_neutralize_diplomacy(state)
	state.set_diplomatic_relation(
		attacker_id, defender_id, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.set_war_objective(
		attacker_id, defender_id, center_id, "州治野战败退重整门禁"
	)
	for city in state.cities:
		if not city.is_dock:
			city.owner_nation = attacker_id
	for member_id in state.administrative_members(center_id):
		state.cities[member_id].owner_nation = attacker_id
	state.cities[center_id].owner_nation = defender_id
	state.cities[center_id].garrison_manpower = 15000
	for edge in state.edges:
		if edge.city_a in [camp_id, center_id] or edge.city_b in [camp_id, center_id]:
			edge.max_manpower = 0
	_enable_edge(state, camp_id, middle_id)
	_enable_edge(state, middle_id, center_id)
	state.road_network_revision += 1
	state.armies.clear()
	state.battles.clear()

	var attackers: Array[Army] = []
	for index in range(4):
		var army := _army(95320 + index, attacker_id, center_id, 15000)
		army.state = Army.State.FIGHTING
		army.campaign_war_id = war_id
		state.armies.append(army)
		attackers.append(army)
	var defender := _army(95330, defender_id, center_id, 15000)
	defender.state = Army.State.FIGHTING
	state.armies.append(defender)
	var late_reinforcement := _army(95331, attacker_id, middle_id, 15000)
	late_reinforcement.state = Army.State.MOVING
	late_reinforcement.on_edge = true
	late_reinforcement.move_from = middle_id
	late_reinforcement.move_to = center_id
	late_reinforcement.move_progress = 1.0
	late_reinforcement.ai_target_city = center_id
	late_reinforcement.campaign_war_id = war_id
	state.armies.append(late_reinforcement)
	var plan := CoalitionCampaignFront.new()
	plan.mode = CoalitionCampaignFront.Mode.OFFENSE
	plan.phase = CoalitionCampaignFront.Phase.ASSAULT_CENTER
	plan.war_id = war_id
	plan.center_city_id = center_id
	plan.camp_city_id = camp_id
	plan.tactical_target_city_ids = [center_id] as Array[int]
	for army in attackers:
		plan.army_assignments[army.id] = center_id
	plan.army_assignments[late_reinforcement.id] = center_id
	state.register_campaign_front(plan, [attacker_id] as Array[int], attacker_id)
	state.ownership_revision += 1
	state.refresh_derived()

	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city = state.cities[center_id]
	battle.edge = state.edge_of(middle_id, center_id)
	battle.siege_attacker_nation = attacker_id
	battle.side_a.assign(attackers)
	battle.side_b.append(defender)
	battle.side_b_defends_city = true
	battle.winner_side = 2
	battle.finished = true
	sim._finish_siege_field_engagement(battle)

	_check(
		plan.phase == CoalitionCampaignFront.Phase.HOLD_CAMP,
		"州治野战失败后战线必须回到驻营重整阶段"
	)
	for army in attackers:
		var retreat_route: Array[int] = []
		if army.move_to >= 0:
			retreat_route.append(army.move_to)
		retreat_route.append_array(army.path)
		_check(
			not retreat_route.is_empty() and retreat_route[-1] == camp_id,
			"败军必须以大营为最终撤退点，实际路线=%s" % str(retreat_route)
		)
		_advance_retreat_to_destination(sim, army)
		_check(
			army.location_city == camp_id and army.state == Army.State.RECOVERING,
			"败军必须在大营进入恢复状态"
		)
		army.morale = army.max_morale
		sim._recover_morale()
		_check(army.state == Army.State.IDLE, "士气恢复后军队必须重新可用")
	# The defeat has already recalled this army, but its old movement command
	# reaches the center before the next planner pass. Arrival must not reopen
	# the siege alone.
	sim._arrive_at_node(late_reinforcement)
	var late_route: Array[int] = []
	if late_reinforcement.move_to >= 0:
		late_route.append(late_reinforcement.move_to)
	late_route.append_array(late_reinforcement.path)
	_check(
		late_reinforcement.state == Army.State.RETREATING
		and not late_route.is_empty()
		and late_route[-1] == camp_id,
		"沿旧命令抵达州治的援军必须转回大营，不能单独重开围城"
	)
	_check(
		sim._siege_battle_of(state.cities[center_id]) == null,
		"重整阶段迟到援军不得创建新围城"
	)
	_advance_retreat_to_destination(sim, late_reinforcement)
	late_reinforcement.morale = late_reinforcement.max_morale
	sim._recover_morale()

	defender.size = 60000
	var reinforcements: Array[Army] = []
	for index in range(2):
		var army := _army(95340 + index, attacker_id, middle_id, 15000)
		army.campaign_war_id = war_id
		army.campaign_front_id = plan.front_id
		state.armies.append(army)
		plan.army_assignments[army.id] = camp_id
		reinforcements.append(army)
	sim._manage_administrative_campaign(plan)
	_check(
		plan.phase == CoalitionCampaignFront.Phase.HOLD_CAMP,
		"总可战兵力足够但援军未到大营时不得提前发动第二波"
	)
	for army in reinforcements:
		_place_idle(army, camp_id)
	sim._manage_administrative_campaign(plan)
	_check(
		plan.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER,
		"大营实际到场兵力超过0.9V后必须重新进攻州治"
	)
	for army in attackers + [late_reinforcement] + reinforcements:
		_check(
			int(plan.army_assignments.get(army.id, -1)) == center_id,
			"第二波发动后全部可战军必须共同转向州治"
		)
	sim.free()
	_finish()


func _two_hop_campaign_chain(state: GameState) -> Dictionary:
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		var members := state.administrative_members(center_id)
		for camp_id in members:
			if camp_id == center_id:
				continue
			for middle_id in members:
				if middle_id in [center_id, camp_id]:
					continue
				if (
					state.edge_of(camp_id, middle_id) != null
					and state.edge_of(middle_id, center_id) != null
					and state.edge_of(camp_id, center_id) == null
				):
					return {"center": center_id, "camp": camp_id, "middle": middle_id}
	return {}


func _advance_retreat_to_destination(sim: Simulation, army: Army) -> void:
	var guard := 0
	while army.state == Army.State.RETREATING and guard < 8:
		army.move_progress = 1.0
		sim._arrive_at_node(army)
		guard += 1


func _neutralize_diplomacy(state: GameState) -> void:
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)


func _enable_edge(state: GameState, city_a: int, city_b: int) -> void:
	var edge := state.edge_of(city_a, city_b)
	if edge == null:
		state._add_edge(city_a, city_b)
		edge = state.edge_of(city_a, city_b)
	edge.kind = Edge.Kind.LAND
	edge.max_manpower = 50000
	edge.base_max_manpower = 50000


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
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		push_error("CAMPAIGN_CENTER_DEFEAT_REGROUP_FAIL: " + failure)
	print("CAMPAIGN_CENTER_DEFEAT_REGROUP_%s failures=%d" % [
		"OK" if _failures.is_empty() else "FAILED", _failures.size(),
	])
	quit(0 if _failures.is_empty() else 1)
