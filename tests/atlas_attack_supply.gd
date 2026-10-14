extends SceneTree
## Splitting the last hostile attack road must not sever its rear supply.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture(split: bool = true) -> GameState:
	var state := GameState.new()
	state._reset_world(94014)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 3, false)
	for id in range(5):
		var city := City.new()
		city.id = id
		city.map_position = Vector2(float(id) / 5.0, 0.5)
		city.owner_nation = id if id < 2 else -1
		city.node_kind = City.NodeKind.SETTLEMENT if id < 2 else City.NodeKind.TRAFFIC
		city.politically_active = id < 2
		city.food_storage = 10000 if id == 0 else 0
		city.food_per_half_year = 10000 if id == 0 else 0
		city.has_warehouse = id < 2
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
	for nation in state.nations:
		nation.capital_city_id = nation.id if nation.id < 2 else -1
		if nation.id < 2: nation.warehouse_city_ids.append(nation.id)
	var pairs := [Vector2i(0,2),Vector2i(2,3),Vector2i(3,4),Vector2i(4,1)] if split else [Vector2i(0,1)]
	for pair in pairs:
		var edge := Edge.new()
		edge.city_a = mini(pair.x,pair.y)
		edge.city_b = maxi(pair.x,pair.y)
		edge.control_city_id = 1
		edge.precise_distance = 0.12 / pairs.size()
		edge.danger = 0.2
		state.edges.append(edge)
		state.edge_lookup[GameState.edge_key(pair.x,pair.y)] = edge
		(state.adjacency[pair.x] as Array[int]).append(pair.y)
		(state.adjacency[pair.y] as Array[int]).append(pair.x)
	state.atlas_layout = {"model":"attack-supply-test","territorial_pairs":[] as Array[Vector2i]}
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	return state

func moving(from: int, to: int, progress: float, path: Array[int]) -> Army:
	var army := Army.new()
	army.id = 41
	army.owner_nation = 0
	army.size = 15000
	army.max_size = 15000
	army.location_city = from
	army.move_from = from
	army.move_to = to
	army.move_progress = progress
	army.path = path.duplicate()
	army.route_origin_city_id = 0
	army.on_edge = true
	army.state = Army.State.MOVING
	return army

func query(state: GameState, army: Army) -> Array[Dictionary]:
	return Pathfinding.supply_sources_from_network(state,army,Pathfinding.build_supply_network(state,army.owner_nation))

func battle_fixture() -> Dictionary:
	var state := fixture()
	var attacker := moving(4,1,1.0,[] as Array[int])
	attacker.on_edge = false
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city = state.cities[1]
	battle.side_b_defends_city = true
	battle.edge = state.edge_of(4,1)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.state = state
	sim.paused = true
	state.armies.append(attacker)
	sim._enter_battle(battle,attacker,1)
	var idle := moving(4,1,0.0,[] as Array[int])
	idle.id = 42
	idle.on_edge = false
	idle.move_to = -1
	idle.state = Army.State.IDLE
	state.armies.append(idle)
	var defender := moving(1,4,0.0,[] as Array[int])
	defender.id = 43
	defender.owner_nation = 1
	defender.location_city = 1
	defender.on_edge = false
	defender.move_to = -1
	state.armies.append(defender)
	sim._enter_battle(battle,defender,2)
	return {"state":state,"sim":sim,"attacker":attacker,"idle":idle,"defender":defender,"battle":battle}

func resolve(data: Dictionary, sliced: bool) -> void:
	if sliced:
		await data.sim._resolve_supply_over_frames()
	else:
		data.sim._resolve_supply()

