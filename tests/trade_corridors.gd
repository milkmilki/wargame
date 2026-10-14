extends SceneTree
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr("TRADE_CORRIDOR_FAIL ",message)
func fixture() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state._reset_world(81); state._generate_nations(GameState.DiplomaticRelation.NEUTRAL,2,false)
	for id in range(4):
		var city := City.new(); city.id=id; city.owner_nation=1 if id==2 else 0
		city.gold_per_month=50 if id in [0,2] else 10; city.food_per_half_year=100
		city.map_position=Vector2(.1+id*.1,.5)
		state.cities.append(city); state.adjacency[id]=[] as Array[int]; state.region_ids.append(1 if id==2 else 0)
	for endpoints in [Vector2i(0,1),Vector2i(1,2),Vector2i(0,3),Vector2i(2,3)]:
		state._add_edge(endpoints.x,endpoints.y)
		var edge := state.edge_of(endpoints.x,endpoints.y)
		edge.road_tier=Edge.RoadTier.MAIN if endpoints.y in [1,2] else Edge.RoadTier.LOCAL
		edge.precise_distance=1.05 if edge.road_tier==Edge.RoadTier.MAIN else 1.
		edge.max_manpower=20000; edge.base_max_manpower=20000
		edge.danger=0.
	state.region_count=2; state.atlas_layout={"model":"corridor-fixture"}
	return state
func shared_fixture() -> GameState:
	var state := fixture(); state.cities.clear(); state.edges.clear(); state.edge_lookup.clear(); state.adjacency.clear(); state.region_ids.clear()
	for id in range(7):
		var city := City.new(); city.id=id; city.owner_nation=0; city.gold_per_month=50 if id<5 else 1
		city.food_per_half_year=100; state.cities.append(city); state.adjacency[id]=[] as Array[int]
		state.region_ids.append(id if id<5 else 0 if id==5 else 3)
	for ends in [Vector2i(0,5),Vector2i(1,5),Vector2i(2,5),Vector2i(3,6),Vector2i(4,6),Vector2i(5,6),Vector2i(0,3)]:
		state._add_edge(ends.x,ends.y); var edge := state.edge_of(ends.x,ends.y)
		edge.precise_distance=1.95 if ends==Vector2i(0,3) else 1. if ends==Vector2i(5,6) else .5
		edge.danger=0.; edge.max_manpower=20000; edge.base_max_manpower=20000; edge.road_tier=Edge.RoadTier.LOCAL
	state.region_count=5; return state
func run():
	var state := fixture(); var rng := state.rng.state
	var military := var_to_bytes(state.adjacency)
	var result := TradeNetwork.build(state)
	check(result.routes.size()==1 and result.routes[0].city_path==[0,1,2],"trade prefers a slightly longer main road over a local shortcut")
	check(is_equal_approx(result.routes[0].transport_cost,2.31),"revenue uses actual physical path cost, without the routing preference discount")
	var builds: int=state.atlas_trade_cache.dijkstra_builds
	check(TradeNetwork.build(state)==result and state.atlas_trade_cache.dijkstra_builds==builds,"repeat settlement reuses corridor paths without searches")
	check(var_to_bytes(state.adjacency)==military and state.rng.state==rng,"corridor routing leaves military graph and random stream unchanged")
	state.edge_of(0,1).max_manpower=0; state.road_network_revision+=1
	var rerouted := TradeNetwork.build(state)
	check(rerouted.routes[0].city_path==[0,3,2] and rerouted.routes[0].status==TradeNetwork.REROUTED,"closed main road falls back to legal local transport")
	state=fixture(); state.edge_of(0,1).precise_distance=10.; state.road_network_revision+=1
	check(TradeNetwork.build(state).routes[0].city_path==[0,3,2],"main-road preference cannot force a large detour")
	state=shared_fixture(); var shared := TradeNetwork.build(state)
	var route: Dictionary=shared.routes.filter(func(r):return r.source==0 and r.destination==3)[0]
	check(route.city_path==[0,5,6,3] and is_equal_approx(route.transport_cost,2.2),"trade joins an existing shared corridor despite a slightly shorter private shortcut")
	state=fixture(); TradeNetwork.build(state)
	state.edge_of(0,1).road_tier=Edge.RoadTier.LOCAL; state.edge_of(1,2).road_tier=Edge.RoadTier.LOCAL
	check(TradeNetwork.build(state).routes[0].city_path==[0,3,2],"road-grade changes invalidate cached routing preferences")
	var native_world := fixture(); var gd_world := fixture()
	NativeCompute.set_backend_for_tests("native"); var native_result := TradeNetwork.build(native_world)
	NativeCompute.set_backend_for_tests("gdscript"); var gd_result := TradeNetwork.build(gd_world)
	check(native_result==gd_result,"native and GDScript use identical corridor selection and physical cost accounting")
	NativeCompute.set_backend_for_tests("native")
	print("TRADE_CORRIDORS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
