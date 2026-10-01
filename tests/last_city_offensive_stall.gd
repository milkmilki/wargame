extends SceneTree
## 终局回归：国家0仅剩州治首都和四支标准主战军；国家1控制其他全部城市，
## 从零按国家可持续容量重建主战军。州战役必须从已有军队中完成集结，不能在
## “州治尚不可攻击”和“尚未分配军队增加 C”之间形成循环等待。
## 末州为无属府州；拔营及残府收复由 campaign_camp_counteroffensive 单独覆盖。

const REMNANT_ID: int = 0
const DOMINANT_ID: int = 1
const LAST_CITY_ID: int = 41
const RUN_DAYS: int = 720


func _init() -> void:
	var state := _build_fixture()
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	state.nations[DOMINANT_ID].ruler_archetype = RulerProfile.BALANCED
	state.nations[DOMINANT_ID].ruler_traits.clear()
	state.nations[DOMINANT_ID].strategic_region_anchor_city_id = LAST_CITY_ID
	state.regional_strategy_revision += 1
	sim.diplomacy_enabled = false
	sim.enfeoff_enabled = false
	var launched := false
	var captured := false
	var first_attack := {}
	var previous_army_count := state.active_army_count(DOMINANT_ID)
	var recruitment_capacity_stable := true
	var diagnostic := OS.get_environment("LAST_CITY_DIAG") == "1"
	for _day in range(_env_int("LAST_CITY_RUN_DAYS", RUN_DAYS)):
		sim._advance_day()
		if diagnostic and (_day < 5 or _day in range(58, 73) or _day % 10 == 0):
			_print_dispatch_diagnostic(state, sim, _day + 1)
		var current_army_count := state.active_army_count(DOMINANT_ID)
		if current_army_count > previous_army_count:
			var immediate_capacity := DiplomacyAI.force_capacity_report(
				state,
				DOMINANT_ID,
				DiplomacyAI.FoodPosture.OFFENSIVE_WAR,
				{}
			)
			recruitment_capacity_stable = (
				current_army_count
					<= int(immediate_capacity["supportable_armies"])
			)
		previous_army_count = current_army_count
		var nation := state.nations[DOMINANT_ID]
		if first_attack.is_empty():
			for army in state.armies:
				if (
					army.owner_nation == DOMINANT_ID
					and army.is_main_battle_role()
					and army.ai_action == ActionCandidate.Kind.ATTACK
					and army.campaign_front_id >= 0
					and state.campaign_front(army.campaign_front_id) != null
					and state.campaign_front(army.campaign_front_id).mode == CoalitionCampaignFront.Mode.OFFENSE
					and army.ai_target_city == LAST_CITY_ID
				):
					first_attack = {
						"day": state.day,
						"army": army.id,
						"size": army.size,
						"max": army.max_size,
						"reason": army.ai_order_reason,
					}
		launched = not first_attack.is_empty()
		captured = state.cities[LAST_CITY_ID].owner_nation == DOMINANT_ID
		if launched or captured or not state.is_enemy(DOMINANT_ID, REMNANT_ID):
			break
	print(
		"verdict=%s day=%d launched=%s owner=%d groups=%d main=%s force=%s first=%s administrative=%s"
		% [
			"LAST_CAPITAL_ATTACK_LAUNCHED" if launched else "LAST_CAPITAL_STALLED",
			state.day,
			str(launched),
			state.cities[LAST_CITY_ID].owner_nation,
			state.nations[DOMINANT_ID].battle_groups.size(),
			str(_main_army_snapshot(state)),
			state.nations[DOMINANT_ID].ai_last_force_reason,
			str(first_attack),
			str(_administrative_snapshot(state)),
		]
	)
	sim.free()
	quit(0 if launched and recruitment_capacity_stable else 1)


