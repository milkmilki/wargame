extends SceneTree

const ATTACKER: int = 0
const DEFENDER: int = 1
const NEUTRAL: int = 2
const MAX_DAYS: int = 1800

var _failures: Array[String] = []


func _init() -> void:
	var world_seed := int(OS.get_environment("CAMPAIGN_CHAIN_SEED"))
	if world_seed == 0:
		world_seed = 96301
	var results := {
		"land": _test_land_campaign_chain(world_seed),
		"river": _test_river_campaign_chain(world_seed),
	}
	_finish(results)


func _test_land_campaign_chain(world_seed: int) -> Dictionary:
	return _run_campaign_chain(world_seed, false)


func _test_river_campaign_chain(world_seed: int) -> Dictionary:
	return _run_campaign_chain(world_seed, true)


func _run_campaign_chain(
	world_seed: int,
	river_crossing: bool
) -> Dictionary:
	var state := GameState.new()
	state.generate_grid_world(world_seed)
	var chain := _administrative_center_chain(state)
	_check(chain.size() == 3, "夹具必须找到连续三州")
	if chain.size() != 3:
		return {}
	_neutralize_diplomacy(state)
	_configure_territory(state, chain)
	var crossing := {}
	if river_crossing:
		crossing = _replace_state_border_with_local_crossing(
			state, chain[1], chain[2]
		)
		_check(not crossing.is_empty(), "跨河夹具必须建立属府间的共享码头")
		if crossing.is_empty():
			return {}
	var route := _entry_route(state, chain[0], chain[1])
	_check(not route.is_empty(), "第一目标州必须存在本国入口府与集结点")
	if route.is_empty():
		return {}
	var entry_id := int(route["entry"])
	var staging_id := int(route["staging"])
	_configure_resources(state, chain)
	state.armies.clear()
	state.battles.clear()
	for index in range(5):
		state.armies.append(_army(963010 + index, ATTACKER, staging_id))
	state.armies.append(_army(963020, DEFENDER, chain[1]))
	state.armies.append(_army(963021, DEFENDER, chain[2]))
	state.day = DiplomacyAI.MIN_NEUTRAL_DAYS
	state.ownership_revision += 1
	state.refresh_derived()
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.diplomacy_enabled = false

	var started := sim._start_war_preparation(ATTACKER, DEFENDER, {
		"objective_city": entry_id,
		"objective_center_city": chain[1],
		"objective_reason": "两州连续战役端到端门禁",
		"mobilization_armies": 0,
	})
	sim._manage_war_preparation_assembly(ATTACKER)
	var prepared_c := DiplomacyAI.war_preparation_arrived_troops(
		state, ATTACKER
	)
	var preparation_requirement := state.campaign_prewar_launch_requirement(
		ATTACKER, DEFENDER, chain[1]
	)
	var prepared_count := state.nations[
		ATTACKER
	].war_preparation_army_ids.size()
	_check(started, "必须成功进入战前集结")
	_check(
		prepared_count > 0 and prepared_count <= 5,
		"备战池必须按需抽调且不能集结全国军队"
	)
	_check(
		prepared_c >= preparation_requirement,
		"备战实际到场C必须满足G+V"
	)
	_check(
		DiplomacyAI.war_preparation_ready(state, ATTACKER),
		"到场C满足G+V后必须允许宣战"
	)
	var declared := sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.DECLARE_WAR,
		"a": ATTACKER,
		"b": DEFENDER,
		"objective_city": entry_id,
		"objective_center_city": chain[1],
		"objective_reason": "两州连续战役端到端门禁",
		"mobilization_armies": 0,
		"reason": "端到端门禁宣战",
	})
	var war_id := state.war_id_between(ATTACKER, DEFENDER)
	_check(declared and war_id >= 0, "集结完成后必须成功宣战")
	var launch_plan := state.campaign_plan(ATTACKER, chain[1])
	_check(
		launch_plan != null
		and launch_plan.phase == AdministrativeCampaignPlan.Phase.BREAK_IN
		and launch_plan.army_assignments.size() == prepared_count,
		"备战军必须原地移交第一州BREAK_IN计划"
	)

	var milestones := {
		"mode": "river" if river_crossing else "land",
		"seed": world_seed,
		"prepared": state.day,
		"declared": state.day,
		"first_defense": -1,
		"first_entry": -1,
		"first_camp": -1,
		"first_camp_arrival": -1,
		"first_camp_command": -1,
		"first_detachment": -1,
		"first_center": -1,
		"first_complete": -1,
		"second_target": -1,
		"old_plan_released": -1,
		"second_entry_id": -1,
		"second_entry": -1,
		"second_camp_id": -1,
		"second_camp": -1,
		"second_camp_arrival": -1,
		"second_camp_command": -1,
		"second_detachment": -1,
		"second_defense": -1,
		"second_fu": -1,
		"second_center": -1,
		"second_complete": -1,
		"river_crossed": -1,
	}
	for _step in range(MAX_DAYS):
		if int(milestones["second_complete"]) >= 0:
			break
		sim._advance_day()
		_record_milestones(
			state, chain, entry_id, war_id, int(crossing.get("dock", -1)),
			milestones
		)
	_check_chain(
		state, chain, entry_id, war_id, river_crossing, crossing, milestones
	)
	sim.free()
	return milestones


