extends SceneTree

var checks := 0
var failures: Array[String] = []

func _init() -> void:
	_test_unrelated_peace()
	_test_access_revoked_during_field()
	_test_access_revoked_during_siege()
	_test_idle_repatriation()
	_test_control_transfer()
	_test_administrative_exit()
	_test_post_battle_revoked_destination()
	_test_old_battle_release()
	for message in failures:
		push_error("DIPLOMATIC_BATTLE_FAIL: " + message)
	print("DIPLOMATIC_BATTLE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _fixture() -> Dictionary:
	var state := GameState.new()
	for owner in range(4):
		var nation := Nation.new()
		nation.id = owner
		nation.capital_city_id = owner * 2
		state.nations.append(nation)
		for offset in range(2):
			var city := City.new()
			city.id = state.cities.size()
			city.owner_nation = owner
			city.map_position = Vector2(city.id * 10, 0)
			state.cities.append(city)
			state.adjacency[city.id] = [] as Array[int]
			state.region_ids.append(0)
			state.recognized_city_owners.append(owner)
			state.administrative_center_by_city.append(owner * 2)
		state.administrative_center_city_ids.append(owner * 2)
		state._add_edge(owner * 2, owner * 2 + 1)
	for endpoints in [Vector2i(0, 2), Vector2i(2, 4), Vector2i(0, 4), Vector2i(0, 6)]:
		state._add_edge(endpoints.x, endpoints.y)
	for first in range(4):
		for second in range(first + 1, 4):
			state.set_diplomatic_relation(first, second, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	var sim := Simulation.new()
	sim.setup(state)
	return {"state": state, "sim": sim}

func _army(data: Dictionary, owner: int, city_id: int) -> Army:
	var state: GameState = data.state
	var army := Army.new()
	army.id = state.armies.size()
	army.owner_nation = owner
	army.location_city = city_id
	army.move_from = city_id
	army.size = 15000
	army.max_size = 15000
	army.morale = 1.0
	army.max_morale = 1.0
	state.armies.append(army)
	return army

func _siege(data: Dictionary, army: Army) -> Battle:
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city = state.cities[4]
	battle.siege_attacker_nation = army.owner_nation
	battle.siege_claimant_nation = army.owner_nation
	sim._enter_battle(battle, army, 1)
	return battle

func _check_retained(army: Army, battle: Battle, label: String) -> void:
	_check(not battle.finished and battle.has_army(army), label + ": battle retains participant")
	_check(army.state == Army.State.FIGHTING and army.battle_id == battle.id, label + ": army retains battle state and reference")
	_check(army.size == 15000 and is_equal_approx(army.morale, 1.0), label + ": no administrative losses or rewards")

func _test_unrelated_peace() -> void:
	var data := _fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army := _army(data, 0, 4)
	var battle := _siege(data, army)
	state.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.NEUTRAL)
	sim._reconcile_battles_after_coalition_peace([0] as Array[int], [3] as Array[int])
	_check_retained(army, battle, "unrelated peace")
	sim._reconcile_battles_after_coalition_peace([0] as Array[int], [3] as Array[int])
	_check_retained(army, battle, "repeated peace")
	sim.free()

func _test_access_revoked_during_field() -> void:
	var data := _fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army := _army(data, 0, 2)
	army.move_to = 4
	army.on_edge = true
	army.move_progress = 0.5
	army.path.assign([2, 0])
	var edge := state.edge_of(2, 4)
	edge.passing_count = 1
	edge.occupied = true
	var enemy := _army(data, 2, 4)
	var battle := state.new_battle(Battle.Kind.FIELD)
	sim._enter_battle(battle, army, 1)
	sim._enter_battle(battle, enemy, 2)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	sim._repatriate_after_access_revoked(0, 1)
	_check_retained(army, battle, "third-party field after alliance exit")
	_check(army.on_edge and is_equal_approx(army.move_progress, 0.5) and edge.passing_count == 1, "alliance exit preserves actual battle position and edge occupancy")
	_check(army.path.is_empty(), "revoked future route is cleared without withdrawing current combat")
	_check_retained(enemy, battle, "opponent unaffected")
	sim.free()

func _test_access_revoked_during_siege() -> void:
	var data := _fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army := _army(data, 0, 4)
	army.path.assign([2, 0])
	var battle := _siege(data, army)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	sim._repatriate_after_access_revoked(0, 1)
	_check_retained(army, battle, "siege with revoked future route")
	_check(army.path.is_empty(), "siege future route cannot use former ally")
	sim.free()

func _test_idle_repatriation() -> void:
	var data := _fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army := _army(data, 0, 2)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	sim._repatriate_after_access_revoked(0, 1)
	_check(army.state == Army.State.RETREATING and army.diplomatic_repatriation and army.battle_id == -1, "idle former-ally garrison still repatriates")
	# Random road distances can make a transit city the first leg; the destination must be home.
	var home_goal: int = army.move_to if army.path.is_empty() else army.path.back()
	_check(army.on_edge and state.edge_of(2, army.move_to) != null and army.size == 15000 and home_goal >= 0 and state.cities[home_goal].owner_nation == 0, "repatriation starts a real route home without losses")
	sim.free()

func _test_control_transfer() -> void:
	var data := _fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	state.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.WAR)
	var army := _army(data, 0, 4)
	var battle := _siege(data, army)
	var defender := _army(data, 2, 4)
	sim._enter_battle(battle, defender, 2)
	battle.side_b_defends_city = true
	state.cities[4].owner_nation = 3
	sim._repatriate_after_territory_settlement([4] as Array[int])
	_check_retained(army, battle, "hostile third-party city transfer")
	_check(not battle.has_army(defender) and defender.battle_id != battle.id, "former city defender exits before territory repatriation")
	sim.free()

