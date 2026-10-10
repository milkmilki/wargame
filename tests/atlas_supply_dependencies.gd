extends SceneTree
## Ignore changes to unusable enemy roads; retain actual blockades and edits.
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func fixture() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new(); state._reset_world(83341)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 3, false)
	var centers := PackedInt32Array(); var members := []
	for id in range(8):
		var city := City.new(); city.id = id; city.name = "supply-%d" % id
		city.owner_nation = 0 if id < 3 else (1 if id < 6 else 2)
		city.map_position = Vector2(float(id)/8., .5)
		city.food_storage = 10000; city.manpower_per_month = 1000
		city.has_warehouse = id in [0,3,6]
		state.cities.append(city); state.adjacency[id] = [] as Array[int]
		centers.append(id); members.append([id])
	for nation in state.nations:
		nation.capital_city_id = [0,3,6][nation.id]
		nation.warehouse_city_ids = [nation.capital_city_id] as Array[int]
	for pair in [Vector2i(0,1),Vector2i(1,2),Vector2i(3,4),Vector2i(4,5),Vector2i(6,7)]:
		state._add_edge(pair.x,pair.y)
		state.edge_of(pair.x,pair.y).control_city_id = pair.x
	state.atlas_layout = {"model":"supply-dependency-test", "territorial_pairs":[] as Array[Vector2i], "hierarchy":{
		"center_by_city":centers,"state_by_city":centers.duplicate(),
		"state_parents":centers.duplicate(),"members":members}}
	state.atlas_layout.settlement_adjacency = state.adjacency.duplicate(true)
	state.rebuild_administrative_regions(); state._initialize_recognized_city_owners()
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	for owner in [0,1]:
		var army := Army.new(); army.id = owner; army.owner_nation = owner
		army.location_city = 2 if owner == 0 else 3; army.move_from = army.location_city
		army.size = 1000; army.max_size = 15000; state.armies.append(army)
	place(state,state.armies[1],3,4)
	return state
func place(state: GameState, army: Army, a: int, b: int):
	if army.on_edge:
		var old := state.edge_of(army.move_from,army.move_to)
		old.passing_count -= 1; old.occupied = old.passing_count > 0
	army.move_from = a; army.move_to = b; army.location_city = a
	army.move_progress = .25; army.on_edge = true; army.state = Army.State.MOVING
	var edge := state.edge_of(a,b); edge.passing_count += 1; edge.occupied = true
func query(sim: Simulation, label: String):
	var state := sim.state
	var actual := sim._cached_supply_sources(state.armies[0],sim._daily_supply_source_cache,
		sim._daily_supply_network_cache,sim._stable_supply_city_source_cache)
	var expected := Pathfinding.build_supply_network(state,0)
	check(var_to_bytes(sim._daily_supply_network_cache[0]) == var_to_bytes(expected),label+": full distance arrays equal unfiltered network")
	check(var_to_bytes(actual) == var_to_bytes(Pathfinding.supply_sources_from_network(state,state.armies[0],expected)),label+": warehouse choices and losses equal")
func run():
	var state := fixture(); var sim := Simulation.new(); sim.state = state
	sim._prepare_supply_network_caches(); query(sim,"initial")
	check(not sim._daily_supply_network_cache[0].is_empty(),"fixture has usable warehouse")
	var rng_before := state.rng.state
	place(state,state.armies[1],4,5); state.day += 1
	sim._prepare_supply_network_caches()
	check(sim._daily_supply_network_cache.has(0),"inaccessible enemy movement preserves logistics cache")
	query(sim,"irrelevant move")
	check(sim._prepared_supply_blocked_edges[0].has(GameState.edge_key(4,5)),"build receives complete actual blocker set")
	place(state,state.armies[1],1,2); state.day += 1
	sim._prepare_supply_network_caches()
	check(not sim._daily_supply_network_cache.has(0),"entering usable corridor invalidates immediately")
	query(sim,"blockade")
	check((sim._daily_supply_network_cache[0][0].dist as PackedFloat64Array)[2] == INF,"blockade cuts supply route")
	place(state,state.armies[1],3,4); state.day += 1
	sim._prepare_supply_network_caches()
	check(not sim._daily_supply_network_cache.has(0),"leaving usable corridor invalidates immediately")
	query(sim,"blockade removed")
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.ALLIED)
	sim._prepare_supply_network_caches()
	check(not sim._daily_supply_network_cache.has(0),"diplomacy changes invalidate access")
	query(sim,"alliance"); sim.free()
	state = fixture(); sim = Simulation.new(); sim.state = state
	var enemy := state.armies[1]; var old_edge := state.edge_of(3,4)
	old_edge.passing_count = 0; old_edge.occupied = false; state.armies.erase(enemy)
	state.edge_of(1,2).max_manpower = 0
	sim._prepare_supply_network_caches(); query(sim,"closed road")
	check((sim._daily_supply_network_cache[0][0].dist as PackedFloat64Array)[2] == INF,"closed route unreachable")
	var edited: Dictionary = state.apply_edge_editor_changes(1,2,{"max_manpower":50000})
	check(bool(edited.get("ok",false)),"real road edit succeeds without traffic bindings")
	sim._prepare_supply_network_caches()
	check(not sim._daily_supply_network_cache.has(0),"road revision invalidates supply field")
	query(sim,"reopened road")
	check(is_finite((sim._daily_supply_network_cache[0][0].dist as PackedFloat64Array)[2]),"road reopening restores route")
	check(state.rng.state == rng_before,"dependency queries do not consume RNG")
	sim.free()
	for legacy in [true,false]:
		state = fixture(); sim = Simulation.new(); sim.state = state
		if legacy: state.atlas_layout.clear()
		else: state.succession_conflicts[0] = SuccessionConflict.new()
		sim._prepare_supply_network_caches(); query(sim,"conservative initial")
		place(state,state.armies[1],4,5); sim._prepare_supply_network_caches()
		check(not sim._daily_supply_network_cache.has(0),"legacy/succession retain full blocker dependencies")
		query(sim,"conservative move"); sim.free()
	for failure in failures: printerr("ATLAS_SUPPLY_DEPENDENCY_FAIL ",failure)
	print("ATLAS_SUPPLY_DEPENDENCY_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
