extends SceneTree
## 非 headless 的 500 城渲染基准。先暂停模拟测纯渲染，再开启模拟测端到端帧耗时。
## 可调：RENDER_BENCH_FRAMES（默认180）、RENDER_BENCH_SCENE（默认五百城场景）、
## RENDER_BENCH_SEED（默认12345，覆盖压力场景的启动随机种子）、
## RENDER_BENCH_DAYS（大于0时至少推进指定天数）、RENDER_BENCH_WAR_PAIRS
## （从接壤国家中确定性选取的强制战争对数）、RENDER_BENCH_SIEGES
## （在这些战争对上注入的持续围城数）。

var _frame_samples: Array[float] = []


class FrameSampler:
	extends Node
	signal sampled

	func _process(_delta: float) -> void:
		sampled.emit()


func _init() -> void:
	var scene_path := OS.get_environment("RENDER_BENCH_SCENE")
	if scene_path.is_empty():
		scene_path = "res://five_hundred_city_stress.tscn"
	var frame_count := _env_int("RENDER_BENCH_FRAMES", 180)
	var target_days := _env_int("RENDER_BENCH_DAYS", 0)
	var requested_war_pairs := _env_int("RENDER_BENCH_WAR_PAIRS", 0)
	var requested_sieges := _env_int("RENDER_BENCH_SIEGES", 0)
	var world_seed := _env_int("RENDER_BENCH_SEED", 12345)
	var sample_gpu_counters := _env_int("RENDER_BENCH_GPU_COUNTERS", 0) != 0
	var zoom_frames := _env_int("RENDER_BENCH_ZOOM_FRAMES", 0)
	var seconds_per_day := float(OS.get_environment(
		"RENDER_BENCH_SECONDS_PER_DAY"
	))
	var serial_workers := _env_int("RENDER_BENCH_SERIAL_WORKERS", 0) != 0
	var runtime_catchup := _env_int("RENDER_BENCH_RUNTIME_CATCHUP", 0) != 0
	var diplomacy_worker := _env_int("RENDER_BENCH_DIPLOMACY_WORKER", 0) != 0
	var legacy_ai_commit := _env_int("RENDER_BENCH_LEGACY_AI_COMMIT", 0) != 0
	var packed := load(scene_path) as PackedScene
	if packed == null:
		printerr("render benchmark scene load failed: %s" % scene_path)
		quit(1)
		return
	var main := packed.instantiate()
	main.set("randomize_world_seed_on_start", false)
	main.set("world_seed", world_seed)
	root.add_child(main)
	for _i in range(60):
		await process_frame
	var simulation := main.get_node_or_null("Simulation") as Simulation
	var forced_wars: Array[Vector2i] = []
	if simulation != null:
		simulation.paused = true
		forced_wars = _force_adjacent_wars(
			simulation.state, requested_war_pairs
		)
	var seeded_sieges := _seed_sieges(
		simulation, forced_wars, requested_sieges
	)
	var render_only := await _sample_frames(
		frame_count, 0, sample_gpu_counters, null
	)
	var zoom_render := {}
	if zoom_frames > 0:
		zoom_render = await _sample_frames(
			zoom_frames, 0, sample_gpu_counters, null,
			main.get_node_or_null("StrategicMap3D") as StrategicMap3D
		)
	if simulation != null:
		simulation.paused = false
		simulation.runtime_stage_profiling_enabled = true
		simulation.ai_parallel_threat_disabled = serial_workers
		simulation.ai_parallel_defense_disabled = serial_workers
		simulation.supply_network_parallel_prebuild_disabled = serial_workers
		simulation.runtime_catchup_during_day_enabled = runtime_catchup
		simulation.diplomacy_frame_slicing_disabled = diplomacy_worker
		simulation.ai_command_commit_slicing_disabled = legacy_ai_commit
		if seconds_per_day > 0.0:
			simulation.seconds_per_day = seconds_per_day
	var with_simulation := await _sample_frames(
		frame_count, target_days, sample_gpu_counters, simulation
	)
	if simulation != null:
		simulation.paused = true
		while simulation.runtime_day_in_progress():
			await process_frame
	print("=== 渲染基准 scene=%s seed=%d frames=%d target_days=%d ===" % [
		scene_path, world_seed, frame_count, target_days,
	])
	print("强制战争 requested=%d actual=%d pairs=%s" % [
		requested_war_pairs, forced_wars.size(), str(forced_wars),
	])
	print("注入围城 requested=%d actual=%d" % [
		requested_sieges, seeded_sieges,
	])
	print("节点数=%d" % _count_nodes(main))
	_print_stats("纯渲染（模拟暂停）", render_only)
	if not zoom_render.is_empty():
		_print_stats("连续缩放（模拟暂停）", zoom_render)
	_print_stats("渲染+模拟", with_simulation)
	if simulation != null:
		_print_runtime_spans(simulation)
	main.queue_free()
	await process_frame
	quit(0)


