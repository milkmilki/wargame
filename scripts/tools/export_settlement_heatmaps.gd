extends SceneTree
## Diagnostic export of the actual environment used by the formal scene.
func _init() -> void:
	call_deferred("run")

func run() -> void:
	var scene := (load("res://eurasia.tscn") as PackedScene).instantiate()
	var manifest: String = scene.map_source_manifest
	var city_count: int = scene.terrain_city_count
	var nation_count_value: int = scene.nation_count
	scene.free()
	var seed_value := 12345
	var state := GameState.new()
	if not state.generate_world(seed_value, nation_count_value, city_count, "", {}, seed_value, "", manifest):
		printerr(state.last_generation_error)
		quit(1)
		return
	var source := (load(state.current_terrain_map_path()) as Texture2D).get_image()
	var analysis := source.duplicate()
	analysis.resize(state.province_map_size.x, state.province_map_size.y, Image.INTERPOLATE_NEAREST)
	var land: PackedByteArray = TerrainMapGenerator._all_land_geometry(analysis).mask
	var latitudes := PackedFloat32Array()
	for y in range(analysis.get_height()):
		latitudes.append(TerrainMapGenerator.latitude_for_map_y((y + 0.5) / analysis.get_height(), state.city_density_settings, manifest))
	var env := SettlementEnvironment.build(source, analysis, land, latitudes, state.map_aspect_ratio,
		MapSource.projection_type(manifest), true, MapSource.hydrology_network(manifest),
		MapSource.estimated_boundary_inflow(manifest), MapSource.river_settlement_model(manifest))
	if env.environment_id != state.generation_metadata.environment_id:
		printerr("Diagnostic environment differs from generated world")
		quit(1)
		return
	var output := {
		"map_source": manifest, "environment_id": env.environment_id,
		"environment_version": SettlementEnvironment.VERSION,
		"river_settlement_model": env.river_settlement_model,
		"density_bounds": MapSource.settlement_density_bounds(manifest),
		"generation_metadata": state.generation_metadata,
		"seed": seed_value, "aspect": state.map_aspect_ratio,
		"size": [analysis.get_width(), analysis.get_height()],
		"bbox": [-12.0, 18.0, 136.0, 57.0], "projection": MapSource.projection_type(manifest),
		"positions": [], "rivers": [], "docks": [],
	}
	for key in ["temperature", "winter_temperature", "rainfall", "aridity", "water", "rainfed", "farmland", "flatness", "cold", "continentality", "local_runoff", "relief", "suitability", "land", "heights"]:
		output[key] = Array(env[key])
	for city in state.cities:
		var position := [city.map_position.x, city.map_position.y]
		if city.is_dock: output.docks.append(position)
		else: output.positions.append(position)
	for river in env.hydrology.features:
		var points := []
		for p in river.points: points.append([p.x, p.y])
		output.rivers.append({"id": river.id, "class": river.river_class, "points": points})
	var output_path := OS.get_environment("SETTLEMENT_HEATMAP_DATA")
	if output_path.is_empty(): output_path = "res://.dbg/settlement-heatmaps-current.json"
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write diagnostics: ", output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(output))
	print("SETTLEMENT_HEATMAP_EXPORT_OK source=", manifest, " seed=", seed_value,
		" environment=", env.environment_id, " cities=", output.positions.size(), " output=", output_path)
	quit()
