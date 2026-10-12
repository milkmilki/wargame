extends SceneTree
class CountingState extends "res://tests/support/grid_world.gd":
	var edge_queries := 0
	func strategic_edge_of(a: int,b: int) -> Edge:
		edge_queries += 1
		return super.strategic_edge_of(a,b)

var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	if not ok: failures += 1; printerr("STRATEGIC_EDGE_QUERIES_FAIL ",label)
func run():
	var state := CountingState.new(); state.generate_world(17941,4,32)
	var view := AiWorldView.build(state,0)
	var pairs := {}
	for city in view.friendly_cities:
		for neighbor in state.strategic_neighbors(city.id):
			if state.edge_of(city.id,neighbor) != null: pairs[GameState.edge_key(city.id,neighbor)] = true
	var snapshot := StrategicMapSnapshot.new()
	snapshot._state = state; snapshot._view = view; snapshot.nation_id = 0
	snapshot.city_value = StrategicMapSnapshot.build_base_city_values(state)
	var base := StrategicMapSnapshot.build_base_edge_values(state); var base_bytes := var_to_bytes(base)
	state.edge_queries = 0; snapshot._finalize_edge_values(base)
	check(state.edge_queries == pairs.size(),"each legacy road is evaluated once per snapshot")
	check(base_bytes == var_to_bytes(base),"national scoring leaves shared base values unchanged")
	check_virtual_road()
	print("STRATEGIC_EDGE_QUERIES failures=",failures); quit(1 if failures else 0)
func check_virtual_road():
	var state := CountingState.new(); var nation := Nation.new(); nation.id = 0; nation.capital_city_id = 0
	state.nations.append(nation)
	for id in range(4):
		var city := City.new(); city.id = id; city.owner_nation = 0 if id < 2 else -1
		city.map_position = Vector2(.2+id*.1,.5)
		if id >= 2: city.node_kind = City.NodeKind.TRAFFIC
		state.cities.append(city)
	for pair in [Vector2i(0,2),Vector2i(2,3),Vector2i(3,1)]:
		var edge := Edge.new(); edge.city_a = pair.x; edge.city_b = pair.y; edge.danger = .7
		state.edges.append(edge); state.edge_lookup[GameState.edge_key(pair.x,pair.y)] = edge
	state.atlas_layout = {
		"settlement_adjacency":{0:[1] as Array[int],1:[0] as Array[int]},
		"strategic_routes":{"0:1":[0,2,3,1]},
	}
	var view := AiWorldView.new(); view.state = state; view.nation_id = 0
	view.friendly_cities.assign([state.cities[0],state.cities[1]])
	var snapshot := StrategicMapSnapshot.new()
	snapshot._state = state; snapshot._view = view; snapshot.nation_id = 0
	snapshot.city_value = {0:2.,1:4.}
	var base := StrategicMapSnapshot.build_base_edge_values(state)
	var state_bytes := var_to_bytes(NativeSnapshotBuilder.build(state)); var rng_state := state.rng.state
	snapshot._finalize_edge_values(base)
	check(state.edge_queries == 1,"one virtual road is reconstructed once despite its two friendly endpoints")
	check(is_equal_approx(snapshot.edge_value[GameState.edge_key(0,1)],.15*2.+.15*4.),"both endpoint bonuses remain in the virtual road score")
	check(state_bytes == var_to_bytes(NativeSnapshotBuilder.build(state)) and rng_state == state.rng.state,"road scoring preserves the gameplay state and RNG")