func _sample_frames(
	frame_count: int,
	target_days: int,
	sample_gpu_counters: bool,
	simulation: Simulation,
	zoom_map: StrategicMap3D = null
) -> Dictionary:
	var samples: Array[float] = []
	var draw_calls: Array[float] = []
	var primitives: Array[float] = []
	var objects: Array[float] = []
	var slow_frames_by_stage := {}
	var slow_streak_16 := 0
	var slow_streak_33 := 0
	var max_slow_streak_16 := 0
	var max_slow_streak_33 := 0
	var peak_activity := {
		"moving_armies": 0,
		"field_battles": 0,
		"sieges": 0,
		"war_pairs": 0,
	}
	var starting_day := simulation.state.day if simulation != null else 0
	var activity_sampled_day := -1
	var sampler := FrameSampler.new()
	sampler.process_priority = 2_147_483_647
	root.add_child(sampler)
	await sampler.sampled
	var sampled_frames := 0
	var interval_stage := _runtime_stage(simulation)
	while (
		sampled_frames < maxi(frame_count, 1)
		or (
			simulation != null
			and target_days > 0
			and simulation.state.day - starting_day < target_days
		)
	):
		var started := Time.get_ticks_usec()
		if zoom_map != null:
			zoom_map._zoom_camera(
				0.88 if sampled_frames % 2 == 0 else 1.0 / 0.88
			)
		await sampler.sampled
		sampled_frames += 1
		var frame_ms := float(Time.get_ticks_usec() - started) / 1000.0
		samples.append(frame_ms)
		slow_streak_16 = slow_streak_16 + 1 if frame_ms > 16.0 else 0
		slow_streak_33 = slow_streak_33 + 1 if frame_ms > 33.0 else 0
		max_slow_streak_16 = maxi(max_slow_streak_16, slow_streak_16)
		max_slow_streak_33 = maxi(max_slow_streak_33, slow_streak_33)
		var elapsed_stage := interval_stage
		interval_stage = _runtime_stage(simulation)
		if simulation != null and frame_ms > 16.0:
			var key := str(elapsed_stage)
			var report: Dictionary = slow_frames_by_stage.get(key, {
				"over_16": 0, "over_33": 0, "peak_ms": 0.0,
				"peak_day": -1,
			})
			report["over_16"] = int(report["over_16"]) + 1
			if frame_ms > 33.0:
				report["over_33"] = int(report["over_33"]) + 1
			if frame_ms > float(report["peak_ms"]):
				report["peak_ms"] = frame_ms
				report["peak_day"] = simulation.state.day
			slow_frames_by_stage[key] = report
		if sample_gpu_counters:
			draw_calls.append(float(Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
			)))
			primitives.append(float(Performance.get_monitor(
				Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
			)))
			objects.append(float(Performance.get_monitor(
				Performance.RENDER_TOTAL_OBJECTS_IN_FRAME
			)))
		if (
			simulation != null
			and simulation.state.day != activity_sampled_day
		):
			_sample_activity(simulation.state, peak_activity)
			activity_sampled_day = simulation.state.day
	samples.sort()
	var total := 0.0
	for value in samples:
		total += value
	var result := {
		"avg_ms": total / float(samples.size()),
		"p95_ms": samples[mini(int(samples.size() * 0.95), samples.size() - 1)],
		"max_ms": samples.back(),
		"fps_avg": 1000.0 / maxf(total / float(samples.size()), 0.001),
		"draw_calls_avg": _average(draw_calls),
		"primitives_avg": _average(primitives),
		"objects_avg": _average(objects),
		"draw_calls_max": _max_value(draw_calls),
		"slow_frames_by_stage": slow_frames_by_stage,
		"max_slow_streak_16": max_slow_streak_16,
		"max_slow_streak_33": max_slow_streak_33,
		"sampled_frames": sampled_frames,
		"peak_activity": peak_activity,
		"days_advanced": (
			simulation.state.day - starting_day if simulation != null else 0
		),
	}
	sampler.queue_free()
	return result


