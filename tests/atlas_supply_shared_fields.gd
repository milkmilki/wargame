extends SceneTree
class CountedState extends GameState:
	var access_queries := 0
	func has_logistics_access(a: int, b: int) -> bool:
		access_queries+=1; return super.has_logistics_access(a,b)
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok: failures.append(message)
func fixture() -> CountedState:
	var state := CountedState.new(); state._reset_world(81577)
	state._generate_nations(GameState.DiplomaticRelation.ALLIED,2,false)
	state.atlas_layout={"model":"shared-supply-test","territorial_pairs":[] as Array[Vector2i]}
	for id in range(8):
		var city := City.new(); city.id=id; city.owner_nation=0 if id<4 else 1
		city.map_position=Vector2(float(id)/8.,.5); city.has_warehouse=id in [0,4]; city.food_storage=10000
		state.cities.append(city); state.adjacency[id]=[] as Array[int]
	for id in range(7):
		var edge := Edge.new(); edge.city_a=id; edge.city_b=id+1; edge.control_city_id=id
		edge.distance=1; edge.max_manpower=50000; state.edges.append(edge)
		state.edge_lookup[GameState.edge_key(id,id+1)]=edge
		(state.adjacency[id] as Array).append(id+1); (state.adjacency[id+1] as Array).append(id)
	for nation in state.nations:
		nation.capital_city_id=0 if nation.id==0 else 4; nation.warehouse_city_ids=[nation.capital_city_id] as Array[int]
		var army := Army.new(); army.id=nation.id; army.owner_nation=nation.id; army.location_city=2 if nation.id==0 else 6
		army.size=1000; army.max_size=15000; state.armies.append(army)
	return state
func run():
	var state := fixture(); var sim := Simulation.new(); root.add_child(sim); sim.paused=true; sim.state=state
	sim._prepare_supply_network_caches()
	var caches: Variant = sim.get("_supply_shared_field_caches_by_nation")
	check(caches is Dictionary,"prepare shared distance fields for equivalent allied logistics graphs")
	if caches is Dictionary:
		var expected := {}
		for owner in [0,1]: expected[owner]=Pathfinding.build_supply_network(state,owner)
		for owner in [0,1]:
			state.access_queries=0
			sim._cached_supply_sources(state.armies[owner],sim._daily_supply_source_cache,sim._daily_supply_network_cache,sim._stable_supply_city_source_cache,caches.get(owner))
			if owner==1: check(state.access_queries<=2,"second equivalent country reuses fields without graph traversal")
			check(var_to_bytes(sim._daily_supply_network_cache[owner])==var_to_bytes(expected[owner]),"shared fields preserve every source distance")
		check((caches[0] as Dictionary).size()==2 and (caches[1] as Dictionary).size()==2,"one field per physical warehouse in shared group")
		state.succession_conflicts[0]=SuccessionConflict.new()
		sim._prepare_supply_network_caches()
		check(sim.get("_supply_shared_field_caches_by_nation").size()==2,"active succession context still permits physically equivalent field sharing")
		state.succession_conflicts.clear()
		state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
		sim._prepare_supply_network_caches(); await sim._prebuild_supply_networks_over_frames([0,1] as Array[int])
		for owner in [0,1]:
			check(var_to_bytes(sim._daily_supply_network_cache[owner])==var_to_bytes(Pathfinding.build_supply_network(state,owner)),"war splits groups and recomputes permissions")
		check((sim.get("_supply_shared_field_caches_by_nation")[0] as Dictionary).size()==1,"hostile countries do not share inaccessible warehouses")
	sim.free()
	for failure in failures: printerr("ATLAS_SUPPLY_SHARED_FAIL ",failure)
	print("ATLAS_SUPPLY_SHARED_RESULT failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
