extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_test_blockade(0, 1)
	_test_blockade(1, 0)
	for message in failures:
		printerr("BLOCKADE_GARRISON_CAPACITY_FAIL ", message)
	print("BLOCKADE_GARRISON_CAPACITY checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _test_blockade(attacker_owner: int, defender_owner: int) -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(94108, 2, 200)
	_check(state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR), "nation zero declares the real war before either side besieges")
	state.armies.clear()
	state.battles.clear()
	var city: City = null
	for city_id in state.administrative_center_city_ids:
		if state.cities[city_id].owner_nation == defender_owner and city_id != state.nations[defender_owner].capital_city_id:
			city = state.cities[city_id]
			break
	_check(city != null, "fixture has a noncapital administrative center")
	if city == null:
		return
	city.garrison_manpower = 5000
	var attacker := Army.new()
	attacker.id = 94100
	attacker.owner_nation = attacker_owner
	attacker.size = 1000
	attacker.max_size = 15000
	attacker.morale = 2.0
	attacker.max_morale = 2.0
	attacker.location_city = state.adjacency[city.id][0]
	attacker.move_from = attacker.location_city
	attacker.move_to = city.id
	state.armies.append(attacker)
	var sim := Simulation.new()
	sim.setup(state)
	sim._start_or_join_siege(attacker, city, state.edge_of(attacker.move_from, city.id))
	_check(state.battles.size() == 1, "real siege entry creates a battle")
	if state.battles.is_empty():
		sim.free()
		return
	var battle: Battle = state.battles[0]
	var guard := sim._attach_city_garrison(battle)
	_check(guard != null and guard.max_size == 15000, "virtual guard uses city establishment")
	sim._detach_city_garrison(battle, guard)
	var revision := state.garrison_revision
	sim._resolve_battles()
	_check(city.garrison_manpower == 4970, "blockade loses 30 from a 15000 establishment, not 10 from 5000 survivors")
	_check(state.garrison_revision == revision + 1, "blockade updates the persistent garrison revision once")
	sim._resolve_battles()
	_check(city.garrison_manpower == 4940, "daily loss stays fixed as survivors decrease")
	_check(not battle.finished and battle.side_b.is_empty(), "blockade retains the persistent guard outside field combat")
	var defender := Army.new()
	defender.owner_nation = defender_owner
	defender.size = 1000
	battle.side_b.append(defender)
	battle.side_b_defends_city = true
	var before := city.garrison_manpower
	revision = state.garrison_revision
	sim._apply_blockade_garrison_attrition(battle)
	_check(city.garrison_manpower == before and state.garrison_revision == revision, "real field defenders suspend blockade attrition")
	battle.side_b.clear()
	battle.side_b_defends_city = false
	# Capture normally recruits the new owner's guard immediately; an empty pool
	# makes the zero-survivor boundary observable after the real transaction.
	state.nations[attacker_owner].manpower_pool = 0
	city.garrison_manpower = 7
	revision = state.garrison_revision
	sim._apply_blockade_garrison_attrition(battle)
	_check(city.garrison_manpower == 0, "remaining guard below the daily loss is clamped to zero")
	_check(battle.finished and battle.winner_side == 1, "zero guard finishes through the actual siege capture lifecycle")
	_check(city.owner_nation == attacker_owner, "actual capture transfers the city to the besieger in both attack directions")
	_check(attacker.battle_id == -1 and attacker.state != Army.State.FIGHTING, "captured siege releases the surviving besieger")
	var owner := city.owner_nation
	revision = state.garrison_revision
	sim._apply_blockade_garrison_attrition(battle)
	_check(city.owner_nation == owner and state.garrison_revision == revision, "finished siege cannot settle attrition again")
	sim.free()