func _print_stats(label: String, stats: Dictionary) -> void:
	print("%s avg=%.2fms p95=%.2fms max=%.2fms fps=%.1f" % [
		label,
		float(stats["avg_ms"]),
		float(stats["p95_ms"]),
		float(stats["max_ms"]),
		float(stats["fps_avg"]),
	])
	print("  sampled_frames=%d" % int(stats["sampled_frames"]))
	print("  max_slow_streak >16ms=%d >33ms=%d" % [
		int(stats["max_slow_streak_16"]),
		int(stats["max_slow_streak_33"]),
	])
	if int(stats["days_advanced"]) > 0:
		print("  advanced_days=%d" % int(stats["days_advanced"]))
	print("  draw_calls avg=%.1f max=%.1f primitives=%.1f objects=%.1f" % [
		float(stats["draw_calls_avg"]),
		float(stats["draw_calls_max"]),
		float(stats["primitives_avg"]),
		float(stats["objects_avg"]),
	])
	var stage_reports: Dictionary = stats["slow_frames_by_stage"]
	var stages := stage_reports.keys()
	stages.sort_custom(func(a: Variant, b: Variant) -> bool:
		return float(stage_reports[a]["peak_ms"]) > float(stage_reports[b]["peak_ms"])
	)
	for stage in stages:
		var report: Dictionary = stage_reports[stage]
		print("  %-24s >16ms=%d >33ms=%d peak=%.2fms day=%d" % [
			stage, int(report["over_16"]), int(report["over_33"]),
			float(report["peak_ms"]),
			int(report.get("peak_day", -1)),
		])
	var activity: Dictionary = stats["peak_activity"]
	if int(activity["war_pairs"]) > 0:
		print("  activity peak: wars=%d moving=%d field=%d siege=%d" % [
			int(activity["war_pairs"]), int(activity["moving_armies"]),
			int(activity["field_battles"]), int(activity["sieges"]),
		])


func _force_adjacent_wars(
	state: GameState, requested_pairs: int
) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var seen := {}
	for edge in state.edges:
		var owner_a := state.cities[edge.city_a].owner_nation
		var owner_b := state.cities[edge.city_b].owner_nation
		if owner_a == owner_b or owner_a < 0 or owner_b < 0:
			continue
		var pair := Vector2i(mini(owner_a, owner_b), maxi(owner_a, owner_b))
		if not seen.has(pair):
			seen[pair] = true
			candidates.append(pair)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	var selected: Array[Vector2i] = []
	var used_nations := {}
	for pair in candidates:
		if selected.size() >= requested_pairs:
			break
		if used_nations.has(pair.x) or used_nations.has(pair.y):
			continue
		selected.append(pair)
		used_nations[pair.x] = true
		used_nations[pair.y] = true
	for pair in candidates:
		if selected.size() >= requested_pairs:
			break
		if selected.has(pair):
			continue
		selected.append(pair)
	for pair in selected:
		state.set_diplomatic_relation(
			pair.x, pair.y, GameState.DiplomaticRelation.WAR
		)
	return selected


