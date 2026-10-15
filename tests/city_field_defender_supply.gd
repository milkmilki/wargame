extends SceneTree
## Real field formations fighting at a city retain reachable rear logistics.
## The virtual city guard keeps the local siege clock instead.
const BattleInformation = preload("res://scripts/atlas/battle_information.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func fixture(allied: bool, local_food: int = 0, cut_route: bool = false, rear_food: int = 10000, participates: bool = true) -> Dictionary:
	var state := GameState.new()
	state._reset_world(94013)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 3, false)
	for id in range(6):
		var city := City.new()
		city.id = id
		city.name = "州治%d" % id
		city.map_position = Vector2(float(id) / 6.0, 0.5)
		city.owner_nation = 0 if id < 2 else (1 if id == 2 else (2 if id == 5 else -1))
		city.node_kind = City.NodeKind.TRAFFIC if id in [3, 4] else City.NodeKind.SETTLEMENT
		city.politically_active = city.node_kind == City.NodeKind.SETTLEMENT
		city.has_warehouse = id in [0, 2, 5]
		city.food_storage = 10000 if id == 2 else (rear_food if id in [0, 5] else (local_food if id == 1 else 0))
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
	for nation in state.nations:
		nation.capital_city_id = 0 if nation.id == 0 else (2 if nation.id == 1 else 5)
		nation.warehouse_city_ids = [nation.capital_city_id] as Array[int]
		nation.treasury_gold = 10000
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
	for pair in [Vector2i(0, 3), Vector2i(3, 4), Vector2i(4, 1), Vector2i(2, 4), Vector2i(5, 3)]:
		var edge := Edge.new()
		edge.city_a = mini(pair.x, pair.y)
		edge.city_b = maxi(pair.x, pair.y)
		edge.control_city_id = 2 if pair.x == 2 else (5 if pair.x == 5 else 0)
		edge.precise_distance = 0.1
		state.edges.append(edge)
		state.edge_lookup[GameState.edge_key(pair.x, pair.y)] = edge
		(state.adjacency[pair.x] as Array[int]).append(pair.y)
		(state.adjacency[pair.y] as Array[int]).append(pair.x)
	state.atlas_layout = {"model": "city-field-defender-supply-test", "territorial_pairs": [] as Array[Vector2i]}
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	if cut_route:
		# A real hostile road separates both friendly warehouses from the city.
		state.edge_of(3, 4).control_city_id = 2
	var defender := Army.new()
	defender.id = 41
	defender.owner_nation = 2 if allied else 0
	defender.size = 12000
	defender.max_size = 15000
	defender.morale = defender.max_morale
	defender.location_city = 1
	defender.move_from = 1
	defender.move_to = -1
	defender.starving = true
	defender.supply_ratio = 0.0
	state.armies.append(defender)
	var attacker := Army.new()
	attacker.id = 42
	attacker.owner_nation = 1
	attacker.size = 10000
	attacker.max_size = 15000
	attacker.morale = attacker.max_morale
	attacker.location_city = 2
	attacker.move_from = 2
	state.armies.append(attacker)
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city = state.cities[1]
	battle.edge = state.edge_of(4, 1)
	battle.side_b_defends_city = true
	battle.field_dice = PackedInt32Array([0, 0, 0, 0])
	battle.field_sequence = 1
	var sim := Simulation.new()
	root.add_child(sim)
	sim.state = state
	sim.paused = true
	sim._enter_battle(battle, attacker, 1)
	if participates:
		sim._enter_battle(battle, defender, 2)
	return {"state": state, "sim": sim, "army": defender, "battle": battle}


func resolve_supply(sim: Simulation, sliced: bool) -> void:
	if sliced:
		await sim._resolve_supply_over_frames()
	else:
		sim._resolve_supply()


func fingerprint(data: Dictionary) -> PackedByteArray:
	var state: GameState = data.state
	var armies := []
	for army in state.armies:
		armies.append([army.size, army.morale, army.starving, army.supply_ratio,
			army.supply_food_debt, army.supply_debt, army.state, army.battle_id])
	return var_to_bytes([armies, state.cities.map(func(city: City): return city.food_storage),
		state.nations.map(func(nation: Nation): return nation.last_food_demand), state.rng.state])


func rear_stock(state: GameState) -> int:
	return state.cities[0].food_storage + state.cities[5].food_storage


