extends SceneTree
## 省界河流专项门禁：河道贴公共省界、码头连接两岸、相邻码头河运连通。


func _init() -> void:
	var city_count := _env_int(
		"RIVER_SHAPE_CITIES", GameState.TERRAIN_CITY_COUNT
	)
	var state := GameState.new()
	state.generate_world(12345, GameState.NATION_COUNT, city_count)
	var generated := TerrainMapGenerator.build(
		GameState.terrain_map_path(), city_count,
		state.city_generation_mask_path, state.city_density_settings
	)
	var valid := state.river_paths.size() == TerrainMapGenerator.RIVER_COUNT
	var boundary_segments := 0
	var invalid_boundary_segments := 0
	var river_pair_keys := {}
	for river_id in range(state.river_paths.size()):
		var path: PackedVector2Array = state.river_paths[river_id]
		valid = valid and path.size() >= 2
		print(
			"BOUNDARY_RIVER_DIRECTION start=", path[0],
			" end=", path[-1],
			" delta=", path[-1] - path[0]
		)
		var delta := path[-1] - path[0]
		valid = (
			valid
			and delta.x >= 0.60
			and TerrainMapGenerator.province_boundary_coast_intersection(
				state.province_ids, state.province_map_size, path[-1]
			)
			and (
				absf(delta.y) <= 0.035
				if river_id == 0
				else delta.y >= 0.035 and delta.y <= 0.14
			)
		)
		for path_index in range(path.size() - 1):
			boundary_segments += 1
			var owners := TerrainMapGenerator.province_boundary_segment_owners(
				state.province_ids, state.province_map_size,
				path[path_index], path[path_index + 1]
			)
			if owners.x < 0:
				invalid_boundary_segments += 1
			else:
				river_pair_keys[TerrainMapGenerator._pair_key(owners.x, owners.y)] = true
	valid = valid and boundary_segments > 0 and invalid_boundary_segments == 0

	var groups := {}
	var invalid_docks := 0
	for dock_value in generated.get("docks", []):
		var dock: Dictionary = dock_value
		var river_id := int(dock["river_id"])
		if not groups.has(river_id):
			groups[river_id] = [] as Array[Dictionary]
		(groups[river_id] as Array[Dictionary]).append(dock)
		var path: PackedVector2Array = state.river_paths[river_id]
		var segment_index := clampi(
			int(floor(float(dock["river_progress"]))), 0, path.size() - 2
		)
		var owners := TerrainMapGenerator.province_boundary_segment_owners(
			state.province_ids, state.province_map_size,
			path[segment_index], path[segment_index + 1]
		)
		var banks := Vector2i(
			mini(int(dock["bank_a"]), int(dock["bank_b"])),
			maxi(int(dock["bank_a"]), int(dock["bank_b"]))
		)
		var dock_city := int(dock["city_id"])
		var landing_a := state.edge_of(banks.x, dock_city)
		var landing_b := state.edge_of(banks.y, dock_city)
		var direct := state.edge_of(banks.x, banks.y)
		if (
			owners != banks
			or landing_a == null or landing_a.kind != Edge.Kind.LANDING
			or landing_b == null or landing_b.kind != Edge.Kind.LANDING
			or (direct != null and direct.kind == Edge.Kind.LAND)
		):
			invalid_docks += 1

	var missing_river_links := 0
	for river_id in range(TerrainMapGenerator.RIVER_COUNT):
		var group: Array = groups.get(river_id, [])
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["river_progress"]) < float(b["river_progress"])
		)
		valid = valid and group.size() >= 2
		for dock_index in range(group.size() - 1):
			var edge := state.edge_of(
				int(group[dock_index]["city_id"]),
				int(group[dock_index + 1]["city_id"])
			)
			if (
				edge == null or edge.kind != Edge.Kind.RIVER
				or edge.max_manpower != Edge.WATER_MANPOWER
				or edge.allows_holding
				or edge.map_path.size() < 2
			):
				missing_river_links += 1
	valid = valid and invalid_docks == 0 and missing_river_links == 0

	var interior_crossings := 0
	for edge in state.edges:
		if edge.max_manpower <= 0 or edge.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]:
			continue
		var edge_path := edge.map_points(
			state.cities[edge.city_a].map_position,
			state.cities[edge.city_b].map_position
		)
		for edge_index in range(edge_path.size() - 1):
			var edge_from := edge_path[edge_index]
			var edge_to := edge_path[edge_index + 1]
			var edge_delta := edge_to - edge_from
			for river_path in state.river_paths:
				for river_index in range(river_path.size() - 1):
					var hit = Geometry2D.segment_intersects_segment(
						edge_from, edge_to,
						river_path[river_index], river_path[river_index + 1]
					)
					if hit == null:
						continue
					var t := (
						(Vector2(hit) - edge_from).dot(edge_delta)
							/ maxf(edge_delta.length_squared(), 0.000001)
					)
					if t > 0.0001 and t < 0.9999:
						interior_crossings += 1
	valid = valid and interior_crossings == 0
	print(
		"BOUNDARY_RIVER_STATS rivers=", state.river_paths.size(),
		" segments=", boundary_segments,
		" invalid_segments=", invalid_boundary_segments,
		" river_pairs=", river_pair_keys.size(),
		" docks=", generated.get("docks", []).size(),
		" invalid_docks=", invalid_docks,
		" missing_links=", missing_river_links,
		" interior_crossings=", interior_crossings
	)
	print("verdict=", "RIVER_SHAPE_OK" if valid else "RIVER_SHAPE_INVALID")
	quit(0 if valid else 1)


func _env_int(key: String, fallback: int) -> int:
	var value := OS.get_environment(key)
	return int(value) if not value.is_empty() else fallback
