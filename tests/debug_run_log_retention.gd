extends SceneTree
## Exercise real files and overlapping Godot processes in an isolated project folder.
const DIRECTORY := "res://.dbg/debug-run-log-retention-test"
class TestLog extends DebugRunLog:
	var output_directory := "res://.dbg/debug-run-log-retention-test"
	func _directory() -> String:
		return output_directory
class RejectedStart extends TestLog:
	var attempted_path := ""
	func record(event: String, details: Dictionary) -> void:
		if event == "session_start":
			attempted_path = path
			_file.close()
			_file = null # Model the writer rejecting its first record.
		else:
			super.record(event, details)

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("DEBUG_RUN_RETENTION_FAIL ", label)

func entries(path: String) -> Array:
	var result := []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		result.append(JSON.parse_string(line))
	return result

func write_text(name_value: String, value: String) -> void:
	var file := FileAccess.open(DIRECTORY.path_join(name_value), FileAccess.WRITE)
	file.store_string(value)
	file.close()

func wait_for_file(name_value: String) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while not FileAccess.file_exists(DIRECTORY.path_join(name_value)) and Time.get_ticks_msec() < deadline:
		await process_frame
	return FileAccess.file_exists(DIRECTORY.path_join(name_value))

func wait_for_exit(pid: int) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await process_frame
	if OS.is_process_running(pid):
		OS.kill(pid) # Only the subprocess created by this test.
		return false
	return true

func child(mode: String) -> void:
	var logger := TestLog.new()
	if logger.begin("retention_child") != OK:
		quit(2)
		return
	write_text("child-path.txt", logger.path)
	if mode == "overlap":
		if not await wait_for_file("release.txt"):
			quit(3)
			return
		logger.close(null)
	else:
		OS.kill(OS.get_process_id()) # Real abrupt termination of this test child.
	quit()

