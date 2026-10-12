extends SceneTree
## Real renderer + naturally frame-sliced Simulation on a frozen EURASIA state.
## Startup, renderer preparation and warm-up are outside the sampling window.
## Run without --headless, with --atlas-cache=res://.dbg/atlas-military-eurasia-mask.bin.
const Fixture = preload("res://tests/support/native_runtime_fixture.gd")
const Benchmark = preload("res://tests/native_runtime_benchmark.gd")
const DIRECTORY := "res://.dbg/native-runtime"
var scene
var simulation: Simulation
var state: GameState
var selected_backend := "native"
var start_day := 330
var days := 30
var speed := 8.0
var warmup_frames := 120
var compute_reference := ""
var sampling := false
var finishing := false
var measure_started := 0
var last_frame := 0
var last_commit := 0
var interval_stage := "idle"
var frames: Array[int] = []
var engine_frame_process: Array[int] = []
var commit_intervals: Array[int] = []
var slow_frames: Array[Dictionary] = []
var input_descriptor: Dictionary = {}
var manifest: Dictionary = {}
var render_preparation_ms := 0
var setup_snapshots: Dictionary = {}
var diagnose_setup := false
var runtime_initial_bytes := PackedByteArray()
var runtime_initial_sha256 := ""
var initialization_changes: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	printerr("NATIVE_GUI_INVALID ", message)
	if simulation != null: simulation.paused = true
	quit(1)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		fail("This probe requires a normal rendering window")
		return
	var cache_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--atlas-cache="): cache_path = argument.trim_prefix("--atlas-cache=")
		elif argument.begins_with("--stage="): start_day = int(argument.trim_prefix("--stage="))
		elif argument.begins_with("--days="): days = int(argument.trim_prefix("--days="))
		elif argument.begins_with("--speed="): speed = float(argument.trim_prefix("--speed="))
		elif argument.begins_with("--warmup-frames="): warmup_frames = int(argument.trim_prefix("--warmup-frames="))
		elif argument.begins_with("--compute-reference="): compute_reference = argument.trim_prefix("--compute-reference=")
		elif argument == "--diagnose-setup": diagnose_setup = true
	if cache_path.is_empty() or not FileAccess.file_exists(cache_path):
		fail("Pass an existing --atlas-cache so terrain and raster are never generated")
		return
	selected_backend = OS.get_environment("WARGAME_COMPUTE_BACKEND")
	if selected_backend not in ["gdscript", "native"] or days <= 0 or warmup_frames < 0:
		fail("Use backend gdscript/native and positive days")
		return
	NativeCompute.set_backend_for_tests(selected_backend)
	manifest = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "/manifest.json"))
	input_descriptor = manifest.get("stages", {}).get(str(start_day), {})
	var frozen_path := DIRECTORY + "/day-%d.bin" % start_day
	if manifest.get("format", "") != Fixture.FORMAT or input_descriptor.is_empty() or not FileAccess.file_exists(frozen_path):
		fail("Frozen fixture manifest and selected day must exist")
		return
	if Fixture.hash_bytes(FileAccess.get_file_as_bytes(frozen_path)) != input_descriptor.file_sha256:
		fail("Frozen fixture file hash does not match its manifest")
		return
	var codec := Fixture.new()
	var frozen_payload: Dictionary = FileAccess.open(frozen_path, FileAccess.READ).get_var(false)
	state = codec.unpack(frozen_payload)
	var world_error := Fixture.validate_world(state, 1, false)
	if int(manifest.get("initial_nations", 0)) != 40 or not world_error.is_empty() or state.day != start_day or digest() != input_descriptor.state_sha256:
		fail("Restored EURASIA state does not match: " + world_error)
		return
	var payload: Dictionary = FileAccess.open(cache_path, FileAccess.READ).get_var(false)
	if payload.get("data", {}).get("options", {}).get("settlement_mask", {}) != state.map_models.settlement_mask:
		fail("Display payload settlement mask differs from the frozen EURASIA input")
		return
	# The compute benchmark restores the same fixture, then runs setup before
	# advancing days. Reproduce that real initialization on an independent copy;
	# compare every raw snapshot byte rather than removing its state changes.
	var oracle_codec := Fixture.new()
	var oracle_state := oracle_codec.unpack(frozen_payload)
	var oracle_simulation := Simulation.new()
	root.add_child(oracle_simulation)
	oracle_simulation.setup(oracle_state)
	oracle_simulation.paused = true
	setup_snapshots["runtime_initial_oracle"] = Fixture.snapshot(oracle_state)
	runtime_initial_bytes = var_to_bytes(setup_snapshots.runtime_initial_oracle)
	runtime_initial_sha256 = Fixture.hash_bytes(runtime_initial_bytes)
	NativeCompute.invalidate_state(oracle_state)
	root.remove_child(oracle_simulation)
	oracle_simulation.free()
	oracle_state = null
	oracle_codec = null
	frozen_payload.clear()
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene = load("res://atlas_military.tscn").instantiate()
	root.add_child(scene)
	var startup_started := Time.get_ticks_msec()
	while not scene.view_ready or scene.overlay == null:
		if Time.get_ticks_msec() - startup_started > 120000:
			fail("Cached real map startup timed out")
			return
		await process_frame
	scene.simulation.paused = true
	setup_snapshots["before_present"] = Fixture.snapshot(state)
	await scene.present_world(state, payload, "native_gui_frozen_day_%d" % start_day)
	simulation = scene.simulation
	simulation.paused = true
	setup_snapshots["after_present"] = Fixture.snapshot(state)
	collect_setup_diff(setup_snapshots.before_present, setup_snapshots.runtime_initial_oracle, "$", initialization_changes)
	if var_to_bytes(setup_snapshots.after_present) != runtime_initial_bytes:
		write_setup_diagnostics()
		fail("GUI initialization differs from synchronous compute initialization")
		return
	var prepared_started := Time.get_ticks_msec()
	if not await scene.await_render_ready(60000):
		fail("Real map display preparation timed out")
		return
	render_preparation_ms = Time.get_ticks_msec() - prepared_started
	for _frame in range(warmup_frames): await process_frame
	setup_snapshots["after_warmup"] = Fixture.snapshot(state)
	if var_to_bytes(setup_snapshots.after_warmup) != runtime_initial_bytes:
		write_setup_diagnostics()
		fail("Rendering warm-up changed the initialized frozen input state")
		return
	if diagnose_setup:
		write_setup_diagnostics()
		print("NATIVE_GUI_SETUP_PASS")
		quit(0)
		return
	setup_snapshots.clear()
	runtime_initial_bytes = PackedByteArray()
	simulation.runtime_stage_profiling_enabled = true
	simulation.tick_phase_profiling_enabled = true
	simulation.runtime_span_total_usec.clear()
	simulation.runtime_span_peak_usec.clear()
	simulation.runtime_day_committed.connect(on_commit)
	simulation.set_speed_multiplier(speed)
	NativeCompute.set_profiling_for_tests(true)
	measure_started = Time.get_ticks_usec()
	last_frame = measure_started
	last_commit = measure_started
	sampling = true
	simulation.paused = false
	print("NATIVE_GUI_STARTED backend=%s day=%d days=%d renderer=%s window=1280x720 vsync=disabled" % [selected_backend, start_day, days, RenderingServer.get_current_rendering_method()])