func _record_milestones(
	state: GameState,
	chain: Array[int],
	entry_id: int,
	war_id: int,
	dock_id: int,
	milestones: Dictionary
) -> void:
	if (
		int(milestones["first_defense"]) < 0
		and _has_defense_plan(state, chain[1], war_id)
	):
		milestones["first_defense"] = state.day
	if int(milestones["first_entry"]) < 0 and state.cities[entry_id].owner_nation == ATTACKER:
		milestones["first_entry"] = state.day
	var first_plan := state.campaign_plan(ATTACKER, chain[1])
	if first_plan != null and first_plan.camp_city_id == entry_id:
		if int(milestones["first_camp"]) < 0:
			milestones["first_camp"] = state.day
		if (
			int(milestones["first_camp_arrival"]) < 0
			and _plan_army_at_city(state, first_plan, entry_id)
		):
			milestones["first_camp_arrival"] = state.day
		if (
			int(milestones["first_camp_command"]) < 0
			and _plan_uses_camp_as_anchor(state, first_plan, entry_id)
		):
			milestones["first_camp_command"] = state.day
		if (
			int(milestones["first_detachment"]) < 0
			and _plan_has_forward_order(first_plan)
		):
			milestones["first_detachment"] = state.day
	if int(milestones["first_center"]) < 0 and state.cities[chain[1]].owner_nation == ATTACKER:
		milestones["first_center"] = state.day
	if int(milestones["first_complete"]) < 0 and _state_controlled(state, chain[1], ATTACKER):
		milestones["first_complete"] = state.day
	var second_plan := state.campaign_plan(ATTACKER, chain[2])
	if (
		int(milestones["first_complete"]) >= 0
		and int(milestones["second_target"]) < 0
		and second_plan != null
		and second_plan.mode == AdministrativeCampaignPlan.Mode.OFFENSE
		and second_plan.war_id == war_id
	):
		milestones["second_target"] = state.day
	if (
		int(milestones["second_target"]) >= 0
		and int(milestones["old_plan_released"]) < 0
	):
		var old_center_plan := state.campaign_plan(ATTACKER, chain[1])
		if (
			old_center_plan == null
			or old_center_plan.mode != AdministrativeCampaignPlan.Mode.OFFENSE
		):
			milestones["old_plan_released"] = state.day
	if second_plan != null:
		if (
			int(milestones["second_entry_id"]) < 0
			and second_plan.phase in [
				AdministrativeCampaignPlan.Phase.ASSEMBLE,
				AdministrativeCampaignPlan.Phase.BREAK_IN,
			]
			and not second_plan.tactical_target_city_ids.is_empty()
		):
			var candidate_entry := int(second_plan.tactical_target_city_ids[0])
			if (
				candidate_entry != chain[2]
				and state.administrative_center_of(candidate_entry) == chain[2]
			):
				milestones["second_entry_id"] = candidate_entry
		var second_camp_id := second_plan.camp_city_id
		if second_camp_id >= 0:
			if int(milestones["second_camp_id"]) < 0:
				milestones["second_camp_id"] = second_camp_id
			if int(milestones["second_entry_id"]) < 0:
				milestones["second_entry_id"] = second_camp_id
			if int(milestones["second_camp"]) < 0:
				milestones["second_camp"] = state.day
			if (
				int(milestones["second_camp_arrival"]) < 0
				and _plan_army_at_city(state, second_plan, second_camp_id)
			):
				milestones["second_camp_arrival"] = state.day
			if (
				int(milestones["second_camp_command"]) < 0
				and _plan_uses_camp_as_anchor(
					state, second_plan, second_camp_id
				)
			):
				milestones["second_camp_command"] = state.day
			if (
				int(milestones["second_detachment"]) < 0
				and _plan_has_forward_order(second_plan)
			):
				milestones["second_detachment"] = state.day
	var second_entry_id := int(milestones["second_entry_id"])
	if (
		second_entry_id >= 0
		and int(milestones["second_entry"]) < 0
		and state.cities[second_entry_id].owner_nation == ATTACKER
	):
		milestones["second_entry"] = state.day
	if (
		int(milestones["second_target"]) >= 0
		and int(milestones["second_defense"]) < 0
		and _has_defense_plan(state, chain[2], war_id)
		and not _has_defense_plan(state, chain[1], war_id)
	):
		milestones["second_defense"] = state.day
	if int(milestones["second_fu"]) < 0:
		for member_id in state.administrative_members(chain[2]):
			if member_id != chain[2] and state.cities[member_id].owner_nation == ATTACKER:
				milestones["second_fu"] = state.day
				break
	if int(milestones["second_center"]) < 0 and state.cities[chain[2]].owner_nation == ATTACKER:
		milestones["second_center"] = state.day
	if int(milestones["second_complete"]) < 0 and _state_controlled(state, chain[2], ATTACKER):
		milestones["second_complete"] = state.day
	if (
		dock_id >= 0
		and int(milestones["second_target"]) >= 0
		and int(milestones["river_crossed"]) < 0
	):
		for army in state.armies:
			if (
				army.owner_nation == ATTACKER
				and (
					army.location_city == dock_id
					or army.move_from == dock_id
					or army.move_to == dock_id
				)
			):
				milestones["river_crossed"] = state.day
				break


