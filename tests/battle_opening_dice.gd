extends SceneTree

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_fixed_dice()
	_test_combat()
	_test_siege_lifecycle()
	_test_snapshot()
	_test_distribution()
	await _test_counter_conquest_equivalence()
	for message in failures:
		push_error(message)
	print("BATTLE_OPENING_DICE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _counter_fixture() -> Dictionary:
	var state := GameState.new()
	state.world_seed = 73
	state.rng.seed = 73
	for owner in range(2):
		var nation := Nation.new()
		nation.id = owner
		nation.name = ["秦", "赵"][owner]
		nation.capital_city_id = owner
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.granary_food = 1000000
		nation.warehouse_city_ids = [owner] as Array[int]
		state.nations.append(nation)
		var city := City.new()
		city.id = owner
		city.name = ["函谷", "邯郸"][owner]
		city.owner_nation = owner
		city.is_capital = true
		city.has_warehouse = true
		city.food_storage = 1000000
		city.garrison_manpower = 3000
		city.map_position = Vector2(owner, 0)
		state.cities.append(city)
		state.adjacency[owner] = [] as Array[int]
		state.recognized_city_owners.append(owner)
		state.administrative_center_by_city.append(owner)
		state.administrative_center_city_ids.append(owner)
		state.region_ids.append(0)
	state._add_edge(0, 1)
	state.edge_of(0, 1).distance = 1
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var war_id := state.war_id_between(0, 1)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.paused = true
	var guard := _army(0)
	guard.owner_nation = 0
	guard.size = 5000
	guard.max_size = 5000
	guard.location_city = 0
	guard.move_from = 0
	guard.campaign_war_id = war_id
	var counter := _army(1)
	counter.owner_nation = 1
	counter.size = 100000
	counter.max_size = 100000
	counter.location_city = 1
	counter.move_from = 1
	counter.campaign_war_id = war_id
	counter.path = [0] as Array[int]
	counter.state = Army.State.MOVING
	state.armies.assign([guard, counter])
	sim._begin_next_leg(counter)
	return {"state": state, "sim": sim, "war_id": war_id}

func _test_counter_conquest_equivalence() -> void:
	var first := _counter_fixture()
	var second := _counter_fixture()
	var field_seen := false
	var assault_seen := false
	Combat.battle_log_enabled = true
	Combat.clear_battle_log()
	for day in range(1, 161):
		first.state.day = day
		second.state.day = day
		first.sim._advance_movement()
		await second.sim._advance_movement_over_frames()
		for context in [first, second]:
			context.sim._resolve_eliminated_nation_capitulations()
			ChronicleRules.finalize_pending(context.state)
		_check(var_to_bytes(NativeSnapshotBuilder.build(first.state)) == var_to_bytes(NativeSnapshotBuilder.build(second.state)), "synchronous/sliced movement and active dice snapshots are identical day=%d" % day)
		for record in Combat.battle_log:
			field_seen = field_seen or bool(record.battle_context.uses_field_combat_rules)
			assault_seen = assault_seen or not bool(record.battle_context.uses_field_combat_rules)
		if not first.state.nations[0].alive:
			break
	_check(field_seen and assault_seen, "counter-conquest actually runs city field and garrison assault")
	_check(not first.state.nations[0].alive and first.state.cities[0].owner_nation == 1, "declared defender moves, captures capital, and eliminates initiator")
	_check(first.state.chronicle_events.size() == 1, "counter-conquest writes exactly one final chronicle")
	if first.state.chronicle_events.size() == 1:
		var event: Dictionary = first.state.chronicle_events[0]
		_check(str(event.views[1]).contains("破之") and str(event.views[1]).ends_with("灭秦为郡"), "victorious defender chronicle preserves reverse-conquest result")
		_check(str(event.views[0]).contains("败绩") and str(event.views[0]).ends_with("国除"), "defeated initiator chronicle records extinction")
	_check(bool(CombatLog.replay_records(Combat.battle_log).ok), "real counter-conquest four-dice log replays")
	Combat.battle_log_enabled = false
	Combat.clear_battle_log()
	first.sim.free()
	second.sim.free()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func _test_fixed_dice() -> void:
	var battle := Battle.new()
	battle.id = 71
	battle.ensure_opening_dice(12345, true)
	var first := battle.field_dice.duplicate()
	battle.ensure_opening_dice(54321, true)
	_check(first == battle.field_dice and battle.field_sequence == 1, "field dice are initialized once")
	battle.ensure_opening_dice(12345, false)
	var assault := battle.assault_dice.duplicate()
	battle.end_field_engagement()
	battle.ensure_opening_dice(12345, true)
	_check(battle.field_sequence == 2 and battle.assault_dice == assault, "relief field has a new sequence while assault dice persist")
	battle.invalidate_assault_dice()
	battle.ensure_opening_dice(12345, false)
	_check(battle.assault_sequence == 2, "new besieger creates a new assault sequence")
	var same := Battle.new()
	same.id = 71
	same.ensure_opening_dice(12345, true)
	_check(same.field_dice == first, "same seed and engagement reproduce all four dice")
	var forward: Array[Battle] = []
	var reverse: Array[Battle] = []
	for id in range(4):
		var item := Battle.new()
		item.id = id
		item.ensure_opening_dice(900, true)
		forward.append(item)
		var other := Battle.new()
		other.id = id
		reverse.append(other)
	for index in range(3, -1, -1):
		reverse[index].ensure_opening_dice(900, true)
	for index in range(4):
		_check(forward[index].field_dice == reverse[index].field_dice, "battle traversal order does not change dedicated dice")

func _army(id: int) -> Army:
	var army := Army.new()
	army.id = id
	army.size = 40000
	army.max_size = 40000
	army.morale = 2.0
	army.max_morale = 2.0
	return army

func _test_combat() -> void:
	for die in [0, 5, 10]:
		_check(is_equal_approx(Battle.dice_multiplier(die), 1.0 + die * 0.1), "inclusive dice multiplier")
	var battle := Battle.new()
	battle.edge = Edge.new()
	battle.edge.max_manpower = 15000
	battle.side_a = [_army(1)]
	battle.side_b = [_army(2)]
	battle.field_dice = PackedInt32Array([10, 0, 10, 0])
	battle.field_sequence = 1
	Combat.battle_log_enabled = true
	Combat.clear_battle_log()
	Combat.resolve_round(battle, 1)
	var record: Dictionary = Combat.battle_log[0]
	_check(record.frontline_strength_a == 30000 and record.frontline_strength_b == 15000, "side frontage may exceed terrain base but not dice-adjusted capacity")
	_check(is_equal_approx(record.effective_attack_a / record.effective_attack_b, 4.0), "attack and expansion apply once")
	_check(is_equal_approx(record.effective_defense_a / record.effective_defense_b, 2.0), "defense applies same performance die once")
	_check(battle.side_a[0].attack == 10 and battle.side_a[0].defense == 10, "base attributes remain unchanged")
	_check(record.casualties_a == 40000 - battle.side_a[0].size and record.casualties_b == 40000 - battle.side_b[0].size, "casualties match actual losses")
	_check(bool(CombatLog.replay_records(Combat.battle_log).ok), "four dice log replays")
	var old := Combat.battle_log.duplicate(true)
	old[0].combat_rules_version = 3
	_check(CombatLog.replay_records(old).errors[0].error == "incompatible_combat_rules", "version 3 battle logs explicitly rejected")
	var corrupt := Combat.battle_log.duplicate(true)
	corrupt[0].opening_dice[0] = 0.5
	_check(not bool(CombatLog.replay_records(corrupt).ok), "fractional dice cannot be silently truncated")
	corrupt = Combat.battle_log.duplicate(true)
	corrupt[0].battle_context.field_sequence = -1
	_check(not bool(CombatLog.replay_records(corrupt).ok), "negative engagement sequence is rejected")
	corrupt[0].battle_context.field_sequence = 0.5
	_check(not bool(CombatLog.replay_records(corrupt).ok), "fractional engagement sequence is rejected")
	corrupt[0].battle_context = []
	_check(not bool(CombatLog.replay_records(corrupt).ok), "malformed battle context returns validation failure")
	var before := battle.field_dice.duplicate()
	battle.side_a[0].funding_multiplier = 0.5
	battle.side_a[0].ruler_attack_multiplier = 5.0
	battle.side_a[0].ruler_defense_multiplier = 5.0
	Combat.resolve_round(battle, 2)
	var next: Dictionary = Combat.battle_log[-1]
	_check(battle.field_dice == before and is_equal_approx(next.effective_defense_a, 50.0), "payment and conqueror update independently of fixed dice without duplicate multiplier")
	Combat.battle_log_enabled = false
	Combat.clear_battle_log()
	var tiny := Battle.new()
	tiny.side_a = [_army(3)]
	tiny.side_b = [_army(4)]
	tiny.side_a[0].size = 1000
	tiny.side_b[0].size = 2000
	tiny.field_dice = PackedInt32Array([0, 0, 10, 10])
	Combat.battle_log_enabled = true
	Combat.resolve_round(tiny)
	_check(Combat.battle_log[0].frontline_strength_a == 1000 and Combat.battle_log[0].frontline_strength_b == 2000, "expanded frontage saturates at actual manpower")
	Combat.battle_log_enabled = false
	Combat.clear_battle_log()

func _test_distribution() -> void:
	var counts: Array = []
	for column in range(4):
		counts.append(PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	var distinct := 0
	for seed in range(10000):
		var battle := Battle.new()
		battle.id = 3
		battle.ensure_opening_dice(seed, true)
		for column in range(4):
			counts[column][battle.field_dice[column]] += 1
		if battle.field_dice[0] != battle.field_dice[1]:
			distinct += 1
	for column in range(4):
		for count in counts[column]:
			_check(count >= 750 and count <= 1070, "10000 seeds have approximately uniform dice distribution")
	_check(distinct > 8500, "symmetric sides do not receive forced equal dice")
	print("BATTLE_DICE_DISTRIBUTION seeds=10000 counts=%s" % str(counts))

func _test_siege_lifecycle() -> void:
	var state := GameState.new()
	state.generate_grid_world(13579)
	state.armies.clear()
	state.battles.clear()
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
	var city := state.cities[state.administrative_center_city_ids[0]]
	var owner := city.owner_nation
	var attacker := (owner + 1) % state.nations.size()
	state.set_diplomatic_relation(attacker, owner, GameState.DiplomaticRelation.WAR)
	var sim := Simulation.new()
	sim.state = state
	var army := _army(100)
	army.owner_nation = attacker
	army.size = 120000
	army.max_size = 120000
	army.location_city = city.id
	army.move_from = city.id
	army.state = Army.State.FIGHTING
	state.armies.append(army)
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city = city
	battle.side_a.append(army)
	battle.siege_attacker_nation = attacker
	army.battle_id = battle.id
	city.garrison_manpower = 30000
	sim._advance_siege(battle)
	_check(battle.assault_sequence == 1 and Battle.valid_dice(battle.assault_dice), "real assault starts its dice only when fighting garrison")
	var assault := battle.assault_dice.duplicate()
	var assault_size := army.size
	army.size = 1
	sim._advance_siege(battle)
	_check(battle.assault_dice == assault and battle.assault_sequence == 1, "insufficient manpower pauses assault without rerolling")
	army.size = assault_size
	var relief := _army(101)
	relief.owner_nation = owner
	relief.location_city = city.id
	relief.move_from = city.id
	state.armies.append(relief)
	sim._enter_battle(battle, relief, 2)
	sim._enter_battle(battle, relief, 2)
	sim._advance_siege(battle)
	_check(battle.field_sequence == 1 and battle.assault_dice == assault and battle.side_b.size() == 1, "relief engagement uses independent dice without resetting assault or duplicating arrivals")
	var field := battle.field_dice.duplicate()
	var reinforcement := _army(102)
	var ally := (owner + 3) % state.nations.size()
	state.set_diplomatic_relation(ally, owner, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(ally, attacker, GameState.DiplomaticRelation.WAR)
	reinforcement.owner_nation = ally
	reinforcement.location_city = city.id
	state.armies.append(reinforcement)
	sim._enter_battle(battle, reinforcement, 2)
	sim._advance_siege(battle)
	_check(battle.field_dice == field and battle.field_sequence == 1 and battle.side_b.has(reinforcement), "different nation reinforcement shares same engagement dice without rerolling")
	relief.morale = 0.01
	reinforcement.morale = 0.01
	sim._advance_siege(battle)
	_check(battle.field_dice.is_empty() and battle.side_b.is_empty(), "finished relief engagement clears only field dice")
	sim._advance_siege(battle)
	_check(battle.assault_dice == assault and battle.assault_sequence == 1, "resumed assault restores original dice")
	var next_relief := _army(103)
	next_relief.owner_nation = owner
	next_relief.location_city = city.id
	state.armies.append(next_relief)
	sim._enter_battle(battle, next_relief, 2)
	sim._advance_siege(battle)
	_check(battle.field_sequence == 2, "a new relief field engagement uses the next sequence")
	# Finish the defender engagement, then let an actual third party challenge.
	sim._release_army_from_administrative_battle(next_relief, battle)
	_check(battle.field_dice.is_empty() and battle.assault_dice == assault, "last opponent administrative exit releases only its field dice")
	sim._retreat_defender(next_relief, city)
	var third := (owner + 2) % state.nations.size()
	state.set_diplomatic_relation(third, attacker, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(third, owner, GameState.DiplomaticRelation.WAR)
	var challenger := _army(105)
	challenger.owner_nation = third
	challenger.location_city = city.id
	challenger.move_from = city.id
	challenger.size = 120000
	state.armies.append(challenger)
	sim._enter_battle(battle, challenger, 2)
	battle.side_b_defends_city = false
	battle.side_a[0].morale = 0.01
	sim._advance_siege(battle)
	_check(battle.field_dice.is_empty() and battle.assault_dice.is_empty(), "third party takeover cannot inherit either dice group")
	_check(battle.siege_attacker_nation == third and battle.side_a.has(challenger), "third party actually wins and takes over the siege")
	sim._advance_siege(battle)
	_check(battle.assault_sequence == 2 and Battle.valid_dice(battle.assault_dice), "new besieger starts a separate assault dice group")
	var block := state.new_battle(Battle.Kind.SIEGE)
	block.city = city
	block.siege_attacker_nation = attacker
	var tiny := _army(104)
	tiny.owner_nation = attacker
	tiny.size = 1
	tiny.location_city = city.id
	tiny.state = Army.State.FIGHTING
	block.side_a.append(tiny)
	city.garrison_manpower = 30000
	sim._advance_siege(block)
	_check(block.assault_dice.is_empty() and block.assault_sequence == 0, "blockade does not roll assault dice")
	sim._finish_battle_administratively(battle)
	_check(battle.field_dice.is_empty() and battle.assault_dice.is_empty(), "administrative exit releases dice without rolling")
	sim.free()

func _test_snapshot() -> void:
	var state := GameState.new()
	state.generate_grid_world(13579)
	var battle := state.new_battle(Battle.Kind.FIELD)
	var rng_before := state.rng.state
	battle.ensure_opening_dice(state.world_seed, true)
	var snapshot := NativeSnapshotBuilder.build(state)
	_check(snapshot.schema_version == 22 and NativeSnapshotBuilder.battle_validation_error(snapshot.battles).is_empty(), "snapshot validates fixed dice")
	_check(state.rng.state == rng_before, "opening dice never consume global random stream")
	var restored := Battle.new()
	restored.id = battle.id
	restored.field_dice = snapshot.battles.field_dice[0].duplicate()
	restored.field_sequence = snapshot.battles.field_sequence[0]
	restored.ensure_opening_dice(999, true)
	_check(restored.field_dice == battle.field_dice and restored.field_sequence == 1, "restored active battle retains its dice instead of rolling again")
	var before := var_to_bytes(snapshot)
	battle.field_dice[0] = (battle.field_dice[0] + 1) % 11
	_check(before != var_to_bytes(NativeSnapshotBuilder.build(state)), "fingerprint covers fixed dice")
	snapshot.battles.field_dice[0][0] = 11
	_check(not NativeSnapshotBuilder.battle_validation_error(snapshot.battles).is_empty(), "snapshot rejects out of range dice")
	snapshot.battles.field_dice[0] = PackedInt32Array([0, 0])
	_check(not NativeSnapshotBuilder.battle_validation_error(snapshot.battles).is_empty(), "snapshot rejects incomplete dice groups")
	snapshot.battles.field_sequence = [0.5]
	_check(not NativeSnapshotBuilder.battle_validation_error(snapshot.battles).is_empty(), "snapshot rejects malformed sequence column")
	snapshot.battles.field_dice = 5
	_check(not NativeSnapshotBuilder.battle_validation_error(snapshot.battles).is_empty(), "snapshot rejects malformed dice column without runtime error")
