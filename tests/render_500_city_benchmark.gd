extends SceneTree
## 非 headless 的 500 城渲染基准。先暂停模拟测纯渲染，再开启模拟测端到端帧耗时。
## 可调：RENDER_BENCH_FRAMES（默认180）、RENDER_BENCH_SCENE（默认五百城场景）。

var _frame_samples: Array[float] = []


func _init() -> void:
	var scene_path := OS.get_environment("RENDER_BENCH_SCENE")
	if scene_path.is_empty():
		scene_path = "res://five_hundred_city_stress.tscn"
	var frame_count := _env_int("RENDER_BENCH_FRAMES", 180)
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
	var render_only := await _sample_frames(frame_count)
	if simulation != null:
		simulation.paused = false
	var with_simulation := await _sample_frames(frame_count)
	print("=== 渲染基准 scene=%s frames=%d ===" % [scene_path, frame_count])
	print("节点数=%d" % _count_nodes(main))
	_print_stats("纯渲染（模拟暂停）", render_only)
	_print_stats("渲染+模拟", with_simulation)
	quit(0)


func _sample_frames(frame_count: int) -> Dictionary:
	var samples: Array[float] = []
	var draw_calls: Array[float] = []
	var primitives: Array[float] = []
	var objects: Array[float] = []
	for _i in range(maxi(frame_count, 1)):
		var started := Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
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
