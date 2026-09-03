extends SceneTree
## 非 headless 的 500 城渲染基准。先暂停模拟测纯渲染，再开启模拟测端到端帧耗时。
## 可调：RENDER_BENCH_FRAMES（默认180）、RENDER_BENCH_SCENE（默认五百城场景）。

var _frame_samples: Array[float] = []


func _init() -> void:
	var scene_path := OS.get_environment("RENDER_BENCH_SCENE")
	if scene_path.is_empty():
		scene_path = "res://five_hundred_city_stress.tscn"
	var frame_count := _env_int("RENDER_BENCH_FRAMES", 180)
	var sample_gpu_counters := _env_int("RENDER_BENCH_GPU_COUNTERS", 0) != 0
	var seconds_per_day := float(OS.get_environment(
		"RENDER_BENCH_SECONDS_PER_DAY"
	))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		printerr("render benchmark scene load failed: %s" % scene_path)
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	for _i in range(60):
		await process_frame
	var simulation := main.get_node_or_null("Simulation") as Simulation
	if simulation != null:
		simulation.paused = true
	var render_only := await _sample_frames(
		frame_count, sample_gpu_counters, null
	)
	if simulation != null:
		simulation.paused = false
		simulation.runtime_stage_profiling_enabled = true
		if seconds_per_day > 0.0:
			simulation.seconds_per_day = seconds_per_day
	var with_simulation := await _sample_frames(
		frame_count, sample_gpu_counters, simulation
	)
	print("=== 渲染基准 scene=%s frames=%d ===" % [scene_path, frame_count])
	print("节点数=%d" % _count_nodes(main))
	_print_stats("纯渲染（模拟暂停）", render_only)
	_print_stats("渲染+模拟", with_simulation)
	if simulation != null:
		_print_runtime_spans(simulation)
	quit(0)


func _sample_frames(
	frame_count: int,
	sample_gpu_counters: bool,
	simulation: Simulation
) -> Dictionary:
	var samples: Array[float] = []
	var draw_calls: Array[float] = []
	var primitives: Array[float] = []
	var objects: Array[float] = []
	var slow_frames_by_stage := {}
	var interval_stage: StringName = &"idle"
	for _i in range(maxi(frame_count, 1)):
		var started := Time.get_ticks_usec()
		await process_frame
		var frame_ms := float(Time.get_ticks_usec() - started) / 1000.0
		samples.append(frame_ms)
		var elapsed_stage := interval_stage
		interval_stage = _runtime_stage(simulation)
		if simulation != null and frame_ms > 16.0:
			var key := str(elapsed_stage)
			var report: Dictionary = slow_frames_by_stage.get(key, {
				"over_16": 0, "over_33": 0, "peak_ms": 0.0,
			})
			report["over_16"] = int(report["over_16"]) + 1
			if frame_ms > 33.0:
				report["over_33"] = int(report["over_33"]) + 1
			report["peak_ms"] = maxf(float(report["peak_ms"]), frame_ms)
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
	samples.sort()
	var total := 0.0
	for value in samples:
		total += value
	return {
		"avg_ms": total / float(samples.size()),
		"p95_ms": samples[mini(int(samples.size() * 0.95), samples.size() - 1)],
		"max_ms": samples.back(),
		"fps_avg": 1000.0 / maxf(total / float(samples.size()), 0.001),
		"draw_calls_avg": _average(draw_calls),
		"primitives_avg": _average(primitives),
		"objects_avg": _average(objects),
		"draw_calls_max": _max_value(draw_calls),
		"slow_frames_by_stage": slow_frames_by_stage,
	}


func _print_stats(label: String, stats: Dictionary) -> void:
	print("%s avg=%.2fms p95=%.2fms max=%.2fms fps=%.1f" % [
		label,
		float(stats["avg_ms"]),
		float(stats["p95_ms"]),
		float(stats["max_ms"]),
		float(stats["fps_avg"]),
	])
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
		print("  %-24s >16ms=%d >33ms=%d peak=%.2fms" % [
			stage, int(report["over_16"]), int(report["over_33"]),
			float(report["peak_ms"]),
		])


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
