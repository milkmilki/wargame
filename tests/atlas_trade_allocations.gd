extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks+=1
	if not ok: failures.append(message)
func fixture() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state._reset_world(812); state._generate_nations(GameState.DiplomaticRelation.NEUTRAL,3,false)
	for id in range(6):
		var city := City.new(); city.id=id; city.owner_nation=id/2; city.gold_per_month=30 if id%2==0 else 10
		city.food_per_half_year=100; city.map_position=Vector2(float(id)/6.,.5)
		state.cities.append(city); state.adjacency[id]=[] as Array[int]; state.region_ids.append(id/2)
		if id>0: state._add_edge(id-1,id)
	state.region_count=3; state.atlas_layout={"model":"allocation-test"}
	return state
func validate(state: GameState,label: String) -> Dictionary:
	var structure := TradeNetwork.build_structure(state)
	for route in structure.routes:
		check(route.city_gold_bonus==TradeNetwork._allocate_route_tax(state,route,route.tax_city_ids,int(route.gold_tax)),label+": exact stateless largest-remainder allocation")
		check(not route.has("tax_allocation") and not route.has("tax_allocation_token"),label+": memo metadata never leaks into public routes")
	return structure
func run():
	var state := fixture(); var rng_before := state.rng.state
	validate(state,"initial")
	var builds := int(state.atlas_trade_cache.get("allocation_builds",0))
	check(builds==3,"initial routes each allocate once")
	state.cities[1].owner_nation=1; state.ownership_revision+=1
	var conquered := validate(state,"transit conquest")
	check(int(state.atlas_trade_cache.get("allocation_builds",0))==builds,"transit conquest reuses physical city allocations")
	check(conquered.nation_trade_gold[1]>0,"new controller receives current transit income")
	state.cities[0].war_disruption_until_day=100
	validate(state,"disruption")
	check(int(state.atlas_trade_cache.get("allocation_builds",0))==builds,"output disruption does not rerun unchanged tax rounding")
	state.cities[1].is_crossroads=true
	validate(state,"hub weight")
	check(int(state.atlas_trade_cache.get("allocation_builds",0))>builds,"hub weights invalidate affected allocations")
	builds=int(state.atlas_trade_cache.get("allocation_builds",0))
	state.nations[0].trade_policy=TradeNetwork.ISOLATION
	validate(state,"policy")
	check(int(state.atlas_trade_cache.get("allocation_builds",0))>builds,"changed tax totals invalidate allocation")
	state.cities[0].gold_per_month=1000; validate(state,"endpoint output")
	var returned := validate(state,"owned return")
	returned.routes[0].city_gold_bonus[0]=999999
	validate(state,"mutation cannot poison memo")
	state.road_network_revision+=1; validate(state,"road edit")
	state.cities[3].gold_per_month=2000; state.day=390
	validate(state,"annual center rotation")
	check(int(state.atlas_trade_centers[1])==3,"annual rotation genuinely replaces a center")
	var route := TradeNetwork.build_structure(state).routes[0] as Dictionary
	for amount in [17,4294967313]:
		check(TradeNetwork._atlas_route_tax_allocation(state,route,route.tax_city_ids,amount)==TradeNetwork._allocate_route_tax(state,route,route.tax_city_ids,amount),"64-bit totals have distinct exact cache inputs")
	var bounded := true
	for pair in state.atlas_trade_cache.tax_allocations:
		bounded=bounded and state.atlas_trade_cache.paths.has(pair)
	check(bounded and state.atlas_trade_cache.tax_allocations.size()<=state.atlas_trade_cache.paths.size(),"one latest allocation per active physical path")
	check(state.rng.state==rng_before,"rounding cache never consumes RNG")
	for failure in failures: printerr("ATLAS_TRADE_ALLOCATION_FAIL ",failure)
	print("ATLAS_TRADE_ALLOCATION_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
