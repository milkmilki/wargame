extends SceneTree
## Map templates must restore their own source without changing other worlds.

func _init() -> void:
	var alternate := "user://test_eurasia_source.json"
	var manifest := MapSource.load_manifest()
	manifest["bbox_wgs84"] = [-12.0, 18.0, 136.0, 57.0]
	manifest["city_density"] = {"peak_latitude": 35.0, "south_edge_multiplier": 0.5, "north_edge_multiplier": 0.2}
	var file := FileAccess.open(alternate, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	var china := GameState.new()
	china.generate_world(12345, 4, 48)
	var template := MapDefinition.from_state(china)
	template["map_source_manifest"] = alternate
	template["map_aspect_ratio"] = 148.0 / 39.0
	template.erase("city_density_settings")
	var restored := GameState.new()
	restored.generate_from_map_definition(template, 12345)
	if MapDefinition.from_state(restored)["map_source_manifest"] != alternate:
		push_error("MAP_SOURCE_ISOLATION_FAILED: template source was ignored")
		quit(1)
		return
	assert(is_equal_approx(restored.city_density_settings["density_peak_latitude"], 35.0))
	assert(is_equal_approx(restored.city_density_settings["latitude_max"], 57.0))
	assert(MapDefinition.from_state(china)["map_source_manifest"] == MapSource.DEFAULT_MANIFEST)
	var generated := GameState.new()
	generated.generate_world(12345, 4, 48, "", {}, 0, "", alternate)
	assert(is_equal_approx(generated.map_aspect_ratio, 148.0 / 39.0))
	var original_again := GameState.new()
	original_again.generate_world(12345, 4, 48)
	assert(original_again.cities[0].map_position == china.cities[0].map_position)
	assert(is_equal_approx(original_again.map_aspect_ratio, MapSource.aspect_ratio()))
	var view := StrategicMap3D.new()
	view.state = generated
	view._configure_dimensions()
	assert(is_equal_approx(view._world_size.x / view._world_size.y, 148.0 / 39.0))
	view.free()
	var history := PoliticalHistory.new()
	history.reset(generated)
	assert(history.build_view_state(generated, 0).map_source_manifest == alternate)
	# Real sources, in the same process: China -> legacy Eurasia -> Mercator -> China.
	var legacy_eurasia := GameState.new()
	var old_source := "res://assets/terrain/eurasia_map_source.json"
	legacy_eurasia.generate_world(12345, 4, 48, "", {}, 12345, "", old_source)
	var old_template := MapDefinition.from_state(legacy_eurasia)
	var mercator := GameState.new()
	var new_source := "res://assets/terrain/eurasia_mercator_map_source.json"
	mercator.generate_world(12345, 4, 48, "", {}, 12345, "", new_source)
	assert(absf(mercator.map_aspect_ratio - 2.8790009154) < 1e-6)
	assert(mercator.current_terrain_map_path() != legacy_eurasia.current_terrain_map_path())
	var old_restored := GameState.new()
	old_restored.generate_from_map_definition(old_template, 12345)
	assert(old_restored.map_source_manifest == old_source)
	assert(MapSource.projection_type(old_source) == "equirectangular")
	assert(old_restored.province_ids == legacy_eurasia.province_ids)
	for city_id in range(legacy_eurasia.cities.size()):
		assert(old_restored.cities[city_id].map_position == legacy_eurasia.cities[city_id].map_position)
	var empty_rivers: Array[PackedVector2Array] = []
	var positions: Array[Vector2] = []
	for city in mercator.land_cities():
		positions.append(city.map_position)
	var rebuilt := TerrainMapGenerator.rebuild_provinces(mercator.current_terrain_map_path(), positions, mercator.edges, empty_rivers, new_source)
	assert(rebuilt.ids == mercator.province_ids, "生成和编辑重建的投影距离不一致")
	var rebuilt_with_rivers := TerrainMapGenerator.rebuild_provinces(mercator.current_terrain_map_path(), positions, mercator.edges, mercator.river_paths, new_source)
	if rebuilt_with_rivers.ids != mercator.province_ids:
		push_error("MAP_SOURCE_ISOLATION_FAILED: 派生河流不能在编辑重建时反向改变省份")
		quit(1)
		return
	history.reset(mercator)
	assert(history.build_view_state(mercator, 0).map_source_manifest == new_source)
	var environment_source := "res://assets/terrain/eurasia_environment_map_source.json"
	var environment := GameState.new()
	assert(environment.generate_world(12345, 4, 48, "", {}, 12345, "", environment_source))
	var environment_template := MapDefinition.from_state(environment)
	var environment_restored := GameState.new()
	environment_restored.generate_from_map_definition(environment_template, 12345)
	assert(environment_restored.province_ids == environment.province_ids)
	for i in range(environment.cities.size()):
		assert(environment_restored.cities[i].map_position == environment.cities[i].map_position)
	history.reset(environment)
	assert(history.build_view_state(environment, 0).map_source_manifest == environment_source)
	var rng_before: int = environment.rng.state
	assert(not environment.generate_world(12345, 40, 500, "", {"latitude_min": 75, "latitude_max": 85}, 12345, "", environment_source))
	assert(environment.last_generation_error.contains("减少城市数"))
	assert(environment.rng.state == rng_before)
	assert(MapDefinition.from_state(environment) == environment_template)
	assert(MapSource.settlement_model(new_source) == MapSource.LEGACY_SETTLEMENT)
	assert(MapSource.settlement_model(environment_source) == MapSource.ENVIRONMENT_SETTLEMENT)
	var china_last := GameState.new()
	china_last.generate_world(12345, 4, 48)
	assert(china_last.province_ids == china.province_ids)
	for city_id in range(china.cities.size()):
		assert(china_last.cities[city_id].map_position == china.cities[city_id].map_position)
	var legacy := template.duplicate(true)
	legacy.erase("map_source_manifest")
	var old_world := GameState.new()
	old_world.generate_from_map_definition(legacy)
	assert(MapDefinition.from_state(old_world)["map_source_manifest"] == MapSource.DEFAULT_MANIFEST)
	var missing := template.duplicate(true)
	missing["map_source_manifest"] = "user://missing_map_source.json"
	assert(not MapDefinition.validate(missing).is_empty())
	DirAccess.remove_absolute(alternate)
	print("MAP_SOURCE_ISOLATION_OK")
	quit(0)
