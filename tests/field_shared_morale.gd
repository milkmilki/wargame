extends SceneTree

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	if "--benchmark" in OS.get_cmdline_user_args():
		_benchmark()
		quit(0)
		return
	_test_pool(false)
	_test_pool(true)
	_test_reinforcements()
	_test_supply_and_removal()
	_test_collective_rout()
	_test_garrison_rules()
	_test_join_and_replay()
	_test_real_unified_retreat()
	_test_city_entry_shared_morale()
	_test_full_battle_trace()
	if failures.is_empty():
		print("FIELD_SHARED_MORALE_OK checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("FIELD_SHARED_MORALE_FAIL: " + failure)
		quit(1)


func _army(id: int, size: int, morale: float, maximum: float = 2.0, modifier: float = 1.0) -> Army:
	var army := Army.new()
	army.id = id
	army.size = size
	army.max_size = size
	army.morale = morale
	army.max_morale = maximum
	army.ruler_morale_multiplier = modifier
	army.state = Army.State.FIGHTING
	return army


func _battle(first: Array[Army], second: Array[Army], city: bool = false) -> Battle:
	var battle := Battle.new()
	battle.side_a = first
	battle.side_b = second
	battle.edge = Edge.new()
	battle.edge.max_manpower = 10000
	if city:
		battle.kind = Battle.Kind.SIEGE
		battle.city = City.new()
	return battle


func _round(battle: Battle) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 713
	CombatFixture.resolve_round(battle)


func _test_pool(reverse: bool) -> void:
	var exhausted := _army(1, 10000, 0.0)
	var fresh := _army(2, 10000, 2.0, 4.0, 1.5)
	var reserve := _army(3, 10000, 1.0)
	var side: Array[Army] = [exhausted, fresh, reserve]
	if reverse:
		side.reverse()
	var battle := _battle(side, [_army(4, 30000, 1.0)])
	_round(battle)
	_check(battle.side_a.has(exhausted) and battle.routed_a.is_empty(), "zero-morale formation shares the side's morale rather than routing alone")
	_check(_close(exhausted.morale / exhausted.max_morale, fresh.morale / fresh.max_morale)
		and _close(reserve.morale / reserve.max_morale, fresh.morale / fresh.max_morale), "mixed maxima and ruler modifiers share one remaining ratio")
	_check(reserve.size == 10000 and reserve.morale < 1.0, "unengaged reserves share morale loss without taking casualties")


func _test_reinforcements() -> void:
	var veteran := _army(1, 10000, 0.4)
	var recruit := _army(2, 10000, 2.0)
	var battle := _battle([veteran, recruit], [_army(3, 20000, 1.0)])
	battle.reinforce_fresh_a.append(recruit)
	_round(battle)
	_check(_close(veteran.morale, recruit.morale) and veteran.morale < 1.2, "fresh reinforcement merges by weight without an extra boost")
	var split := _battle([_army(11, 10000, 0.4), _army(12, 5000, 2.0), _army(13, 5000, 2.0)], [_army(14, 20000, 1.0)])
	split.reinforce_fresh_a.assign([split.side_a[1], split.side_a[2]])
	_round(split)
	_check(_close(split.side_a[0].morale, veteran.morale), "splitting a same-round reinforcement does not change shared morale")
	var old := battle.shared_morale_summary(battle.side_a)
	var delayed := _army(6, 5000, 0.8)
	var expected_ratio := (float(old.capacity) * float(old.ratio) + float(delayed.size) * delayed.combat_morale()) / (float(old.capacity) + float(delayed.size) * delayed.combat_max_morale())
	battle.side_a.append(delayed)
	battle.reinforce_fresh_a.append(delayed)
	_round(battle)
	_check(veteran.morale / veteran.max_morale < expected_ratio and _close(veteran.morale / veteran.max_morale, delayed.morale / delayed.max_morale), "later-round arrivals merge with the depleted current side, without resetting its morale or bonus allowance")
	var tired := _battle([_army(21, 10000, 1.6), _army(22, 10000, 0.4)], [_army(23, 20000, 1.0)])
	_round(tired)
	_check(tired.side_a[0].morale < 1.0 and _close(tired.side_a[0].morale, tired.side_a[1].morale), "low-morale reinforcement can lower collective morale")


func _test_supply_and_removal() -> void:
	var first := _army(1, 10000, 1.0)
	var second := _army(2, 10000, 1.0)
	var battle := _battle([first, second], [_army(3, 20000, 1.0)])
	_round(battle)
	var previous := first.morale
	var sim := Simulation.new()
	sim._accrue_supply_pressure(first, 1.0)
	_round(battle)
	_check(first.morale < previous and _close(first.morale, second.morale), "supply pressure enters the next shared result and is not overwritten")
	var departing := first.morale
	battle.remove_army(first)
	_round(battle)
	_check(first.morale == departing, "administrative exit does not receive later shared losses")
	sim.free()


func _test_collective_rout() -> void:
	var weak := _army(1, 10000, 0.02)
	var support := _army(2, 10000, 1.0)
	var battle := _battle([weak, support], [_army(3, 20000, 1.0)])
	_round(battle)
	_check(not battle.finished and battle.side_a.size() == 2 and battle.routed_a.is_empty(), "one weak formation cannot independently leave a healthy side")
	weak.morale = 0.14
	support.morale = 0.14
	_round(battle)
	_check(battle.finished and battle.winner_side == 2 and battle.side_a.size() == 2 and battle.routed_a.is_empty(), "collective defeat retains all survivors for unified settlement")
	var draw := _battle([_army(5, 10000, 0.14)], [_army(6, 10000, 0.14)])
	_round(draw)
	_check(draw.finished and draw.winner_side == 0, "simultaneous symmetric collapse is a draw")
	var empty := _battle([_army(7, 0, 1.0)], [_army(8, 10000, 1.0)])
	_round(empty)
	_check(empty.finished and empty.winner_side == 2, "annihilation still ends the engagement")
	var city := _battle([_army(9, 10000, 0.02), _army(10, 10000, 1.0)], [_army(11, 20000, 1.0)], true)
	_round(city)
	_check(city.side_a.size() == 2 and city.routed_a.is_empty(), "real-army city engagements use collective morale")


func _test_garrison_rules() -> void:
	var broken := _army(1, 10000, 0.02)
	var healthy := _army(2, 10000, 1.0)
	var garrison := _army(3, 20000, 1.0, 1.0)
	garrison.is_city_garrison = true
	var siege := _battle([broken, healthy], [garrison], true)
	Combat.battle_log_enabled = true
	Combat.clear_battle_log()
	CombatFixture.resolve_round(siege)
	_check(siege.routed_a.has(broken) and not siege.side_a.has(broken), "virtual-garrison assault retains individual routing")
	_check(bool(CombatLog.replay_records(Combat.battle_log).ok), "garrison assault logs preserve initially routed participants for replay")
	Combat.battle_log_enabled = false
	Combat.clear_battle_log()


func _test_join_and_replay() -> void:
	var first := _army(1, 10000, 0.4, 2.0, 1.5)
	first.owner_nation = 0
	var enemy := _army(2, 20000, 1.0, 3.0, 0.8)
	enemy.owner_nation = 1
	var battle := _battle([first], [enemy], true)
	battle.id = 100
	var arrival := _army(3, 10000, 2.0)
	arrival.owner_nation = 0
	var sim := Simulation.new()
	sim.state = GameState.new()
	sim.state.battles.append(battle)
	sim._enter_battle(battle, arrival, 1)
	sim._enter_battle(battle, arrival, 1)
	var other := _battle([], [])
	other.id = 101
	sim._enter_battle(other, arrival, 1)
	_check(not other.has_army(arrival) and arrival.battle_id == battle.id, "a participant cannot simultaneously enter another engagement")
	_check(battle.side_a.size() == 2 and battle.reinforce_fresh_a.size() == 1, "city reinforcements use the common duplicate-safe entry")
	_check(first.morale == 0.4 and arrival.morale == 2.0, "entry does not prematurely change existing or incoming morale")
	var small_max := _army(51, 10000, 0.01, 0.1)
	var large_max := _army(52, 10000, 0.4, 4.0)
	var victors: Array[Army] = [small_max, large_max]
	sim._award_field_victory(victors)
	sim._finish_field(victors, [] as Array[Army], battle.side_morale(victors))
	_check(small_max.state == Army.State.MOVING and large_max.state == Army.State.MOVING,
		"different individual morale maxima cannot make only part of the winning side retreat")
	Combat.battle_log_enabled = true
	Combat.clear_battle_log()
	CombatFixture.resolve_round(battle)
	var records := Combat.battle_log.duplicate(true)
	_check(bool(CombatLog.replay_records(records).ok), "shared battle logs replay mixed maxima and ruler modifiers exactly")
	_check(float(records[0].battle_context.shared_ratio_without_arrivals_a) < float(records[0].battle_context.shared_ratio_before_a), "log distinguishes morale before and after arrivals merge")
	records[0].erase("combat_rules_version")
	var old := CombatLog.replay_records(records)
	_check(not bool(old.ok) and old.errors[0].error == "incompatible_combat_rules", "old combat logs are explicitly rejected")
	Combat.battle_log_enabled = false
	Combat.clear_battle_log()
	battle.finished = true
	var late := _army(4, 10000, 2.0)
	late.state = Army.State.IDLE
	sim._enter_battle(battle, late, 1)
	_check(not battle.has_army(late) and late.state == Army.State.IDLE, "a completed engagement cannot be revived by reinforcements")
	sim.free()


func _test_real_unified_retreat() -> void:
	var state := GameState.new()
	state.generate_grid_world(74410)
	state.armies.clear()
	state.battles.clear()
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var sim := Simulation.new()
	sim.setup(state)
	var battle := state.new_battle(Battle.Kind.FIELD)
	var origin := -1
	var target := -1
	for pair in state.territorial_border_pairs():
		if state.cities[pair.x].owner_nation == 0 and state.cities[pair.y].owner_nation == 1:
			battle.edge = state.edge_of(pair.x, pair.y)
			origin = pair.x
			target = pair.y
			break
	_check(battle.edge != null, "retreat fixture has a real frontier route")
	if battle.edge == null:
		sim.free()
		return
	for index in range(3):
		var owner := 0 if index < 2 else 1
		var army := _army(index, 10000, 0.14 if owner == 0 else 1.0)
		army.owner_nation = owner
		army.battle_id = battle.id
		army.on_edge = true
		army.move_from = origin if owner == 0 else target
		army.move_to = target if owner == 0 else origin
		army.location_city = army.move_from
		army.move_progress = 0.5
		state.armies.append(army)
		if owner == 0:
			battle.side_a.append(army)
		else:
			battle.side_b.append(army)
	sim._resolve_battles()
	_check(state.armies[0].state == Army.State.RETREATING and state.armies[1].state == Army.State.RETREATING,
		"all defeated survivors begin real retreat in the same resolution batch")
	_check(state.armies[0].battle_id == -1 and state.armies[1].battle_id == -1 and state.battles.is_empty(), "unified settlement leaves no old active participant references")
	_check(state.armies[2].size > 10000 - 1000, "winning survivor receives the existing establishment reward")
	var snapshot := NativeSnapshotBuilder.build(state)
	_check(snapshot.schema_version == 22 and not snapshot.battles.has("reinforcement_morale_a"), "snapshot drops obsolete reinforcement counters")
	sim.free()


func _test_city_entry_shared_morale() -> void:
	var state := GameState.new()
	state.generate_grid_world(74410)
	state.armies.clear()
	state.battles.clear()
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var city := state.cities_of(1)[0]
	var sim := Simulation.new()
	sim.setup(state)
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city = city
	battle.siege_attacker_nation = 0
	battle.side_b_defends_city = true
	for index in range(4):
		var owner := 0 if index < 2 else 1
		var army := _army(index, 10000, 0.02 if index % 2 == 0 else 1.0)
		army.owner_nation = owner
		army.battle_id = battle.id
		army.location_city = city.id
		army.move_from = city.id
		state.armies.append(army)
		if owner == 0:
			battle.side_a.append(army)
		else:
			battle.side_b.append(army)
	var stale := _army(99, 10000, 0.02)
	stale.owner_nation = 1
	stale.location_city = city.id
	stale.move_from = city.id
	stale.battle_id = 999
	state.armies.append(stale)
	sim._resolve_battles()
	_check(battle.side_a.size() == 2 and battle.side_b.size() == 2, "siege shell cannot withdraw individual members before the real field round")
	_check(state.armies[0].state == Army.State.FIGHTING and state.armies[2].state == Army.State.FIGHTING,
		"existing low-morale attackers and defenders remain in the collective engagement")
	_check(_close(state.armies[0].morale, state.armies[1].morale) and _close(state.armies[2].morale, state.armies[3].morale), "city resolution projects shared morale on both complete sides")
	_check(stale.state == Army.State.RETREATING, "invalid fighting state cannot shelter an unfit nonparticipant from city evacuation")
	sim.free()


func _benchmark() -> void:
	var first: Array[Army] = []
	var second: Array[Army] = []
	for index in range(80):
		first.append(_army(index, 15000, 2.0))
		second.append(_army(100 + index, 15000, 2.0))
	var battle := _battle(first, second)
	battle.field_dice = PackedInt32Array([0, 0, 0, 0])
	battle.field_sequence = 1
	var elapsed := 0
	var peak := 0
	for iteration in range(3200):
		for army in first + second:
			army.size = 15000
			army.morale = 2.0
		battle.finished = false
		battle.winner_side = 0
		var started := Time.get_ticks_usec()
		Combat.resolve_round(battle, iteration)
		var duration := Time.get_ticks_usec() - started
		if iteration >= 200:
			elapsed += duration
			peak = maxi(peak, duration)
	print("FIELD_SHARED_BENCH rounds=3000 armies=160 average_us=%.3f peak_us=%d" % [float(elapsed) / 3000.0, peak])


func _test_full_battle_trace() -> void:
	var first: Array[Army] = []
	var second: Array[Army] = []
	for index in range(4):
		first.append(_army(index, 15000, 1.0))
	for index in range(3):
		second.append(_army(100 + index, 15000, 1.0))
	var battle := _battle(first, second)
	var individual_routs := 0
	while not battle.finished and battle.round_no < 2000:
		_round(battle)
		individual_routs += battle.routed_a.size() + battle.routed_b.size()
	_check(battle.finished and individual_routs == 0, "a complete reserve-heavy field battle converges without individual routs")
	print("FIELD_SHARED_TRACE rounds=%d casualties_a=%d casualties_b=%d individual_routs=%d winner=%d" % [
		battle.round_no, 60000 - battle.side_size(battle.side_a), 45000 - battle.side_size(battle.side_b), individual_routs, battle.winner_side])


func _close(first: float, second: float) -> bool:
	return absf(first - second) < 0.000000001


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
