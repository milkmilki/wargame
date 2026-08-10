extends SceneTree
## 40 国统一进度观测：推进到出现统一者或达到年数上限，定期打印势力集中度。
## 用于验收“N 年内完成一次完整统一”，也可作为数值调整前后的 A/B 基准。
## 环境变量：UNIFY_NATIONS/UNIFY_YEARS/UNIFY_SEED/UNIFY_SAMPLE_DAYS/UNIFY_LOG。

var _log: FileAccess = null


func _init() -> void:
	var nations := _env_int("UNIFY_NATIONS", 40)
	var max_years := _env_int("UNIFY_YEARS", 100)
	var world_seed := _env_int("UNIFY_SEED", 12345)
	var sample_days := _env_int("UNIFY_SAMPLE_DAYS", 1095)
	var max_days := max_years * 365
	var log_path := OS.get_environment("UNIFY_LOG")
	if not log_path.is_empty():
		_log = FileAccess.open(log_path, FileAccess.WRITE)

	var state := GameState.new()
	state.generate_world(world_seed, nations)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)

	_emit("=== 统一进度 国=%d seed=%d 上限=%d年(%d天) 采样=%d天 ===" % [
		nations, world_seed, max_years, max_days, sample_days,
	])
	var started := Time.get_ticks_msec()
	_sample(state, Time.get_ticks_msec() - started)
	while state.day < max_days and state.winner == -1:
		sim._advance_day()
		if state.day % sample_days == 0:
			_sample(state, Time.get_ticks_msec() - started)
	_sample(state, Time.get_ticks_msec() - started)
	if state.winner != -1:
		_emit("verdict=UNIFIED winner=%d year=%.1f day=%d elapsed=%.1fs" % [
			state.winner,
			float(state.day) / 365.0,
			state.day,
			float(Time.get_ticks_msec() - started) / 1000.0,
		])
	else:
		_emit("verdict=NO_UNIFICATION_IN_%dY alive=%d elapsed=%.1fs" % [
			max_years,
			_alive(state),
			float(Time.get_ticks_msec() - started) / 1000.0,
		])
	if _log != null:
		_log.close()
	sim.free()
	quit(0)


func _emit(line: String) -> void:
	print(line)
	if _log != null:
		_log.store_line(line)
		_log.flush()


func _sample(state: GameState, elapsed_ms: int) -> void:
	var counts := {}
	for city in state.cities:
		if city.owner_nation < 0:
			continue
		counts[city.owner_nation] = int(counts.get(city.owner_nation, 0)) + 1
	var total := 0
	for nid in counts:
		total += int(counts[nid])
	total = maxi(total, 1)
	var max_share := 0.0
	var hhi := 0.0
	for nid in counts:
		var share := float(counts[nid]) / float(total)
		hhi += share * share
		if share > max_share:
			max_share = share
	var wars := 0
	var alliances := 0
	for a in range(state.nations.size()):
		if not state.nations[a].alive:
			continue
		for b in range(a + 1, state.nations.size()):
			if not state.nations[b].alive:
				continue
			if state.is_enemy(a, b):
				wars += 1
			elif state.is_allied(a, b):
				alliances += 1
	_emit("  year=%5.1f day=%6d alive=%2d max_share=%.3f HHI=%.4f wars=%d allies=%d %.1fs" % [
		float(state.day) / 365.0,
		state.day,
		_alive(state),
		max_share,
		hhi,
		wars,
		alliances,
		float(elapsed_ms) / 1000.0,
	])


func _alive(state: GameState) -> int:
	var count := 0
	for nation in state.nations:
		if nation.alive:
			count += 1
	return count


func _env_int(key: String, fallback: int) -> int:
	var raw := OS.get_environment(key)
	return int(raw) if not raw.is_empty() else fallback
