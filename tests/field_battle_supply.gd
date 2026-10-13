extends SceneTree
## A city's defenders may still use an accessible rear supply anchor. Actual
## formations stationed inside the besieged city retain the local food clock.
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func fixture(position: String, local_food: int, cut_route: bool = false) -> Dictionary:
	var state := GameState.new()
	state._reset_world(94013)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 2, false)
	for id in range(5):
		var city := City.new()
		city.id = id
		city.map_position = Vector2(float(id) / 5.0, 0.5)
		city.owner_nation = 1 if id == 2 else (0 if id < 2 else -1)
		city.node_kind = City.NodeKind.SETTLEMENT if id < 3 else City.NodeKind.TRAFFIC
		city.politically_active = id < 3
		city.food_storage = 10000 if id in [0, 2] else (local_food if id == 1 else 0)
		city.has_warehouse = id in [0, 2]
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
	for nation in state.nations:
		nation.capital_city_id = 0 if nation.id == 0 else 2
		nation.warehouse_city_ids = [nation.capital_city_id] as Array[int]
		nation.treasury_gold = 10000
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
	for pair in [Vector2i(0, 3), Vector2i(3, 4), Vector2i(4, 1), Vector2i(2, 4)]:
		var edge := Edge.new()
		edge.city_a = mini(pair.x, pair.y)
		edge.city_b = maxi(pair.x, pair.y)
		edge.control_city_id = 2 if pair.x == 2 else 0
		edge.precise_distance = 0.1
		state.edges.append(edge)
		state.edge_lookup[GameState.edge_key(pair.x, pair.y)] = edge
		(state.adjacency[pair.x] as Array[int]).append(pair.y)
		(state.adjacency[pair.y] as Array[int]).append(pair.x)
	state.atlas_layout = {"model": "field-battle-supply-test", "territorial_pairs": [] as Array[Vector2i]}
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	if cut_route:
		state.edge_of(0, 3).control_city_id = 2
	var defender := Army.new()
	defender.id = 41
	defender.owner_nation = 0
	defender.size = 12000
	defender.max_size = 15000
	defender.morale = defender.max_morale
	defender.location_city = 1 if position == "inside" else 4
	defender.move_from = defender.location_city
	defender.move_to = -1 if position == "inside" else 1
	defender.move_progress = 0.6 if position == "approaching" else (0.0 if position == "inside" else 1.0)
	defender.on_edge = position == "approaching"
	# A stale shortage must be refreshed from today's real food sources.
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


func test_reachable(position: String, local_food: int, sliced: bool) -> PackedByteArray:
	var data := fixture(position, local_food)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army: Army = data.army
	var label := "%s local=%d sliced=%s" % [position, local_food, sliced]
	var rng_before := state.rng.state
	var sources := Pathfinding.supply_sources(state, army)
	check(sources.size() == 1 and sources[0].city_id == 0, label + " has a genuine reachable capital warehouse")
	check(state.cities[4].node_kind == City.NodeKind.TRAFFIC and state.cities[4].owner_nation == -1,
		label + " rear anchor is an ownerless physical traffic node")
	await resolve_supply(sim, sliced)
	check(army.supply_ratio == 1.0 and not army.starving, label + " accessible rear stock fully feeds city defenders")
	check(state.cities[0].food_storage == 9999, label + " short rear route withdraws one actual daily capital ration")
	check(state.cities[1].food_storage == local_food, label + " normal supply does not draw besieged city stock")
	var capital_after := state.cities[0].food_storage
	var debt_after := army.supply_food_debt
	sim._drain_siege_food()
	check(army.supply_ratio == 1.0 and not army.starving, label + " siege food clock preserves real rear supply")
	check(state.cities[0].food_storage == capital_after and army.supply_food_debt == debt_after,
		label + " daily siege clock does not charge this formation twice")
	check(state.cities[1].food_storage == maxi(local_food - Simulation.SIEGE_CITY_FOOD_PER_DAY, 0),
		label + " city pays only its existing fixed siege food clock")
	var morale_after := army.morale
	var size_after := army.size
	sim._apply_supply_pressure()
	check(army.morale == morale_after and army.size == size_after and not army.starving,
		label + " fully supplied rear formation suffers no false starvation pressure")
	var logging := Combat.battle_log_enabled
	var log_before := Combat.battle_log.duplicate()
	Combat.battle_log_enabled = true
	Combat.clear_battle_log()
	Combat.resolve_round(data.battle)
	check(not Combat.battle_log.is_empty() and Combat.battle_log[0].effective_attack_b > 0.0
		and Combat.battle_log[0].effective_defense_b > 0.0,
		label + " real city-field round uses positive defender fire and defense")
	Combat.battle_log.assign(log_before)
	Combat.battle_log_enabled = logging
	check(state.rng.state == rng_before, label + " supply and fixed-dice combat preserve simulation random stream")
	var result := fingerprint(data)
	sim.free()
	return result


