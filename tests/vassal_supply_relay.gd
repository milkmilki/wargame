extends SceneTree
## Both public supply queries and actual withdrawals must honor a real fief's relay.
const FamilyFixture = preload("res://tests/ruler_family_fixture.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture() -> GameState:
	var state := GameState.new()
	state._reset_world(61016)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 2, false)
	state.atlas_layout = {"model":"atlas-military-v1","territorial_pairs":[] as Array[Vector2i]}
	for id in range(5):
		var city := City.new()
		city.id = id
		city.name = "城%d" % id
		city.owner_nation = 0 if id < 4 else 1
		city.map_position = Vector2(float(id)/5.0,0.5)
		city.manpower_per_month = 1000
		city.gold_per_month = 100
		city.food_per_half_year = 60000
		city.is_capital = id in [0,4]
		city.has_warehouse = city.is_capital
		city.food_storage = 100000 if city.is_capital else 0
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
	for id in range(4):
		var road := Edge.new()
		road.city_a = id; road.city_b = id+1
		road.control_city_id = 4
		road.max_manpower = Edge.STANDARD_MANPOWER
		road.distance = 1
		state.edges.append(road)
		state.edge_lookup[GameState.edge_key(id,id+1)] = road
		state.adjacency[id].append(id+1); state.adjacency[id+1].append(id)
	for home in range(2):
		state.nations[home].capital_city_id = 0 if home == 0 else 4
		state.nations[home].warehouse_city_ids = [state.nations[home].capital_city_id] as Array[int]
		state.nations[home].manpower_pool = 100000
		state.nations[home].treasury_gold = 10000
	state.recognized_city_owners = PackedInt32Array([0,0,0,0,1])
	state.administrative_center_by_city = PackedInt32Array(range(5))
	state.administrative_center_city_ids = PackedInt32Array(range(5))
	state.administrative_region_ids = PackedInt32Array(range(5))
	state.administrative_region_count = 5
	FamilyTree.ensure_all(state)
	FamilyFixture.ensure_candidates(state,0,3)
	state.refresh_derived()
	return state

func run() -> void:
	for backend in ["gdscript","native"]:
		NativeCompute.set_backend_for_tests(backend)
		var state := fixture()
		var subject := state.enfeoff(0,[2,3] as Array[int])
		check(subject >= 0, backend+": actual complete fief created")
		if subject < 0: continue
		var army := state.create_army(subject,state.nations[subject].capital_city_id,1000)
		check(army != null, backend+": fief recruits from transferred manpower")
		if army == null: continue
		var rng := state.rng.state
		var direct := Pathfinding.supply_sources(state,army)
		var cached := Pathfinding.supply_sources_from_network(state,army,Pathfinding.build_supply_network(state,subject))
		check(direct == cached, backend+": direct and batched capital sources agree")
		check(direct.size() == 1 and direct[0].owner_nation == 0 and is_zero_approx(direct[0].loss), backend+": fief capital has zero-loss access to the real root granary")
		army.move_from = 2; army.move_to = 3; army.on_edge = true; army.state = Army.State.MOVING; army.move_progress = 0.4
		direct = Pathfinding.supply_sources(state,army)
		cached = Pathfinding.supply_sources_from_network(state,army,Pathfinding.build_supply_network(state,subject))
		check(direct == cached, backend+": moving army receives the same relay-adjusted losses")
		# A real neutral city blocks the outward leg, even though rural roads are public.
		army.on_edge = false; army.state = Army.State.IDLE; army.location_city = 4
		check(Pathfinding.supply_sources(state,army).is_empty(), backend+": neutral city is not opened by a vassal relay")
		army.location_city = state.nations[subject].capital_city_id
		var sim := Simulation.new(); sim.setup(state)
		var food_before := state.nations[0].granary_food
		for day in range(30): sim._resolve_supply()
		check(is_equal_approx(army.supply_ratio,1.0) and state.nations[0].granary_food < food_before, backend+": daily supply consumes actual root food")
		check(state.nations[subject].granary_food == 0 and state.cities[army.location_city].food_storage == 0, backend+": relay never creates duplicate stock")
		check(state.rng.state == rng, backend+": read queries and supply preserve simulation RNG")
		var blockade := state.new_battle(Battle.Kind.SIEGE)
		blockade.city = state.cities[0]
		check(state.nations[0].granary_food > 0 and Pathfinding.supply_sources(state,army).is_empty(), backend+": a besieged root granary cannot export its remaining food through a relay")
		blockade.finished = true
		check(not Pathfinding.supply_sources(state,army).is_empty(), backend+": lifting the root blockade restores relay supply")
		state.edge_of(2,3).max_manpower = 0
		army.location_city = 3 if state.nations[subject].capital_city_id == 2 else 2
		check(Pathfinding.supply_sources(state,army).is_empty(), backend+": a closed local road still cuts supply beyond the relay")
		army.location_city = state.nations[subject].capital_city_id
		state.cities[0].food_storage = 0; state.refresh_derived()
		check(Pathfinding.supply_sources(state,army).is_empty(), backend+": an empty root granary disables relay supply")
		sim.free()
	NativeCompute.set_backend_for_tests("native")
	for failure in failures: push_error("VASSAL_SUPPLY_RELAY_FAIL: "+failure)
	print("VASSAL_SUPPLY_RELAY checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
