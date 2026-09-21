extends SceneTree


func _init() -> void:
	var state := _make_state()
	var pairs := state.territorial_border_pairs()
	var neighbors_0 := state.territorial_border_neighbors(0)
	var neighbors_1 := state.territorial_border_neighbors(1)
	var cache := {}
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.NEUTRAL)
	var view := AiWorldView.build(state, 0)
	var snapshot := StrategicMapSnapshot.new()
	snapshot.nation_id = 0
	snapshot._state = state
	snapshot._view = view
	snapshot._find_frontier(cache)
	var simulation := Simulation.new()
	simulation.setup(state)
	simulation._refresh_war_flags()
	var enclave_draft := _enclave_draft(state)
	var enclaves_moved := simulation._plan_coalition_enclave_transfers(
		enclave_draft, [0, 2] as Array[int]
	)
	var valid := (
		pairs.size() == 2
		and pairs[0] == Vector2i(0, 1)
		and pairs[1] == Vector2i(3, 5)
		and neighbors_0 == [1]
		and neighbors_1 == [0]
		and state.cities_share_territorial_border(0, 1)
		and not state.cities_share_territorial_border(0, 3)
		and not state.cities_share_territorial_border(1, 3)
		and DiplomacyAI._frontier_edges(state, 0, 1, cache) == 1
		and DiplomacyAI._frontier_edges(state, 0, 2, cache) == 0
		and DiplomacyAI._frontier_edges(state, 1, 2, cache) == 0
		and not DiplomacyAI.within_diplomatic_range(state, 0, 2, cache)
		and snapshot.frontier_cities == [0]
		and snapshot.frontier_enemy_cities == [1]
		and not snapshot.frontier_cities.has(2)
		and not snapshot.frontier_enemy_cities.has(4)
		and state.cities[0].at_war
		and state.cities[1].at_war
		and not state.cities[2].at_war
		and not state.cities[4].at_war
		and enclaves_moved == 1
		and int((enclave_draft["owners"] as Array)[0]) == 0
		and int((enclave_draft["owners"] as Array)[1]) == 0
		and int((enclave_draft["owners"] as Array)[3]) == 2
	)

	# Closing either bank connection removes the local crossing immediately.
	state.edge_of(1, 2).max_manpower = 0
	state.road_network_revision += 1
	valid = valid and state.territorial_border_pairs() == [Vector2i(3, 5)]
	valid = valid and not state.cities_share_territorial_border(0, 1)
	state.cities[2].owner_nation = 0
	state.ownership_revision += 1
	var expedition_cache := {}
	valid = valid and DiplomacyAI._bordering_nation_ids(
		state, 0, expedition_cache
	).is_empty()
	valid = valid and DiplomacyAI._expedition_target_nation_ids(
		state, 0, expedition_cache
	) == [2]
	valid = valid and DiplomacyAI.can_initiate_war_at_range(
		state, 0, 2, expedition_cache
	)
	valid = valid and DiplomacyAI.war_staging_cities_for_objective(
		state, 0, 3, expedition_cache
	) == [2]
	simulation.free()

	if valid:
		print("TERRITORIAL_BORDER_TOPOLOGY_OK")
		quit(0)
		return
	push_error(
		"TERRITORIAL_BORDER_TOPOLOGY_FAILED pairs=%s n0=%s n1=%s"
		% [str(pairs), str(neighbors_0), str(neighbors_1)]
	)
	quit(1)


func _make_state() -> GameState:
	var state := GameState.new()
	for nation_id in range(3):
		var nation := Nation.new()
		nation.id = nation_id
		nation.alive = true
		state.nations.append(nation)

	_add_city(state, 0, false) # 0: first bank of the local crossing
	_add_city(state, 1, false) # 1: opposite bank of the same dock
	_add_city(state, 2, true)  # 2: shared local dock, occupied by a third nation
	_add_city(state, 2, false) # 3: land beyond a second dock
	_add_city(state, 2, true)  # 4: second dock in the river chain
	_add_city(state, 2, false) # 5: opposite bank of the second dock

	_add_edge(state, 0, 2, Edge.Kind.LANDING)
	_add_edge(state, 1, 2, Edge.Kind.LANDING)
	_add_edge(state, 2, 4, Edge.Kind.RIVER)
	_add_edge(state, 3, 4, Edge.Kind.LANDING)
	_add_edge(state, 5, 4, Edge.Kind.LANDING)
	state.recognized_city_owners.resize(state.cities.size())
	for city in state.cities:
		state.recognized_city_owners[city.id] = city.owner_nation
	return state


func _enclave_draft(state: GameState) -> Dictionary:
	var owners: Array[int] = []
	var legal: Array[int] = []
	var sponsors: Array[int] = []
	for city in state.cities:
		owners.append(city.owner_nation)
		legal.append(city.owner_nation)
		sponsors.append(-1)
	# Nation 0 owns both banks of the first crossing and one bank at the
	# downstream dock. The river link between docks must not join the pocket.
	owners[1] = 0
	legal[1] = 0
	owners[3] = 0
	legal[3] = 0
	return {
		"owners": owners,
		"legal": legal,
		"sponsors": sponsors,
		"operation_by_city": {},
	}


func _add_city(state: GameState, owner: int, is_dock: bool) -> void:
	var city := City.new()
	city.id = state.cities.size()
	city.owner_nation = owner
	city.is_dock = is_dock
	city.politically_active = true
	state.cities.append(city)
	state.adjacency[city.id] = [] as Array[int]


func _add_edge(state: GameState, a: int, b: int, kind: int) -> void:
	var edge := Edge.new()
	edge.city_a = mini(a, b)
	edge.city_b = maxi(a, b)
	edge.kind = kind
	edge.max_manpower = (
		Edge.WATER_MANPOWER
		if kind == Edge.Kind.RIVER
		else Edge.TERRAIN_LOW_MANPOWER
	)
	edge.base_max_manpower = edge.max_manpower
	state.edges.append(edge)
	state.edge_lookup[GameState.edge_key(a, b)] = edge
	(state.adjacency[a] as Array[int]).append(b)
	(state.adjacency[b] as Array[int]).append(a)
