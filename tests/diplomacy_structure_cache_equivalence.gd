extends SceneTree
## 外交结构缓存等价守卫：联盟集团、集团战争时长和敌对集团数量的
## 单 tick 缓存只能消除重复遍历，不得改变动作选择或长期世界状态。


func _init() -> void:
	var days := _env_int("DIPLOMACY_CACHE_EQUIV_DAYS", 365)
	var nations := _env_int("DIPLOMACY_CACHE_EQUIV_NATIONS", 40)
	var cities := _env_int("DIPLOMACY_CACHE_EQUIV_CITIES", 160)
	var legacy := _run_world(nations, cities, days, true)
	var optimized := _run_world(nations, cities, days, false)
	var state_mismatches := _compare_states(legacy.state, optimized.state)
	var legacy_actions := DiplomacyAI.choose_actions(
		optimized.state, {}, false
	)
	var optimized_actions := DiplomacyAI.choose_actions(
		optimized.state, {}, true
	)
	var action_mismatches := (
		0 if str(legacy_actions) == str(optimized_actions) else 1
	)
	var prefilter_state := GameState.new()
	prefilter_state.generate_world(12345, nations, cities)
	prefilter_state.day = DiplomacyAI.MIN_NEUTRAL_DAYS
	DiplomacyAI.alliance_acceptance_prefilter_disabled = true
	var unfiltered_alliance_actions := DiplomacyAI.choose_actions(
		prefilter_state, {}, true
	)
	DiplomacyAI.alliance_acceptance_prefilter_disabled = false
	DiplomacyAI.reset_alliance_acceptance_prefilter_counters()
	var filtered_alliance_actions := DiplomacyAI.choose_actions(
		prefilter_state, {}, true
	)
	var prefilter_counters := (
		DiplomacyAI.alliance_acceptance_prefilter_counters()
	)
	var prefilter_mismatches := (
		0
		if str(unfiltered_alliance_actions) == str(filtered_alliance_actions)
		else 1
	)
	if int(prefilter_counters.get("prunes", 0)) <= 0:
		prefilter_mismatches += 1
	if prefilter_state.nations.size() >= 2:
		prefilter_state.set_diplomatic_relation(
			0, 1, GameState.DiplomaticRelation.WAR
		)
	DiplomacyAI.reset_campaign_v_index_counters()
	var campaign_v_cache := {}
	var campaign_v_mismatches := 0
	var nonzero_campaign_v := 0
	for attacker_id in range(prefilter_state.nations.size()):
		for center_value in prefilter_state.administrative_center_city_ids:
			var center_id := int(center_value)
			var indexed_v := DiplomacyAI._cached_campaign_reinforcement_threat(
				prefilter_state, attacker_id, center_id, campaign_v_cache
			)
			var direct_v := prefilter_state.campaign_reinforcement_threat(
				attacker_id, center_id
			)
			if direct_v > 0:
				nonzero_campaign_v += 1
			if indexed_v != direct_v:
				campaign_v_mismatches += 1
	var campaign_v_counters := DiplomacyAI.campaign_v_index_counters()
	if (
		int(campaign_v_counters.get("builds", 0))
			> prefilter_state.nations.size()
		or nonzero_campaign_v <= 0
		or int(campaign_v_counters.get("hits", 0)) <= 0
		or int(campaign_v_counters.get("legacy_scans", 0)) != 0
	):
		campaign_v_mismatches += 1
	if action_mismatches > 0:
		print("legacy_actions=%s" % str(legacy_actions))
		print("optimized_actions=%s" % str(optimized_actions))
	print(
		"=== 外交结构缓存等价校验 (%d国/%d城/%d天) ==="
		% [nations, cities, days]
	)
	print("长期状态不一致=%d 动作列表不一致=%d 结盟预筛不一致=%d V索引不一致=%d 预筛=%s V索引=%s" % [
		state_mismatches, action_mismatches, prefilter_mismatches,
		campaign_v_mismatches, str(prefilter_counters),
		str(campaign_v_counters),
	])
	var mismatches := (
		state_mismatches + action_mismatches + prefilter_mismatches
		+ campaign_v_mismatches
	)
	print("verdict=%s" % (
		"DIPLOMACY_STRUCTURE_CACHE_EQUIVALENT"
		if mismatches == 0
		else "DIPLOMACY_STRUCTURE_CACHE_DIVERGED"
	))
	legacy.free()
	optimized.free()
	quit(0 if mismatches == 0 else 1)


func _run_world(
	nations: int,
	cities: int,
	days: int,
	disable_cache: bool
) -> Simulation:
	var world := GameState.new()
	world.generate_world(12345, nations, cities)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(world)
	sim.diplomacy_structure_cache_disabled = disable_cache
	for _day in range(days):
		if world.winner != -1:
			break
		sim._advance_day(false)
	return sim


func _compare_states(legacy: GameState, optimized: GameState) -> int:
	var mismatches := 0
	if (
		legacy.day != optimized.day
		or legacy.winner != optimized.winner
		or str(legacy.diplomatic_history)
			!= str(optimized.diplomatic_history)
	):
		mismatches += 1
	for city in legacy.cities:
		var other := optimized.cities[city.id]
		if (
			city.owner_nation != other.owner_nation
			or legacy.recognized_owner_of(city.id)
				!= optimized.recognized_owner_of(city.id)
			or city.garrison_manpower != other.garrison_manpower
			or city.food_storage != other.food_storage
		):
			mismatches += 1
	var optimized_armies := {}
	for army in optimized.armies:
		optimized_armies[army.id] = army
	if legacy.armies.size() != optimized.armies.size():
		mismatches += 1
	for army in legacy.armies:
		var other: Army = optimized_armies.get(army.id)
		if other == null or _army_fp(army) != _army_fp(other):
			mismatches += 1
	if legacy.nations.size() != optimized.nations.size():
		mismatches += 1
	for nation in legacy.nations:
		if (
			nation.id >= optimized.nations.size()
			or _nation_fp(nation) != _nation_fp(optimized.nations[nation.id])
		):
			mismatches += 1
	return mismatches


func _nation_fp(nation: Nation) -> String:
	return str([
		nation.alive, nation.treasury_gold, nation.manpower_pool,
		nation.granary_food, nation.war_preparation_target_nation,
		nation.war_preparation_objective_city,
		nation.campaign_objective_center_city,
	])


func _army_fp(army: Army) -> String:
	return str([
		army.owner_nation, army.size, army.state, army.location_city,
		army.move_from, army.move_to, army.move_progress, army.path,
		army.morale, army.supply_ratio, army.ai_action,
		army.ai_target_city,
	])


func _env_int(key: String, fallback: int) -> int:
	var value := OS.get_environment(key)
	return int(value) if not value.is_empty() else fallback
