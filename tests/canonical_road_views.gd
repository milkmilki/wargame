extends SceneTree
## Political roads, trade ribbons and directed trade flow consume the same
## authoritative geometry, including when a visual river atlas is supplied.
const Atlas = preload("res://scripts/view/map_visual_atlas.gd")
const Generator = preload("res://scripts/core/terrain_map_generator.gd")
const Hydro = preload("res://scripts/core/terrain_hydrology.gd")
const CANONICAL := "res://assets/terrain/eurasia_hydrology_map_source.json"
const LEGACY := MapSource.DEFAULT_MANIFEST
var failures: Array[String] = []

func _init() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("CANONICAL_ROAD_VIEWS_FAIL: ", message)

func fixture(path: PackedVector2Array, kind: int, manifest: String = CANONICAL) -> GameState:
	var state := GameState.new()
	state.map_source_manifest = manifest
	state.map_aspect_ratio = 1.0
	for position in [path[0], path[-1]]:
		var city := City.new()
		city.id = state.cities.size()
		city.map_position = position
		state.cities.append(city)
	var edge := Edge.new()
	edge.city_a = 0
	edge.city_b = 1
	edge.kind = kind
	edge.map_path = path.duplicate()
	edge.max_manpower = Edge.WATER_MANPOWER if kind in [Edge.Kind.RIVER, Edge.Kind.SEA] else Edge.TERRAIN_STANDARD_MANPOWER
	edge.distance = Generator.distance_units_for_metric_length(Generator.metric_polyline_length(path, 1.0))
	state.edges.append(edge)
	state.edge_lookup[state._edge_key(0, 1)] = edge
	return state

func assert_consumers(state: GameState, atlas: Dictionary, label: String) -> void:
	var expected := state.edges[0].map_path
	var political := Atlas.visual_road_path(state, 0, atlas)
	check(political == expected, label + " political road keeps exact Edge.map_path")
	var route := {"city_path": [0, 1], "status": TradeNetwork.ACTIVE, "food": 0}
	var trade := MapRenderer.trade_route_map_paths(state, route, atlas)
	check(trade.size() == 1 and trade[0] == expected, label + " trade road keeps exact Edge.map_path")
	check(MapRenderer.trade_route_flow_path(state, route, atlas) == expected, label + " trade flow keeps exact Edge.map_path")
	var reversed := expected.duplicate()
	reversed.reverse()
	route.city_path = [1, 0]
	var reverse_trade := MapRenderer.trade_route_map_paths(state, route, atlas)
	check(reverse_trade.size() == 1 and reverse_trade[0] == reversed, label + " reverse trade changes only direction")
	route.city_path = [0, 1]
	route.food = 10
	route.food_source_city = 1
	route.food_destination_city = 0
	check(MapRenderer.trade_route_flow_path(state, route, atlas) == reversed, label + " food flow reverses authoritative path toward destination")
	check(state.edges[0].map_path == expected, label + " consumers preserve simulation geometry")

func run() -> void:
	var path := PackedVector2Array([Vector2(0.2, 0.5), Vector2(0.4, 0.3), Vector2(0.6, 0.7), Vector2(0.8, 0.5)])
	# An intentionally different derived river curve detects reprojection; it
	# has the same endpoints so endpoint-only tests cannot see the mismatch.
	var derived := PackedVector2Array([path[0], Vector2(0.5, 0.2), path[-1]])
	for kind in [Edge.Kind.LAND, Edge.Kind.LANDING, Edge.Kind.RIVER, Edge.Kind.SEA]:
		var state := fixture(path, kind)
		state.river_features = [MapFeatureContract.make_river(7, path, MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY)]
		var atlas := {"river_paths": {7: derived}}
		assert_consumers(state, {}, "kind=%d without atlas" % kind)
		assert_consumers(state, atlas, "kind=%d with visual river atlas" % kind)
		if kind == Edge.Kind.RIVER:
			state.edges[0].river_reaches = [{"river_id": 7, "from": 0.0, "to": 3.0}]
			assert_consumers(state, atlas, "river with explicit reach references")
		# An editor refresh changes the edge route and road revision. Both the
		# regenerated political cache and trade consumers must use the new path.
		atlas["size"] = Vector2i(64, 64)
		atlas["revision"] = {"roads": state.road_network_revision}
		atlas["road_paths"] = {0: path.duplicate()}
		atlas["road_paths_revision"] = state.road_network_revision
		state.edges[0].map_path = PackedVector2Array([path[0], Vector2(0.5, 0.8), path[-1]])
		state.road_network_revision += 1
		Atlas.refresh_road_paths(state, atlas)
		check(atlas.road_paths_revision == state.road_network_revision, "road refresh publishes current revision")
		assert_consumers(state, atlas, "kind=%d after road edit refresh" % kind)
	# Use a real terrain route around a river obstacle, then verify every
	# consumer retains every detour vertex and the corresponding route length.
	var size := Vector2i(32, 32)
	var ids := PackedInt32Array()
	ids.resize(size.x * size.y)
	ids.fill(0)
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0.6))
	var barrier := PackedVector2Array([Vector2(0.5, 0.25), Vector2(0.5, 0.75)])
	var rivers := [MapFeatureContract.make_river(0, barrier, MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY)]
	var detour := Generator.province_pair_path(ids, size, path[0], path[-1], 0, 0, Hydro.barriers(rivers, size), {"strict": true, "image": image, "aspect": 1.0, "river_paths": [barrier]})
	check(detour.size() > 2, "real routing fixture contains a legal detour around the river")
	if detour.size() >= 2:
		var state := fixture(detour, Edge.Kind.LAND)
		assert_consumers(state, {"river_paths": {0: barrier}}, "generated land detour")
		for i in range(detour.size() - 1):
			check(Geometry2D.segment_intersects_segment(detour[i], detour[i + 1], barrier[0], barrier[1]) == null, "generated and displayed road never shortcuts across main river")
		check(state.edges[0].distance == Generator.distance_units_for_metric_length(Generator.metric_polyline_length(detour, 1.0)), "stored travel distance matches displayed detour")
	var legacy := fixture(path, Edge.Kind.RIVER, LEGACY)
	legacy.river_features = [MapFeatureContract.make_river(7, path, MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY)]
	check(Atlas.visual_road_path(legacy, 0, {"river_paths": {7: derived}}) == derived, "legacy scene retains derived river rendering")
	print("CANONICAL_ROAD_VIEWS: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
