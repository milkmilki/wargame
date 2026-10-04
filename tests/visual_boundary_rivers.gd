extends SceneTree

const RIVERS := preload("res://scripts/view/visual_boundary_rivers.gd")
const ATLAS := preload("res://scripts/view/map_visual_atlas.gd")
const GEOMETRY := preload("res://scripts/view/visual_region_geometry.gd")


func _init() -> void:
	# A shared bent administrative boundary, with reversed copies in each city.
	var boundary := PackedVector2Array([
		Vector2(0.5, 0.0), Vector2(0.5, 0.3),
		Vector2(0.6, 0.5), Vector2(0.5, 0.7), Vector2(0.5, 1.0),
	])
	var left := boundary.duplicate()
	left.append(Vector2(0.0, 1.0))
	left.append(Vector2.ZERO)
	var right := boundary.duplicate()
	right.reverse()
	right.append(Vector2(1.0, 0.0))
	right.append(Vector2.ONE)
	var regions: Array[Dictionary] = [
		{"city_id": 0, "polygon": left},
		{"city_id": 1, "polygon": right},
	]
	var feature := MapFeatureContract.make_river(7, PackedVector2Array([
		Vector2(0.48, 0.0), Vector2(0.48, 0.5), Vector2(0.48, 1.0),
	]))
	var original: PackedVector2Array = feature["points"].duplicate()
	var features: Array = [feature]
	var result := RIVERS.build_paths(regions, features, Vector2i(128, 128))
	var path: PackedVector2Array = result["paths"].get(7, PackedVector2Array())
	var valid := path.size() >= boundary.size()
	for point in path:
		var nearest := INF
		for index in range(boundary.size() - 1):
			nearest = minf(nearest, point.distance_to(
				Geometry2D.get_closest_point_to_segment(point, boundary[index], boundary[index + 1])
			))
		valid = valid and nearest < 0.00001
	valid = valid and feature["points"] == original
	var repeated := RIVERS.build_paths(regions, features, Vector2i(128, 128))
	valid = valid and path == repeated["paths"][7]
	var state := GameState.new()
	state.river_features = [feature]
	var a := City.new()
	a.id = 0
	a.map_position = Vector2(0.48, 0.2)
	var b := City.new()
	b.id = 1
	b.map_position = Vector2(0.48, 0.8)
	state.cities = [a, b]
	var water_edge := Edge.new()
	water_edge.city_a = 0
	water_edge.city_b = 1
	water_edge.kind = Edge.Kind.RIVER
	water_edge.map_path = PackedVector2Array([a.map_position, b.map_position])
	state.edges = [water_edge]
	var height := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	height.fill(Color.WHITE)
	var atlas := ATLAS.build_visual_atlas(state, height, Vector2i(128, 128), null, {
		"regions": regions,
	})
	valid = valid and ATLAS.visual_river_path(state, 7, atlas) == path
	var mask: Image = atlas["river_mask"]
	valid = valid and mask.get_pixel(76, 64).r > 0.5
	valid = valid and mask.get_pixel(61, 64).r < 0.5
	var channel := ATLAS.visual_road_path(state, 0, atlas)
	valid = valid and channel.size() >= 3
	for point in channel:
		var nearest := INF
		for index in range(boundary.size() - 1):
			nearest = minf(nearest, point.distance_to(
				Geometry2D.get_closest_point_to_segment(point, boundary[index], boundary[index + 1])
			))
		valid = valid and nearest < 0.00001
	valid = valid and water_edge.map_path == PackedVector2Array([a.map_position, b.map_position])
	var old_city_texture: Image = atlas["city_id"]
	state.road_network_revision += 1
	ATLAS.refresh_road_paths(state, atlas)
	valid = valid and atlas["city_id"] == old_city_texture
	valid = valid and ATLAS.visual_road_path(state, 0, atlas) == channel
	var shader := FileAccess.get_file_as_string("res://scripts/view/terrain/navigation_ants.gdshader")
	valid = valid and shader.contains("TIME * flow_speed") and shader.contains("discard;")
	valid = valid and is_equal_approx(StrategicMap3D.RIVER_BASE_HALF_WIDTH, 0.075 * 3.0)
	valid = valid and is_equal_approx(StrategicMap3D.WATER_ROUTE_WIDTH, 0.075 * 0.5)
	var no_graph := RIVERS.build_paths([], features, Vector2i(128, 128))
	valid = valid and no_graph["paths"][7].is_empty()
	valid = valid and no_graph["missing_river_ids"] == PackedInt32Array([7])
	var fragment_graph := AStar2D.new()
	fragment_graph.add_point(0, Vector2(0.5, 0.0))
	fragment_graph.add_point(1, Vector2(0.5, 0.94))
	fragment_graph.connect_points(0, 1)
	fragment_graph.add_point(2, Vector2(0.5, 0.99))
	fragment_graph.add_point(3, Vector2(0.51, 0.99))
	fragment_graph.connect_points(2, 3)
	var connected_route := RIVERS._route(fragment_graph, PackedVector2Array([
		Vector2(0.5, 0.0), Vector2(0.5, 1.0),
	]), Vector2i(2048, 2048))
	valid = valid and connected_route == PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.5, 0.94)])
	var sea_barrier := Image.create(128, 128, false, Image.FORMAT_L8)
	sea_barrier.fill(Color.WHITE)
	for y in range(62, 66):
		for x in range(128):
			sea_barrier.set_pixel(x, y, Color.BLACK)
	var disconnected := RIVERS.build_paths(regions, features, Vector2i(128, 128), sea_barrier)
	valid = valid and disconnected["paths"][7].is_empty()
	var imported := feature.duplicate(true)
	imported["source_kind"] = MapFeatureContract.SOURCE_IMPORTED
	var natural := RIVERS.build_paths([], [imported], Vector2i(128, 128))
	valid = valid and natural["paths"][7] == MapFeatureContract.build_high_precision_river_path(
		imported, Vector2i(128, 128)
	)
	if OS.get_environment("WW_TEST_REAL_RIVERS") == "1":
		state.generate_world(12345, 40)
		var texture := load(GameState.terrain_map_path()) as Texture2D
		var geometry := GEOMETRY.build_visual_region_geometry(
			texture.get_image(), ATLAS.visual_city_seeds(state), Vector2i(256, 256)
		)
		var before := hash(state.river_features)
		var started := Time.get_ticks_msec()
		var actual := RIVERS.build_paths(
			geometry["regions"], state.river_features, ATLAS.SIZE, geometry["land_mask"]
		)
		print("BOUNDARY_RIVER_REAL routes=", actual["paths"].size(),
			" missing=", actual["missing_river_ids"],
			" elapsed_ms=", Time.get_ticks_msec() - started)
		valid = valid and actual["missing_river_ids"].is_empty()
		valid = valid and before == hash(state.river_features)
		var segments := {}
		for region in geometry["regions"]:
			var polygon: PackedVector2Array = region["polygon"]
			for index in range(polygon.size()):
				segments[_segment_key(polygon[index], polygon[(index + 1) % polygon.size()])] = true
		for river_path in actual["paths"].values():
			for index in range(river_path.size() - 1):
				valid = valid and segments.has(_segment_key(river_path[index], river_path[index + 1]))
		var edge_signature := hash(state.edges.map(func(edge: Edge) -> PackedVector2Array:
			return edge.map_path
		))
		var water_count := 0
		var water_atlas := {"river_paths": actual["paths"]}
		for index in range(state.edges.size()):
			if state.edges[index].kind != Edge.Kind.RIVER:
				continue
			water_count += 1
			var water_path := ATLAS.visual_road_path(state, index, water_atlas)
			valid = valid and water_path.size() >= 2
		valid = valid and edge_signature == hash(state.edges.map(func(edge: Edge) -> PackedVector2Array:
			return edge.map_path
		))
		print("NAVIGATION_REAL water_edges=", water_count)
	if not valid:
		push_error("VISUAL_BOUNDARY_RIVERS_FAILED")
		quit(1)
		return
	print("VISUAL_BOUNDARY_RIVERS_OK")
	quit(0)


func _segment_key(a: Vector2, b: Vector2) -> String:
	var ka := "%d:%d" % [roundi(a.x * 1000000.0), roundi(a.y * 1000000.0)]
	var kb := "%d:%d" % [roundi(b.x * 1000000.0), roundi(b.y * 1000000.0)]
	return ka + "/" + kb if ka < kb else kb + "/" + ka
