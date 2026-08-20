extends SceneTree
## 等价性守卫：资源缓存贯通与单 tick 决策上下文只能消除重复计算，不得改变 AI 结果。


func _init() -> void:
	var days := _env_int("AI_CONTEXT_EQUIV_DAYS", 365)
	var nations := _env_int("AI_CONTEXT_EQUIV_NATIONS", 40)
	var cities := _env_int("AI_CONTEXT_EQUIV_CITIES", 160)
	var legacy := _run_world(nations, cities, days, true, true)
	var cold_context := _run_world(nations, cities, days, false, true)
	var optimized := _run_world(nations, cities, days, false, false)
	var legacy_mismatches := _compare_states(legacy.state, optimized.state)
	var cache_reuse_mismatches := _compare_states(
		cold_context.state, optimized.state
	)
	var mismatches := legacy_mismatches + cache_reuse_mismatches
	print("=== AI 决策上下文等价校验 (%d国/%d城/%d天) ===" % [
		nations,
		cities,
		days,
	])
	print("旧上下文→优化 不一致=%d" % legacy_mismatches)
	print("冷资源缓存→快照缓存复用 不一致=%d" % cache_reuse_mismatches)
	print(
		"verdict=%s"
		% (
			"AI_CONTEXT_EQUIVALENT"
			if mismatches == 0
			else "AI_CONTEXT_DIVERGED"
		)
	)
	legacy.free()
	cold_context.free()
	optimized.free()
	quit(0 if mismatches == 0 else 1)


func _run_world(
	nations: int,
	cities: int,
	days: int,
	legacy_path: bool,
	disable_snapshot_resource_reuse: bool
) -> Simulation:
	var world := GameState.new()
	world.generate_world(12345, nations, cities)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(world)
	sim.ai_force_resource_cache_disabled = legacy_path
	sim.ai_decision_context_disabled = legacy_path
	sim.ai_snapshot_resource_cache_reuse_disabled = (
		disable_snapshot_resource_reuse
	)
	for _day in range(days):
		if world.winner != -1:
			break
		sim._advance_day(false)
	return sim


func _compare_states(legacy: GameState, optimized: GameState) -> int:
	var mismatches := 0
	if legacy.day != optimized.day or legacy.winner != optimized.winner:
		mismatches += 1
	for city in legacy.cities:
		var other := optimized.cities[city.id]
		if (
			city.owner_nation != other.owner_nation
			or not is_equal_approx(city.fort_strength, other.fort_strength)
			or city.food_storage != other.food_storage
		):
			mismatches += 1
			if mismatches <= 10:
				print("city=%d 不一致" % city.id)
	for nation in legacy.nations:
		var other := optimized.nations[nation.id]
		if _nation_fp(nation) != _nation_fp(other):
			mismatches += 1
			if mismatches <= 10:
				print("nation=%d 不一致" % nation.id)
	var optimized_armies := {}
	for army in optimized.armies:
		optimized_armies[army.id] = army
	if legacy.armies.size() != optimized.armies.size():
		mismatches += 1
	for army in legacy.armies:
		var other: Army = optimized_armies.get(army.id)
		if other == null or _army_fp(army) != _army_fp(other):
			mismatches += 1
			if mismatches <= 10:
				print("army=%d 不一致" % army.id)
	return mismatches


func _nation_fp(nation: Nation) -> String:
	return str([
		nation.alive,
		nation.treasury_gold,
		nation.manpower_pool,
		nation.granary_food,
		nation.last_food_demand,
		nation.food_demand_ema,
		nation.war_preparation_target_nation,
		nation.war_preparation_objective_city,
		nation.campaign_preparation_targets,
		nation.campaign_preparation_assignments,
		nation.campaign_attack_assignments,
		nation.campaign_active_echelons,
		nation.campaign_launched_armies,
	])


func _army_fp(army: Army) -> String:
	return str([
		army.owner_nation,
		army.size,
		army.state,
		army.location_city,
		army.move_from,
		army.move_to,
		army.move_progress,
		army.path,
		army.morale,
		army.supply_ratio,
		army.supply_food_debt,
		army.starving,
		army.strategic_role,
		army.battle_group_id,
		army.ai_action,
		army.ai_target_city,
		army.ai_order_until_day,
		army.line_assignment_city,
	])


func _env_int(key: String, fallback: int) -> int:
	var value := OS.get_environment(key)
	return int(value) if not value.is_empty() else fallback
