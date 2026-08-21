extends SceneTree
## Geometry gate for dock-to-land-city spacing. Boundary docks must remain
## visually separate from every ordinary city and formal edge map paths may
## touch a river only at the dock endpoint of a landing edge.


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	var docks: Array[City] = []
	var land: Array[City] = []
	for city in state.cities:
		if city.is_dock:
			docks.append(city)
		else:
			land.append(city)
	var minimum := INF
	var closest_pair := Vector2i(-1, -1)
	var crossing_count := 0
	for dock in docks:
		for city in land:
			var delta := dock.map_position - city.map_position
			delta.x *= state.map_aspect_ratio
			if delta.length() < minimum:
				minimum = delta.length()
				closest_pair = Vector2i(dock.id, city.id)
	for edge in state.edges:
		if edge.max_manpower <= 0 or edge.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]:
			continue
		var road_path := edge.map_points(
			state.cities[edge.city_a].map_position,
			state.cities[edge.city_b].map_position
		)
		for road_index in range(road_path.size() - 1):
			var road_start := road_path[road_index]
			var road_end := road_path[road_index + 1]
			var road_delta := road_end - road_start
			for river_id in range(state.river_paths.size()):
				var river := state.river_paths[river_id]
				for segment_index in range(river.size() - 1):
					var hit = Geometry2D.segment_intersects_segment(
						road_start, road_end,
						river[segment_index], river[segment_index + 1]
					)
					if hit == null:
						continue
					var t := (
						(Vector2(hit) - road_start).dot(road_delta)
							/ maxf(road_delta.length_squared(), 0.000001)
					)
					if (
						t > TerrainMapGenerator.RIVER_CROSSING_ENDPOINT_EPS
						and t < 1.0 - TerrainMapGenerator.RIVER_CROSSING_ENDPOINT_EPS
					):
						crossing_count += 1
						print(
							"DOCK_CITY_CROSS edge=", edge.city_a, "-", edge.city_b,
							" kind=", edge.kind, " river=", river_id, " t=", t,
							" pos=", road_start, " -> ", road_end, " hit=", hit
						)
	if minimum < TerrainMapGenerator.RIVER_DOCK_CITY_MIN_SPACING:
		push_error("DOCK_CITY_SPACING_FAILED min=%f pair=%s" % [minimum, str(closest_pair)])
		quit(1)
		return
	if crossing_count > 0:
		push_error("DOCK_CITY_SPACING_CROSSING_FAILED count=%d" % crossing_count)
		quit(1)
		return
	print(
		"DOCK_CITY_SPACING min=", minimum,
		" pair=", closest_pair, " docks=", docks.size()
	)
	quit(0)
