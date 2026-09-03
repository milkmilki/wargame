extends SceneTree
## 500 城压力测试：等比提高聚落密度生成 ~500 陆城的战场，跑若干天，
## 报告生成可行性、贸易结构规模/耗时和 AI 分阶段耗时（稀疏化前后对比用）。可调环境变量：
##   AI_STRESS_CITIES(默认500) AI_STRESS_NATIONS(默认80) AI_STRESS_DAYS(默认120)
##   AI_STRESS_SEED(默认12345)
##   AI_STRESS_VISIBILITY_HOPS(默认-1；A/B 基准使用 7 或 10)
##   AI_STRESS_SPREAD_RUNTIME(默认0；1 模拟实际分帧/工作线程路径)

func _init() -> void:
	var cities := _env_int("AI_STRESS_CITIES", 500)
	var nations := _env_int("AI_STRESS_NATIONS", 80)
	var days := _env_int("AI_STRESS_DAYS", 120)
	var world_seed := _env_int("AI_STRESS_SEED", 12345)
	var visibility_hops := _env_int("AI_STRESS_VISIBILITY_HOPS", -1)
	var spread_runtime_work := _env_int("AI_STRESS_SPREAD_RUNTIME", 0) != 0
	var gen_start := Time.get_ticks_usec()
	var state := GameState.new()
	state.generate_world(world_seed, nations, cities)
	var gen_ms := float(Time.get_ticks_usec() - gen_start) / 1000.0
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.ai_visibility_hops = visibility_hops
	var diplomatic_range_cache := {}
	var diplomatic_pairs := 0
	var diplomatic_range_symmetric := true
	var diplomatic_degree := PackedInt32Array()
	diplomatic_degree.resize(state.nations.size())
	diplomatic_degree.fill(0)
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			var forward := DiplomacyAI.within_diplomatic_range(
				state, nation_a, nation_b, diplomatic_range_cache
			)
			var reverse := DiplomacyAI.within_diplomatic_range(
				state, nation_b, nation_a, diplomatic_range_cache
			)
			diplomatic_range_symmetric = (
				diplomatic_range_symmetric and forward == reverse
			)
			if forward:
				diplomatic_pairs += 1
				diplomatic_degree[nation_a] += 1
				diplomatic_degree[nation_b] += 1
	var all_diplomatic_pairs := (
		state.nations.size() * (state.nations.size() - 1) / 2
	)

	print("=== 500城压力测试 请求城=%d 国=%d seed=%d ===" % [
		cities, nations, world_seed,
	])
	print("AI 可见范围=%s" % (
		"全知" if visibility_hops < 0 else "%d 跳" % visibility_hops
	))
	print("运行时分帧/工作线程=%s" % ("开启" if spread_runtime_work else "关闭"))
	print("生成耗时=%.1fms 实际陆城=%d 总城(含码头)=%d 边=%d 军=%d" % [
		gen_ms,
		state.land_cities().size(),
		state.cities.size(),
		state.edges.size(),
		state.armies.size(),
	])
	var trade_profile := {"enabled": true}
	TradeNetwork.reset_connectivity_prefilter_counters()
	var trade_started := Time.get_ticks_usec()
	var trade_structure := TradeNetwork.build_structure(
		state, true, trade_profile
	)
	var trade_ms := float(
		Time.get_ticks_usec() - trade_started
	) / 1000.0
	var international_routes := 0
	var minimum_international_hops := 2147483647
	var international_counts := PackedInt32Array()
	international_counts.resize(state.nations.size())
	international_counts.fill(0)
	for route_value in trade_structure.get("routes", []):
		var route: Dictionary = route_value
		if not bool(route.get("international", false)):
			continue
		international_routes += 1
		international_counts[int(route["nation_a"])] += 1
		international_counts[int(route["nation_b"])] += 1
		var preferred_path: Array = route.get(
			"preferred_city_path", []
		)
		if not preferred_path.is_empty():
			minimum_international_hops = mini(
				minimum_international_hops, preferred_path.size() - 1
			)
	print("贸易结构=%.1fms 路线=%d 国际=%d 国际最短跳数=%s" % [
		trade_ms,
		(trade_structure.get("routes", []) as Array).size(),
		international_routes,
		(
			str(minimum_international_hops)
			if minimum_international_hops < 2147483647 else "无"
		),
	])
	print("外交两跳候选=%d/%d (%.1f%%)" % [
		diplomatic_pairs, all_diplomatic_pairs,
		100.0 * float(diplomatic_pairs)
			/ maxf(float(all_diplomatic_pairs), 1.0),
	])
	var minimum_diplomatic_degree := 0
	if not diplomatic_degree.is_empty():
		minimum_diplomatic_degree = diplomatic_degree[0]
		for degree in diplomatic_degree:
			minimum_diplomatic_degree = mini(
				minimum_diplomatic_degree, degree
			)
	print("外交两跳最少对象数=%d" % minimum_diplomatic_degree)
	_print_trade_profile(trade_profile)
	var initial_trade_counters := (
		TradeNetwork.connectivity_prefilter_counters()
	)

	var ai_times: Array[int] = []
	var all_times: Array[int] = []
	var phase_totals := {}
	var invariant_failure_day := -1
	sim.tick_phase_profiling_enabled = true
	sim.ai_snapshot_substage_profiling_enabled = true
	var run_start := Time.get_ticks_usec()
	for _d in range(days):
		if state.winner != -1:
			break
		var t := Time.get_ticks_usec()
		sim._advance_day(spread_runtime_work)
		var dt := Time.get_ticks_usec() - t
		all_times.append(dt)
		for stage_value in sim.tick_profile_last_usec:
			var stage := str(stage_value)
			phase_totals[stage] = (
				int(phase_totals.get(stage, 0))
				+ int(sim.tick_profile_last_usec[stage_value])
			)
		if (
			sim.tick_profile_last_usec.has("ai_view_setup")
			or sim.tick_profile_last_usec.has("ai")
		):
			ai_times.append(dt)
		if invariant_failure_day < 0 and not state.territory_structure_valid():
			invariant_failure_day = state.day
	var run_ms := float(Time.get_ticks_usec() - run_start) / 1000.0

	var ai_avg := 0
	var ai_peak := 0
	for v in ai_times:
		ai_avg += v
		ai_peak = maxi(ai_peak, v)
	var ordinary_avg := 0
	var ord_n := 0
	for i in range(all_times.size()):
		if all_times[i] < ai_peak / 4:
			ordinary_avg += all_times[i]
			ord_n += 1
	print("推进 %d 天总耗时=%.1fms" % [state.day, run_ms])
	print("AI决策日: n=%d 均值=%.1fms 峰值=%.1fms" % [
		ai_times.size(),
		float(ai_avg) / 1000.0 / maxf(float(ai_times.size()), 1.0),
		float(ai_peak) / 1000.0,
	])
	print("存活国=%d winner=%d" % [_alive(state), state.winner])
	print("贸易缓存 structure=%d/%d forecast=%d/%d" % [
		sim.trade_structure_build_total,
		sim.trade_structure_cache_hit_total,
		sim.trade_forecast_build_total,
		sim.trade_forecast_cache_hit_total,
	])
	_print_runtime_hotspots(phase_totals, maxi(state.day, 1))
	var route_limits_valid := true
	for count in international_counts:
		route_limits_valid = (
			route_limits_valid
			and count <= TradeNetwork.MAX_INTERNATIONAL_ROUTES_PER_NATION
		)
	var candidate_bound := (
		nations * TradeNetwork.MAX_INTERNATIONAL_PARTNERS_PER_NATION
	)
	var ok := (
		state.land_cities().size() == cities
		and minimum_international_hops
			>= TradeNetwork.MIN_INTERNATIONAL_ROUTE_HOPS
		and route_limits_valid
		and international_routes > 0
		and int(initial_trade_counters.get(
			"candidate_connectivity_queries", 0
		)) <= candidate_bound
		and diplomatic_range_symmetric
		and diplomatic_pairs > 0
		and diplomatic_pairs < all_diplomatic_pairs
		and minimum_diplomatic_degree > 0
		and invariant_failure_day < 0
		and sim.ai_command_commit_failure_total == 0
	)
	print("健康检查 territory_invalid_day=%d commit_failures=%d candidate_bound=%d" % [
		invariant_failure_day, sim.ai_command_commit_failure_total, candidate_bound,
	])
	print("verdict=%s" % ("STRESS_PASS" if ok else "STRESS_FAIL"))
	sim.free()
	quit(0 if ok else 1)


