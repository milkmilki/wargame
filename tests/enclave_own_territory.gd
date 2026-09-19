extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(95001)
	for city in state.cities:
		city.owner_nation = 3
		state.recognized_city_owners[city.id] = 3
	for edge in state.edges:
		edge.max_manpower = 0
	for city_id in [0, 16]:
		state.cities[city_id].owner_nation = 0
		state.recognized_city_owners[city_id] = 0
	state.cities[8].owner_nation = 1
	state.recognized_city_owners[8] = 1
	state.edge_of(0, 8).max_manpower = Edge.STANDARD_MANPOWER
	state.edge_of(8, 16).max_manpower = Edge.STANDARD_MANPOWER
	state.nations[0].capital_city_id = 0
	state.nations[1].capital_city_id = 8
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	state.refresh_derived()
	var simulation := Simulation.new()
	simulation.setup(state)
	var allied_live := simulation._capital_connected_territory(0)
	var allied_planned := simulation._planned_capital_connected_territory(
		0, _territory_draft(state)
	)
	state.suzerainty[1] = {
		"overlord_id": 0,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": -1,
		"civil_war": false,
	}
	state.refresh_derived()
	var vassal_live := simulation._capital_connected_territory(0)
	var vassal_planned := simulation._planned_capital_connected_territory(
		0, _territory_draft(state)
	)
	var valid := (
		_only_capital_connected(allied_live)
		and _only_capital_connected(allied_planned)
		and _only_capital_connected(vassal_live)
		and _only_capital_connected(vassal_planned)
	)
	simulation.free()
	if valid:
		print("ENCLAVE_OWN_TERRITORY_OK")
		quit(0)
		return
	push_error(
		"ENCLAVE_OWN_TERRITORY_FAILED allied=%s/%s vassal=%s/%s"
		% [
			str(allied_live.keys()), str(allied_planned.keys()),
			str(vassal_live.keys()), str(vassal_planned.keys()),
		]
	)
	quit(1)


func _territory_draft(state: GameState) -> Dictionary:
	var owners: Array[int] = []
	var legal: Array[int] = []
	var sponsors: Array[int] = []
	for city in state.cities:
		owners.append(city.owner_nation)
		legal.append(state.recognized_owner_of(city.id))
		sponsors.append(city.occupation_sponsor_nation)
	return {
		"owners": owners,
		"legal": legal,
		"sponsors": sponsors,
		"operation_by_city": {},
		"proposed_suzerainty": state.suzerainty.duplicate(true),
	}


func _only_capital_connected(connected: Dictionary) -> bool:
	return (
		connected.has(0)
		and not connected.has(8)
		and not connected.has(16)
	)
