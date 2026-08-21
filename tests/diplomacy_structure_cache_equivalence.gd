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
	print(
		"=== 外交结构缓存等价校验 (%d国/%d城/%d天) ==="
		% [nations, cities, days]
	)
	print("长期状态不一致=%d 动作列表不一致=%d" % [
		state_mismatches, action_mismatches,
	])
	var mismatches := state_mismatches + action_mismatches
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
			or city.fort_strength != other.fort_strength
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
	for nation in legacy.nations:
		if _nation_fp(nation) != _nation_fp(optimized.nations[nation.id]):
			mismatches += 1
	return mismatches


func _nation_fp(nation: Nation) -> String:
	return str([
		nation.alive, nation.treasury_gold, nation.manpower_pool,
		nation.granary_food, nation.war_preparation_target_nation,
		nation.war_preparation_objective_city,
		nation.campaign_preparation_targets,
		nation.campaign_preparation_assignments,
		nation.campaign_attack_assignments,
	])


func _army_fp(army: Army) -> String:
	return str([
		army.owner_nation, army.size, army.state, army.location_city,
		army.move_from, army.move_to, army.move_progress, army.path,
		army.morale, army.supply_ratio, army.ai_action,
		army.ai_target_city, army.line_assignment_city,
	])


func _env_int(key: String, fallback: int) -> int:
	var value := OS.get_environment(key)
	return int(value) if not value.is_empty() else fallback
