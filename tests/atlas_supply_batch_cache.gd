extends SceneTree
## Real worker queries must share stationary city results across armies/days.
class CountedState extends GameState:
	var siege_queries := 0
	var relay_queries := 0
	func city_under_siege(city_id: int) -> bool:
		siege_queries += 1
		return super.city_under_siege(city_id)
	func food_pool_relay_capitals(holder_id: int) -> Array[int]:
		relay_queries += 1
		return super.food_pool_relay_capitals(holder_id)
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func fixture() -> CountedState:
	var state := CountedState.new(); state._reset_world(83119)
	state._generate_nations(GameState.DiplomaticRelation.ALLIED,2,false)
	for id in range(6):
		var city := City.new(); city.id=id; city.name="supply-%d"%id
		city.owner_nation=0 if id<3 else 1; city.map_position=Vector2(float(id)/6.,.5)
		city.has_warehouse=id in [0,3]; city.food_storage=10000
		state.cities.append(city); state.adjacency[id]=[] as Array[int]
	for id in range(5):
		var edge := Edge.new(); edge.city_a=id; edge.city_b=id+1
		edge.distance=1; edge.max_manpower=50000
		state.edges.append(edge); state.edge_lookup[GameState.edge_key(id,id+1)]=edge
		(state.adjacency[id] as Array).append(id+1); (state.adjacency[id+1] as Array).append(id)
	for nation in state.nations:
		nation.capital_city_id=0 if nation.id==0 else 3
		nation.warehouse_city_ids=[nation.capital_city_id] as Array[int]
	for id in range(5):
		var army := Army.new(); army.id=id; army.owner_nation=0 if id<4 else 1
		army.location_city=2 if id<3 or id==4 else 1
		army.size=1000; army.max_size=15000; state.armies.append(army)
	return state
func compare(sim: Simulation, result: Dictionary, label: String):
	for army in sim.state.armies:
		var oracle := Pathfinding.supply_sources_from_network(sim.state,army,sim._daily_supply_network_cache[army.owner_nation])
		check(var_to_bytes(result.get(army.get_instance_id(),[]))==var_to_bytes(oracle),label+": exact sources/loss/order army%d"%army.id)
func query(sim: Simulation) -> Dictionary:
	var ids := sim._prepare_supply_network_caches()
	await sim._prebuild_supply_networks_over_frames(ids)
	(sim.state as CountedState).siege_queries=0
	return await sim._precompute_supply_sources_over_frames()
func run():
	var state := fixture(); var sim := Simulation.new(); root.add_child(sim); sim.state=state; sim.paused=true
	var rng_before := state.rng.state
	state.relay_queries=0; sim._prepare_supply_network_caches()
	check(state.relay_queries==2,"prepare relay origins once per warehouse owner, not per traveler")
	var cold := await query(sim)
	check(state.siege_queries==3,"cold worker queries unique owner/city pairs once")
	compare(sim,cold,"cold")
	state.day+=1; var warm := await query(sim)
	check(state.siege_queries==0,"next day stationary armies reuse persistent city sources without worker queries")
	compare(sim,warm,"warm")
	var siege := state.new_battle(Battle.Kind.SIEGE); siege.city=state.cities[1]
	var isolated := await query(sim)
	check(state.siege_queries==1,"non-warehouse siege refreshes only affected stationed city")
	check(isolated[state.armies[3].get_instance_id()].is_empty(),"besieged city loses external supply immediately")
	compare(sim,isolated,"siege")
	siege.finished=true; var released := await query(sim)
	check(state.siege_queries==1,"lifting siege refreshes only affected city")
	compare(sim,released,"released")
	state.cities[0].food_storage=0
	var empty := await query(sim); compare(sim,empty,"empty warehouse")
	for sources in empty.values():
		check((sources as Array).all(func(source): return int(source.city_id)!=0),"empty warehouse removed")
	state.cities[0].food_storage=10000; var restored := await query(sim); compare(sim,restored,"restocked")
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	var war := await query(sim); compare(sim,war,"war permissions")
	check((war[state.armies[4].get_instance_id()] as Array).is_empty(),"foreign army cannot reuse other country's city cache")
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.ALLIED)
	state.edge_of(1,2).max_manpower=0; state.road_network_revision+=1
	var blocked := await query(sim); compare(sim,blocked,"closed road")
	state.edge_of(1,2).max_manpower=50000; state.road_network_revision+=1
	var mover := state.armies[0]; mover.on_edge=true; mover.state=Army.State.MOVING
	mover.move_from=1; mover.move_to=2; mover.move_progress=.1
	var moving := await query(sim); compare(sim,moving,"moving initial")
	var first := var_to_bytes(moving[mover.get_instance_id()])
	mover.move_progress=.8
	moving=await query(sim); compare(sim,moving,"moving changed progress")
	check(var_to_bytes(moving[mover.get_instance_id()])!=first,"moving army keeps exact progress-dependent losses")
	check(state.rng.state==rng_before,"query scheduling never consumes RNG")
	sim.free()
	for failure in failures: printerr("ATLAS_SUPPLY_BATCH_FAIL ",failure)
	print("ATLAS_SUPPLY_BATCH_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
