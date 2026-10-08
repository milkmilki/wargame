extends SceneTree

var SOURCE: String = OS.get_environment("HYDROLOGY_SOURCE") if not OS.get_environment("HYDROLOGY_SOURCE").is_empty() else "res://assets/terrain/eurasia_atlas_map_source.json"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var startup_started := Time.get_ticks_msec()
	root.size = Vector2i(1800, 1000)
	var main := (load("res://eurasia.tscn") as PackedScene).instantiate()
	assert(main.map_source_manifest == "res://assets/terrain/eurasia_hydrology_map_source.json")
	# Explicit test override previews an unpromoted manifest without changing the scene.
	main.map_source_manifest = SOURCE
	assert(main.nation_count == 40 and main.terrain_city_count == 500)
	assert(main.randomize_world_seed_on_start)
	assert(is_equal_approx(main.map_world_scale, 2.0))
	assert(main.initial_city_mask_path.is_empty())
	assert(not main.initial_city_names_visible and main.initial_nation_names_visible)
	main.world_seed = 12345
	main.randomize_world_seed_on_start = false
	root.add_child(main)
	main.simulation.paused = true
	var map: StrategicMap3D = main.map_3d
	await _wait_terrain(map)
	print("EURASIA_STARTUP_MS ", Time.get_ticks_msec() - startup_started)
	assert(main.state.map_source_manifest == SOURCE)
	assert(not main.map_editor_panel._density_peak_latitude.editable)
	assert(not main.map_editor_panel._north_density.editable and not main.map_editor_panel._south_density.editable)
	assert(main.map_editor_panel._latitude_min.editable and main.map_editor_panel._latitude_max.editable)
	var previous_state: GameState = main.state
	var previous_template := MapDefinition.from_state(main.state)
	main._on_map_regenerate_requested(500, "", "", {"latitude_min": 75.0, "latitude_max": 85.0})
	assert(main.state == previous_state and MapDefinition.from_state(main.state) == previous_template)
	assert(main.map_editor_panel._status.text.contains("减少城市数"))
	print("EURASIA_SCENE_PHASE initial_terrain_ready")
	var old_position: Vector2 = main.state.cities[0].map_position
	var original_rivers: Array = main.state.river_features.duplicate(true)
	var moved_position := old_position
	for offset in [Vector2(2.0 / 256.0, 0.0), Vector2(-2.0 / 256.0, 0.0), Vector2(0.0, 2.0 / 256.0), Vector2(0.0, -2.0 / 256.0)]:
		var candidate: Vector2 = old_position + offset
		if TerrainMapGenerator.is_land_map_position(main.state.current_terrain_map_path(), candidate):
			moved_position = candidate
			break
	assert(moved_position != old_position)
	main._on_city_changes_requested(0, {"map_x": moved_position.x, "map_y": moved_position.y})
	print("EURASIA_SCENE_PHASE city_move_applied")
	assert(map._trade_route_mesh_segments().size() <= main.state.edges.size() * 4)
	main.simulation.paused = true
	await _wait_terrain(map)
	assert(main.state.cities[0].map_position == moved_position)
	assert(main.state.river_features == original_rivers)
	assert(main.state.territory_structure_valid())
	_assert_continental_corridor(main.state)
	assert(main.state.map_source_manifest == SOURCE)
	print("EURASIA_SCENE_PHASE city_move_terrain_ready")
	print("EURASIA_TRADE_MESH routes=%d unique_edge_styles=%d" % [main.state.trade_routes.size(), map._trade_route_mesh_segments().size()])
	assert(main.state.land_cities().size() == 500)
	assert(main.state.nations.size() == 40)
	assert(is_equal_approx(map._world_size.x / map._world_size.y, 2.8790009154))
	assert(is_equal_approx(main.renderer._map_size.x / main.renderer._map_size.y, 2.8790009154))
	assert(not map._nation_labels.is_empty())
	for position in [Vector2(0.1, 0.5), Vector2(0.5, 0.5), Vector2(0.85, 0.5)]:
		var world := map._terrain.map_to_world(position)
		var screen := map._camera.unproject_position(world)
		assert(map._screen_to_map_position(screen).distance_to(position) < 0.015)
	main.map_editor_panel.open_panel()
	print("EURASIA_SCENE_PHASE picking_ready")
	await process_frame
	assert(is_equal_approx(main.map_editor_panel._latitude_max.value, 57.0))
	assert(is_equal_approx(main.map_editor_panel._density_peak_latitude.value, 35.0))
	assert(is_equal_approx(main.map_editor_panel._latitude_max.max_value, MapSource.MERCATOR_LATITUDE_LIMIT))
	main._on_map_regenerate_requested(500, "", "", {})
	print("EURASIA_SCENE_PHASE regenerated")
	main.simulation.paused = true
	await _wait_terrain(map)
	assert(main.state.map_source_manifest == SOURCE)
	var saved := MapDefinition.save_state(main.state, "eurasia_scene_smoke.json")
	assert(saved.ok)
	main._on_map_load_requested("eurasia_scene_smoke.json")
	print("EURASIA_SCENE_PHASE template_loaded")
	main.simulation.paused = true
	await _wait_terrain(map)
	assert(main.state.map_source_manifest == SOURCE)
	assert(main._debug_generation_settings().map_source_manifest == SOURCE)
	assert(main._debug_generation_settings().projection == "web_mercator")
	assert(main._debug_generation_settings().river_settlement_model == MapSource.river_settlement_model(SOURCE))
	main._on_history_position_requested(0)
	await _wait_terrain(map)
	assert(main._history_active)
	assert(map.state.map_source_manifest == SOURCE)
	assert(map.state.province_ids == main.state.province_ids)
	assert(map.state.river_features == main.state.river_features)
	main._leave_history_view()
	main.map_editor_panel.close_panel()
	main.simulation.paused = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved.path))
	var output := OS.get_environment("EURASIA_VISUAL_DIR")
	var reference_ids: PackedByteArray = main.renderer.visual_atlas().city_id.get_data()
	for mode in [MapRenderer.MapMode.POLITICAL, MapRenderer.MapMode.LOYALTY, MapRenderer.MapMode.TRADE, MapRenderer.MapMode.REGION]:
		map.set_map_mode(mode)
		await process_frame
		assert(main.renderer.visual_atlas().city_id.get_data() == reference_ids, "切换视图不能重新划分省份")
		var shown: Image = main.renderer.visual_atlas().city_id
		for y in range(main.state.province_map_size.y):
			for x in range(main.state.province_map_size.x):
				var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(main.state.province_map_size)
				var pixel := Vector2i(uv * Vector2(shown.get_size()))
				var visible_id:=int(shown.get_pixelv(pixel).r)
				assert(MapRenderer.nation_at_map_position(main.state,uv)==(main.state.cities[visible_id].owner_nation if visible_id>=0 else -1))
		if not output.is_empty():
			DirAccess.make_dir_recursive_absolute(output)
			await _screenshot(output.path_join("province-ids-mode-%d.png" % mode))
	map.set_map_mode(MapRenderer.MapMode.POLITICAL)
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		await _screenshot(output.path_join("eurasia-full.png"))
		var overview := map._camera_distance
		for detail in [{"name": "eurasia-mediterranean", "center": _uv(15.0, 38.0)}, {"name": "eurasia-china", "center": _uv(108.9, 34.3)}]:
			var center := map._terrain.map_to_world(detail.center)
			map._camera_target = Vector3(center.x, 0.0, center.z)
			map._camera_distance = overview * 0.28
			map._apply_camera_transform()
			await _screenshot(output.path_join(detail.name + ".png"))
	print("EURASIA_SCENE_OK cities=500 nations=40 aspect=2.879001 projection=web_mercator city_move=OK editor_regenerate=OK template_load=OK history=OK picking=OK")
	quit(0)

