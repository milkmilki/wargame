extends SceneTree
const EnvModel = preload("res://scripts/core/settlement_environment.gd")
const Sampler = preload("res://scripts/core/settlement_sampler.gd")
const SOURCE := "res://assets/terrain/eurasia_environment_map_source.json"
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
	var environment := EnvModel.build(source, analysis, land, latitudes, aspect, MapSource.projection_type(SOURCE))
	var first := Sampler.sample(source, land, environment, 500, aspect, 2342006650)
	var cold_usec := Time.get_ticks_usec() - started
	assert(first.ok and not environment.cache_hit)
	started = Time.get_ticks_usec()
	var cached := EnvModel.build(source, analysis, land, latitudes, aspect, MapSource.projection_type(SOURCE))
	var second := Sampler.sample(source, land, cached, 500, aspect, 12345)
	var warm_usec := Time.get_ticks_usec() - started
	assert(second.ok and cached.cache_hit and environment.environment_id == cached.environment_id)
	assert(first.positions != second.positions)
	print("ENVIRONMENT_BENCHMARK cold_ms=%.3f warm_ms=%.3f" % [cold_usec / 1000.0, warm_usec / 1000.0])
	var path := OS.get_environment("ENV_DIAGNOSTICS_FILE")
	if not path.is_empty():
		var output := {}
		for key in ["temperature", "winter_temperature", "rainfall", "aridity", "water", "farmland", "cold", "suitability", "land", "heights"]:
			output[key] = Array(environment[key])
		output["positions"] = []
		for p in first.positions: output.positions.append([p.x, p.y])
		output["aspect"] = aspect
		output["size"] = [256, 256]
		output["seed"] = 2342006650
		output["environment_version"] = EnvModel.VERSION
		FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(output))
	# Data, latitude and projection identities must all invalidate the environment.
	var altered := source.duplicate()
	altered.set_pixel(10, 10, Color(1, 1, 1, 1))
	var changed := EnvModel.build(altered, analysis, land, latitudes, aspect, MapSource.projection_type(SOURCE))
	assert(changed.environment_id != environment.environment_id)
	latitudes.fill(75)
	changed = EnvModel.build(source, analysis, land, latitudes, aspect, MapSource.projection_type(SOURCE))
	assert(changed.environment_id != environment.environment_id)
	assert(not Sampler.sample(source, land, changed, 500, aspect, 2342006650).ok)
	changed = EnvModel.build(source, analysis, land, latitudes, aspect, "equirectangular")
	assert(not changed.cache_hit)
	print("ENVIRONMENT_BENCHMARK_OK")
	quit()