func guard_routes() -> void:
	var state := fixture()
	var attacker := moving(3,4,0.5,[4,1] as Array[int])
	var network_before := var_to_bytes(Pathfinding.build_supply_network(state,0))
	check(query(state,attacker).size()==1,"terminal corridor joins the real rear field")
	check(var_to_bytes(Pathfinding.build_supply_network(state,0))==network_before,"attack queries do not open the shared rear field to hostile territory")
	var field := state.new_battle(Battle.Kind.FIELD)
	field.edge = state.edge_of(3,4)
	field.side_a.append(attacker)
	attacker.state = Army.State.FIGHTING
	attacker.battle_id = field.id
	check(query(state,attacker).size()==1,"contact on the terminal attack road retains the committed destination and rear supply")
	attacker.path.clear()
	check(query(state,attacker).is_empty(),"a field battle alone does not grant hostile logistics transit")
	attacker.path = [4,1] as Array[int]
	attacker.state = Army.State.MOVING
	attacker.battle_id = -1
	field.finished = true
	var blocker := moving(0,2,0.5,[2] as Array[int])
	blocker.owner_nation = 1
	state.armies.append(blocker)
	check(query(state,attacker).is_empty(),"enemy presence cuts the terminal road")
	state.armies.clear()
	state.edge_of(2,3).max_manpower = 0
	check(query(state,attacker).is_empty(),"zero-capacity terminal road is impassable")
	state.edge_of(2,3).max_manpower = 50000
	state.cities[3].node_kind = City.NodeKind.SETTLEMENT
	state.cities[3].owner_nation = 1
	check(query(state,attacker).is_empty(),"supplies cannot traverse an uncaptured hostile settlement")
	state.cities[3].node_kind = City.NodeKind.TRAFFIC
	state.cities[3].owner_nation = -1
	attacker.path = [4] as Array[int]
	check(query(state,attacker).is_empty(),"an arbitrary hostile junction is not an attack goal")
	attacker.path = [4,1] as Array[int]
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.NEUTRAL)
	check(query(state,attacker).is_empty(),"peace removes the hostile terminal exception")
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	state.cities[0].food_storage = 0
	state.cities[1].food_storage = 10000
	check(query(state,attacker).is_empty(),"enemy food cannot replace an empty rear warehouse")
	state.cities[0].food_storage = 10000
	var foreign := City.new()
	foreign.id = 5
	foreign.node_kind = City.NodeKind.SETTLEMENT
	foreign.owner_nation = 2
	state.cities.append(foreign)
	state.adjacency[5] = [] as Array[int]
	state.edge_of(2,3).control_city_id = 5
	for relation in [GameState.DiplomaticRelation.NEUTRAL,GameState.DiplomaticRelation.WAR]:
		state.set_diplomatic_relation(0,2,relation)
		check(query(state,attacker).is_empty(),"unrelated foreign jurisdiction is never opened by the target exception")

func run() -> void:
	var plain := fixture(false)
	var split := fixture()
	var order: Array[int] = [0,2,3,4,1]
	var loss := Pathfinding._supply_edge_loss(plain.edges[0])
	var rng := split.rng.state
	for index in range(4):
		for progress in [0.1,0.5,0.9]:
			var physical: float = (index + progress) / 4.0
			var original := query(plain,moving(0,1,physical,[1] as Array[int]))
			var army := moving(order[index],order[index+1],progress,order.slice(index+1))
			var actual := query(split,army)
			check(original.size()==1,"unsplit attack road has a real rear warehouse")
			check(actual.size()==1,"split attack road retains supply at leg %d progress %.1f"%[index,progress])
			if not actual.is_empty():
				check(actual[0].city_id==0 and is_equal_approx(actual[0].loss,physical*loss),"transport loss remains additive across hostile traffic segments")
			check(var_to_bytes(Pathfinding.supply_sources(split,army))==var_to_bytes(actual),"direct and batched attack supply agree")
	guard_routes()
	var sync := battle_fixture()
	var sliced := battle_fixture()
	check(query(sync.state,sync.attacker).size()==1,"arrived besieger retains its connected rear beyond the final junction")
	check(query(sync.state,sync.idle).is_empty(),"idle troops at the same junction have no hostile transit permission")
	# Warm the old owner/city cache with the idle formation first.
	for data in [sync,sliced]:
		data.sim._cached_supply_sources(data.idle,data.sim._daily_supply_source_cache,data.sim._daily_supply_network_cache,data.sim._stable_supply_city_source_cache)
	for phase in ["connected","interdicted","reopened"]:
		for data in [sync,sliced]:
			if phase == "interdicted":
				var blocker := moving(0,2,0.5,[2] as Array[int])
				blocker.id = 44
				blocker.owner_nation = 1
				data.state.armies.append(blocker)
			elif phase == "reopened":
				data.state.armies.pop_back()
		await resolve(sync,false)
		await resolve(sliced,true)
		check(var_to_bytes(NativeSnapshotBuilder.build(sync.state))==var_to_bytes(NativeSnapshotBuilder.build(sliced.state)),phase+": sync and worker supply are byte equivalent")
		for data in [sync,sliced]:
			var expected := 0.0 if phase == "interdicted" else 1.0
			check(data.attacker.supply_ratio==expected,phase+": attacker refreshes corridor access despite the persistent rear field")
			check(data.idle.supply_ratio==0.0,phase+": same-position idle cache remains isolated")
			check(data.defender.supply_ratio==0.0,phase+": resident defender keeps local siege isolation")
			check(data.state.cities[1].food_storage==0,phase+": enemy city is never a food source")
	check(sync.state.cities[0].food_storage<10000,"food comes from the real rear warehouse")
	check(split.rng.state==rng and split.cities[4].owner_nation==-1,"supply does not change owners or random state")
	sync.sim.free()
	sliced.sim.free()
	for failure in failures: printerr("ATLAS_ATTACK_SUPPLY_FAIL ",failure)
	print("ATLAS_ATTACK_SUPPLY_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