func _test_administrative_exit() -> void:
	var data := _fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army := _army(data, 0, 4)
	var battle := _siege(data, army)
	battle.routed_a.append(army)
	battle.frontline_priority_a[army] = 0
	sim._release_army_from_administrative_battle(army, battle)
	_check(not battle.has_army(army) and not battle.reinforce_fresh_a.has(army) and not battle.routed_a.has(army) and not battle.frontline_priority_a.has(army), "administrative exit removes all battle-side references")
	_check(army.battle_id == -1 and army.state != Army.State.FIGHTING, "administrative exit clears army reference")
	_check(army.size == 15000 and is_equal_approx(army.morale, 1.0), "administrative exit does not award or penalize combat resources")
	var position := [army.move_from, army.move_to, army.move_progress]
	sim._release_army_from_administrative_battle(army, battle)
	_check(position == [army.move_from, army.move_to, army.move_progress], "repeated administrative exit does not restart movement")
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.NEUTRAL)
	sim._reconcile_battles_after_coalition_peace([0] as Array[int], [2] as Array[int])
	_check(battle.finished and state.battle_by_id(battle.id) == null, "fully peaceful battle is removed")
	sim.free()

func _test_post_battle_revoked_destination() -> void:
	var data := _fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army := _army(data, 0, 0)
	army.move_to = 2
	army.on_edge = true
	army.move_progress = 0.5
	army.path.assign([3])
	var enemy := _army(data, 2, 2)
	var battle := state.new_battle(Battle.Kind.FIELD)
	sim._enter_battle(battle, army, 1)
	sim._enter_battle(battle, enemy, 2)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	sim._repatriate_after_access_revoked(0, 1)
	_check_retained(army, battle, "combat on revoked destination edge")
	battle.finished = true
	sim._resume_after_battle(army)
	army.move_progress = 1.0
	sim._arrive_at_node(army)
	_check(army.state == Army.State.RETREATING and army.move_to == 0, "after combat, neutral destination repatriates rather than continuing forbidden route")
	_check(not army.path.has(3) and army.battle_id == -1, "post-combat movement does not reuse revoked future path")
	sim.free()

func _test_old_battle_release() -> void:
	var data := _fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army := _army(data, 0, 4)
	var old_battle := _siege(data, army)
	old_battle.finished = true
	army.battle_id = -1
	var new_battle := state.new_battle(Battle.Kind.FIELD)
	sim._enter_battle(new_battle, army, 1)
	sim._release_army_from_administrative_battle(army, old_battle)
	_check(not old_battle.has_army(army), "old battle release removes its own references")
	_check_retained(army, new_battle, "old battle release preserves newer battle binding")
	sim.free()
