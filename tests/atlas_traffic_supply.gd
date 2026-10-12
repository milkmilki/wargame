extends SceneTree
## Ownerless Atlas junctions must use the jurisdiction-aware warehouse field.
var failures: Array[String] = []
var checks := 0

func _initialize(): call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture() -> GameState:
	var state := GameState.new()
	state._reset_world(94012)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 3, false)
	for id in range(5):
		var city := City.new()
		city.id = id
		city.map_position = Vector2(float(id)/5., .5)
		city.owner_nation = id if id < 3 else -1
		city.node_kind = City.NodeKind.SETTLEMENT if id < 3 else City.NodeKind.TRAFFIC
		city.politically_active = id < 3
		city.food_storage = 1000 if id == 0 else 0
		city.has_warehouse = id == 0
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
	for nation in state.nations:
		nation.capital_city_id = nation.id
		nation.warehouse_city_ids = [nation.id] as Array[int]
	for pair in [Vector2i(0,3), Vector2i(3,4), Vector2i(4,1)]:
		var edge := Edge.new()
		edge.city_a = mini(pair.x,pair.y)
		edge.city_b = maxi(pair.x,pair.y)
		edge.control_city_id = 0 if pair.y != 1 else 1
		state.edges.append(edge)
		state.edge_lookup[GameState.edge_key(pair.x,pair.y)] = edge
		(state.adjacency[pair.x] as Array[int]).append(pair.y)
		(state.adjacency[pair.y] as Array[int]).append(pair.x)
	state.atlas_layout = {"model":"traffic-supply-test","territorial_pairs":[] as Array[Vector2i]}
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	return state

func moving(a: int, b: int) -> Army:
	var army := Army.new()
	army.id = 9000
	army.owner_nation = 0
	army.location_city = a
	army.move_from = a
	army.move_to = b
	army.move_progress = .87
	army.on_edge = true
	army.state = Army.State.MOVING
	army.size = 15000
	army.max_size = 15000
	return army

func query(state: GameState, army: Army) -> Array[Dictionary]:
	return Pathfinding.supply_sources_from_network(state, army, Pathfinding.build_supply_network(state,army.owner_nation))

func run() -> void:
	var state := fixture()
	var army := moving(3,4)
	var network := Pathfinding.build_supply_network(state,0)
	check(not network.is_empty() and is_finite(network[0].dist[3]) and is_finite(network[0].dist[4]),"real warehouse field reaches both ownerless junctions")
	var rng_before := state.rng.state
	var sources := query(state,army)
	check(sources.size()==1 and sources[0].city_id==0,"moving between ownerless friendly junctions receives food")
	var direct := Pathfinding.supply_sources(state,army)
	check(direct.size()==1 and direct[0].city_id==0,"uncached query also recognizes friendly traffic endpoint")
	if not sources.is_empty():
		var edge_loss := Pathfinding._supply_edge_loss(state.edge_of(3,4))
		check(is_equal_approx(sources[0].loss,network[0].dist[3]+.87*edge_loss),"moving loss includes actual position on current segment")
	army = moving(4,1)
	sources = query(state,army)
	check(sources.size()==1,"final attack leg can draw from reachable rear junction, as from a friendly settlement")
	var siege := state.new_battle(Battle.Kind.SIEGE)
	siege.city = state.cities[1]
	siege.side_a.append(army)
	army.on_edge=false
	army.move_progress=1.0
	army.state=Army.State.FIGHTING
	army.battle_id=siege.id
	check(query(state,army).size()==1,"arrived besieger retains the same accessible rear supply anchor")
	check(state.cities[3].owner_nation==-1 and state.cities[4].owner_nation==-1 and state.rng.state==rng_before,"queries never invent junction owners or consume random stream")
	siege.finished=true
	army=moving(3,4)
	for owner in [1,2]:
		state.cities[0].owner_nation=owner
		state.nations[owner].warehouse_city_ids.clear()
		check(query(state,army).is_empty(),"enemy or neutral warehouse is not usable")
		state.cities[0].owner_nation=0
		state.nations[0].warehouse_city_ids=[0] as Array[int]
		state.edge_of(0,3).control_city_id=owner
		check(query(state,army).is_empty(),"enemy or neutral rear road cannot connect warehouse to junction")
		check(Pathfinding.supply_sources(state,army).is_empty(),"uncached search also rejects hostile or neutral rear jurisdiction")
		state.edge_of(0,3).control_city_id=0
	state.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.ALLIED)
	state.edge_of(0,3).control_city_id=2
	check(query(state,army).size()==1,"allied road grants the existing logistics permission")
	state.edge_of(0,3).control_city_id=0
	var blocker := moving(0,3)
	blocker.owner_nation=1
	state.armies.append(blocker)
	check(query(state,army).is_empty(),"enemy presence on rear road still blocks warehouse field")
	state.armies.clear()
	state.cities[0].food_storage=0
	check(query(state,army).is_empty(),"empty warehouse cannot produce food")
	# Exercise the actual inventory withdrawal, not just source selection.
	state=fixture()
	state.cities[0].food_per_half_year=1000
	army=moving(3,4)
	var sim := Simulation.new()
	sim.state=state
	sim._withdraw_supply_for_plan({"army":army,"sources":query(state,army),"demand":3})
	check(not army.starving and army.supply_ratio==1.0 and state.cities[0].food_storage==997,"legal marching supply consumes real warehouse stock exactly once")
	state.edge_of(0,3).control_city_id=2
	sim._withdraw_supply_for_plan({"army":army,"sources":query(state,army),"demand":3})
	check(army.starving and army.supply_ratio==0.0 and state.cities[0].food_storage==997,"cut rear route causes real shortage without draining inaccessible warehouse")
	sim.free()
	for failure in failures: printerr("ATLAS_TRAFFIC_SUPPLY_FAIL ",failure)
	print("ATLAS_TRAFFIC_SUPPLY_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