func _check_chain(
	state: GameState,
	chain: Array[int],
	entry_id: int,
	war_id: int,
	river_crossing: bool,
	crossing: Dictionary,
	milestones: Dictionary
) -> void:
	for key in [
		"first_defense", "first_entry", "first_camp", "first_camp_arrival",
		"first_camp_command", "first_detachment", "first_center",
		"first_complete", "second_target", "old_plan_released",
		"second_entry_id", "second_entry", "second_camp_id", "second_camp",
		"second_camp_arrival", "second_camp_command", "second_detachment",
		"second_defense", "second_fu", "second_center", "second_complete",
	]:
		_check(int(milestones[key]) >= 0, "链条里程碑未发生：%s" % key)
	var ordered := [
		"prepared", "declared", "first_entry", "first_camp",
		"first_camp_arrival", "first_detachment", "first_center",
		"first_complete", "second_target", "second_entry", "second_camp",
		"second_camp_arrival", "second_detachment", "second_center",
		"second_complete",
	]
	for index in range(1, ordered.size()):
		_check(
			int(milestones[ordered[index]]) >= int(milestones[ordered[index - 1]]),
			"战役里程碑顺序错误：%s" % str(milestones)
		)
	_check(_state_controlled(state, chain[1], ATTACKER), "第一州必须完整占领")
	_check(_state_controlled(state, chain[2], ATTACKER), "第二州必须完整占领")
	_check(
		state.administrative_center_of(int(milestones["second_camp_id"]))
			== chain[2],
		"换州后的新大营必须属于第二目标州"
	)
	_check(
		int(milestones["second_camp_id"]) != entry_id,
		"换州后不得继续复用第一州旧大营"
	)
	if river_crossing:
		var bank_a := int(crossing["bank_a"])
		var bank_b := int(crossing["bank_b"])
		var support := state.territorial_border_support_edges(bank_a, bank_b)
		_check(
			state.cities_share_territorial_border(bank_a, bank_b),
			"同一码头两岸属府必须仍是领土接壤"
		)
		_check(
			support.size() == 2
			and support[0].kind == Edge.Kind.LANDING
			and support[1].kind == Edge.Kind.LANDING,
			"跨河州界必须只由两条LANDING边支撑"
		)
		_check(int(milestones["river_crossed"]) >= 0, "进攻军必须实际经过共享码头")
	for army in state.armies:
		if army.owner_nation == ATTACKER and army.size > 0:
			_check(
				army.campaign_war_id in [-1, war_id],
				"进攻军不得串入其他战争池"
			)