func test_isolated(local_food: int, sliced: bool) -> PackedByteArray:
	var data := fixture("inside", local_food)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army: Army = data.army
	var label := "inside local=%d sliced=%s" % [local_food, sliced]
	var rng_before := state.rng.state
	await resolve_supply(sim, sliced)
	check(state.cities[0].food_storage == 10000, label + " stationed besieged formation cannot draw national stock")
	check(army.supply_ratio == (1.0 if local_food > 0 else 0.0), label + " stationed food status comes from local stock")
	sim._drain_siege_food()
	check(state.cities[0].food_storage == 10000, label + " siege ration remains isolated even with wealthy capital")
	check(state.cities[1].food_storage == (98 if local_food > 0 else 0),
		label + " local formation pays its establishment ration plus fixed siege clock exactly once")
	check(army.supply_ratio == (1.0 if local_food > 0 else 0.0), label + " siege clock preserves local food rule")
	check(state.rng.state == rng_before, label + " local supply preserves random stream")
	var result := fingerprint(data)
	sim.free()
	return result


func test_cut_route(sliced: bool) -> PackedByteArray:
	var data := fixture("arrived", 0, true)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army: Army = data.army
	var rng_before := state.rng.state
	var label := "cut rear route sliced=%s" % sliced
	check(Pathfinding.supply_sources(state, army).is_empty(), label + " hostile rear road genuinely disconnects warehouse")
	await resolve_supply(sim, sliced)
	check(army.supply_ratio == 0.0 and army.starving, label + " inaccessible national food leaves field formation unsupplied")
	check(state.cities[0].food_storage == 10000, label + " inaccessible capital inventory is untouched")
	sim._drain_siege_food()
	sim._apply_supply_pressure()
	check(army.supply_ratio == 0.0 and army.morale < army.max_morale, label + " real shortage applies normal supply pressure")
	check(state.rng.state == rng_before, label + " cut-route settlement preserves random stream")
	var result := fingerprint(data)
	sim.free()
	return result


func run() -> void:
	for position in ["arrived", "approaching"]:
		for food in [0, 100]:
			var sync := await test_reachable(position, food, false)
			var sliced := await test_reachable(position, food, true)
			check(sync == sliced, "%s local=%d complete supply/clock/combat outcome is byte-equivalent across drivers" % [position, food])
	for food in [0, 100]:
		var sync := await test_isolated(food, false)
		var sliced := await test_isolated(food, true)
		check(sync == sliced, "inside local=%d complete local ration outcome is byte-equivalent across drivers" % food)
	var cut_sync := await test_cut_route(false)
	var cut_sliced := await test_cut_route(true)
	check(cut_sync == cut_sliced, "cut-route supply and shortage outcome is byte-equivalent across drivers")
	for failure in failures:
		printerr("FIELD_BATTLE_SUPPLY_FAIL ", failure)
	print("FIELD_BATTLE_SUPPLY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
