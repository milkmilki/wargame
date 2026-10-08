extends SceneTree
const EnvModel = preload("res://scripts/core/settlement_environment.gd")
const Sampler = preload("res://scripts/core/settlement_sampler.gd")
var SOURCE: String = OS.get_environment("HYDROLOGY_SOURCE") if not OS.get_environment("HYDROLOGY_SOURCE").is_empty() else "res://assets/terrain/eurasia_uniform_river_map_source.json"
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var source := (load(MapSource.texture_path(SOURCE)) as Texture2D).get_image()
	var analysis := source.duplicate()
	analysis.resize(256, 256, Image.INTERPOLATE_NEAREST)
	var land: PackedByteArray = TerrainMapGenerator._all_land_geometry(analysis).mask
	var latitudes := PackedFloat32Array()
	for y in range(256): latitudes.append(MapSource.latitude_at_y((y + 0.5) / 256.0, 18.0, 57.0, SOURCE))
	var aspect := MapSource.aspect_ratio(SOURCE)
	var started := Time.get_ticks_usec()
	var environment := EnvModel.build(source, analysis, land, latitudes, aspect, MapSource.projection_type(SOURCE), true, MapSource.hydrology_network(SOURCE), true, MapSource.river_settlement_model(SOURCE))
	var reserved := TerrainMapGenerator._reserve_hydrology_docks(environment, analysis, aspect, 500)
	var bounds := MapSource.settlement_density_bounds(SOURCE)
	var first := Sampler.sample(source, land, environment, 500, aspect, 2342006650, reserved, bounds)
	print("UNIFORM_PHASES environment_ms=", environment.elapsed_usec / 1000.0, " support_ms=", environment.river_support_usec / 1000.0, " sampler=", first.generation_metadata, " reserved=", reserved.size())
	var cold_usec := Time.get_ticks_usec() - started
	assert(first.ok and not environment.cache_hit)
	started = Time.get_ticks_usec()
	var cached := EnvModel.build(source, analysis, land, latitudes, aspect, MapSource.projection_type(SOURCE), true, MapSource.hydrology_network(SOURCE), true, MapSource.river_settlement_model(SOURCE))
	var second := Sampler.sample(source, land, cached, 500, aspect, 12345, TerrainMapGenerator._reserve_hydrology_docks(cached, analysis, aspect, 500), bounds)
	var warm_usec := Time.get_ticks_usec() - started
	print("UNIFORM_WARM_PHASES environment_ms=", cached.elapsed_usec / 1000.0, " sampler=", second.generation_metadata)
	assert(second.ok and cached.cache_hit and environment.environment_id == cached.environment_id)
	assert(first.positions != second.positions)
	print("HYDROLOGY_BENCHMARK cold_ms=%.3f warm_ms=%.3f" % [cold_usec / 1000.0, warm_usec / 1000.0])
	var major := 0
	for f in environment.hydrology.features:
		if f.river_class == "major": major += 1
	print("HYDROLOGY_NETWORK reaches=%d major=%d basins=%d blocked=%d" % [environment.hydrology.features.size(), major, environment.hydrology.basin_count, environment.hydrology.blocked_edges.size()])
	var path := OS.get_environment("ENV_DIAGNOSTICS_FILE")
	if not path.is_empty():
		var output := {}
		for key in ["temperature", "winter_temperature", "rainfall", "aridity", "water", "farmland", "cold", "suitability", "land", "heights", "rainfed", "flatness"]:
			output[key] = Array(environment[key])
		output["rivers"] = []
		for f in environment.hydrology.features:
			var points := []
			for p in f.points: points.append([p.x, p.y])
			output.rivers.append({"points": points, "class": f.river_class, "terminal": f.terminal_kind})
		output["flow"] = Array(environment.hydrology.flow)
		output["downstream"] = Array(environment.hydrology.get("downstream", []))
		output["positions"] = []
		for p in first.positions: output.positions.append([p.x, p.y])
		output["aspect"] = aspect
		output["size"] = [256, 256]
		output["seed"] = 2342006650
		output["environment_version"] = EnvModel.VERSION
		output["map_source"] = SOURCE
		output["river_settlement_model"] = MapSource.river_settlement_model(SOURCE)
		output["settlement_density_bounds"] = bounds
		output["selection_weight"] = []
		for value in environment.suitability: output.selection_weight.append(clampf(value, bounds.minimum, bounds.maximum))
		FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(output))
	print("HYDROLOGY_BENCHMARK_OK")
	quit()
