extends SceneTree
## The formal entry and reproduction log must use the native Atlas world.
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("ATLAS_ENTRY_FAIL ", message)

func _initialize() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://atlas_military.tscn", "formal 2D entry")
	var scene := (load("res://atlas_military.tscn") as PackedScene).get_state()
	var earth_default := false
	for property in range(scene.get_node_property_count(0)):
		if scene.get_node_property_name(0,property) == "terrain_model":
			earth_default = scene.get_node_property_value(0,property) == "earth"
	check(earth_default, "real Earth default")
	var state := GameState.new()
	state.generate_from_atlas(preload("res://tests/atlas_military_inputs.gd").military())
	var rng_state := state.rng.state
	var logger := DebugRunLog.new()
	check(logger.begin("res://atlas_military.tscn") == OK, "log opens")
	logger.world_started(state, {"terrain_model":"earth"}, "native_atlas")
	logger.world_started(state, {"terrain_model":"earth"}, "template_reload")
	logger.close(state)
	var entries: Array = []
	for line in FileAccess.get_file_as_string(logger.path).split("\n"):
		if not line.is_empty(): entries.append(JSON.parse_string(line))
	check(entries[0].scene == "res://atlas_military.tscn" and entries[0].pid == OS.get_process_id(), "actual scene and PID")
	check(entries[1].seed == state.world_seed and entries[1].world_index == 1 and entries[2].world_index == 2, "actual seed and world counter")
	check(MapDefinition.validate(JSON.parse_string(FileAccess.get_file_as_string(entries[1].initial_map_template))).is_empty(), "reproducible initial Atlas template")
	check(state.rng.state == rng_state, "logging leaves simulation RNG untouched")
	print("ATLAS_ENTRY_CONTRACT failures=", failures)
	quit(1 if failures else 0)
