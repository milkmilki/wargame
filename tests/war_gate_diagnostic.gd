extends SceneTree
## 宣战瓶颈诊断：推进到指定年份后，枚举所有存活国对，统计宣战为何不发生。
## 区分“硬门槛挡住”（无合法目标）vs“评分不足”（有目标但 war_desire 达不到线）。

func _init() -> void:
	if OS.get_environment("PROBE_FIXTURES") == "1":
		quit(0 if _probe_conqueror_remnants() else 1)
		return
	var probe_year := _env_int("PROBE_YEAR", 20)
	var world_seed := _env_int("PROBE_SEED", 12345)
	var nations := _env_int("PROBE_NATIONS", 40)
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(world_seed, nations)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	while state.day < probe_year * 365 and state.winner == -1:
		sim._advance_day()
		if state.day % 365 == 0:
			print("WAR_PROBE_PROGRESS day=%d" % state.day)

	var alive := 0
	for n in state.nations:
		if n.alive:
			alive += 1
	# 统计联盟网密度
	var ally_pairs := 0
	var war_pairs := 0
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			if state.is_allied(a, b):
				ally_pairs += 1
			elif state.is_enemy(a, b):
				war_pairs += 1

	# 逐对分析：为什么不能/不宣战
	var cache := {}
	var can_declare := 0          # 通过 can_declare_war 基本门槛
	var has_frontier := 0         # 且接壤
	var no_shared_ally := 0       # 且无共同盟友
	var passes_hard_gate := 0     # 全部硬门槛通过（war_desire != -INF）
	var above_war_line := 0       # 且 war_desire >= WAR_DECLARE_SCORE
	var best_desire := -1e9
	var era := DiplomacyAI.unification_era_factor(state)

	for a in range(state.nations.size()):
		if not state.nations[a].alive:
			continue
		for b in range(state.nations.size()):
			if a == b or not state.nations[b].alive:
				continue
			if not state.can_declare_war(a, b):
				continue
			can_declare += 1
			var frontier := DiplomacyAI._frontier_edges(state, a, b, cache)
			if frontier > 0:
				has_frontier += 1
			var shared := DiplomacyAI._has_shared_ally(state, a, b, cache)
			if not shared:
				no_shared_ally += 1
			var desire := DiplomacyAI.war_desire(state, a, b, cache)
			if desire > -1e30:
				passes_hard_gate += 1
				if desire > best_desire:
					best_desire = desire
				if desire >= DiplomacyAI.WAR_DECLARE_SCORE:
					above_war_line += 1

	print("=== 宣战瓶颈诊断 year=%d seed=%d ===" % [probe_year, world_seed])
	print("alive=%d ally_pairs=%d war_pairs=%d era_factor=%.3f" % [
		alive, ally_pairs, war_pairs, era,
	])
	# 备战状态统计：区分“没想宣战” vs “想了但卡在备战集结”
	var preparing := 0
	var prep_targets: Array[int] = []
	for n in state.nations:
		if n.alive and n.war_preparation_target_nation >= 0:
			preparing += 1
			prep_targets.append(n.id)
	print("处于备战中(war_preparation_target>=0)的国家数=%d ids=%s" % [
		preparing, str(prep_targets),
	])
	# 累计外交事件分布：一锤定音区分“从没想打” vs “备战了但超时取消” vs “宣战了但速和”
	var action_counts := {}
	var peace_count := 0
	var zero_transfer_peaces := 0
	var transferred_total := 0
	var transferred_max := 0
	var surrender_peaces := 0
	for event in state.diplomatic_history:
		var k := int(event.get("action", -1))
		action_counts[k] = int(action_counts.get(k, 0)) + 1
		if k != DiplomacyAI.Action.MAKE_PEACE:
			continue
		peace_count += 1
		var transferred := int(event.get("territories_transferred", 0))
		transferred_total += transferred
		transferred_max = maxi(transferred_max, transferred)
		if transferred == 0:
			zero_transfer_peaces += 1
		if int(event.get("surrendering_nation", -1)) >= 0:
			surrender_peaces += 1
	print("外交事件累计分布(action_kind:次数): %s" % str(action_counts))
	print("  (参考 DiplomacyAI.Action 枚举：NONE/MAKE_PEACE/DECLARE_WAR/FORM_ALLIANCE/LEAVE_ALLIANCE/PREPARE_WAR/CANCEL_WAR_PREPARATION)")
	print(
		"议和成果: peaces=%d zero_transfer=%d transferred_total=%d max=%d surrenders=%d"
		% [
			peace_count,
			zero_transfer_peaces,
			transferred_total,
			transferred_max,
			surrender_peaces,
		]
	)
	print("有序对(可宣战基本门槛 can_declare_war)=%d" % can_declare)
	print("  其中接壤(frontier>0)=%d" % has_frontier)
	print("  其中无共同盟友(no_shared_ally)=%d" % no_shared_ally)
	print("  通过全部硬门槛(war_desire!=-INF)=%d" % passes_hard_gate)
	print("  且评分>=宣战线%.2f 的=%d" % [DiplomacyAI.WAR_DECLARE_SCORE, above_war_line])
	print("通过硬门槛者的最高 war_desire=%.3f" % best_desire)
	_probe_regional_remnants(state)
	if passes_hard_gate == 0:
		print("verdict=BLOCKED_BY_HARD_GATE")
	elif above_war_line == 0:
		print("verdict=BLOCKED_BY_SCORE best=%.3f line=%.2f" % [
			best_desire, DiplomacyAI.WAR_DECLARE_SCORE,
		])
	else:
		print("verdict=WAR_POSSIBLE count=%d" % above_war_line)
	sim.free()
	quit(0)


