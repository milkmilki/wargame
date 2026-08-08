extends SceneTree
## 纯计算量测量：同步 _advance_day(false) 逐日计时，隔离「一个 tick 需要多少计算」，
## 不受运行时 _time_acc 调度与分帧跨帧等待干扰。用于判断决策日/普通日的纯计算墙钟
## 是否超过 8x 视觉预算（125ms/tick）——超则计算追不上播放，插值无法根治顿挫。

func _init() -> void:
	var nations := _env_int("COMPUTE_NATIONS", 40)
	var cities := _env_int("COMPUTE_CITIES", 160)
	var days := _env_int("COMPUTE_DAYS", 365)
	var speed := _env_int("COMPUTE_SPEED", 8)

	var state := GameState.new()
	state.generate_world(12345, nations, cities)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	var budget_ms := 1000.0 / float(speed)

	var peak := 0.0
	var sum := 0.0
	var n := 0
	var over_budget := 0
	var peak_day := 0
	var over_month := 0
	for _d in range(days):
		if state.winner != -1:
			break
		var t0 := Time.get_ticks_usec()
		sim._advance_day(false)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		if ms > peak:
			peak = ms
			peak_day = state.day
		sum += ms
		n += 1
		if ms > budget_ms:
			over_budget += 1
			if state.day % 30 == 0:
				over_month += 1

	print("=== 纯计算量测量 国=%d 城=%d 推进%d天 (8x视觉预算=%.1fms/tick) ===" % [
		nations, cities, state.day, budget_ms,
	])
	print("每日tick 纯计算: 峰值=%.1fms(第%d天) 均值=%.1fms (n=%d)" % [
		peak, peak_day, sum / maxf(float(n), 1.0), n,
	])
	print("超视觉预算的天数: %d / %d (%.1f%%)，其中月结算日 %d 天" % [
		over_budget, n, 100.0 * float(over_budget) / maxf(float(n), 1.0),
		over_month,
	])
	print("峰值/预算 = %.2fx  均值/预算 = %.2fx" % [
		peak / budget_ms,
		(sum / maxf(float(n), 1.0)) / budget_ms,
	])
	print("verdict=COMPUTE_MEASURE_DONE")
	sim.free()
	quit(0)


func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if not v.is_empty() else fallback