func _seed_sieges(
	simulation: Simulation,
	war_pairs: Array[Vector2i],
	requested_sieges: int
) -> int:
	if simulation == null or requested_sieges <= 0:
		return 0
	var state := simulation.state
	var seeded := 0
	var used_armies := {}
	var used_cities := {}
	for pair in war_pairs:
		if seeded >= requested_sieges:
			break
		var siege_edge: Edge = null
		var target_city_id := -1
		for edge in state.edges:
			var owner_a := state.cities[edge.city_a].owner_nation
			var owner_b := state.cities[edge.city_b].owner_nation
			if owner_a == pair.x and owner_b == pair.y:
				siege_edge = edge
				target_city_id = edge.city_b
				break
			if owner_a == pair.y and owner_b == pair.x:
				siege_edge = edge
				target_city_id = edge.city_a
				break
		if siege_edge == null or used_cities.has(target_city_id):
			continue
		var attacker: Army = null
		for army in state.armies:
			if (
				army.owner_nation == pair.x
				and army.size > 0
				and not used_armies.has(army.id)
			):
				attacker = army
				break
		if attacker == null:
			continue
		var target := state.cities[target_city_id]
		target.fort_strength = maxi(target.fort_strength, 100)
		attacker.state = Army.State.IDLE
		attacker.on_edge = false
		attacker.location_city = target_city_id
		attacker.move_from = target_city_id
		attacker.move_to = -1
		attacker.move_progress = 0.0
		attacker.path.clear()
		simulation._start_or_join_siege(attacker, target, siege_edge)
		if attacker.state != Army.State.FIGHTING:
			continue
		used_armies[attacker.id] = true
		used_cities[target_city_id] = true
		seeded += 1
	return seeded


func _sample_activity(state: GameState, peak: Dictionary) -> void:
	var moving := 0
	for army in state.armies:
		if army.size > 0 and army.state in [
			Army.State.MOVING, Army.State.RETREATING,
		]:
			moving += 1
	var fields := 0
	var sieges := 0
	for battle in state.battles:
		if battle.finished:
			continue
		if battle.kind == Battle.Kind.FIELD:
			fields += 1
		else:
			sieges += 1
	var wars := 0
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			if state.is_enemy(nation_a, nation_b):
				wars += 1
	peak["moving_armies"] = maxi(int(peak["moving_armies"]), moving)
	peak["field_battles"] = maxi(int(peak["field_battles"]), fields)
	peak["sieges"] = maxi(int(peak["sieges"]), sieges)
	peak["war_pairs"] = maxi(int(peak["war_pairs"]), wars)


func _runtime_stage(simulation: Simulation) -> StringName:
	if simulation == null or not simulation.runtime_day_in_progress():
		return &"idle"
	return (
		simulation.runtime_profile_stage
		if not simulation.runtime_profile_stage.is_empty()
		else &"unknown"
	)


func _print_runtime_spans(simulation: Simulation) -> void:
	var peaks := simulation.runtime_span_peak_usec
	var stages := peaks.keys()
	stages.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(peaks[a]) > int(peaks[b])
	)
	print("同步跨度计时:")
	for stage in stages:
		print("  %-24s total=%.2fms peak=%.2fms" % [
			stage,
			float(simulation.runtime_span_total_usec.get(stage, 0)) / 1000.0,
			float(peaks[stage]) / 1000.0,
		])


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _max_value(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, value)
	return result


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


func _env_int(key: String, fallback: int) -> int:
	var raw := OS.get_environment(key)
	return fallback if raw.is_empty() else int(raw)