func start_child(mode: String) -> int:
	for name_value in ["child-path.txt", "release.txt"]:
		DirAccess.remove_absolute(DIRECTORY.path_join(name_value))
	return OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/debug_run_log_retention.gd", "--", "--retention-child=" + mode])

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--retention-child="):
			await child(argument.trim_prefix("--retention-child="))
			return
	check(DebugRunLog.DIRECTORY == "res://.dbg/debug_runs", "default output belongs to the project")
	var first := TestLog.new()
	check(first.begin("retention_first") == OK, "first session opens")
	var output_prefix := ProjectSettings.globalize_path(DIRECTORY) + "/"
	check(first.path.begins_with(output_prefix), "isolated logger uses the project output directory")
	if not first.path.begins_with(output_prefix):
		first.close(null)
		quit(1)
		return
	write_text("keep.txt", "unrelated file")
	write_text("run-not-a-session.jsonl", "unrelated file")
	var state := GameState.new()
	state.world_seed = 7
	var rng_before := state.rng.state
	first.world_started(state, {"case": 1}, "first_world")
	var first_map: String = entries(first.path)[1].initial_map_template
	check(FileAccess.file_exists(first_map), "initial map exists")
	first.world_started(state, {"case": 2}, "replacement_world")
	var worlds := entries(first.path)
	var latest_map: String = worlds[2].initial_map_template
	check(not FileAccess.file_exists(first_map) and FileAccess.file_exists(latest_map), "rebuilding retains only the newest map")
	check(worlds[1].world_index == 1 and worlds[2].world_index == 2, "world index metadata survives map rotation")
	check(state.rng.state == rng_before, "recording does not advance simulation RNG")
	var blocked_template := first.path.get_basename() + "-world3-map.json"
	DirAccess.make_dir_absolute(blocked_template)
	first.world_started(state, {"case": 3}, "failed_replacement")
	check(FileAccess.file_exists(latest_map), "failed map replacement preserves the last readable template")
	var failed_world: Dictionary = entries(first.path)[3]
	check(failed_world.initial_map_template == "" and failed_world.map_template_error != "OK", "failed replacement is recorded explicitly")
	DirAccess.remove_absolute(blocked_template) # Empty fixture directory only.
	first.close(state)
	var closed_text := FileAccess.get_file_as_string(first.path)
	first.close(state)
	check(FileAccess.get_file_as_string(first.path) == closed_text, "close is idempotent")
	var second := TestLog.new()
	check(second.begin("retention_second") == OK, "next session opens")
	check(not FileAccess.file_exists(first.path) and not FileAccess.file_exists(latest_map), "next run removes the previous closed log and map")
	check(FileAccess.file_exists(DIRECTORY.path_join("keep.txt")) and FileAccess.file_exists(DIRECTORY.path_join("run-not-a-session.jsonl")), "cleanup preserves unrelated files")
	second.close(null)
	var pid := start_child("overlap")
	check(pid > 0 and await wait_for_file("child-path.txt"), "overlapping subprocess starts")
	var child_path := FileAccess.get_file_as_string(DIRECTORY.path_join("child-path.txt"))
	var newest := TestLog.new()
	check(newest.begin("retention_newest") == OK, "newer session starts while the older process is active")
	check(FileAccess.file_exists(child_path), "active process retains its log")
	newest.close(null)
	write_text("release.txt", "close")
	check(await wait_for_exit(pid), "older process closes after the newer session")
	check(not FileAccess.file_exists(child_path) and FileAccess.file_exists(newest.path), "late close cannot replace or delete the newer session")
	pid = start_child("crash")
	check(pid > 0 and await wait_for_file("child-path.txt"), "interrupted subprocess starts")
	child_path = FileAccess.get_file_as_string(DIRECTORY.path_join("child-path.txt"))
	check(await wait_for_exit(pid), "interrupted subprocess exits")
	var recovered := TestLog.new()
	check(recovered.begin("retention_after_crash") == OK, "new session starts after interruption")
	check(not FileAccess.file_exists(child_path), "next run removes stale interrupted output")
	recovered.close(null)
	var logs := []
	for name_value in DirAccess.get_files_at(DIRECTORY):
		if name_value.ends_with(".jsonl") and name_value != "run-not-a-session.jsonl": logs.append(name_value)
	check(logs == [recovered.path.get_file()], "only the latest finished run remains")
	var blocked := TestLog.new()
	blocked.output_directory = DIRECTORY.path_join("keep.txt")
	check(blocked.begin("retention_unwritable") != OK, "unwritable destination reports failure")
	check(FileAccess.file_exists(recovered.path), "failed startup does not purge the last good record")
	var rejected := RejectedStart.new()
	check(rejected.begin("retention_rejected_start") != OK, "failed first record reports startup failure")
	check(FileAccess.file_exists(recovered.path), "failed first record preserves the last good session")
	check(rejected.path.is_empty() and not FileAccess.file_exists(rejected.attempted_path), "failed startup removes partial output and permits retry")
	var dropped := TestLog.new()
	check(dropped.begin("retention_released_object") == OK, "short-lived session opens")
	var dropped_path := dropped.path
	dropped = null
	check(FileAccess.file_exists(dropped_path + ".closed"), "releasing the logger closes retention ownership")
	check(entries(dropped_path)[-1].event == "session_end", "released logger finishes its record")
	var preview_script := load("res://scripts/atlas/military_preview.gd") as GDScript
	check(preview_script != null and preview_script.can_instantiate(), "preview script compiles")
	if preview_script == null or not preview_script.can_instantiate():
		quit(1)
		return
	var preview = preview_script.new()
	preview.run_log = TestLog.new()
	preview.generation_index = 1
	preview.begin_log("earth", 7)
	check(not preview.run_log.path.is_empty(), "map preview writes through the campaign session logger")
	check(not FileAccess.file_exists(dropped_path), "next run cleans a released logger while its process still runs")
	if not preview.run_log.path.is_empty():
		var preview_path: String = preview.run_log.path
		preview.generation_index = 2
		preview.begin_log("earth", 8)
		check(preview.run_log.path == preview_path, "preview rebuilds reuse the same session")
		var records := entries(preview_path)
		check(records[1].world_index == 1 and records[2].world_index == 2 and records[2].seed == 8, "preview preserves per-world generation metadata")
	preview.run_log.close(null)
	preview.free()
	print("DEBUG_RUN_RETENTION checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