func _alive(state: GameState) -> int:
	var n := 0
	for nation in state.nations:
		if nation.alive:
			n += 1
	return n


func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if not v.is_empty() else fallback


func _print_trade_profile(profile: Dictionary) -> void:
	for key in [
		"ai_snapshot_forecast_structure_international_candidates",
		"ai_snapshot_forecast_structure_international_candidates_pair_prefilter",
		"ai_snapshot_forecast_structure_international_candidates_pair_iteration_count",
		"ai_snapshot_forecast_structure_international_candidates_emitted",
		"ai_snapshot_forecast_structure_international_candidates_union_gate",
		"ai_snapshot_forecast_structure_international_routes",
	]:
		if not profile.has(key):
			continue
		var value := int(profile[key])
		print("贸易剖析 %s=%s" % [
			key,
			str(value) if key.ends_with("count") or key.ends_with("emitted")
			else "%.2fms" % (float(value) / 1000.0),
		])


func _print_runtime_hotspots(totals: Dictionary, days: int) -> void:
	var rows: Array[Dictionary] = []
	for stage_value in totals:
		var stage := str(stage_value)
		if stage == "total" or stage.ends_with("_count"):
			continue
		rows.append({"stage": stage, "usec": int(totals[stage_value])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["usec"]) != int(b["usec"]):
			return int(a["usec"]) > int(b["usec"])
		return str(a["stage"]) < str(b["stage"])
	)
	print("运行热点（前12项，日均）:")
	for row in rows.slice(0, mini(12, rows.size())):
		print("  %s=%.2fms" % [
			str(row["stage"]),
			float(row["usec"]) / 1000.0 / float(days),
		])