func _probe_regional_remnants(state: GameState) -> void:
	var cache := {}
	for nation in state.nations:
		if not nation.alive or state.is_vassal(nation.id):
			continue
		var integration := RegionalStrategy.integration_report(state, nation.id)
		var total := int(integration.total)
		if total <= 0 or (float(integration.integrated) / total < 0.75 and nation.ruler_archetype != RulerProfile.CONQUEROR):
			continue
		var region := int(integration.region_id)
		var owners := {}
		for city_id in RegionalStrategy.geometry(state)["members"].get(region, []):
			var owner := state.cities[int(city_id)].owner_nation
			if owner != nation.id and not state.is_same_suzerainty_system(nation.id, owner):
				owners[owner] = true
		print("REGIONAL_REMNANT nation=%d ruler=%s progress=%d/%d complete=%s preparation=%d wars=%d direct_neighbors=%s expansion_neighbors=%s remaining_owners=%s" % [
			nation.id, RulerProfile.archetype_name(nation.ruler_archetype), integration.integrated, total,
			integration.complete, nation.war_preparation_target_nation, state.active_war_count(nation.id),
			DiplomacyAI._direct_bordering_nation_ids(state, nation.id, cache),
			DiplomacyAI._expansion_bordering_nation_ids(state, nation.id, cache), owners.keys()])
		for owner in owners:
			_probe_pair(state, nation.id, int(owner), cache)


