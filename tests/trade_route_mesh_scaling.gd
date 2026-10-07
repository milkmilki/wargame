extends SceneTree
## Shared trade corridors must not allocate the same ribbon for every route.

func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(12345)
	var edge: Edge = state.edges[0]
	var route := {"city_path": [edge.city_a, edge.city_b], "status": TradeNetwork.ACTIVE, "food": 0}
	state.trade_routes = [route]
	var view := StrategicMap3D.new()
	view.state = state
	var unique: Array = view._trade_route_mesh_segments()
	assert(unique.size() == 1)
	for index in range(1000):
		state.trade_routes.append(route.duplicate(true))
	state.trade_routes.append({"city_path": [edge.city_b, edge.city_a], "status": TradeNetwork.ACTIVE, "food": 0})
	assert(view._trade_route_mesh_segments().size() == 1)
	state.trade_routes.append({"city_path": [edge.city_a, edge.city_b], "status": TradeNetwork.ACTIVE, "food": 1})
	state.trade_routes.append({"city_path": [edge.city_a, edge.city_b], "status": TradeNetwork.BLOCKED})
	state.trade_routes.append({"city_path": [-1, 999999], "status": TradeNetwork.ACTIVE})
	var styles: Array = view._trade_route_mesh_segments()
	assert(styles.size() == 3)
	var colors := {}
	for segment in styles:
		assert(segment.edge_index == 0)
		colors[segment.color] = true
	assert(colors.size() == 3)
	view.free()
	print("TRADE_ROUTE_MESH_SCALING_OK routes=1005 segments=3")
	quit()
