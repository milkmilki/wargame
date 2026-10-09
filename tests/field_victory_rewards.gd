extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	_test_road_reward()
	_test_allied_rewards(false)
	_test_allied_rewards(true)
	_test_caps_and_nonparticipants()
	_test_draw_and_annihilation()
	_test_city_engagements()
	_test_virtual_garrison_has_no_reward()
	_test_real_round_and_report()
	if failures.is_empty():
		print("FIELD_VICTORY_REWARDS_OK")
		quit(0)
	else:
		for failure in failures:
			push_error("FIELD_VICTORY_REWARDS_FAIL: " + failure)
		quit(1)


func _test_road_reward() -> void:
	var f := _fixture()
	var winner := _army(f, 0, 12000, 15000, 0.6)
	var loser := _army(f, 1, 10000, 15000, 0.1)
	f.battle.side_a = [winner] as Array[Army]
	f.battle.side_b = [loser] as Array[Army]
	f.battle.winner_side = 1
	f.battle.finished = true
	f.sim._finish_field_battle(f.battle)
	_check(winner.size == 13500 and is_equal_approx(winner.morale, 1.0), "road winner gains 10% maximum troops and 20% maximum morale")
	_check(loser.size == 2000, "victory reward does not change the loser's pursuit loss")
	_check(winner.max_size == 15000 and winner.state == Army.State.MOVING, "victory preserves establishment and forward movement")
	f.sim.free()


func _test_allied_rewards(reverse: bool) -> void:
	var f := _fixture()
	f.state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	var first := _army(f, 0, 800, 1000, 0.6)
	var second := _army(f, 2, 1500, 2000, 0.6)
	var loser := _army(f, 1, 125, 1000, 0.1)
	var victors: Array[Army] = [first, second]
	if reverse:
		victors.reverse()
	f.battle.side_a = victors
	f.battle.side_b = [loser] as Array[Army]
	f.battle.winner_side = 1
	f.battle.finished = true
	if reverse:
		first.id = 9002
		second.id = 9001
	f.sim._finish_field_battle(f.battle)
	_check(first.size == 900 and second.size == 1700 and loser.size == 25,
		"allied victors each receive their own establishment reward independent of army IDs/order and loser size")
	_check(first.owner_nation == 0 and second.owner_nation == 2, "allied armies retain separate ownership")
	f.sim.free()


func _test_caps_and_nonparticipants() -> void:
	var f := _fixture()
	var wounded := _army(f, 0, 14800, 15000, 1.9)
	var full := _army(f, 0, 15000, 15000, 0.6)
	var dead := _army(f, 0, 0, 15000, 0.6)
	var exhausted := _army(f, 0, 10000, 15000, 0.0)
	var retreating := _army(f, 0, 10000, 15000, 0.6)
	retreating.forced_retreat = true
	var waiting := _army(f, 0, 10000, 15000, 0.6)
	waiting.state = Army.State.IDLE
	var loser := _army(f, 1, 10000, 15000, 0.1)
	f.battle.side_a = [wounded, full, full, dead, exhausted, retreating] as Array[Army]
	f.battle.side_b = [loser] as Array[Army]
	f.battle.winner_side = 1
	f.battle.finished = true
	f.sim._finish_field_battle(f.battle)
	_check(wounded.size == 15000 and wounded.morale == wounded.max_morale, "both rewards cap at establishment and maximum morale")
	_check(full.size == 15000 and is_equal_approx(full.morale, 1.0), "full formations still receive morale but no extra troops")
	_check(dead.size == 0 and is_equal_approx(dead.morale, 0.6), "dead armies are not resurrected")
	_check(exhausted.size == 11500 and is_equal_approx(exhausted.morale, 0.4), "reward adds maximum-morale percentage instead of multiplying zero morale")
	_check(retreating.size == 10000 and is_equal_approx(retreating.morale, 0.6), "forced-retreat winners receive no reward and keep retreating")
	_check(waiting.size == 10000 and is_equal_approx(waiting.morale, 0.6), "armies outside the battle receive no reward")
	f.sim.free()


