extends SceneTree
## 省份对偶道路门禁：陆路只能连接接壤省份，正式折线不得穿第三省。


func _init() -> void:
	var nation_count := _env_int("ROAD_PROVINCE_NATIONS", 4)
	var city_count := _env_int("ROAD_PROVINCE_CITIES", 160)
	var state := GameState.new()
	state.generate_world(12345, nation_count, city_count)
	var shared := TerrainMapGenerator.province_shared_boundary_counts(
		state.province_ids, state.province_map_size
	)
	var capacities := {}
	var invalid_adjacency := 0
	var invalid_segment := 0
	var curved_paths := 0
	var maximum_path_points := 0
	var land_edges := 0
	var water_edges := 0
	var disconnected_nations := 0
	for edge in state.edges:
		if edge.kind == Edge.Kind.LAND:
			land_edges += 1
			capacities[edge.max_manpower] = int(
				capacities.get(edge.max_manpower, 0)
			) + 1
			if not shared.has(
				TerrainMapGenerator._pair_key(edge.city_a, edge.city_b)
			):
				invalid_adjacency += 1
			if edge.map_path.size() >= 2:
				curved_paths += 1
				maximum_path_points = maxi(
					maximum_path_points, edge.map_path.size()
				)
			var path := edge.map_points(
				state.cities[edge.city_a].map_position,
				state.cities[edge.city_b].map_position
			)
			for index in range(path.size() - 1):
				if not TerrainMapGenerator.province_segment_stays_in_pair(
					state.province_ids, state.province_map_size,
					path[index], path[index + 1], edge.city_a, edge.city_b
				):
					invalid_segment += 1
					break
		elif edge.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]:
			water_edges += 1
	print("ROAD_PROVINCE_STATS land=", land_edges,
		" water=", water_edges, " capacities=", capacities,
		" invalid_adjacency=", invalid_adjacency,
		" invalid_segment=", invalid_segment,
		" curved_paths=", curved_paths,
		" max_path_points=", maximum_path_points)
	for nation in state.nations:
		var component_sizes := []
		for component in state._initial_owner_components(nation.id):
			var land_count := 0
			var dock_count := 0
			for city_id in component:
				if state.cities[int(city_id)].is_dock:
					dock_count += 1
				else:
					land_count += 1
			component_sizes.append([land_count, dock_count])
			if land_count <= 1 and dock_count == 0:
				for city_id_value in component:
					var city_id := int(city_id_value)
					var links := []
					for neighbor in state.neighbors(city_id):
						var edge := state.edge_of(city_id, neighbor)
						links.append([
							neighbor, state.cities[neighbor].owner_nation,
							edge.kind, edge.max_manpower, edge.is_backbone,
						])
					print("ISOLATED_CITY id=", city_id, " links=", links)
		if component_sizes.size() != 1:
			disconnected_nations += 1
			print("NATION_COMPONENTS id=", nation.id, " sizes=", component_sizes)
	var standard_count := int(capacities.get(Edge.TERRAIN_STANDARD_MANPOWER, 0))
	var low_count := int(capacities.get(Edge.TERRAIN_LOW_MANPOWER, 0))
	var valid := (
		land_edges > 0
		and water_edges > 0
		and invalid_adjacency == 0
		and invalid_segment == 0
		and curved_paths > 0
		and standard_count > 0
		and standard_count < low_count
		and disconnected_nations == 0
	)
	print("verdict=", "ROAD_PROVINCE_OK" if valid else "ROAD_PROVINCE_INVALID")
	quit(0 if valid else 1)


func _env_int(key: String, fallback: int) -> int:
	var value := OS.get_environment(key)
	return int(value) if not value.is_empty() else fallback