func test_reachable(allied: bool, local_food: int, sliced: bool) -> PackedByteArray:
	var data := fixture(allied, local_food)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army: Army = data.army
	var battle: Battle = data.battle
	var label := "inside allied=%s local=%d sliced=%s" % [allied, local_food, sliced]
	var rng_before := state.rng.state
	check(battle.uses_field_combat_rules() and army.location_city == battle.city.id and not army.is_city_garrison,
		label + " real resident army entered city-field combat")
	# The rear junction is genuinely connected; a new rule cannot fake a supply source.
	var rear_probe := Army.new()
	rear_probe.owner_nation = army.owner_nation
	rear_probe.location_city = 4
	rear_probe.move_from = 4
	check(not Pathfinding.supply_sources(state, rear_probe).is_empty(), label + " physical rear road reaches friendly warehouses")
	check(not Pathfinding.supply_sources(state, army).is_empty(), label + " city-field army can query its reachable rear warehouse")
	var stock_before := rear_stock(state)
	await resolve_supply(sim, sliced)
	check(army.supply_ratio == 1.0 and not army.starving, label + " rear stock feeds real city-field defender")
	check(rear_stock(state) == stock_before - 1, label + " defender withdraws one real rear ration")
	check(state.cities[1].food_storage == local_food, label + " field ration is not charged to city stock")
	var stock_after := rear_stock(state)
	var debt_after := army.supply_food_debt
	sim._drain_siege_food()
	check(army.supply_ratio == 1.0 and not army.starving, label + " city food clock does not overwrite field supply")
	check(rear_stock(state) == stock_after and army.supply_food_debt == debt_after,
		label + " siege clock does not charge the field ration twice")
	check(state.cities[1].food_storage == maxi(0, local_food - Simulation.SIEGE_CITY_FOOD_PER_DAY),
		label + " city pays only fixed siege food clock")
	var morale_before := army.morale
	var size_before := army.size
	sim._apply_supply_pressure()
	check(army.morale == morale_before and army.size == size_before, label + " no false starvation damage")
	var before_inspection := fingerprint(data)
	var details := BattleInformation.snapshot(state, battle)
	check(details.field and details.b.supply == 1.0 and details.b.fire > 0.0 and details.b.defense > 0.0,
		label + " battle detail shows supplied real army with effective fire and defense")
	var document := BattleInformation.document(state, battle.id)
	var found_supply := false
	for row in document.sections[0].rows:
		if row.label == "供给率":
			found_supply = row.cells[1] == "100%"
	check(found_supply, label + " comparison displays defender supply as 100 percent")
	check(fingerprint(data) == before_inspection, label + " detail lookup is read-only")
	check(state.rng.state == rng_before, label + " supply and inspection preserve random stream")
	var result := fingerprint(data)
	sim.free()
	return result


func test_shortage(cut_route: bool, sliced: bool) -> PackedByteArray:
	var data := fixture(false, 0, cut_route, 10000 if cut_route else 0)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army: Army = data.army
	var label := "inside shortage cut_route=%s sliced=%s" % [cut_route, sliced]
	var rng_before := state.rng.state
	var stock_before := rear_stock(state)
	await resolve_supply(sim, sliced)
	check(army.supply_ratio == 0.0 and army.starving, label + " unreachable or empty warehouse provides no invented food")
	check(rear_stock(state) == stock_before, label + " unavailable rear stocks are untouched")
	sim._drain_siege_food()
	sim._apply_supply_pressure()
	check(army.supply_ratio == 0.0 and army.morale < army.max_morale,
		label + " genuine field shortage applies normal morale pressure")
	check(BattleInformation.snapshot(state, data.battle).b.supply == 0.0, label + " detail preserves genuine zero supply")
	check(state.rng.state == rng_before, label + " shortage settlement preserves random stream")
	var result := fingerprint(data)
	sim.free()
	return result


func test_virtual_guard(local_food: int, sliced: bool) -> PackedByteArray:
	var data := fixture(false, local_food)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var battle: Battle = data.battle
	var field_army: Army = data.army
	battle.remove_army(field_army)
	state.armies.erase(field_army)
	battle.city.garrison_manpower = 1000
	var guard := sim._attach_city_garrison(battle)
	check(guard != null and not battle.uses_field_combat_rules(), "virtual guard uses pure siege rules")
	var rng_before := state.rng.state
	var stock_before := rear_stock(state)
	await resolve_supply(sim, sliced)
	sim._drain_siege_food()
	check(rear_stock(state) == stock_before, "virtual guard never draws external warehouses")
	check(battle.city.food_storage == maxi(0, local_food - Simulation.SIEGE_CITY_FOOD_PER_DAY),
		"virtual guard keeps exactly the existing local siege food clock")
	check(guard.supply_ratio == (1.0 if local_food > Simulation.SIEGE_CITY_FOOD_PER_DAY else 0.0),
		"virtual guard supply still follows real city food")
	check(state.rng.state == rng_before, "virtual guard clock preserves random stream")
	var result := fingerprint(data)
	sim._detach_city_garrison(battle, guard)
	sim.free()
	return result


