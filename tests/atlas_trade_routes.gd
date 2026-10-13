extends SceneTree
const TradeView = preload("res://scripts/atlas/trade_view.gd")
class View extends "res://scripts/atlas/military_preview.gd":
	func _ready() -> void:
		add_child(map_root)
		add_child(render_scheduler)
		make_ui()
		set_process(false)
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func fixture() -> GameState:
	var state := GameState.new()
	state.trade_enabled = true
	state.rng.seed = 94110
	for point in [Vector2(.12, .47), Vector2(.3, .5), Vector2(.54, .43), Vector2(.55, .68), Vector2(.99, .35), Vector2(.01, .36)]:
		var city := City.new()
		city.id = state.cities.size()
		city.map_position = point
		state.cities.append(city)
	state.cities[1].node_kind = City.NodeKind.TRAFFIC
	for endpoints in [Vector2i(0, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(4, 5)]:
		var edge := Edge.new()
		edge.city_a = endpoints.x
		edge.city_b = endpoints.y
		state.edges.append(edge)
		state.edge_lookup[GameState.edge_key(endpoints.x, endpoints.y)] = edge
	state.edges[0].map_path = PackedVector2Array([state.cities[0].map_position, Vector2(.2, .44), state.cities[1].map_position])
	state.trade_routes = [
		{"city_path": [0, 1, 2], "status": TradeNetwork.RouteStatus.ACTIVE},
		{"city_path": [2, 1, 0], "status": TradeNetwork.RouteStatus.REROUTED},
		{"city_path": [1, 3], "status": TradeNetwork.RouteStatus.BLOCKED},
		{"city_path": [4, 5], "status": TradeNetwork.RouteStatus.ACTIVE},
	]
	return state


func run() -> void:
	var module = load("res://scripts/atlas/trade_view.gd")
	if not module.get_script_method_list().any(func(method): return method.name == "route_segments"):
		check(false, "trade view must derive drawable corridors from published trade routes")
		finish()
		return
	var state := fixture()
	var before := var_to_bytes(state.trade_routes)
	var roads := var_to_bytes(state.edges[0].map_path)
	var rng_before := state.rng.state
	var segments: Array = module.route_segments(state)
	check(segments.size() == 4, "shared and reversed routes draw each physical corridor once")
	var by_edge := {}
	for segment in segments:
		by_edge[segment.edge_key] = segment
		check(segment.path.size() >= 2, "drawable corridor has a nonempty polyline")
	var trunk: Dictionary = by_edge[GameState.edge_key(0, 1)]
	check(trunk.route_count == 2 and trunk.active_count == 2, "shared corridor retains both route contributions")
	check(trunk.path.size() == 3 and trunk.path[1].is_equal_approx(Vector2(.2, .44) * Vector2(2048, 1024)), "trade ink follows the real road bend through a traffic junction")
	var blocked: Dictionary = by_edge[GameState.edge_key(1, 3)]
	check(blocked.active_count == 0 and blocked.route_count == 1, "blocked trade remains distinguishable from working corridors")
	var wrapped: PackedVector2Array = by_edge[GameState.edge_key(4, 5)].path
	check(absf(wrapped[-1].x - wrapped[0].x) < 50, "dateline corridor takes the short wrapped path")
	check(var_to_bytes(state.trade_routes) == before and var_to_bytes(state.edges[0].map_path) == roads and state.rng.state == rng_before, "presentation leaves route publications, roads and simulation randomness untouched")
	state.trade_routes.append({"city_path": [0, 99, 3], "status": TradeNetwork.RouteStatus.ACTIVE})
	state.trade_routes.append({"city_path": [2, 3], "status": TradeNetwork.RouteStatus.ACTIVE})
	check(module.route_segments(state) == segments, "invalid nodes and absent roads never create fabricated trade links")
	state.trade_routes.append({"city_path": [0, 1, 0], "status": TradeNetwork.RouteStatus.ACTIVE})
	var loop: Array = module.route_segments(state)
	check(loop[0].route_count == 3, "one route traversing an edge twice is counted once")
	state.trade_enabled = false
	check(module.route_segments(state).is_empty(), "disabled trade has no leftover route overlay")
	state.trade_enabled = true
	state.trade_routes.clear()
	check(module.route_segments(state).is_empty(), "an empty publication draws no invented hub connections")
	var route_class = module.get_script_constant_map().get("Routes")
	if route_class == null:
		check(false, "trade corridors need a drawable route layer")
		finish()
		return
	var layer = route_class.new()
	root.add_child(layer)
	layer.set_segments(segments)
	layer.set_view(1., Rect2(0, 0, 2048, 1024))
	await process_frame
	check(not layer.stroke_layers.is_empty(), "route layer creates visible stylized strokes")
	var builds: Array = layer.stroke_layers.map(func(stroke): return stroke.build_count)
	var meshes: Array = layer.stroke_layers.map(func(stroke): return stroke.chunks.map(func(chunk): return chunk.mesh))
	var count: int = layer.build_count
	layer.set_segments(segments.duplicate(true))
	layer.set_view(4., Rect2(400, 300, 600, 300))
	for frame in range(3):
		await process_frame
	check(layer.build_count == count, "identical publications and paused frames retain route geometry")
	check(layer.stroke_layers.map(func(stroke): return stroke.build_count) == builds, "zoom and pan update stroke uniforms without rebuilding geometry")
	check(layer.stroke_layers.map(func(stroke): return stroke.chunks.map(func(chunk): return chunk.mesh)) == meshes, "camera changes reuse the existing GPU meshes")
	layer.set_segments([])
	check(layer.markers.is_empty() and layer.stroke_layers.all(func(stroke): return stroke.chunks.is_empty()), "empty network clears all old ink and direction marks")
	layer.free()
	await check_preview()
	finish()


func check_preview() -> void:
	var view := View.new()
	root.add_child(view)
	view.state = fixture()
	view.mode_control.select(4)
	view.refresh_trade_routes()
	check(is_instance_valid(view.trade_routes_layer) and view.trade_routes_layer.get_parent() == view.map_root, "trade mode attaches the corridor layer to the real map")
	for frame in range(120):
		if view.trade_routes_layer.stroke_layers.all(func(stroke): return not stroke.preparing):
			break
		await process_frame
	check(view.trade_routes_layer.stroke_layers.all(func(stroke): return not stroke.preparing), "scheduled route meshes finish publishing")
	var count: int = view.trade_routes_layer.build_count
	for frame in range(5):
		view.refresh_trade_routes()
	check(view.trade_routes_layer.build_count == count and view.state.atlas_trade_cache.is_empty(), "paused trade view neither rebuilds nor runs trade searches")
	view.state.trade_routes[0].city_path = [0, 1]
	view.state.trade_revision += 1
	view.refresh_trade_routes()
	check(view.trade_routes_layer.build_count == count + 1, "a new trade publication refreshes the route overlay")
	view.mode_control.select(0)
	view.update_mode()
	check(not view.trade_routes_layer.visible, "political mode hides trade routes")
	view.historical_view = true
	view.mode_control.select(4)
	view.update_mode()
	view.refresh_trade_routes()
	check(not view.trade_routes_layer.visible, "historical snapshots do not borrow current trade routes")
	view.historical_view = false
	view.update_mode()
	check(view.trade_routes_layer.visible, "returning to the live trade view restores routes")
	view.queue_free()
	await process_frame


func finish() -> void:
	for message in failures:
		printerr("ATLAS_TRADE_ROUTES_FAIL ", message)
	print("ATLAS_TRADE_ROUTES checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
