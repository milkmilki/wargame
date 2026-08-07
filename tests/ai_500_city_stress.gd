extends SceneTree
## 500 城压力测试：等比提高聚落密度生成 ~500 陆城的战场，跑若干天，
## 报告生成可行性 + AI 决策日耗时（稀疏化前后对比用）。可调环境变量：
##   AI_STRESS_CITIES(默认500) AI_STRESS_NATIONS(默认80) AI_STRESS_DAYS(默认120)

func _init() -> void:
	var cities := _env_int("AI_STRESS_CITIES", 500)
	var nations := _env_int("AI_STRESS_NATIONS", 80)
	var days := _env_int("AI_STRESS_DAYS", 120)
	var gen_start := Time.get_ticks_usec()
	var state := GameState.new()
	state.generate_world(12345, nations, cities)
	var gen_ms := float(Time.get_ticks_usec() - gen_start) / 1000.0
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)

	print("=== 500城压力测试 请求城=%d 国=%d ===" % [cities, nations])
	print("生成耗时=%.1fms 实际陆城=%d 总城(含码头)=%d 边=%d 军=%d" % [
		gen_ms,
		state.land_cities().size(),
		state.cities.size(),
		state.edges.size(),
		state.armies.size(),
	])

	var ai_times: Array[int] = []
	var all_times: Array[int] = []
	var run_start := Time.get_ticks_usec()
	for _d in range(days):
		if state.winner != -1:
			break
		var interval := Simulation.AI_DECISION_INTERVAL_DAYS
		var is_ai_day := state.day % interval == 0
		var t := Time.get_ticks_usec()
		sim._advance_day(false)
		var dt := Time.get_ticks_usec() - t
		all_times.append(dt)
		if is_ai_day:
			ai_times.append(dt)
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
	print("verdict=STRESS_DONE")
	sim.free()
	quit(0)


func _alive(state: GameState) -> int:
	var n := 0
	for nation in state.nations:
		if nation.alive:
			n += 1
	return n


func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if not v.is_empty() else fallback