func _test_draw_and_annihilation() -> void:
	var f := _fixture()
	var first := _army(f, 0, 10000, 15000, 0.6)
	var second := _army(f, 1, 10000, 15000, 0.6)
	f.battle.side_a = [first] as Array[Army]
	f.battle.side_b = [second] as Array[Army]
	f.battle.finished = true
	f.sim._finish_field_battle(f.battle)
	_check(first.size == 2000 and second.size == 2000 and is_equal_approx(first.morale, 0.6) and is_equal_approx(second.morale, 0.6), "draw awards neither side")
	f.sim.free()
	f = _fixture()
	first = _army(f, 0, 12000, 15000, 0.6)
	second = _army(f, 1, 0, 15000, 0.0)
	f.battle.side_a = [first] as Array[Army]
	f.battle.side_b = [second] as Array[Army]
	f.battle.winner_side = 1
	f.battle.finished = true
	f.sim._finish_field_battle(f.battle)
	_check(first.size == 13500 and is_equal_approx(first.morale, 1.0), "victory reward is independent of the defeated army's surviving manpower")
	f.sim.free()


func _test_city_engagements() -> void:
	for winning_side in [1, 2]:
		var f := _fixture(Battle.Kind.SIEGE)
		var attacker := _army(f, 0, 12000, 15000, 0.6)
		var defender := _army(f, 1, 12000, 15000, 0.6)
		f.battle.side_a = [attacker] as Array[Army]
		f.battle.side_b = [defender] as Array[Army]
		f.battle.side_b_defends_city = true
		f.battle.winner_side = winning_side
		f.battle.finished = true
		var winner := attacker if winning_side == 1 else defender
		f.sim._finish_siege_field_engagement(f.battle)
		_check(winner.size == 13500 and is_equal_approx(winner.morale, 1.0), "city attacker and defender receive the same real-field reward")
		if winning_side == 1:
			f.battle.city.garrison_manpower = 100000
			f.sim._advance_siege(f.battle)
			_check(winner.size == 13500 and is_equal_approx(winner.morale, 1.0), "blockade does not repeat the previous field reward")
			var relief := _army(f, 1, 10000, 15000, 0.1)
			f.battle.side_b = [relief] as Array[Army]
			f.battle.winner_side = 1
			f.battle.finished = true
			f.sim._finish_siege_field_engagement(f.battle)
			_check(winner.size == 15000 and is_equal_approx(winner.morale, 1.4), "a later distinct field engagement may earn its own reward")
		f.sim.free()


func _test_virtual_garrison_has_no_reward() -> void:
	var f := _fixture(Battle.Kind.SIEGE)
	var attacker := _army(f, 0, 12000, 15000, 0.6)
	f.battle.side_a = [attacker] as Array[Army]
	f.battle.city.garrison_manpower = 1
	f.sim._advance_siege(f.battle)
	_check(f.battle.finished and f.battle.winner_side == 1, "virtual garrison fixture really captures the city")
	_check(attacker.size <= 12000 and attacker.morale <= 0.6, "virtual garrison victory gives neither field morale nor manpower rewards")
	f.sim.free()


