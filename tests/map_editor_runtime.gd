extends SceneTree
## End-to-end contract for rectangular generation, negative-height water, runtime
## city-count regeneration, constrained editing and map-definition round trips.


func _init() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("MAP_EDITOR_RUNTIME_FAILED: " + message)
	quit(1)


func _run() -> void:
	var state := GameState.new()
	state.generate_world(24680, 4, 96)
	if state.land_cities().size() != 96:
		_fail("requested city count was not generated exactly")
		return
	if state.city_generation_mask_path != GameState.DEFAULT_CITY_MASK_PATH:
		_fail("default China city mask was not applied")
		return
	var default_mask := (
		load(GameState.DEFAULT_CITY_MASK_PATH) as Texture2D
	).get_image()
	if (
		state.map_source_region_normalized
			!= Rect2(0.0, 0.0, 1.0, 1.0)
		or not is_equal_approx(
			state.map_aspect_ratio,
			TerrainMapGenerator.FULL_MAP_ASPECT_RATIO
		)
	):
		_fail("map must retain the complete geographic rectangle")
		return
	var height_image := (
		load(GameState.terrain_map_path()) as Texture2D
	).get_image()
	var minimum_coast_distance_pixels := INF
	var alpha_image := height_image
	for city in state.land_cities():
		var mask_pixel := default_mask.get_pixel(
			clampi(int(city.map_position.x * default_mask.get_width()), 0, default_mask.get_width() - 1),
			clampi(int(city.map_position.y * default_mask.get_height()), 0, default_mask.get_height() - 1)
		)
		if mask_pixel.get_luminance() < 0.5:
			_fail("default-mask city generated in a black region")
			return
		var pixel := height_image.get_pixel(
			clampi(int(city.map_position.x * height_image.get_width()), 0, height_image.get_width() - 1),
			clampi(int(city.map_position.y * height_image.get_height()), 0, height_image.get_height() - 1)
		)
		if pixel.a < TerrainMapGenerator.ALPHA_THRESHOLD:
			_fail("generated city landed in negative-height water")
			return
		var px := clampi(int(city.map_position.x * alpha_image.get_width()), 0, alpha_image.get_width() - 1)
		var py := clampi(int(city.map_position.y * alpha_image.get_height()), 0, alpha_image.get_height() - 1)
		for radius in range(1, 65):
			var found_water := false
			for sample in [Vector2i(px - radius, py), Vector2i(px + radius, py), Vector2i(px, py - radius), Vector2i(px, py + radius)]:
				if sample.x < 0 or sample.y < 0 or sample.x >= alpha_image.get_width() or sample.y >= alpha_image.get_height():
					continue
				if alpha_image.get_pixelv(sample).a <= TerrainMapGenerator.ALPHA_THRESHOLD:
					found_water = true
					break
			if found_water:
				minimum_coast_distance_pixels = minf(minimum_coast_distance_pixels, radius)
				break
	if minimum_coast_distance_pixels > 32.0:
		_fail("all generated cities remain artificially inset from the packed coastline")
		return

	var renderer := StrategicTerrainRenderer.new()
	root.add_child(renderer)
	renderer.configure(Vector2i(96, 56), Vector2(64.0, 36.864), 4.8, 64)
	renderer.generate_from_height_texture(
		load(GameState.terrain_map_path()) as Texture2D,
		Rect2(0.0, 0.0, 1.0, 1.0),
		TerrainMapGenerator.ALPHA_THRESHOLD,
		TerrainMapGenerator.LUMA_THRESHOLD
	)
	var water_samples := 0
	for height in renderer._height_samples:
		if height < StrategicTerrainRenderer.WATER_SURFACE_HEIGHT:
			water_samples += 1
	if water_samples <= 0:
		_fail("rectangular terrain contains no negative-height water samples")
		return

	var city := state.land_cities()[0]
	var original_city_id := city.id
	var original_position := city.map_position
	var moved_position := original_position
	for offset in [
		Vector2(0.002, 0.0),
		Vector2(-0.002, 0.0),
		Vector2(0.0, 0.002),
		Vector2(0.0, -0.002),
	]:
		var candidate: Vector2 = original_position + offset
		if TerrainMapGenerator.is_land_map_position(
			GameState.terrain_map_path(), candidate
		):
			moved_position = candidate
			break
	if moved_position == original_position:
		_fail("could not find nearby editable land position")
		return
	var city_result := state.apply_city_editor_changes(city.id, {
		"map_x": moved_position.x,
		"map_y": moved_position.y,
		"gold_per_month": 77,
		"fort_strength_max": 42,
		"fort_strength": 31,
		"food_storage": 9876,
		"terrain_output_multiplier": 1.25,
		"development_gold_multiplier": 2.5,
		"is_crossroads": true,
	})
	if not bool(city_result.get("ok", false)):
		_fail("city edit was rejected")
		return
	var edited_edge: Edge = null
	for edge in state.edges:
		if edge.kind == Edge.Kind.LAND:
			edited_edge = edge
			break
	if edited_edge == null:
		_fail("no editable land edge")
		return
	var edge_a := edited_edge.city_a
	var edge_b := edited_edge.city_b
	var edge_result := state.apply_edge_editor_changes(edge_a, edge_b, {
		"max_manpower": 10000,
		"distance": 9,
		"danger": 0.73,
		"max_height_difference": 0.44,
		"land_ratio": 0.88,
		"is_backbone": true,
	})
	if not bool(edge_result.get("ok", false)):
		_fail("edge edit was rejected")
		return

	var file_name := "map_editor_runtime_roundtrip.json"
	var saved := MapDefinition.save_state(state, file_name)
	if not bool(saved.get("ok", false)):
		_fail(str(saved.get("error", "save failed")))
		return
	var loaded := MapDefinition.load_file(file_name)
	if not bool(loaded.get("ok", false)):
		_fail(str(loaded.get("error", "load failed")))
		return
	var invalid_version := (loaded["data"] as Dictionary).duplicate(true)
	invalid_version["version"] = MapDefinition.VERSION + 1
	if MapDefinition.validate(invalid_version).is_empty():
		_fail("future map versions must be rejected")
		return
	var invalid_edge := (loaded["data"] as Dictionary).duplicate(true)
	(invalid_edge["edges"] as Array)[0]["city_b"] = 999999
	if MapDefinition.validate(invalid_edge).is_empty():
		_fail("invalid edge endpoint must be rejected")
		return
	var restored := GameState.new()
	restored.generate_from_map_definition(loaded["data"], 24680)
	var restored_edge := restored.edge_of(edge_a, edge_b)
	var original_sea_count := 0
	var restored_sea_count := 0
	for source_edge in state.edges:
		if source_edge.kind == Edge.Kind.SEA:
			original_sea_count += 1
	for target_edge in restored.edges:
		if target_edge.kind == Edge.Kind.SEA:
			restored_sea_count += 1
	var checks := {
		"city_count": restored.land_cities().size() == 96,
		"gold": restored.cities[original_city_id].gold_per_month == 77,
		"position": restored.cities[original_city_id].map_position.distance_to(moved_position) <= 0.00001,
		"fort": restored.cities[original_city_id].fort_strength_max == 42,
		"food_total": restored.nations[restored.cities[original_city_id].owner_nation].granary_food >= 9876,
		"development": is_equal_approx(restored.cities[original_city_id].development_gold_multiplier, 2.5),
		"crossroads": restored.cities[original_city_id].is_crossroads,
		"edge_exists": restored_edge != null,
		"edge_capacity": restored_edge != null and restored_edge.max_manpower == 10000,
		"edge_distance": restored_edge != null and restored_edge.distance == 9,
		"edge_danger": restored_edge != null and is_equal_approx(restored_edge.danger, 0.73),
		"edge_relief": restored_edge != null and is_equal_approx(restored_edge.max_height_difference, 0.44),
		"edge_land": restored_edge != null and is_equal_approx(restored_edge.land_ratio, 0.88),
		"edge_backbone": restored_edge != null and restored_edge.is_backbone,
		"sea_roundtrip": restored_sea_count == original_sea_count,
		"armies": not restored.armies.is_empty(),
		"day_zero": restored.day == 0,
	}
	var round_trip_valid := true
	for check_value in checks.values():
		round_trip_valid = round_trip_valid and bool(check_value)
	if not round_trip_valid:
		print("MAP_EDITOR_RUNTIME_DIAGNOSTIC checks=", checks)
		_fail("saved map did not round-trip edited topology and properties")
		return
	print(
		"MAP_EDITOR_RUNTIME_OK cities=", restored.land_cities().size(),
		" edges=", restored.edges.size(),
		" water_samples=", water_samples,
		" coast_distance_px=", minimum_coast_distance_pixels,
		" path=", saved["path"]
	)
	renderer.free()
	quit(0)
