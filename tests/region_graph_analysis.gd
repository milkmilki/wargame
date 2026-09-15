extends SceneTree


func _init() -> void:
	var links: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 0),
		Vector2i(2, 3),
		Vector2i(3, 4), Vector2i(4, 5), Vector2i(5, 3),
	]
	var active := PackedInt32Array([0, 1, 2, 3, 4, 5])
	var result := RegionGraphAnalysis.analyze(6, active, links)
	var reversed_links := links.duplicate()
	reversed_links.reverse()
	var repeated := RegionGraphAnalysis.analyze(6, active, reversed_links)
	var regions: PackedInt32Array = result["region_ids"]
	var scores: PackedFloat32Array = result["betweenness"]
	var same_partition := (
		regions[0] == regions[1]
		and regions[1] == regions[2]
		and regions[3] == regions[4]
		and regions[4] == regions[5]
		and regions[0] != regions[3]
	)
	var bridge_is_central := (
		is_equal_approx(scores[2], scores[3])
		and scores[2] > scores[0]
		and scores[3] > scores[5]
	)
	var deterministic: bool = (
		regions == repeated["region_ids"]
		and scores == repeated["betweenness"]
		and result["key_city_ids"] == repeated["key_city_ids"]
	)
	var state := GameState.new()
	state.generate_grid_world(77001)
	var state_analysis_valid: bool = (
		state.region_ids.size() == state.cities.size()
		and state.node_betweenness.size() == state.cities.size()
		and state.region_count > 1
		and not state.region_key_city_ids.is_empty()
	)
	for key_city_id in state.region_key_city_ids:
		state_analysis_valid = (
			state_analysis_valid
			and key_city_id >= 0
			and key_city_id < state.cities.size()
			and state.node_betweenness[key_city_id] > 0.0
		)
	for city in state.cities:
		state_analysis_valid = (
			state_analysis_valid
			and state.region_ids[city.id] >= 0
			and state.region_ids[city.id] < state.region_count
		)
	var region_overlay := MapRenderer.build_region_overlay_image(state)
	var region_overlay_valid := (
		region_overlay != null
		and not region_overlay.is_empty()
		and region_overlay.get_size() == state.province_map_size
	)
	if region_overlay_valid:
		for y in range(state.province_map_size.y):
			for x in range(state.province_map_size.x):
				var pixel_index := y * state.province_map_size.x + x
				var city_id := state.province_ids[pixel_index]
				if city_id < 0:
					continue
				var region_id := state.region_ids[city_id]
				var expected_color := (
					state.region_colors[region_id]
					if region_id >= 0
						and region_id < state.region_colors.size()
					else Color.TRANSPARENT
				)
				var actual_color := region_overlay.get_pixel(x, y)
				region_overlay_valid = (
					region_overlay_valid
					and _colors_match_rgba8(actual_color, expected_color)
				)
	if (
		int(result.get("region_count", 0)) == 2
		and same_partition
		and bridge_is_central
		and deterministic
		and state_analysis_valid
		and region_overlay_valid
	):
		print(
			"REGION_GRAPH_ANALYSIS_OK regions=%s scores=%s keys=%s"
			% [
				str(regions),
				str(scores),
				str(result["key_city_ids"]),
			]
		)
		quit(0)
		return
	push_error(
		"REGION_GRAPH_ANALYSIS_FAILED regions=%s scores=%s repeated=%s"
		% [str(regions), str(scores), str(repeated)]
	)
	quit(1)


func _colors_match_rgba8(actual: Color, expected: Color) -> bool:
	var tolerance := 1.0 / 255.0 + 0.00001
	return (
		absf(actual.r - expected.r) <= tolerance
		and absf(actual.g - expected.g) <= tolerance
		and absf(actual.b - expected.b) <= tolerance
		and absf(actual.a - expected.a) <= tolerance
	)
