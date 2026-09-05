extends SceneTree
## 500 城国家显示 CPU 微基准。只测贴图数据生成，不包含 GPU 上传和帧等待。

const ITERATIONS: int = 3


func _init() -> void:
	var state := GameState.new()
	var started := Time.get_ticks_usec()
	state.generate_world(12345, 80, 500)
	_print_span("world_generation", started, 1)

	started = Time.get_ticks_usec()
	var topology := MapRenderer.build_province_boundary_topology(state)
	_print_span("boundary_topology", started, 1)
	var geometry := MapRenderer.classify_province_boundary_topology(
		state, topology
	)
	var country_segments: PackedVector2Array = geometry["country"]
	var output_size := Vector2(state.province_map_size) * float(
		MapRenderer.PROVINCE_VISUAL_SUPERSAMPLE
	)
	var total_segment_length := 0.0
	var maximum_segment_length := 0.0
	for index in range(0, country_segments.size(), 2):
		var length := (
			(country_segments[index + 1] - country_segments[index])
			* output_size
		).length()
		total_segment_length += length
		maximum_segment_length = maxf(maximum_segment_length, length)
	print("country_segments=%d avg_length=%.2fpx max_length=%.2fpx" % [
		country_segments.size() / 2,
		total_segment_length / float(maxi(country_segments.size() / 2, 1)),
		maximum_segment_length,
	])

	var opacity: Image
	started = Time.get_ticks_usec()
	for _iteration in range(ITERATIONS):
		opacity = MapRenderer.build_country_fill_opacity_image(state)
	_print_span("country_opacity", started, ITERATIONS)

	var fill_source: Image
	started = Time.get_ticks_usec()
	for _iteration in range(ITERATIONS):
		fill_source = MapRenderer.build_province_overlay_image(state)
	_print_span("province_overlay", started, ITERATIONS)

	started = Time.get_ticks_usec()
	for _iteration in range(ITERATIONS):
		MapRenderer.build_political_canvas_images(
			state, geometry, false, fill_source, true, opacity
		)
	_print_span("political_canvas", started, ITERATIONS)

	var country_boundaries: Image
	started = Time.get_ticks_usec()
	for _iteration in range(ITERATIONS):
		country_boundaries = MapRenderer.build_country_boundary_image(
			state, geometry, true
		)
	_print_span("country_boundaries", started, ITERATIONS)
	print("country_boundary_hash=%d" % hash(country_boundaries.get_data()))

	var country_color: Image
	started = Time.get_ticks_usec()
	for _iteration in range(ITERATIONS):
		country_color = MapRenderer.build_country_color_image(
			state, true, -1, opacity
		)
	_print_span("country_color", started, ITERATIONS)
	print("country_color_hash=%d" % hash(country_color.get_data()))

	started = Time.get_ticks_usec()
	var boundary_job := {"image": null}
	var boundary_task_id := WorkerThreadPool.add_task(
		_build_boundary_job.bind(boundary_job, state, geometry),
		false,
		"WorldWar country display benchmark"
	)
	var parallel_opacity := MapRenderer.build_country_fill_opacity_image(state)
	var parallel_source := MapRenderer.build_province_overlay_image(state)
	MapRenderer.build_political_canvas_images(
		state, geometry, false, parallel_source, true, parallel_opacity
	)
	MapRenderer.build_country_color_image(
		state, true, -1, parallel_opacity
	)
	WorkerThreadPool.wait_for_task_completion(boundary_task_id)
	_print_span("parallel_ownership_refresh_cpu", started, 1)
	var parallel_boundary: Image = boundary_job["image"]
	print("parallel_boundary_hash=%d" % hash(parallel_boundary.get_data()))
	quit(0)


func _print_span(label: String, started_usec: int, iterations: int) -> void:
	var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	print("%s avg=%.2fms" % [label, elapsed_ms / float(iterations)])


func _build_boundary_job(
	job: Dictionary, state: GameState, geometry: Dictionary
) -> void:
	job["image"] = MapRenderer.build_country_boundary_image(
		state, geometry, true
	)