func _main_army_snapshot(state: GameState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for army in state.armies:
		if army.owner_nation == DOMINANT_ID and army.is_main_battle_role():
			result.append({
				"id": army.id,
				"size": army.size,
				"max": army.max_size,
				"group": army.battle_group_id,
				"state": army.state,
				"action": army.ai_action,
				"target": army.ai_target_city,
			})
	return result


func _print_dispatch_diagnostic(state: GameState, sim: Simulation, elapsed: int) -> void:
	var fronts: Array[Dictionary] = []
	for front_value in state.campaign_fronts.values():
		var front := front_value as CoalitionCampaignFront
		fronts.append({"id": front.front_id, "members": front.participant_nation_ids,
			"center": front.center_city_id, "mode": front.mode, "phase": front.phase,
			"C": sim._front_effective_manpower(front), "assignments": front.army_assignments,
			"receiver": state.campaign_receiving_city(front), "locked": front.combat_report_locked,
			"camp": front.camp_city_id, "camp_food": state.cities[front.camp_city_id].food_storage if front.camp_city_id >= 0 else -1})
	var pairs: Array[Dictionary] = []
	for pair_value in state.campaign_pairs.values():
		var pair := pair_value as CoalitionCampaignPair
		pairs.append({"id": pair.pair_id, "a": pair.side_a_nation_ids, "b": pair.side_b_nation_ids,
			"slots": pair.battlefields, "cooldown": pair.cooldown_until_by_nation,
			"dominant_proposal_C": sim._pair_proposal_force(pair, [DOMINANT_ID] as Array[int])})
	var troops: Array[Dictionary] = []
	var army_totals := {"count": 0, "bound": 0, "idle_unlocked": 0, "moving": 0, "deployment_locked": 0}
	for army in state.armies:
		if army.owner_nation != DOMINANT_ID:
			continue
		army_totals["count"] += 1
		army_totals["bound"] += int(army.campaign_front_id >= 0)
		army_totals["moving"] += int(army.state == Army.State.MOVING)
		army_totals["deployment_locked"] += int(army.defensive_deployment_until_day > state.day)
		army_totals["idle_unlocked"] += int(army.state == Army.State.IDLE and army.defensive_deployment_until_day <= state.day)
		if troops.size() >= 10 and army.campaign_front_id < 0:
			continue
		troops.append({"id": army.id, "size": army.size, "state": army.state,
			"city": army.current_city_node(), "war": army.campaign_war_id, "front": army.campaign_front_id,
			"effective": state.army_effective_for_field_campaign(army), "deployment_until": army.defensive_deployment_until_day,
			"order_until": army.ai_order_until_day, "action": army.ai_action,
			"target": army.ai_target_city, "morale": army.morale, "supply": army.supply_ratio})
	var proposal := {}
	for component in state.coalition_campaign_components():
		if (component["members"] as Array[int]).has(DOMINANT_ID):
			proposal = sim._select_component_objective(component, {}, {})
			break
	var nation := state.nations[DOMINANT_ID]
	print("LAST_CITY_DIAG elapsed=%d fronts=%s pairs=%s army_totals=%s troops=%s legal=%s objective=%s ruler=%s military=%s" % [
		elapsed, str(fronts), str(pairs), str(army_totals), str(troops),
		DiplomacyAI._ruler_allows_war_objective(state, DOMINANT_ID, LAST_CITY_ID), str(proposal),
		str({"archetype": nation.ruler_archetype, "traits": nation.ruler_traits,
			"started": nation.ruler_started_day, "anchor": nation.strategic_region_anchor_city_id}),
		state.nations[DOMINANT_ID].ai_last_force_reason])


func _administrative_snapshot(state: GameState) -> Dictionary:
	var center_id := state.administrative_center_of(LAST_CITY_ID)
	var plan := state.campaign_front_for(DOMINANT_ID, center_id)
	var defender_armies: Array[Dictionary] = []
	for army in state.armies:
		if army.owner_nation == REMNANT_ID:
			defender_armies.append({
				"id": army.id,
				"size": army.size,
				"state": army.state,
				"city": army.current_city_node(),
			})
	return {
		"center": center_id,
		"is_zhou": state.is_zhou_city(LAST_CITY_ID),
		"center_owner": (
			state.cities[center_id].owner_nation if center_id >= 0 else -1
		),
		"objective_center": state.campaign_objective_center(DOMINANT_ID),
		"plan_center": plan.center_city_id if plan != null else -1,
		"plan_phase": plan.phase if plan != null else -1,
		"assignments": (
			plan.army_assignments.duplicate() if plan != null else {}
		),
		"C": state.campaign_committed_manpower(DOMINANT_ID, center_id),
		"R": state.campaign_siege_requirement(DOMINANT_ID, center_id),
		"V": state.campaign_reinforcement_threat(
			DOMINANT_ID, center_id
		),
		"garrison": state.cities[center_id].garrison_manpower if center_id >= 0 else -1,
		"defender_armies": defender_armies,
	}


func _build_fixture() -> GameState:
	var state := GameState.new()
	state.generate_world(12345, 4)
	assert(
		state.is_zhou_city(LAST_CITY_ID),
		"末城夹具必须选择行政州治"
	)
	state.day = 60 * 365
	# Keep the terminal mobilization scenario independent of camp succession:
	# an enemy-held fu would otherwise be a real unfinished recapture task.
	for member_id in state.administrative_members(LAST_CITY_ID):
		if member_id == LAST_CITY_ID:
			continue
		var nearest_center := -1
		var nearest_distance := INF
		for center_id in state.administrative_center_city_ids:
			if center_id == LAST_CITY_ID:
				continue
			var distance := state.cities[member_id].map_position.distance_squared_to(state.cities[center_id].map_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_center = center_id
		state.administrative_center_by_city[member_id] = nearest_center
	state.administrative_region_revision += 1
	assert(state.administrative_members(LAST_CITY_ID) == [LAST_CITY_ID])
	state.armies.clear()
	state.battles.clear()
	for nation in state.nations:
		# This is a mobilization/capacity fixture, not a sixty-year succession replay.
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
		nation.ruler_started_day = state.day
		nation.battle_groups.clear()
		nation.next_battle_group_id = 0
		nation.alive = nation.id in [REMNANT_ID, DOMINANT_ID]
		nation.warehouse_city_ids.clear()
		nation.capital_city_id = -1
		nation.war_preparation_target_nation = -1
		nation.war_preparation_objective_city = -1
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	for city in state.cities:
		city.owner_nation = (
			REMNANT_ID
			if city.id == LAST_CITY_ID
			else DOMINANT_ID
		)
		state.recognized_city_owners[city.id] = city.owner_nation
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
	state.set_diplomatic_relation(
		REMNANT_ID,
		DOMINANT_ID,
		GameState.DiplomaticRelation.WAR
	)
	state.set_war_objective(
		DOMINANT_ID,
		REMNANT_ID,
		LAST_CITY_ID,
		"last-capital administrative campaign regression"
	)
	var staging := DiplomacyAI.staging_cities_for_objective(
		state,
		DOMINANT_ID,
		LAST_CITY_ID
	)
	assert(not staging.is_empty(), "末州首都必须存在合法集结城市")
	var entry_edge := state.edge_of(staging[0], LAST_CITY_ID)
	assert(
		entry_edge != null
			and entry_edge.max_manpower > 0,
		"末州首都必须存在正容量入口"
	)
	entry_edge.max_manpower = Edge.TERRAIN_LOW_MANPOWER
	entry_edge.base_max_manpower = Edge.TERRAIN_LOW_MANPOWER
	var dominant_capital := staging[0]
	var farthest_distance := -1.0
	for city in state.land_cities_of(DOMINANT_ID):
		var distance := city.map_position.distance_squared_to(
			state.cities[LAST_CITY_ID].map_position
		)
		if distance > farthest_distance:
			farthest_distance = distance
			dominant_capital = city.id
	state.nations[REMNANT_ID].capital_city_id = LAST_CITY_ID
	state.nations[REMNANT_ID].warehouse_city_ids = [
		LAST_CITY_ID
	] as Array[int]
	state.cities[LAST_CITY_ID].is_capital = true
	state.cities[LAST_CITY_ID].has_warehouse = true
	state.cities[LAST_CITY_ID].food_storage = 10000
	state.nations[DOMINANT_ID].capital_city_id = dominant_capital
	state.nations[DOMINANT_ID].warehouse_city_ids = [
		dominant_capital
	] as Array[int]
	state.cities[dominant_capital].is_capital = true
	state.cities[dominant_capital].has_warehouse = true
	state.cities[dominant_capital].food_storage = 1000000
	state.nations[REMNANT_ID].treasury_gold = 1000
	state.nations[REMNANT_ID].manpower_pool = 0
	state.nations[DOMINANT_ID].treasury_gold = 1000000
	state.nations[DOMINANT_ID].manpower_pool = 1000000
	state.nations[DOMINANT_ID].military_payment_ratio = 1.0
	for garrison_index in range(4):
		var garrison := state.create_army(
			REMNANT_ID,
			LAST_CITY_ID,
			GameState.INITIAL_HEAVY_ARMY_SIZE,
			GameState.INITIAL_HEAVY_ARMY_SIZE
		)
		if garrison == null:
			garrison = Army.new()
			garrison.id = 100000 + garrison_index
			garrison.owner_nation = REMNANT_ID
			garrison.size = GameState.INITIAL_HEAVY_ARMY_SIZE
			garrison.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
			garrison.max_morale = Army.DEFAULT_MAX_MORALE
			garrison.morale = Army.DEFAULT_MAX_MORALE
			garrison.location_city = LAST_CITY_ID
			garrison.move_from = LAST_CITY_ID
			garrison.state = Army.State.IDLE
			state.armies.append(garrison)
		garrison.attack = 10
		garrison.defense = 10
	var initial_groups := _env_int("LAST_CITY_MAIN_GROUPS", 0)
	for _group_index in range(initial_groups):
		var group := state.create_battle_group(DOMINANT_ID)
		for _army_index in range(BattleGroup.MAX_ARMIES):
			var main_army := state.create_army(
				DOMINANT_ID,
				dominant_capital,
				GameState.INITIAL_HEAVY_ARMY_SIZE,
				GameState.INITIAL_HEAVY_ARMY_SIZE
			)
			main_army.attack = 15
			main_army.defense = 15
			assert(state.assign_army_to_battle_group(main_army, group.id))
	state.refresh_derived()
	return state


func _env_int(key: String, fallback: int) -> int:
	var raw := OS.get_environment(key)
	return int(raw) if not raw.is_empty() else fallback