func _process(_delta: float) -> bool:
	if not sampling: return false
	var now := Time.get_ticks_usec()
	var interval := now - last_frame
	last_frame = now
	frames.append(interval)
	engine_frame_process.append(int(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0))
	var current_stage := str(simulation.runtime_profile_stage) if simulation.runtime_day_in_progress() else "idle"
	if interval > 33000:
		slow_frames.append({"day": state.day, "wall_usec": interval, "from": interval_stage, "to": current_stage})
	interval_stage = current_stage
	if finishing:
		sampling = false
		finish.call_deferred()
	elif now - measure_started > 300000000:
		sampling = false
		fail("GUI simulation timed out before the final committed day")
	return false

func on_commit(day: int) -> void:
	var now := Time.get_ticks_usec()
	commit_intervals.append(now - last_commit)
	last_commit = now
	if day >= start_day + days:
		simulation.paused = true
		finishing = true

func digest() -> String:
	return Fixture.hash_bytes(var_to_bytes(Fixture.snapshot(state)))

func write_setup_diagnostics() -> void:
	var prefix := DIRECTORY + "/gui-setup-%s-%d" % [selected_backend, OS.get_process_id()]
	for label in setup_snapshots:
		FileAccess.open(prefix + "-" + label + ".bin", FileAccess.WRITE).store_var(setup_snapshots[label], false)
		FileAccess.open(prefix + "-" + label + ".json", FileAccess.WRITE).store_string(JSON.stringify(setup_snapshots[label], "  "))
	var changes: Array[Dictionary] = []
	collect_setup_diff(setup_snapshots.before_present, setup_snapshots.after_present, "$", changes)
	var warmup_changes: Array[Dictionary] = []
	if setup_snapshots.has("after_warmup"):
		collect_setup_diff(setup_snapshots.after_present, setup_snapshots.after_warmup, "$", warmup_changes)
	var oracle_changes: Array[Dictionary] = []
	if setup_snapshots.has("runtime_initial_oracle"):
		collect_setup_diff(setup_snapshots.runtime_initial_oracle, setup_snapshots.after_present, "$", oracle_changes)
	var report := {"present_changes": changes, "warmup_changes": warmup_changes, "input_sha256": input_descriptor.state_sha256,
		"runtime_initial_sha256": runtime_initial_sha256, "gui_vs_initialization_oracle_changes": oracle_changes,
		"before_present_sha256": Fixture.hash_bytes(var_to_bytes(setup_snapshots.before_present)),
		"after_present_sha256": Fixture.hash_bytes(var_to_bytes(setup_snapshots.after_present))}
	if setup_snapshots.has("after_warmup"):
		report["after_warmup_sha256"] = Fixture.hash_bytes(var_to_bytes(setup_snapshots.after_warmup))
	FileAccess.open(prefix + "-diff.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_GUI_SETUP_DIFF path=", ProjectSettings.globalize_path(prefix + "-diff.json"), " changes=", JSON.stringify(report))

