extends SceneTree

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	check(main.has_method("_debug_generation_settings"), "debug scene records reproduction settings")
	if not main.has_method("_debug_generation_settings"):
		main.free()
		_finish()
		return
	main.use_grid_world = true
	main.randomize_world_seed_on_start = true
	root.add_child(main)
	await process_frame
	main.simulation.paused = true
	var logger: RefCounted = main._debug_run_log
	check(logger != null and not str(logger.path).is_empty(), "debug launch creates a run log automatically")
	var first_path: String = logger.path
	var records := read_records(first_path)
	check(records.size() == 3 and records[0].event == "session_start" and records[1].event == "generation_requested" and records[2].event == "world_start", "startup records are flushed immediately")
	check(int(records[2].seed) == main.state.world_seed and main.state.world_seed != main.world_seed, "actual randomized seed is recorded rather than scene fallback")
	check(records[0].scene == "res://main.tscn" and records[0].has("engine") and records[0].has("code"), "scene, engine and code revision are recorded")
	check(records[2].settings.randomize_world_seed_on_start and records[2].settings.use_grid_world, "generation switches are recorded")
	check(records[2].nation_count == main.state.nations.size() and records[2].city_count == main.state.cities.size(), "resolved world sizes are recorded")
	check(MapDefinition.validate(JSON.parse_string(FileAccess.get_file_as_string(records[2].initial_map_template))).is_empty(), "initial resolved map is a valid reproducible template")
	var before := var_to_bytes(main.state.family_trees)
	var rng_state: int = main.state.rng.state
	main.state.day = 30
	main._on_history_day_committed(30)
	main._on_history_day_committed(30)
	records = read_records(first_path)
	check(records.size() == 4 and records[3].event == "checkpoint" and records[3].day == 30, "monthly progress checkpoint is logged once")
	check(var_to_bytes(main.state.family_trees) == before and main.state.rng.state == rng_state, "logging consumes no randomness and changes no genealogy")
	main._start_new_game(98765)
	records = read_records(first_path)
	check(records.back().event == "world_start" and int(records.back().seed) == 98765 and int(records.back().world_index) == 2, "regeneration logs the new seed in the same session")
	main._start_from_map_definition(MapDefinition.from_state(main.state))
	records = read_records(first_path)
	check(records.back().source == "map_definition", "loaded or edited maps have an explicit origin")
	main.queue_free()
	await process_frame
	records = read_records(first_path)
	check(records.back().event == "session_end", "normal shutdown records final progress")
	var service: RefCounted = load("res://scripts/core/debug_run_log.gd").new()
	check(service.begin("res://other.tscn") == OK and service.path != first_path, "separate sessions never overwrite one another")
	service.close(null)
	print("DEBUG_RUN_LOG_PATH " + ProjectSettings.globalize_path(first_path))
	_finish()

func read_records(path: String) -> Array:
	var records: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var record: Variant = JSON.parse_string(line)
		if record is Dictionary: records.append(record)
	return records

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _finish() -> void:
	for failure in failures: push_error("DEBUG_RUN_LOG_FAIL: " + failure)
	print("DEBUG_RUN_LOG_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
