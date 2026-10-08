extends SceneTree
const SOURCE := "res://assets/terrain/eurasia_hydrology_map_source.json"
var failures := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("EURASIA_ROAD_WORLD_FAIL: ", message)

func run() -> void:
	var seed_value := int(OS.get_environment("ROAD_TEST_SEED"))
	if seed_value == 0: seed_value = 1107871845
	var baseline_path := OS.get_environment("ROAD_BASELINE_TEMPLATE")
	# Isolate road simplification from the independent sparse-ferry policy.
	MapSource.load_manifest(SOURCE)
	MapSource._cache[SOURCE].erase("ferry_interval")
	var before := GameState.new()
	if not baseline_path.is_empty():
		before.generate_from_map_definition(JSON.parse_string(FileAccess.get_file_as_string(baseline_path)), seed_value)
	else:
		MapSource.load_manifest(SOURCE)
		MapSource._cache[SOURCE]["road_path_model"] = "legacy"
		check(before.generate_world(seed_value, 40, 500, "", {}, seed_value, "", SOURCE), "baseline generation")
	MapSource._cache.erase(SOURCE)
	MapSource.load_manifest(SOURCE)
	MapSource._cache[SOURCE].erase("ferry_interval")
	var state := GameState.new()
	check(state.generate_world(seed_value, 40, 500, "", {}, seed_value, "", SOURCE), state.last_generation_error)
	if failures:
		quit(1)
		return
	check(state.land_cities().size() == 500 and state.nations.size() == 40, "500 land cities and 40 nations")
	check(state.province_ids == before.province_ids, "province IDs stay unchanged")
	# Template deserialization omits transient hydrology fields and rounds
	# double widths to JSON precision. Compare the complete persisted contract
	# at that precision, rather than native runtime dictionaries/float bits.
	check(JSON.stringify(MapFeatureContract.serialize_rivers(state.river_features)) == JSON.stringify(MapFeatureContract.serialize_rivers(before.river_features)), "persisted river geometry and topology stay unchanged")
	check(state.cities.size() == before.cities.size() and state.edges.size() == before.edges.size(), "cities, docks and road adjacency counts stay unchanged")
	for i in range(state.cities.size()):
		check(state.cities[i].map_position == before.cities[i].map_position, "city/dock position stays unchanged")
	var source := (load(state.current_terrain_map_path()) as Texture2D).get_image()
	var options := {"image": source, "river_paths": MapFeatureContract.major_paths(state.river_features), "aspect": state.map_aspect_ratio}
	var changed := 0
	var old_points := 0
	var new_points := 0
	for i in range(state.edges.size()):
		var edge := state.edges[i]
		var original := before.edges[i]
		check(edge.city_a == original.city_a and edge.city_b == original.city_b and edge.kind == original.kind, "edge identity stays unchanged")
		if edge.kind != Edge.Kind.LAND:
			check(edge.map_path == original.map_path, "river/landing/sea routes stay unchanged")
			continue
		old_points += original.map_path.size()
		new_points += edge.map_path.size()
		if edge.map_path == original.map_path: continue
		changed += 1
		check(edge.map_path[0] == original.map_path[0] and edge.map_path[-1] == original.map_path[-1], "fixed road endpoints")
		check(TerrainMapGenerator.metric_polyline_length(edge.map_path, state.map_aspect_ratio) <= TerrainMapGenerator.metric_polyline_length(original.map_path, state.map_aspect_ratio) + .000001, "simplification never lengthens route")
		check(edge.distance == TerrainMapGenerator.distance_units_for_metric_length(TerrainMapGenerator.metric_polyline_length(edge.map_path, state.map_aspect_ratio)), "travel distance matches new route")
		for j in range(edge.map_path.size() - 1):
			var a := edge.map_path[j]
			var b := edge.map_path[j+1]
			var retained := false
			for k in range(original.map_path.size() - 1):
				if a == original.map_path[k] and b == original.map_path[k+1]: retained = true; break
			if retained: continue
			check(TerrainMapGenerator._safe_road_shortcut(a, b, options), "new shortcut passes full DEM and main-river checks")
			check(TerrainMapGenerator._segment_in_pair_exact(state.province_ids, state.province_map_size, a, b, edge.city_a, edge.city_b), "new shortcut stays inside endpoint provinces")
	check(changed > 0 and new_points < old_points, "formal source actually simplifies roads")
	var saved := MapDefinition.from_state(state)
	check(MapDefinition.validate(saved).is_empty(), "new template validates")
	var restored := GameState.new()
	restored.generate_from_map_definition(saved, seed_value)
	for i in range(state.edges.size()): check(restored.edges[i].map_path == state.edges[i].map_path, "template preserves exact road path")
	FileAccess.open("res://.dbg/road-fix-before-%d.json" % seed_value, FileAccess.WRITE).store_string(JSON.stringify(MapDefinition.from_state(before)))
	FileAccess.open("res://.dbg/road-fix-after-%d.json" % seed_value, FileAccess.WRITE).store_string(JSON.stringify(saved))
	print("EURASIA_ROAD_WORLD seed=", seed_value, " changed=", changed, " points=", old_points, "->", new_points, " metadata=", state.generation_metadata.get("road_path_simplification"))
	var output := OS.get_environment("ROAD_VISUAL_DIR")
	if not output.is_empty():
		root.size = Vector2i(1600, 900)
		DirAccess.make_dir_recursive_absolute(output)
		var simulation := Simulation.new()
		root.add_child(simulation)
		simulation.setup(state)
		simulation.paused = true
		var overlay := MapRenderer.new()
		root.add_child(overlay)
		overlay.setup(state, simulation)
		overlay.set_world_layer_visible(false)
		overlay.set_city_names_visible(false)
		overlay.set_nation_names_visible(false)
		overlay.set_army_icon_scale(.25)
		var view := StrategicMap3D.new()
		root.add_child(view)
		view.setup(state, simulation, overlay)
		while view._terrain == null or view._terrain.land_cell_count() == 0: await process_frame
		for mode in [MapRenderer.MapMode.POLITICAL, MapRenderer.MapMode.TRADE]:
			view.set_map_mode(mode)
			await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(output.path_join("road-mode-%d.png" % mode)) == OK, "real rendered preview")
		view.free(); overlay.free(); simulation.free()
	print("EURASIA_ROAD_PATH_WORLD: %d failures" % failures)
	quit(1 if failures else 0)