func _probe_pair(state: GameState, nation_id: int, target_id: int, cache: Dictionary = {}) -> Dictionary:
	var nation := state.nations[nation_id]
	var resources := DiplomacyAI.resource_report(state, nation_id, cache)
	var objective := DiplomacyAI._cached_war_objective(state, nation_id, target_id, cache)
	var food := DiplomacyAI.war_food_report(state, nation_id,
		DiplomacyAI._campaign_troop_target(state, nation_id, target_id, cache),
		DiplomacyAI.FoodPosture.OFFENSIVE_WAR, cache)
	var attitude := DiplomacyAI.diplomatic_attitude(state, nation_id, target_id, cache)
	var ratio := DiplomacyAI._national_power(state, nation_id, cache) / maxf(DiplomacyAI._coalition_power(state, target_id, cache), 1.0)
	var terms := {
		"power_ratio": ratio,
		"target_distraction": state.active_war_count(target_id) * 0.25,
		"border": minf(DiplomacyAI._frontier_edges(state, nation_id, target_id, cache) * 0.10, 0.50),
		"reserve_quality": minf(float(food.target_runway_years) / DiplomacyAI.OFFENSIVE_CAMPAIGN_YEARS, 1.5) * 0.20,
		"objective": minf(float(objective.get("value", 0.0)) * 0.05, 0.50),
		"mobilization": DiplomacyAI.mobilization_capacity(state, nation_id, DiplomacyAI.FoodPosture.OFFENSIVE_WAR, cache) * 0.15,
		"regional_rivalry": DiplomacyAI.unification_rivalry(state, nation_id, target_id, cache),
		"integration": RegionalStrategy.integration_war_bonus(state, nation_id, target_id),
		"peace_escalation": DiplomacyAI.neutral_peace_escalation(state, nation_id, target_id),
	}
	var positive := 0.0
	for value in terms.values():
		positive += float(value)
	var benefit_multiplier := RulerProfile.war_benefit_multiplier(nation)
	var aggression := state.effective_ai_aggression(nation_id) - 1.0
	var attitude_penalty := attitude * DiplomacyAI.ATTITUDE_WAR_WEIGHT
	var overextension := state.active_war_count(nation_id) * 0.75
	var gates := {
		"peaceful_polity_border_or_expedition": DiplomacyAI.can_initiate_war_at_range(state, nation_id, target_id, cache),
		"neutral_and_truce_expired": state.can_declare_war(nation_id, target_id),
		"alliance_declaration": DiplomacyAI._cached_can_alliance_declare_war(state, nation_id, target_id, cache),
		"no_shared_ally": not DiplomacyAI._has_shared_ally(state, nation_id, target_id, cache),
		"war_limit": state.active_war_count(nation_id) < DiplomacyAI.MAX_CONCURRENT_WARS,
		"resource_reserves": DiplomacyAI.offensive_resources_ready(state, nation_id, resources),
		"campaign_food": DiplomacyAI.offensive_food_sustainable(state, food),
		"legal_objective": not objective.is_empty(),
		"ruler_objective": not objective.is_empty() and DiplomacyAI._ruler_allows_war_objective(state, nation_id, int(objective.get("city_id", -1))),
		"independent_actor": not state.is_vassal(nation_id),
		"preparation_cooldown": nation.war_preparation_cancelled_day < 0 or state.day - nation.war_preparation_cancelled_day >= DiplomacyAI.WAR_PREPARATION_CANCEL_COOLDOWN_DAYS,
	}
	var blocked: Array[String] = []
	for gate in gates:
		if gate == "ruler_objective" and objective.is_empty():
			continue
		if not bool(gates[gate]):
			blocked.append(str(gate))
	var era := DiplomacyAI.unification_era_factor(state)
	var manpower_required := maxi(roundi(lerpf(DiplomacyAI.MIN_MANPOWER_RESERVE,
		DiplomacyAI.MIN_MANPOWER_RESERVE / 5.0, era)),
		ceili(float(resources.troops) * lerpf(0.15, DiplomacyAI.TOTAL_WAR_MANPOWER_SHARE, era)))
	var capacity := state.manpower_pool_capacity(nation_id)
	if capacity > 0:
		manpower_required = mini(manpower_required, capacity)
	var result := {
		"nation": nation_id, "target": target_id, "blocked": blocked,
		"actual_desire": str(DiplomacyAI.war_desire(state, nation_id, target_id, cache)),
		"ungated_score_estimate": positive * benefit_multiplier + aggression - attitude_penalty - overextension,
		"threshold": DiplomacyAI.WAR_DECLARE_SCORE, "positive_terms": terms,
		"benefit_multiplier": benefit_multiplier, "aggression": aggression,
		"attitude_penalty": attitude_penalty, "war_penalty": overextension,
		"gold": nation.treasury_gold, "gold_required": roundi(float(resources.gold_reserve_target) * (1.0 - era)),
		"manpower": nation.manpower_pool, "manpower_required": manpower_required,
		"food_years": resources.food_runway_years, "full_food_years": food.target_runway_years,
		"leave_alliance_desire": str(DiplomacyAI.leave_alliance_desire(state, nation_id, target_id, cache)),
		"leave_threshold": DiplomacyAI.LEAVE_ALLIANCE_SCORE,
	}
	if objective.is_empty():
		result["objective_candidates"] = _probe_objective_candidates(state, nation_id, target_id, cache)
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(state, actions, {}, {}, nation_id, nation_id + 1)
	result["collected_actions"] = actions.size()
	print("WAR_GATE_DETAIL " + JSON.stringify(result))
	return result


