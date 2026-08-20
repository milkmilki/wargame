extends SceneTree

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
	var height_image := (
		load(GameState.terrain_map_path()) as Texture2D
	).get_image()
	var valid := state.river_paths.size() == 2
	var docks_by_river := {}
	var dock_x_by_river := {}
	for dock in generated.get("docks", []):
		var river_id := int(dock.get("river_id", -1))
		docks_by_river[river_id] = int(docks_by_river.get(river_id, 0)) + 1
		if not dock_x_by_river.has(river_id):
			dock_x_by_river[river_id] = []
		(dock_x_by_river[river_id] as Array).append(float(dock["position"].x))
	print("RIVER_DOCK_COUNTS ", docks_by_river)
	print("RIVER_DOCK_X ", dock_x_by_river)
	valid = valid and int(docks_by_river.get(0, 0)) >= 6
	valid = valid and int(docks_by_river.get(1, 0)) >= 12
	var south_east_docks := 0
	var south_mouth_docks := 0
	for x_value in dock_x_by_river.get(1, []):
		var x := float(x_value)
		if x >= 0.60:
			south_east_docks += 1
		if x >= 0.70:
			south_mouth_docks += 1
	valid = valid and south_east_docks >= 6 and south_mouth_docks >= 3
	var south_docks: Array = []
	for dock_value in generated.get("docks", []):
		var dock: Dictionary = dock_value
		if int(dock.get("river_id", -1)) == 1:
			south_docks.append(dock)
	south_docks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["river_progress"]) < float(b["river_progress"])
	)
	var south_connected_segments := 0
	var south_east_connected_segments := 0
	var south_curved_edge_segments := 0
	for dock_index in range(south_docks.size() - 1):
		var from_dock: Dictionary = south_docks[dock_index]
		var to_dock: Dictionary = south_docks[dock_index + 1]
		var edge := state.edge_of(
			int(from_dock["city_id"]), int(to_dock["city_id"])
		)
		var segment_valid := (
			edge != null
			and edge.kind == Edge.Kind.RIVER
			and edge.max_manpower == Edge.WATER_MANPOWER
			and edge.map_path.size() >= 2
		)
		valid = valid and segment_valid
		if not segment_valid:
			print("SOUTH_RIVER_MISSING_SEGMENT docks=", [
				int(from_dock["city_id"]), int(to_dock["city_id"])
			])
			continue
		south_connected_segments += 1
		if float((to_dock["position"] as Vector2).x) >= 0.60:
			south_east_connected_segments += 1
		if edge.map_path.size() > 2:
			south_curved_edge_segments += 1
		var edge_points := edge.map_points(
			state.cities[edge.city_a].map_position,
			state.cities[edge.city_b].map_position
		)
		valid = valid and (
			edge_points[0].is_equal_approx(
				state.cities[edge.city_a].map_position
			)
			and edge_points[-1].is_equal_approx(
				state.cities[edge.city_b].map_position
			)
		)
	valid = valid and (
		south_connected_segments == south_docks.size() - 1
		and south_east_connected_segments >= south_east_docks - 1
		and south_curved_edge_segments > 0
	)
	print(
		"SOUTH_RIVER_NETWORK segments=", south_connected_segments,
		" east_segments=", south_east_connected_segments,
		" curved_segments=", south_curved_edge_segments
	)
	for river_index in range(state.river_paths.size()):
		var path := state.river_paths[river_index]
		var min_y := INF
		var max_y := -INF
		var eastmost := path[0].x
		var maximum_backtrack := 0.0
		var maximum_line_deviation := 0.0
		for point in path:
			min_y = minf(min_y, point.y)
			max_y = maxf(max_y, point.y)
			maximum_backtrack = maxf(maximum_backtrack, eastmost - point.x)
			eastmost = maxf(eastmost, point.x)
			var ratio := inverse_lerp(path[0].x, path[-1].x, point.x)
			var line_y := lerpf(path[0].y, path[-1].y, ratio)
			maximum_line_deviation = maxf(
				maximum_line_deviation, absf(point.y - line_y)
			)
		var water_before_last := false
		var last_is_water := false
		var maximum_step := Vector2.ZERO
		for index in range(path.size()):
			var pixel := Vector2i(
				clampi(
					int(path[index].x * height_image.get_width()),
					0, height_image.get_width() - 1
				),
				clampi(
					int(path[index].y * height_image.get_height()),
					0, height_image.get_height() - 1
				)
			)
			if index + 1 < path.size():
				var step := (path[index + 1] - path[index]).abs()
				maximum_step = maximum_step.max(step)
			if index + 1 < path.size() and not TerrainMapGenerator.packed_is_land(
				height_image.get_pixelv(pixel)
			):
				water_before_last = true
			if index + 1 == path.size():
				last_is_water = not TerrainMapGenerator.packed_is_land(
					height_image.get_pixelv(pixel)
				)
		print("RIVER_SHAPE id=", river_index,
			" y_span=", max_y - min_y,
			" line_deviation=", maximum_line_deviation,
			" backtrack=", maximum_backtrack,
			" water_before_last=", water_before_last,
			" last_is_water=", last_is_water,
			" max_step=", maximum_step,
			" start=", path[0], " end=", path[-1])
		valid = valid and (
			max_y - min_y <= 0.09
			and maximum_line_deviation <= 0.055
			and maximum_backtrack <= 0.025
			and not water_before_last
			and last_is_water
			and maximum_step.x <= 0.006
			and maximum_step.y <= 0.010
			and path[-1].x - path[0].x >= 0.40
		)
		if river_index == 1:
			valid = valid and path[-1].x >= 0.78
	var sea_crosses_river := false
	var landing_crosses_river := false
	var land_crosses_river := false
	for edge in state.edges:
		if edge.max_manpower <= 0:
			continue
		if edge.kind not in [Edge.Kind.LAND, Edge.Kind.SEA, Edge.Kind.LANDING]:
			continue
		var edge_path := edge.map_points(
			state.cities[edge.city_a].map_position,
			state.cities[edge.city_b].map_position
		)
		for edge_index in range(edge_path.size() - 1):
			var edge_from := edge_path[edge_index]
			var edge_to := edge_path[edge_index + 1]
			var edge_delta := edge_to - edge_from
			var edge_length_squared := edge_delta.length_squared()
			for river_path in state.river_paths:
				for river_index in range(river_path.size() - 1):
					var hit = Geometry2D.segment_intersects_segment(
						edge_from, edge_to,
						river_path[river_index], river_path[river_index + 1]
					)
					if hit != null:
						if edge.kind == Edge.Kind.SEA:
							sea_crosses_river = true
						elif edge.kind == Edge.Kind.LAND:
							var edge_t := (
								(Vector2(hit) - edge_from).dot(edge_delta)
								/ maxf(edge_length_squared, 0.000001)
							)
							if (
								edge_t > TerrainMapGenerator.RIVER_CROSSING_ENDPOINT_EPS
								and edge_t < 1.0 - TerrainMapGenerator.RIVER_CROSSING_ENDPOINT_EPS
							):
								land_crosses_river = true
						else:
							var endpoint_touch := (
								Vector2(hit).distance_to(edge_path[0]) <= 0.0001
								or Vector2(hit).distance_to(edge_path[-1]) <= 0.0001
							)
							if not endpoint_touch:
								landing_crosses_river = true
								print("LANDING_RIVER_INTERSECTION edge=", [edge.city_a, edge.city_b], " path=", edge_path, " hit=", hit)
	valid = valid and not sea_crosses_river and not land_crosses_river
	valid = valid and not landing_crosses_river
	print("SEA_CROSSES_RIVER ", sea_crosses_river,
		" LAND_CROSSES_RIVER ", land_crosses_river,
		" LANDING_CROSSES_RIVER ", landing_crosses_river)
	print("verdict=", "RIVER_SHAPE_OK" if valid else "RIVER_SHAPE_INVALID")
	quit(0 if valid else 1)


func _env_int(key: String, fallback: int) -> int:
	var value := OS.get_environment(key)
	return int(value) if not value.is_empty() else fallback
