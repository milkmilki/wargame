extends SceneTree

const SOURCE := "res://assets/terrain/eurasia_mercator_map_source.json"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1800, 1000)
	var main := (load("res://eurasia.tscn") as PackedScene).instantiate()
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
	assert(main.state.map_source_manifest == SOURCE)
	print("EURASIA_SCENE_PHASE initial_terrain_ready")
	var old_position: Vector2 = main.state.cities[0].map_position
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
	main._on_history_position_requested(0)
	await _wait_terrain(map)
	assert(main._history_active)
	assert(map.state.map_source_manifest == SOURCE)
	assert(map.state.province_ids == main.state.province_ids)
	main._leave_history_view()
	main.map_editor_panel.close_panel()
	main.simulation.paused = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved.path))
	var output := OS.get_environment("EURASIA_VISUAL_DIR")
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