func _uv(lon: float, lat: float) -> Vector2:
	var uv := MapSource.lonlat_to_map(lon, lat, SOURCE)
	return Vector2(uv[0], uv[1])

func _assert_continental_corridor(state: GameState) -> void:
	var anchors: Array[int] = []
	for point in [_uv(3.0, 46.0), _uv(60.0, 40.0), _uv(108.9, 34.3)]:
		var nearest := -1
		var distance := INF
		for city in state.land_cities():
			var delta: Vector2 = city.map_position - point
			delta.x *= state.map_aspect_ratio
			if delta.length_squared() < distance:
				distance = delta.length_squared()
				nearest = city.id
		anchors.append(nearest)
	var queue: Array[int] = [anchors[0]]
	var visited := {anchors[0]: true}
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for neighbor in state.neighbors(current):
			var edge: Edge = state.edge_of(current, neighbor)
			if edge.kind != Edge.Kind.SEA and edge.max_manpower > 0 and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	assert(visited.has(anchors[1]) and visited.has(anchors[2]), "编辑重建后欧亚陆路通道断开")

func _wait_terrain(map: StrategicMap3D) -> void:
	var started := Time.get_ticks_msec()
	while map._terrain == null or map._terrain.land_cell_count() <= 0:
		assert(Time.get_ticks_msec() - started < 60000, "欧亚地形生成超时")
		await process_frame
	await process_frame
	await process_frame

func _screenshot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	assert(screenshot != null and not screenshot.is_empty())
	assert(screenshot.save_png(path) == OK)