func _probe_objective_candidates(state: GameState, nation_id: int, target_id: int, cache: Dictionary) -> Array[Dictionary]:
	var centers := {}
	for city in state.cities_of(target_id):
		var center := state.administrative_center_of(city.id)
		if center >= 0:
			centers[center] = true
	var rows: Array[Dictionary] = []
	for center_id in centers:
		var direct_candidates: Array[int] = []
		for city_id in state.administrative_members(int(center_id)):
			if state.cities[city_id].owner_nation == target_id and not DiplomacyAI.staging_cities_for_objective(state, nation_id, city_id, cache).is_empty():
				direct_candidates.append(city_id)
		var plan := state.campaign_front_for(nation_id, int(center_id), CoalitionCampaignFront.Mode.OFFENSE)
		rows.append({"center": center_id, "owner": state.cities[int(center_id)].owner_nation,
			"region_allowed": RegionalStrategy.allows_objective(state, nation_id, int(center_id)),
			"direct_entry_candidates": direct_candidates,
			"committed": 0 if plan == null else state.campaign_committed_manpower(nation_id, int(center_id)),
			"requirement": state.campaign_required_manpower(nation_id,
				DiplomacyAI._cached_campaign_siege_requirement(state, nation_id, int(center_id), cache)
				+ DiplomacyAI._cached_campaign_reinforcement_threat(state, nation_id, int(center_id), cache)),
			"tactical_target": DiplomacyAI.administrative_tactical_target(state, nation_id, target_id, int(center_id), -1, false, cache)})
	return rows


