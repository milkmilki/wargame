extends SceneTree
## Exact warehouse selection/order with bounded endpoint access queries and no
## global city-rank materialization for source-only ties.
const Legacy = preload("res://tests/support/legacy_supply_pathfinding.gd")
class CountedState extends GameState:
	var access_calls := 0
	func has_logistics_access(traveler: int, owner: int) -> bool:
		access_calls += 1
		return super.has_logistics_access(traveler, owner)
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func _initialize(): call_deferred("run")
func fixture() -> CountedState:
	var state := CountedState.new(); state._reset_world(991)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 2, false)
	for id in range(256):
		var city := City.new(); city.id = id; city.owner_nation = id % 2
		city.map_position = Vector2(float(id % 16) / 16., float(id / 16) / 16.)
		city.food_storage = 1000; city.has_warehouse = true
		state.cities.append(city)
	# Two distinct warehouses are equivalent in the original quantized keys.
	state.cities[3].map_position = state.cities[2].map_position
	state.nations[0].capital_city_id = 0; state.nations[1].capital_city_id = 1
	state.nations[0].warehouse_city_ids = [0] as Array[int]
	var edge := Edge.new(); edge.city_a = 0; edge.city_b = 1; edge.precise_distance = .1
	state.edges.append(edge); state.edge_lookup[GameState.edge_key(0, 1)] = edge
	return state
func network(state: GameState, equal_loss: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in range(65, 1, -1):
		var dist := PackedFloat64Array(); dist.resize(state.cities.size()); dist.fill(INF)
		dist[0] = .5 if equal_loss else float(id % 7) * .04
		dist[1] = .5 if equal_loss else float(id % 5) * .03
		result.append({"city_id":id,"owner_nation":state.cities[id].owner_nation,"dist":dist})
	return result
func compare(state: CountedState, army: Army, sources: Array[Dictionary], label: String):
	var network_bytes := var_to_bytes(sources)
	var rng_before := state.rng.state
	state.access_calls = 0
	var expected := Legacy.supply_sources_from_network(state, army, sources)
	var old_calls := state.access_calls
	state.access_calls = 0; EquivariantOrder._city_rank_cache.clear()
	var actual := Pathfinding.supply_sources_from_network(state, army, sources)
	check(var_to_bytes(actual) == var_to_bytes(expected), label+" exact source losses and order")
	check(state.access_calls <= 2, label+" at most two endpoint access queries")
	check(EquivariantOrder._city_rank_cache.is_empty(), label+" no full-world rank for warehouse ties")
	check(var_to_bytes(sources) == network_bytes and state.rng.state == rng_before, label+" immutable inputs and RNG")
	return old_calls
func run():
	var state := fixture(); var cases := 0
	for relation in [GameState.DiplomaticRelation.NEUTRAL, GameState.DiplomaticRelation.ALLIED, GameState.DiplomaticRelation.WAR]:
		state.set_diplomatic_relation(0, 1, relation)
		for equal_loss in [false, true]:
			for reverse in [false, true]:
				for progress in [-.1, 0., .25, .5, 1., 1.1]:
					var army := Army.new(); army.owner_nation = 0; army.location_city = 0
					army.on_edge = true; army.move_from = 1 if reverse else 0; army.move_to = 0 if reverse else 1
					army.move_progress = progress
					compare(state, army, network(state, equal_loss), "case%d"%cases); cases += 1
	var army := Army.new(); army.owner_nation = 0; army.location_city = 0
	compare(state, army, network(state, true), "stationary tie")
	compare(state, army, [], "empty network")
	army.location_city = -1; compare(state, army, [], "invalid origin")
	army.location_city = 0; army.move_from = 0; army.move_to = 1; army.on_edge = true
	state.edge_lookup.clear(); compare(state, army, network(state, true), "missing edge")
	army.on_edge = false
	var siege := state.new_battle(Battle.Kind.SIEGE); siege.city = state.cities[0]
	state.cities[0].food_storage = 1000
	compare(state, army, network(state, true), "isolated besieged warehouse")
	state.cities[0].food_storage = 0
	compare(state, army, network(state, true), "empty besieged warehouse")
	# A new capital and mirrored coordinates must immediately change tie order.
	siege.finished = true; state.nations[0].capital_city_id = 15
	for city in state.cities: city.map_position.x = 1. - city.map_position.x
	compare(state, army, network(state, true), "mirrored changed capital")
	state.nations[0].capital_city_id = -1
	compare(state, army, network(state, true), "no capital centroid")
	var earth := CountedState.new()
	earth.generate_from_atlas(preload("res://tests/atlas_military_inputs.gd").military())
	var real_networks := {}
	for owner in [0, 7, 23]: real_networks[owner] = Pathfinding.build_supply_network(earth, owner)
	for owner in real_networks:
		var samples := 0
		for edge in earth.edges:
			if samples >= 8: break
			army = Army.new(); army.owner_nation = owner; army.location_city = edge.city_a
			army.move_from = edge.city_a; army.move_to = edge.city_b; army.on_edge = true; army.move_progress = .37
			compare(earth, army, real_networks[owner], "earth%d-%d"%[owner,samples]); samples += 1
	for failure in failures: printerr("ATLAS_SUPPLY_SOURCE_FAIL ", failure)
	print("ATLAS_SUPPLY_SOURCE_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
