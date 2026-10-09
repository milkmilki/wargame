extends SceneTree
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("ATLAS_JUNCTION_FAIL ",message)
func _initialize() -> void:
	var state := GameState.new(); state._reset_world(7); state._generate_nations(GameState.DiplomaticRelation.NEUTRAL,3,false)
	for id in range(4):
		var city := City.new(); city.id = id; city.name = "节点%d"%id; city.short_name = String.chr(0x4e00+id); city.map_position = Vector2(id*.1,.5)
		city.owner_nation = id if id<3 else -1
		if id==3: city.node_kind = City.NodeKind.TRAFFIC; city.politically_active = false
		state.cities.append(city); state.adjacency[id] = [] as Array[int]
	for id in range(3):
		var edge := Edge.new(); edge.city_a = id; edge.city_b = 3; edge.precise_distance = .1; edge.control_city_id = id
		state.edges.append(edge); state.edge_lookup[GameState.edge_key(id,3)] = edge
		(state.adjacency[id] as Array[int]).append(3); (state.adjacency[3] as Array[int]).append(id)
	state.atlas_layout = {"hierarchy":{"state_parents":PackedInt32Array([0,1,2]),"members":[[0],[1],[2]]},"territorial_pairs":[]}
	state.rebuild_administrative_regions(); state._initialize_recognized_city_owners(); state._initialize_capitals_and_warehouses(); state.refresh_derived()
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	for id in range(2):
		var army := Army.new(); army.id = id; army.owner_nation = id; army.size = 15000; army.max_size = 15000; army.attack = 10; army.defense = 10; army.morale = 1.; army.max_morale = 1.
		army.move_from = id; army.move_to = 3; army.move_progress = 1.; army.on_edge = true; army.state = Army.State.MOVING; army.path = [id] as Array[int]
		state.armies.append(army); state.edges[id].passing_count = 1; state.edges[id].occupied = true
	var sim := Simulation.new(); sim.state = state; sim._detect_atlas_junction_contacts()
	check(state.battles.size()==1,"different incoming edges collide at junction")
	var battle := state.battles[0]
	check(battle.kind==Battle.Kind.FIELD and battle.city==null and battle.traffic_node_id==3,"junction is field battle without siege garrison")
	# Reinforcement must join from its own incoming road, rather than pass through.
	var reinforcement := Army.new(); reinforcement.id = 2; reinforcement.owner_nation = 0; reinforcement.size = 1000; reinforcement.max_size = 1000; reinforcement.move_from = 2; reinforcement.move_to = 3; reinforcement.move_progress = 1.; reinforcement.on_edge = true; reinforcement.state = Army.State.MOVING
	state.armies.append(reinforcement); state.edges[2].passing_count = 1; state.edges[2].occupied = true
	sim._detect_atlas_junction_contacts()
	check(battle.has_army(reinforcement),"junction reinforcement from another incoming edge")
	battle.finished = true; battle.winner_side = 1; sim._finish_field_battle(battle)
	for army in state.armies: check(army.battle_id==-1,"field battle bindings released")
	check(state.cities[3].owner_nation==-1 and not state.cities[3].is_capital,"junction never occupied")
	print("ATLAS_JUNCTION_ENCOUNTERS failures=",failures); sim.free(); quit(1 if failures else 0)