func _probe_conqueror_remnants() -> bool:
	var valid := true
	for scenario in ["neutral", "capital_only_remnant", "allied_remnant", "shared_ally", "vassal_border", "no_manpower", "no_gold"]:
		var state := _remnant_fixture()
		match scenario:
			"capital_only_remnant":
				state.cities[27].owner_nation = 0
				state.recognized_city_owners[27] = 0
				state.ownership_revision += 1
				state.armies[6].location_city = 28
				state.armies[6].move_from = 28
			"allied_remnant":
				state.nations[1].strategic_region_anchor_city_id = 29
				state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
				state.diplomatic_since_day[state._diplomacy_key(0, 1)] = 0
			"shared_ally":
				state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
				state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.ALLIED)
			"vassal_border":
				state.nations[2].strategic_region_anchor_city_id = 0
				state.cities[26].owner_nation = 2
				state.recognized_city_owners[26] = 2
				state.suzerainty[2] = {"overlord_id": 0, "civil_war": false}
				state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
				state.ownership_revision += 1
			"no_manpower":
				state.nations[0].manpower_pool = 0
			"no_gold":
				state.nations[0].treasury_gold = 0
		print("WAR_GATE_SCENARIO " + scenario)
		var report := RegionalStrategy.integration_report(state, 0)
		print("WAR_GATE_PROGRESS %d/%d" % [report.integrated, report.total])
		var detail := _probe_pair(state, 0, 1)
		var expected_actions := 1 if scenario in ["neutral", "capital_only_remnant", "vassal_border"] else 0
		if int(detail.collected_actions) != expected_actions:
			valid = false
			push_error("WAR_GATE_FIXTURE unexpected preparation count in " + scenario)
		if scenario == "allied_remnant" and float(detail.leave_alliance_desire) < DiplomacyAI.LEAVE_ALLIANCE_SCORE:
			valid = false
			push_error("WAR_GATE_FIXTURE allied remnant must include regional integration exit benefit")
		if scenario == "capital_only_remnant":
			var front := CoalitionCampaignFront.new()
			front.mode = CoalitionCampaignFront.Mode.OFFENSE
			front.center_city_id = 28
			front.army_assignments[state.armies[0].id] = 28
			state.register_campaign_front(front, [0] as Array[int], 0)
			var tactical := DiplomacyAI.administrative_tactical_target(state, 0, 1, 28)
			print("WAR_GATE_SYNTHETIC_BINDING committed=%d tactical_target=%d" % [state.campaign_committed_manpower(0, 28), tactical])
			if tactical != 28:
				valid = false
				push_error("WAR_GATE_FIXTURE synthetic binding must isolate the capital selection dependency")
		if scenario == "vassal_border":
			var vassal := _probe_pair(state, 2, 1)
			if float(vassal.actual_desire) < DiplomacyAI.WAR_DECLARE_SCORE or int(vassal.collected_actions) != 0:
				valid = false
				push_error("WAR_GATE_FIXTURE border vassal must be willing but excluded as an actor")
	print("WAR_GATE_FIXTURES_RESULT valid=%s" % valid)
	return valid


func _remnant_fixture() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.day = 3650
	for owner in range(3):
		var nation := Nation.new()
		nation.id = owner
		nation.capital_city_id = [0, 28, 29][owner]
		nation.strategic_region_anchor_city_id = 0 if owner < 2 else 29
		nation.treasury_gold = 1000000
		nation.manpower_pool = 1000000
		nation.granary_food = 1000000
		nation.ruler_archetype = RulerProfile.CONQUEROR if owner != 1 else RulerProfile.BALANCED
		nation.ruler_traits.clear()
		state.nations.append(nation)
	for id in range(30):
		var owner := 0 if id < 27 else (1 if id < 29 else 2)
		var center := 0 if id < 27 else (28 if id < 29 else 29)
		var city := City.new()
		city.id = id
		city.owner_nation = owner
		city.map_position = Vector2(id, 0)
		city.gold_per_month = 1000
		city.food_per_half_year = 100000
		city.manpower_per_month = 1000
		city.food_storage = 1000000
		city.garrison_manpower = 1000 if id == center else 0
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		state.region_ids.append(0 if id < 29 else 1)
		state.administrative_center_by_city.append(center)
		state.recognized_city_owners.append(owner)
		if id == center:
			state.administrative_center_city_ids.append(id)
		if id > 0:
			state._add_edge(id - 1, id)
	for a in range(3):
		for b in range(a + 1, 3):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	for owner in range(3):
		for _formation in range(6 if owner == 0 else 1):
			var army := Army.new()
			army.id = state.armies.size()
			army.owner_nation = owner
			army.location_city = [26, 27, 29][owner]
			army.move_from = army.location_city
			army.size = 15000
			army.max_size = 15000
			army.morale = 2.0
			army.max_morale = 2.0
			army.ruler_attack_multiplier = RulerProfile.attack_multiplier(state.nations[owner])
			army.ruler_defense_multiplier = RulerProfile.defense_multiplier(state.nations[owner])
			army.ruler_morale_multiplier = RulerProfile.morale_multiplier(state.nations[owner])
			state.armies.append(army)
	return state


func _env_int(key: String, fallback: int) -> int:
	var raw := OS.get_environment(key)
	return int(raw) if not raw.is_empty() else fallback
