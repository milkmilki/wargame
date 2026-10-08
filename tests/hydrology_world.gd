extends SceneTree

var SOURCE: String = OS.get_environment("HYDROLOGY_SOURCE") if not OS.get_environment("HYDROLOGY_SOURCE").is_empty() else "res://assets/terrain/eurasia_hydrology_map_source.json"
const SEEDS: Array[int] = [2342006650, 12345, 23456, 34567, 45678]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var china := GameState.new()
	china.generate_world(12345, 4, 48)
	var legacy_environment := GameState.new()
	var old_source := "res://assets/terrain/eurasia_environment_map_source.json"
	assert(legacy_environment.generate_world(12345, 4, 48, "", {}, 12345, "", old_source))
	var legacy_template := MapDefinition.from_state(legacy_environment)
	var selected := SEEDS.duplicate()
	if not OS.get_environment("HYDROLOGY_SEED").is_empty():
		selected = [int(OS.get_environment("HYDROLOGY_SEED"))]
	for seed_value in selected:
		var state := GameState.new()
		if not state.generate_world(seed_value, 40, 500, "", {}, seed_value, "", SOURCE):
			push_error(state.last_generation_error)
			quit(1)
			return
		assert(state.land_cities().size() == 500)
		assert(state.nations.size() == 40)
		assert(absf(state.map_aspect_ratio - 2.8790009154) < 1e-6)
		assert(state.city_generation_mask_path.is_empty())
		assert(MapFeatureContract.validate_rivers(state.river_features).is_empty())
		assert(not MapFeatureContract.major_rivers(state.river_features).is_empty())
		var template := MapDefinition.from_state(state)
		assert(MapDefinition.validate(template).is_empty())
		assert(state.territory_structure_valid())
		var land_image := (load(state.current_terrain_map_path()) as Texture2D).get_image()
		_assert_hydrology_coverage(state, land_image)
		var seed_cells := {}
		for city in state.land_cities():
			var cell := Vector2i(city.map_position * Vector2(state.province_map_size))
			assert(not seed_cells.has(cell), "two cities cannot share a province seed cell")
			seed_cells[cell] = true
			var pixel := Vector2i(Vector2(land_image.get_size()) * city.map_position).clamp(Vector2i.ZERO, land_image.get_size() - Vector2i.ONE)
			assert(TerrainMapGenerator.packed_is_land(land_image.get_pixelv(pixel)))
			assert(city.owner_nation >= 0 and city.owner_nation < 40)
		for edge in state.edges:
			if edge.kind == Edge.Kind.RIVER:
				assert(not edge.river_reaches.is_empty())
				for reach in edge.river_reaches: assert(state.river_features[reach.river_id].river_class == "major")
			if edge.kind == Edge.Kind.LAND:
				assert(not state.cities[edge.city_a].is_dock and not state.cities[edge.city_b].is_dock)
				assert(edge.land_ratio >= TerrainMapGenerator.ROAD_MINIMUM_LAND_RATIO)
				assert(TerrainMapGenerator.province_segment_stays_in_pair(
					state.province_ids, state.province_map_size,
					state.cities[edge.city_a].map_position, state.cities[edge.city_b].map_position,
					edge.city_a, edge.city_b
				) or edge.map_path.size() >= 2)
		var west := _nearest_city(state, _uv(3.0, 46.0))
		var middle := _nearest_city(state, _uv(60.0, 40.0))
		var east := _nearest_city(state, _uv(108.9, 34.3))
		assert(_reachable(state, west, middle) and _reachable(state, middle, east), "欧亚大陆交通不连通")
		var dock_count := state.cities.size() - 500
		assert(dock_count > 0)
		assert(state.generation_metadata.settlement_model == "environment_v1")
		assert(state.generation_metadata.seed == seed_value)
		for nation in state.nations:
			assert(not state.land_cities_of(nation.id).is_empty())
		for city in state.cities:
			if city.is_dock:
				var banks := 0
				for neighbor in state.neighbors(city.id):
					if state.edge_of(city.id, neighbor).kind == Edge.Kind.LANDING:
						banks += 1
				assert(banks == 2)
		var restored := GameState.new()
		restored.generate_from_map_definition(template, seed_value)
		assert(restored.current_terrain_map_path() == state.current_terrain_map_path())
		assert(restored.province_ids == state.province_ids)
		assert(restored.river_features == state.river_features)
		var before_failed := MapDefinition.from_state(restored)
		restored.armies[0].on_edge = true
		assert(not restored.apply_city_editor_changes(0, {"map_x": restored.cities[0].map_position.x + 0.001}).ok)
		assert(MapDefinition.from_state(restored) == before_failed)
		restored.armies[0].on_edge = false
		var edit := restored.apply_city_editor_changes(0, {"gold_per_month": 77})
		assert(edit.ok)
		assert(MapDefinition.from_state(restored).map_source_manifest == SOURCE)
		print("EURASIA_SEED_OK seed=%d cities=500 nations=40 docks=%d west=%d middle=%d east=%d" % [seed_value, dock_count, west, middle, east])
		await process_frame
	var china_again := GameState.new()
	china_again.generate_world(12345, 4, 48)
	assert(china_again.current_terrain_map_path() == GameState.terrain_map_path())
	assert(china_again.province_ids == china.province_ids)
	assert(china_again.map_aspect_ratio == china.map_aspect_ratio)
	for city_id in range(china.cities.size()):
		assert(china_again.cities[city_id].map_position == china.cities[city_id].map_position)
	var legacy_again := GameState.new()
	assert(legacy_again.generate_world(12345, 4, 48, "", {}, 12345, "", old_source))
	assert(MapDefinition.from_state(legacy_again) == legacy_template)
	print("HYDROLOGY_WORLD_OK")
	quit(0)

