extends SceneTree
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok: failures.append(message)
func fixture(region_count: int = 3) -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state._reset_world(81); state._generate_nations(GameState.DiplomaticRelation.NEUTRAL,3,false)
	for id in range(region_count*2):
		var city := City.new(); city.id=id; city.owner_nation=(id/2)%3
		city.gold_per_month=30 if id%2==0 else 10
		city.food_per_half_year=100; city.manpower_per_month=100
		city.map_position=Vector2(id*.1,.5)
		state.cities.append(city); state.adjacency[id]=[] as Array[int]
		state.region_ids.append(id/2)
		if id>0: state._add_edge(id-1,id)
	state.region_count=region_count
	state.atlas_layout={"model":"trade-schedule-fixture"}
	return state
func run():
	var state := fixture(); var rng_before := state.rng.state
	var initial := TradeNetwork.build(state)
	var path_builds := int(state.atlas_trade_cache.path_builds)
	var field_builds := int(state.atlas_trade_cache.dijkstra_builds)
	Simulation.monthly_gold_flows(state)
	check(int(state.atlas_trade_cache.path_builds)==path_builds and int(state.atlas_trade_cache.dijkstra_builds)==field_builds,"static fiscal fallback reuses same geometry")
	var centers := TradeNetwork.regional_trade_centers(state)
	var before := var_to_bytes(initial.routes)
	state.cities[1].gold_per_month=200
	state.day=30
	var unchanged := TradeNetwork.build(state)
	check(TradeNetwork.regional_trade_centers(state)==centers,"initial centers fixed for first year")
	check(unchanged.routes[0].source==initial.routes[0].source,"production change does not move endpoint")
	state.cities[0].owner_nation=1; state.ownership_revision+=1
	var transferred := TradeNetwork.build(state)
	check(transferred.routes[0].city_path==initial.routes[0].city_path,"conquest keeps physical path")
	check(transferred.routes[0].nation_a==1,"endpoint country follows actual owner")
	check(transferred.nation_trade_gold[0]==transferred.city_gold_bonus[1],"former owner receives only its remaining transit district income")
	check(int(state.atlas_trade_cache.path_builds)==path_builds and int(state.atlas_trade_cache.dijkstra_builds)==field_builds,"conquest and output changes never search again")
	check(var_to_bytes(initial.routes)==before,"returned results cannot mutate earlier publication")
	state.nations[1].trade_policy=TradeNetwork.GOLD
	var changed_policy := TradeNetwork.build(state)
	check(changed_policy.nation_trade_gold[1]>=transferred.nation_trade_gold[1],"current policy updates revenue without new endpoint")
	var peace_token := TradeNetwork.structure_fingerprint(state)
	state.set_diplomatic_relation(1,2,GameState.DiplomaticRelation.WAR)
	check(TradeNetwork.structure_fingerprint(state)==peace_token,"declaration only affects settlement, not fiscal structure")
	var wartime := TradeNetwork.build(state)
	check(wartime.nation_trade_gold[1]==int(floor(changed_policy.nation_trade_gold[1]*.5)),"war discount uses current relations on frozen routes")
	state.set_diplomatic_relation(1,2,GameState.DiplomaticRelation.NEUTRAL)
	state.edge_of(1,2).danger=.2; state.road_network_revision+=1
	TradeNetwork.build(state)
	check(TradeNetwork.regional_trade_centers(state)[0]==0,"road edits preserve annual center selection")
	state.day=360
	var refreshed := TradeNetwork.build(state)
	check(TradeNetwork.regional_trade_centers(state)[0]==1,"scheduled region changes center at first year")
	check(TradeNetwork.regional_trade_centers(state)[1]==2,"other regions retain centers until their turn")
	check(refreshed.routes[0].source==1,"reselected center has actual connecting path")
	state.cities[0].gold_per_month=500; state.day=719
	TradeNetwork.build(state)
	check(TradeNetwork.regional_trade_centers(state)[0]==1,"center remains fixed until next annual turn")
	state.day=720; TradeNetwork.build(state)
	check(TradeNetwork.regional_trade_centers(state)[0]==0,"next annual turn updates same region")
	check(state.rng.state==rng_before,"trade schedule consumes no simulation RNG")
	state.edge_of(1,2).max_manpower=0; state.road_network_revision+=1
	var closed := TradeNetwork.build(state)
	check(int(state.atlas_trade_cache.path_builds)>0,"road edit immediately rebuilds geometry")
	check(closed.routes.any(func(r): return r.status==TradeNetwork.RouteStatus.BLOCKED),"closed bridge blocks actual route without waiting one year")
	var cache_routes: int = state.atlas_trade_cache.paths.size()
	check(cache_routes<=3 and state.atlas_trade_cache.fields.size()<=6,"old centers and fields are removed from cache")
	state=fixture(25); TradeNetwork.build(state)
	for id in range(1,50,2): state.cities[id].gold_per_month=200
	for month in range(12,24):
		state.day=month*30; TradeNetwork.build(state)
		var refreshed_count := 0
		for region in range(25):
			var expected := region*2+1 if region%12<=month%12 else region*2
			check(state.atlas_trade_centers[region]==expected,"stable yearly partition region %d month %d"%[region,month])
			if region%12==month%12: refreshed_count+=1
		check(refreshed_count in [2,3],"25 regions refresh 2-3 per month")
		check(state.atlas_trade_cache.paths.size()<=300 and state.atlas_trade_cache.fields.size()<=50,"bounded route and field cache after rotation")
	var thread := Thread.new(); thread.start(func(): return TradeNetwork.build(state))
	var concurrent := TradeNetwork.build(state)
	check(thread.wait_to_finish()==concurrent,"worker and foreground builders share cache safely")
	concurrent.routes[0].city_path.append(-999)
	check(not TradeNetwork.build(state).routes[0].city_path.has(-999),"caller mutations do not poison shared cache")
	state=fixture()
	for city in state.cities: city.owner_nation=-1
	check(TradeNetwork.build(state).routes.is_empty(),"no eligible center produces empty trade")
	for failure in failures: printerr("ATLAS_TRADE_SCHEDULE_FAIL ",failure)
	print("ATLAS_TRADE_SCHEDULE failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
