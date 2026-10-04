extends SceneTree
## The 500-city scene randomizes settlements, unlike the fixed-layout AI benchmark.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := 0
	if not is_equal_approx(TerrainMapGenerator.minimum_dock_city_spacing_for_count(200), TerrainMapGenerator.RIVER_DOCK_CITY_MIN_SPACING) or not is_equal_approx(TerrainMapGenerator.minimum_dock_city_spacing_for_count(64), TerrainMapGenerator.RIVER_DOCK_CITY_MIN_SPACING):
		failures += 1
		push_error("default and sparse maps must retain original dock clearance")
	for seed_value in [12345, 45678, 67890, 987654321]:
		var terrain := TerrainMapGenerator.build(
			GameState.terrain_map_path(), 500, GameState.DEFAULT_CITY_MASK_PATH,
			{}, seed_value, 80
		)
		var docks: Array = terrain.get("docks", [])
		var rivers: Array = terrain.get("river_paths", [])
		var western := 0
		var eastern := 0
		var dock_range := Vector2(INF, -INF)
		var minimum_city_clearance := TerrainMapGenerator.minimum_dock_city_spacing_for_count(500)
		for dock in docks:
			var x := float(dock.position.x)
			dock_range.x = minf(dock_range.x, x)
			dock_range.y = maxf(dock_range.y, x)
			if x >= 0.5: eastern += 1
			else: western += 1
			if TerrainMapGenerator._minimum_metric_position_distance(dock.position, terrain.positions, terrain.map_aspect_ratio) < minimum_city_clearance:
				failures += 1
				push_error("dense-map dock violates density-scaled city clearance")
		for river_index in range(rivers.size()):
			var river: PackedVector2Array = rivers[river_index]
			print("LARGE_MAP_RIVER endpoints=", river[0], " -> ", river[-1])
			var eastern_start := lerpf(river[0].x, river[-1].x, 0.8)
			var downstream_docks := 0
			for dock in docks:
				if int(dock.river_id) == river_index and float(dock.position.x) >= eastern_start:
					downstream_docks += 1
			if downstream_docks == 0:
				failures += 1
				push_error("500-city river eastern reach loses all docks: seed=%d river=%d" % [seed_value, river_index])
			var east_segments := 0
			var east_candidates := 0
			var maximum_clearance := 0.0
			for path_index in range(river.size() - 1):
				var position: Vector2 = river[path_index].lerp(river[path_index + 1], 0.5)
				if position.x < 0.6: continue
				east_segments += 1
				var clearance := TerrainMapGenerator._minimum_metric_position_distance(position, terrain.positions, terrain.map_aspect_ratio)
				maximum_clearance = maxf(maximum_clearance, clearance)
				if clearance >= minimum_city_clearance: east_candidates += 1
			print("LARGE_MAP_EAST_RIVER segments=%d clearance_candidates=%d max_clearance=%.5f" % [east_segments, east_candidates, maximum_clearance])
		print("LARGE_MAP_DOCK_DISTRIBUTION west=%d east=%d x=%s" % [western, eastern, str(dock_range)])
		print("LARGE_MAP_DOCKS seed=%d rivers=%d docks=%d candidates=%d" % [
			seed_value, rivers.size(), docks.size(),
			(terrain.get("dock_bank_regions", []) as Array).size()
		])
		if rivers.size() != TerrainMapGenerator.RIVER_COUNT or docks.is_empty():
			failures += 1
			push_error("500-city randomized map must retain navigable rivers and docks: %d" % seed_value)
		var landing_banks := {}
		var river_paths: Array[PackedVector2Array] = terrain.river_paths
		for road in terrain.roads:
			if int(road.get("kind", Edge.Kind.LAND)) in [Edge.Kind.LAND, Edge.Kind.LANDING] and TerrainMapGenerator._road_dictionary_crosses_rivers(road, terrain.positions, river_paths):
				failures += 1
				push_error("dense-map road bypasses a dock by crossing a river")
			if int(road.get("kind", Edge.Kind.LAND)) != Edge.Kind.LANDING:
				continue
			var dock_id := maxi(int(road.a), int(road.b))
			if not landing_banks.has(dock_id): landing_banks[dock_id] = []
			(landing_banks[dock_id] as Array).append(mini(int(road.a), int(road.b)))
		for index in range(docks.size()):
			var dock: Dictionary = docks[index]
			var banks: Array = landing_banks.get(int(dock.city_id), [])
			if int(dock.city_id) != 500 + index or banks.size() != 2 or not banks.has(int(dock.bank_a)) or not banks.has(int(dock.bank_b)) or int(dock.bank_a) == int(dock.bank_b):
				failures += 1
				push_error("500-city dock must expose its two distinct banks: %d" % seed_value)
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--screenshot="):
			continue
		root.size = Vector2i(1280, 720)
		var main := (load("res://five_hundred_city_stress.tscn") as PackedScene).instantiate()
		main.world_seed = 12345
		main.randomize_world_seed_on_start = false
		root.add_child(main)
		var sim := main.get_node("Simulation") as Simulation
		sim.paused = true
		var map := main.get_node("StrategicMap3D") as StrategicMap3D
		var deadline := Time.get_ticks_msec() + 60000
		while map._dock_rings.multimesh == null and Time.get_ticks_msec() < deadline:
			await process_frame
		var dock_count := 0
		var first_dock: City
		for city in main.state.cities:
			if city.is_dock:
				dock_count += 1
				if first_dock == null or city.map_position.x > first_dock.map_position.x: first_dock = city
		print("LARGE_MAP_DOCK_SCENE seed=%d docks=%d visible=%s" % [main.state.world_seed, dock_count, str(map._dock_rings.visible)])
		if first_dock == null or not map._dock_rings.visible or map._dock_rings.multimesh == null:
			failures += 1
		else:
			map._camera_target = map._terrain.map_to_world(first_dock.map_position)
			map._camera_distance = 12.0
			map._apply_camera_transform()
			print("LARGE_MAP_DOCK_TRANSFORM ", map._dock_rings.multimesh.get_instance_transform(first_dock.id))
		for frame in range(3): await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(argument.trim_prefix("--screenshot="))
		main.queue_free()
		await process_frame
	quit(1 if failures > 0 else 0)