func _plan_army_at_city(
	state: GameState,
	plan: AdministrativeCampaignPlan,
	city_id: int
) -> bool:
	for army in state.armies:
		if (
			army.owner_nation == ATTACKER
			and army.size > 0
			and plan.army_assignments.has(army.id)
			and (
				(not army.on_edge and army.location_city == city_id)
				or (army.on_edge and army.move_from == city_id)
			)
		):
			return true
	return false


func _plan_has_forward_order(plan: AdministrativeCampaignPlan) -> bool:
	return (
		not plan.tactical_target_city_ids.is_empty()
		and plan.phase in [
			AdministrativeCampaignPlan.Phase.RAID_FU,
			AdministrativeCampaignPlan.Phase.ASSAULT_CENTER,
			AdministrativeCampaignPlan.Phase.CLEANUP,
		]
	)


func _plan_uses_camp_as_anchor(
	state: GameState,
	plan: AdministrativeCampaignPlan,
	camp_id: int
) -> bool:
	if plan.army_assignments.values().has(camp_id):
		return true
	for army in state.armies:
		if (
			army.owner_nation == ATTACKER
			and army.size > 0
			and plan.army_assignments.has(army.id)
			and army.on_edge
			and army.move_from == camp_id
			and plan.tactical_target_city_ids.has(
				int(plan.army_assignments[army.id])
			)
		):
			return true
	return false


func _has_defense_plan(state: GameState, center_id: int, war_id: int) -> bool:
	var plan := state.campaign_plan(DEFENDER, center_id)
	return (
		plan != null
		and plan.mode == AdministrativeCampaignPlan.Mode.DEFENSE
		and plan.war_id == war_id
	)


func _state_controlled(state: GameState, center_id: int, owner_id: int) -> bool:
	for member_id in state.administrative_members(center_id):
		if state.cities[member_id].owner_nation != owner_id:
			return false
	return true


func _configure_territory(state: GameState, chain: Array[int]) -> void:
	for city in state.cities:
		city.owner_nation = NEUTRAL
		state.recognized_city_owners[city.id] = NEUTRAL
		city.occupation_sponsor_nation = -1
	for member_id in state.administrative_members(chain[0]):
		state.cities[member_id].owner_nation = ATTACKER
		state.recognized_city_owners[member_id] = ATTACKER
	for center_id in [chain[1], chain[2]]:
		for member_id in state.administrative_members(center_id):
			state.cities[member_id].owner_nation = DEFENDER
			state.recognized_city_owners[member_id] = DEFENDER
		state.cities[center_id].garrison_manpower = 3000
	state.nations[ATTACKER].capital_city_id = chain[0]
	state.nations[DEFENDER].capital_city_id = chain[2]


func _configure_resources(state: GameState, chain: Array[int]) -> void:
	for nation in state.nations:
		nation.manpower_pool = 0
		nation.treasury_gold = 1000000
	for city in state.cities:
		city.food_storage = 1000000
		city.has_warehouse = false
	for nation_id in [ATTACKER, DEFENDER]:
		var capital_id := state.nations[nation_id].capital_city_id
		state.cities[capital_id].has_warehouse = true
		state.nations[nation_id].warehouse_city_ids = [capital_id] as Array[int]


func _replace_state_border_with_local_crossing(
	state: GameState,
	center_a: int,
	center_b: int
) -> Dictionary:
	var bank_pair := _fu_border_pair(state, center_a, center_b)
	if bank_pair == Vector2i(-1, -1):
		return {}
	for edge in state.edges:
		var edge_center_a := state.administrative_center_of(edge.city_a)
		var edge_center_b := state.administrative_center_of(edge.city_b)
		if (
			edge.kind == Edge.Kind.LAND
			and (
				(edge_center_a == center_a and edge_center_b == center_b)
				or (edge_center_a == center_b and edge_center_b == center_a)
			)
		):
			edge.max_manpower = 0
			edge.base_max_manpower = 0
	var dock := City.new()
	dock.id = state.cities.size()
	dock.owner_nation = NEUTRAL
	dock.loyalty_target_nation = NEUTRAL
	dock.is_dock = true
	dock.politically_active = true
	dock.map_position = (
		state.cities[bank_pair.x].map_position
		+ state.cities[bank_pair.y].map_position
	) * 0.5
	state.cities.append(dock)
	state.adjacency[dock.id] = [] as Array[int]
	state.recognized_city_owners.append(NEUTRAL)
	state.administrative_region_ids.append(-1)
	state.administrative_center_by_city.append(-1)
	state.administrative_hop_distances.append(-1)
	state.region_ids.append(-1)
	state.node_betweenness.append(0.0)
	_add_typed_edge(state, bank_pair.x, dock.id, Edge.Kind.LANDING)
	_add_typed_edge(state, bank_pair.y, dock.id, Edge.Kind.LANDING)
	state.road_network_revision += 1
	_check(
		state.cities_share_territorial_border(bank_pair.x, bank_pair.y),
		"共享码头建立后两岸属府必须形成领土边界"
	)
	return {
		"bank_a": bank_pair.x,
		"bank_b": bank_pair.y,
		"dock": dock.id,
	}