func collect_setup_diff(before: Variant, after: Variant, path: String, changes: Array[Dictionary]) -> void:
	if var_to_bytes(before) == var_to_bytes(after): return
	if typeof(before) != typeof(after):
		changes.append({"path": path, "before_type": typeof(before), "after_type": typeof(after)})
		return
	if before is Dictionary:
		if var_to_bytes(before.keys()) != var_to_bytes(after.keys()):
			changes.append({"path": path + ".keys", "before": before.keys(), "after": after.keys()})
		for key in before:
			if after.has(key): collect_setup_diff(before[key], after[key], path + "." + str(key), changes)
		return
	if before is Array:
		if before.size() != after.size(): changes.append({"path": path + ".size", "before": before.size(), "after": after.size()})
		for index in range(mini(before.size(), after.size())):
			collect_setup_diff(before[index], after[index], "%s[%d]" % [path, index], changes)
		return
	changes.append({"path": path, "before": before, "after": after})

func summarize(samples: Array[int]) -> Dictionary:
	if samples.is_empty(): return {}
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	var total := 0
	for value in samples: total += value
	return {"samples": samples.size(), "mean_usec": float(total) / samples.size(),
		"p50_usec": sorted[clampi(ceili(sorted.size() * .50) - 1, 0, sorted.size() - 1)],
		"p95_usec": sorted[clampi(ceili(sorted.size() * .95) - 1, 0, sorted.size() - 1)],
		"p99_usec": sorted[clampi(ceili(sorted.size() * .99) - 1, 0, sorted.size() - 1)],
		"peak_usec": sorted.back()}

func compute_reference_row(output_hash: String) -> Dictionary:
	if compute_reference.is_empty(): return {}
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(compute_reference))
	if report.get("backend", "") != selected_backend: return {"error": "compute reference backend mismatch"}
	for row in report.get("stages", []):
		if int(row.start_day) == start_day and int(row.end_day) == start_day + days:
			if row.input_sha256 != input_descriptor.state_sha256 or row.output_sha256 != output_hash:
				return {"error": "GUI and synchronous compute state digests differ"}
			return {"path": compute_reference, "report_sha256": Fixture.hash_bytes(FileAccess.get_file_as_bytes(compute_reference)),
				"daily_pure_compute": row.daily, "monthly_peak_usec": row.monthly_peak_usec,
				"input_sha256": row.input_sha256, "output_sha256": row.output_sha256}
	return {"error": "compute reference does not contain the selected day range"}

func finish() -> void:
	if simulation.runtime_day_in_progress() or state.day != start_day + days:
		fail("Probe ended without committing the exact requested day range")
		return
	var elapsed := Time.get_ticks_usec() - measure_started
	var output_hash := digest()
	var reference := compute_reference_row(output_hash)
	if reference.has("error"):
		fail(str(reference.error))
		return
	var report := {"backend": selected_backend, "pid": OS.get_process_id(), "world_seed": state.world_seed,
		"start_day": start_day, "end_day": state.day, "input_sha256": input_descriptor.state_sha256,
		"fixture_input_sha256": input_descriptor.state_sha256, "runtime_initial_sha256": runtime_initial_sha256,
		"initialization_changes": initialization_changes,
		"output_sha256": output_hash, "fixture_file_sha256": input_descriptor.file_sha256,
		"mask": state.map_models.settlement_mask, "engine": Engine.get_version_info(),
		"processor": OS.get_processor_name(), "cpu_count": OS.get_processor_count(),
		"renderer": RenderingServer.get_current_rendering_method(), "display_server": DisplayServer.get_name(),
		"window": [root.size.x, root.size.y], "vsync": "disabled", "max_fps": Engine.max_fps,
		"speed": speed, "warmup_frames": warmup_frames, "render_preparation_ms_excluded": render_preparation_ms,
		"wall_elapsed_usec": elapsed, "frame_wall": summarize(frames),
		"engine_frame_process": summarize(engine_frame_process), "day_commit_intervals_with_idle_and_waits": summarize(commit_intervals),
		"slow_frames_over_33ms": slow_frames, "raw_frame_wall_usec": frames,
		"raw_commit_intervals_usec": commit_intervals, "runtime_span_total_usec": simulation.runtime_span_total_usec,
		"runtime_span_peak_usec": simulation.runtime_span_peak_usec, "native_profile": NativeCompute.profile_snapshot(),
		"compute_reference": reference, "dll_hashes": Benchmark.dll_hashes(), "build_manifests": Benchmark.build_manifests(),
		"current_source_sha256": preload("res://scripts/atlas/military_import.gd").source_fingerprint(),
		"memory": OS.get_static_memory_usage()}
	var path := DIRECTORY + "/gui-%s-%d.json" % [selected_backend, OS.get_process_id()]
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_GUI_PASS report=", ProjectSettings.globalize_path(path), " frame_wall=", JSON.stringify(report.frame_wall), " output_sha256=", output_hash)
	root.remove_child(scene)
	scene.queue_free()
	await process_frame
	quit(0)