func _uv(lon: float, lat: float) -> Vector2:
	var uv := MapSource.lonlat_to_map(lon, lat, SOURCE)
	return Vector2(uv[0], uv[1])

func _assert_province_coverage(state: GameState, source: Image) -> void:
	var image: Image = source.duplicate()
	image.resize(state.province_map_size.x, state.province_map_size.y, Image.INTERPOLATE_NEAREST)
	var width := image.get_width()
	var height := image.get_height()
	var visited := PackedByteArray()
	visited.resize(width * height)
	for start in range(visited.size()):
		if visited[start] != 0 or not TerrainMapGenerator.packed_is_land(image.get_pixel(start % width, start / width)):
			continue
		var queue: Array[int] = [start]
		visited[start] = 1
		var cursor := 0
		var assigned := 0
		while cursor < queue.size():
			var index := queue[cursor]
			cursor += 1
			if state.province_ids[index] >= 0:
				assigned += 1
			var point := Vector2i(index % width, index / width)
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = point + offset
				if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
					continue
				var next_index := next.y * width + next.x
				if visited[next_index] == 0 and TerrainMapGenerator.packed_is_land(image.get_pixelv(next)):
					visited[next_index] = 1
					queue.append(next_index)
		assert(assigned == 0 or assigned == queue.size(), "有种子的陆地连通块存在未分配省份空洞")

func _nearest_city(state: GameState, position: Vector2) -> int:
	var result := -1
	var distance := INF
	for city in state.land_cities():
		var delta: Vector2 = city.map_position - position
		delta.x *= state.map_aspect_ratio
		if delta.length_squared() < distance:
			distance = delta.length_squared()
			result = city.id
	return result

func _reachable(state: GameState, from: int, to: int) -> bool:
	var queue: Array[int] = [from]
	var visited := {from: true}
	var index := 0
	while index < queue.size():
		var current := queue[index]
		index += 1
		if current == to:
			return true
		for neighbor in state.neighbors(current):
			var edge: Edge = state.edge_of(current, neighbor)
			if edge.kind == Edge.Kind.SEA or edge.max_manpower <= 0 or visited.has(neighbor):
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return false

func _assert_hydrology_coverage(state: GameState, source: Image) -> void:
	var hydro = preload("res://scripts/core/terrain_hydrology.gd")
	var size := state.province_map_size
	var image := source.duplicate()
	image.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	var land: PackedByteArray = TerrainMapGenerator._all_land_geometry(image).mask
	var barriers: Dictionary = hydro.barriers(state.river_features, size)
	var components: PackedInt32Array = hydro.components(land, size, barriers)
	var seeded := {}
	for city in state.land_cities():
		var p := Vector2i(city.map_position * Vector2(size))
		seeded[components[p.y * size.x + p.x]] = true
	for i in range(land.size()):
		if land[i] == 0: continue
		assert((state.province_ids[i] >= 0) == seeded.has(components[i]))
	# The province owner's seed must be reachable without crossing a major edge.
	var visited := PackedByteArray()
	visited.resize(land.size())
	for city in state.land_cities():
		var p := Vector2i(city.map_position * Vector2(size))
		var index := p.y * size.x + p.x
		var queue := PackedInt32Array([index])
		visited[index] = 1
		var head := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			var point := Vector2i(current % size.x, current / size.x)
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = point + offset
				if not Rect2i(Vector2i.ZERO, size).has_point(next): continue
				var j := next.y * size.x + next.x
				if visited[j] != 0 or state.province_ids[j] != city.id: continue
				if barriers.has(hydro.edge_key(current, j, land.size())): continue
				visited[j] = 1
				queue.append(j)
	for i in range(land.size()):
		if state.province_ids[i] >= 0: assert(visited[i] != 0)