func test_local_fallback(warehouse: bool, sliced: bool) -> PackedByteArray:
	var data := fixture(false, 100, true)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army: Army = data.army
	var city: City = data.battle.city
	if warehouse:
		city.has_warehouse = true
		state.nations[0].warehouse_city_ids.append(city.id)
	var label := "inside local fallback warehouse=%s sliced=%s" % [warehouse, sliced]
	var rng_before := state.rng.state
	var stock_before := rear_stock(state)
	var sources := Pathfinding.supply_sources(state, army)
	check(sources.size() == 1 and int(sources[0].city_id) == city.id,
		label + " disconnected rear leaves actual city stock as the sole source")
	await resolve_supply(sim, sliced)
	check(army.supply_ratio == 1.0 and not army.starving, label + " local food really feeds field troops")
	check(city.food_storage == 99 and rear_stock(state) == stock_before,
		label + " one establishment ration comes from the real local stock")
	var debt_after := army.supply_food_debt
	sim._drain_siege_food()
	check(city.food_storage == 99 - Simulation.SIEGE_CITY_FOOD_PER_DAY,
		label + " only fixed city clock follows, with no second field ration")
	check(army.supply_food_debt == debt_after and rear_stock(state) == stock_before,
		label + " siege clock preserves field food debt and unreachable warehouses")
	check(army.supply_ratio == 1.0 and BattleInformation.snapshot(state, data.battle).b.supply == 1.0,
		label + " actual local self-supply appears in battle details")
	check(state.rng.state == rng_before, label + " local fallback preserves random stream")
	var result := fingerprint(data)
	sim.free()
	return result


func test_role_cache_transition(sliced: bool) -> PackedByteArray:
	var data := fixture(false, 0, false, 10000, false)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army: Army = data.army
	var battle: Battle = data.battle
	var label := "resident enters field combat sliced=%s" % sliced
	var rng_before := state.rng.state
	check(not battle.has_army(army) and Pathfinding.supply_sources(state, army).is_empty(),
		label + " ordinary isolated resident begins with empty city sources")
	var stock_before := rear_stock(state)
	await resolve_supply(sim, sliced)
	check(army.supply_ratio == 0.0 and army.starving and rear_stock(state) == stock_before,
		label + " actual first settlement primes an empty resident source result")
	# Another ordinary resident is processed at the same node before the newly
	# participating army. A city-only cache or parallel alias must not mix roles.
	var resident := Army.new()
	resident.id = 43
	resident.owner_nation = army.owner_nation
	resident.size = 1000
	resident.max_size = 15000
	resident.location_city = army.location_city
	resident.move_from = army.location_city
	state.armies.push_front(resident)
	state.day += 1
	sim._enter_battle(battle, army, 2)
	check(battle.uses_field_combat_rules() and army.state == Army.State.FIGHTING,
		label + " real battle entry switches only the participating army's role")
	check(not Pathfinding.supply_sources(state, army).is_empty(), label + " participating army immediately sees its rear sources")
	await resolve_supply(sim, sliced)
	check(army.supply_ratio == 1.0 and not army.starving and rear_stock(state) < stock_before,
		label + " prior empty resident cache cannot suppress real rear withdrawal and full field supply")
	check(resident.supply_ratio == 0.0 and resident.starving and not battle.has_army(resident),
		label + " uncommitted same-city resident does not inherit field supply")
	var debt_after := army.supply_food_debt
	sim._drain_siege_food()
	check(army.supply_ratio == 1.0 and army.supply_food_debt == debt_after,
		label + " city clock cannot reapply old isolated resident treatment")
	check(BattleInformation.snapshot(state, battle).b.supply == 1.0,
		label + " battle display reflects the new participating role")
	check(state.rng.state == rng_before, label + " role transition and cache reuse preserve random stream")
	var result := fingerprint(data)
	sim.free()
	return result


func run() -> void:
	for allied in [false, true]:
		for local_food in [0, 100]:
			var sync := await test_reachable(allied, local_food, false)
			var sliced := await test_reachable(allied, local_food, true)
			check(sync == sliced, "resident city-field defender allied=%s local=%d is sync/sliced byte-equivalent" % [allied, local_food])
	for cut_route in [false, true]:
		var sync := await test_shortage(cut_route, false)
		var sliced := await test_shortage(cut_route, true)
		check(sync == sliced, "resident city-field genuine shortage cut_route=%s is sync/sliced byte-equivalent" % cut_route)
	for local_food in [0, 100]:
		var sync := await test_virtual_guard(local_food, false)
		var sliced := await test_virtual_guard(local_food, true)
		check(sync == sliced, "virtual city guard local=%d is sync/sliced byte-equivalent" % local_food)
	for warehouse in [false, true]:
		var sync := await test_local_fallback(warehouse, false)
		var sliced := await test_local_fallback(warehouse, true)
		check(sync == sliced, "resident local fallback warehouse=%s is sync/sliced byte-equivalent" % warehouse)
	var transition_sync := await test_role_cache_transition(false)
	var transition_sliced := await test_role_cache_transition(true)
	check(transition_sync == transition_sliced, "resident-to-field role transition is sync/sliced byte-equivalent")
	for failure in failures:
		printerr("CITY_FIELD_DEFENDER_SUPPLY_FAIL ", failure)
	print("CITY_FIELD_DEFENDER_SUPPLY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