func _fu_border_pair(
	state: GameState,
	center_a: int,
	center_b: int
) -> Vector2i:
	for pair in state.territorial_border_pairs():
		var pair_center_a := state.administrative_center_of(pair.x)
		var pair_center_b := state.administrative_center_of(pair.y)
		if pair_center_a == center_b and pair_center_b == center_a:
			pair = Vector2i(pair.y, pair.x)
			pair_center_a = center_a
			pair_center_b = center_b
		if (
			pair_center_a == center_a
			and pair_center_b == center_b
			and pair.x != center_a
			and pair.y != center_b
		):
			return pair
	return Vector2i(-1, -1)


func _add_typed_edge(
	state: GameState,
	city_a: int,
	city_b: int,
	kind: int
) -> void:
	var edge := Edge.new()
	edge.city_a = mini(city_a, city_b)
	edge.city_b = maxi(city_a, city_b)
	edge.kind = kind
	edge.distance = 1
	edge.max_manpower = 45000
	edge.base_max_manpower = 45000
	state.edges.append(edge)
	state.edge_lookup[GameState.edge_key(city_a, city_b)] = edge
	(state.adjacency[city_a] as Array[int]).append(city_b)
	(state.adjacency[city_b] as Array[int]).append(city_a)


func _entry_route(
	state: GameState,
	attacker_center: int,
	target_center: int
) -> Dictionary:
	for member_id in state.administrative_members(target_center):
		if member_id == target_center:
			continue
		for neighbor_id in state.territorial_border_neighbors(member_id):
			if state.administrative_center_of(neighbor_id) == attacker_center:
				return {"entry": member_id, "staging": neighbor_id}
	return {}


func _administrative_center_chain(state: GameState) -> Array[int]:
	var adjacency := {}
	for center_value in state.administrative_center_city_ids:
		adjacency[int(center_value)] = {}
	for pair in state.territorial_border_pairs():
		var center_a := state.administrative_center_of(pair.x)
		var center_b := state.administrative_center_of(pair.y)
		if center_a < 0 or center_b < 0 or center_a == center_b:
			continue
		(adjacency[center_a] as Dictionary)[center_b] = true
		(adjacency[center_b] as Dictionary)[center_a] = true
	var centers: Array[int] = []
	for center_value in adjacency:
		centers.append(int(center_value))
	EquivariantOrder.sort_city_ids(centers, state, ATTACKER)
	for middle in centers:
		var neighbors: Array[int] = []
		for neighbor_value in (adjacency[middle] as Dictionary):
			neighbors.append(int(neighbor_value))
		EquivariantOrder.sort_city_ids(neighbors, state, ATTACKER, middle)
		for first in neighbors:
			if not _centers_have_fu_border(state, first, middle):
				continue
			for second in neighbors:
				if (
					second != first
					and _centers_have_fu_border(state, middle, second)
				):
					return [first, middle, second] as Array[int]
	return []


func _centers_have_fu_border(
	state: GameState,
	source_center: int,
	target_center: int
) -> bool:
	for pair in state.territorial_border_pairs():
		var center_a := state.administrative_center_of(pair.x)
		var center_b := state.administrative_center_of(pair.y)
		if center_a == source_center and center_b == target_center:
			return pair.x != source_center and pair.y != target_center
		if center_b == source_center and center_a == target_center:
			return pair.y != source_center and pair.x != target_center
	return false


func _neutralize_diplomacy(state: GameState) -> void:
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)


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
		_failures.append(message)


func _finish(milestones: Dictionary) -> void:
	for failure in _failures:
		push_error("CAMPAIGN_CHAIN_E2E_FAIL: " + failure)
	print("CAMPAIGN_CHAIN_E2E_%s milestones=%s" % [
		"OK" if _failures.is_empty() else "FAILED",
		str(milestones),
	])
	quit(0 if _failures.is_empty() else 1)
