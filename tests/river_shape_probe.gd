extends SceneTree

func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	var generated := TerrainMapGenerator.build(
		GameState.terrain_map_path(), GameState.TERRAIN_CITY_COUNT,
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
	for edge in state.edges:
		if edge.kind not in [Edge.Kind.SEA, Edge.Kind.LANDING]:
			continue
		var edge_path := edge.map_points(
			state.cities[edge.city_a].map_position,
			state.cities[edge.city_b].map_position
		)
		for edge_index in range(edge_path.size() - 1):
			for river_path in state.river_paths:
				for river_index in range(river_path.size() - 1):
					if Geometry2D.segment_intersects_segment(
						edge_path[edge_index], edge_path[edge_index + 1],
						river_path[river_index], river_path[river_index + 1]
					) != null:
						if edge.kind == Edge.Kind.SEA:
							sea_crosses_river = true
						else:
							var hit: Vector2 = Geometry2D.segment_intersects_segment(
								edge_path[edge_index], edge_path[edge_index + 1],
								river_path[river_index], river_path[river_index + 1]
							)
							var endpoint_touch := (
								hit.distance_to(edge_path[0]) <= 0.0001
								or hit.distance_to(edge_path[-1]) <= 0.0001
							)
							if not endpoint_touch:
								landing_crosses_river = true
								print("LANDING_RIVER_INTERSECTION edge=", [edge.city_a, edge.city_b], " path=", edge_path, " hit=", hit)
	valid = valid and not sea_crosses_river
	valid = valid and not landing_crosses_river
	print("SEA_CROSSES_RIVER ", sea_crosses_river,
		" LANDING_CROSSES_RIVER ", landing_crosses_river)
	print("verdict=", "RIVER_SHAPE_OK" if valid else "RIVER_SHAPE_INVALID")
	quit(0 if valid else 1)