func _test_real_round_and_report() -> void:
	for kind in [Battle.Kind.FIELD, Battle.Kind.SIEGE]:
		var f := _fixture(kind)
		var winner := _army(f, 0, 12000, 15000, 0.6)
		var loser := _army(f, 1, 2000, 15000, 0.06)
		var waiting := _army(f, 0, 10000, 15000, 0.6)
		waiting.state = Army.State.IDLE
		var front := f.state.create_campaign_front(f.state.war_id_between(0, 1), [0] as Array[int], 0,
			CoalitionCampaignFront.Mode.OFFENSE, f.state.administrative_center_of(f.target)) as CoalitionCampaignFront
		for army in [winner, waiting]:
			army.campaign_front_id = front.front_id
			army.campaign_war_id = front.war_id
			front.army_assignments[army.id] = front.center_city_id
		f.battle.side_a = [winner] as Array[Army]
		f.battle.side_b = [loser] as Array[Army]
		f.battle.side_b_defends_city = kind == Battle.Kind.SIEGE
		Combat.battle_log_enabled = true
		Combat.clear_battle_log()
		f.sim._resolve_battles()
		_check(not Combat.battle_log.is_empty(), "real round must be logged")
		if Combat.battle_log.is_empty():
			Combat.battle_log_enabled = false
			f.sim.free()
			continue
		var entry: Dictionary = Combat.battle_log[-1]
		_check(int(entry.winner_or_draw) == 1, "real combat must actually award victory to the expected side")
		var surviving: Dictionary = entry.participants_after_a[0]
		_check(winner.size == mini(15000, int(surviving.size) + 1500) and is_equal_approx(winner.morale, minf(2.0, float(surviving.morale) + 0.4)),
			"real road/city combat awards the survivor after actual round losses")
		_check(not front.combat_report_locked and front.reported_effective_manpower == winner.size + waiting.size,
			"post-field report includes the winner's reward without altering the remote army")
		_check(waiting.size == 10000 and is_equal_approx(waiting.morale, 0.6), "same-front nonparticipant receives no reward")
		var size_before := winner.size
		var morale_before := winner.morale
		if kind == Battle.Kind.SIEGE:
			f.battle.city.garrison_manpower = 100000
		f.sim._resolve_battles()
		_check(winner.size == size_before and winner.morale == morale_before, "later resolve batches cannot repeat an already completed field reward")
		Combat.battle_log_enabled = false
		Combat.clear_battle_log()
		f.sim.free()


func _fixture(kind: int = Battle.Kind.FIELD) -> Dictionary:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(74410)
	state.armies.clear()
	state.battles.clear()
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var edge: Edge
	var origin := -1
	var target := -1
	for pair in state.territorial_border_pairs():
		if state.cities[pair.x].owner_nation == 0 and state.cities[pair.y].owner_nation == 1:
			edge = state.edge_of(pair.x, pair.y)
			origin = pair.x
			target = pair.y
			break
	if kind == Battle.Kind.SIEGE:
		for center_id in state.administrative_center_city_ids:
			if state.cities[center_id].owner_nation == 1:
				target = center_id
				origin = state.neighbors(target)[0]
				edge = state.edge_of(origin, target)
				break
	if edge == null:
		push_error("FIELD_VICTORY_REWARDS_FAIL: no frontier edge")
		quit(1)
	var sim := Simulation.new()
	sim.setup(state)
	var battle := state.new_battle(kind)
	battle.edge = edge
	if kind == Battle.Kind.SIEGE:
		battle.city = state.cities[target]
		battle.siege_attacker_nation = 0
	return {"state": state, "sim": sim, "battle": battle, "origin": origin, "target": target}


func _army(f: Dictionary, owner: int, size: int, maximum: int, morale: float) -> Army:
	var army := Army.new()
	army.id = 744100 + f.state.armies.size()
	army.owner_nation = owner
	army.size = size
	army.max_size = maximum
	army.max_morale = 2.0
	army.morale = morale
	army.state = Army.State.FIGHTING
	army.battle_id = f.battle.id
	army.move_from = f.origin if owner != 1 else f.target
	army.move_to = f.target if owner != 1 else f.origin
	army.location_city = army.move_from
	army.on_edge = f.battle.kind == Battle.Kind.FIELD
	army.move_progress = 0.5
	if f.battle.kind == Battle.Kind.SIEGE:
		army.location_city = f.battle.city.id
		army.move_from = army.location_city
		army.move_to = -1
	f.state.armies.append(army)
	return army


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
