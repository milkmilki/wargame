extends SceneTree
const View=preload("res://scripts/atlas/trade_view.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr("CORRIDOR_WORLD_FAIL ",message)
func run():
	var state := GameState.new(); state.generate_from_atlas(preload("res://tests/atlas_military_inputs.gd").eurasia_military())
	check(state.world_seed==1 and state.nations.size()==40 and state.atlas_layout.data.options.settlement_mask.enabled,"actual seed-1/40/Eurasia")
	var military := var_to_bytes(state.adjacency); var regions := state.region_ids.duplicate(); var rng := state.rng.state
	var network := TradeNetwork.build(state)
	var graph: Dictionary=state.atlas_trade_cache.graph
	var baseline := graph.duplicate(); baseline.selection_weights={}
	var fields := {}; var allowed := TradeNetwork._ideal_city_mask(state)
	var native_batch := NativeCompute.begin_trade_batch(state,baseline)
	var changed := 0; var max_detour := 1.; var before_edges := {}; var after_edges := {}
	var main_before := 0.; var land_before := 0.; var main_after := 0.; var land_after := 0.
	for route in network.routes:
		var source: int=route.source
		if not fields.has(source): fields[source]=TradeNetwork._dijkstra_field(state,baseline,[source] as Array[int],allowed,true,{},{})
		var selection := TradeNetwork._select_preferred_endpoints_from_field(state,[source] as Array[int],[int(route.destination)] as Array[int],fields[source])
		if selection.path!=route.city_path: changed+=1
		max_detour=maxf(max_detour,float(route.transport_cost)/float(selection.cost))
		check(float(route.transport_cost)<=float(selection.cost)*1.24+.005,"preference retains bounded real transport detour")
		check(is_equal_approx(float(route.transport_cost),TradeNetwork._physical_path_cost(graph,route.city_path,true)),"published cost is exact actual transport cost")
		for variant in [selection.path,route.city_path]:
			for index in range(1,variant.size()):
				var key := GameState.edge_key(int(variant[index-1]),int(variant[index])); var edge: Edge=graph.edge_lookup[key]
				if is_same(variant,selection.path):
					before_edges[key]=true
					if edge.kind==Edge.Kind.LAND:
						land_before+=edge.distance_units()
						if edge.road_tier==Edge.RoadTier.MAIN: main_before+=edge.distance_units()
				else:
					after_edges[key]=true
					if edge.kind==Edge.Kind.LAND:
						land_after+=edge.distance_units()
						if edge.road_tier==Edge.RoadTier.MAIN: main_after+=edge.distance_units()
	if native_batch: NativeCompute.end_trade_batch(state)
	check(changed>0 and network.routes.size()==300,"real routes concentrate without deleting any market pair")
	check(main_after/land_after>=main_before/land_before,"land commerce uses main roads more often")
	check(state.rng.state==rng and state.region_ids==regions and var_to_bytes(state.adjacency)==military,"routing leaves partitions, army adjacency and randomness unchanged")
	print("CORRIDOR_WORLD checks=",checks," failures=",failures," changed_routes=",changed," max_detour=",max_detour," edges_before=",before_edges.size()," edges_after=",after_edges.size()," main_before=",main_before/land_before," main_after=",main_after/land_after)
	quit(1 if failures else 0)
