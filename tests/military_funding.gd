extends SceneTree
var failures: Array[String] = []
var checks := 0
func _init() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(62011)
	var sim := Simulation.new()
	sim.setup(state)
	var army := state.armies[0]
	var nation := state.nations[army.owner_nation]
	nation.ruler_archetype = RulerProfile.CONQUEROR
	nation.ruler_traits.clear()
	var base := Vector2(army.attack, army.defense)
	for payment in [0.0, 0.5, 1.0, 2.0]:
		nation.military_payment_ratio = payment
		state.refresh_derived()
		var expected := 0.5 + 0.5 * clampf(payment, 0, 1)
		_check(is_equal_approx(army.combat_attack(), base.x * 5 * expected), "payment attack applied once")
		_check(is_equal_approx(float(army.call("combat_defense")), base.y * 5 * expected), "payment defense applied once")
		_check(Vector2(army.attack, army.defense) == base, "base stats preserved")
		_check(is_equal_approx(ArmyPower.effective(army), army.size * sqrt(base.x * base.y) / 10 * 5 * expected), "planning power matches paid quality")
		var army_power := 0.0
		for owned_army in state.armies:
			if owned_army.owner_nation == nation.id:
				army_power += ArmyPower.effective(owned_army)
		_check(is_equal_approx(DiplomacyAI._national_power(state, nation.id), army_power + state.cities_of(nation.id).size() * 1500.0), "diplomatic power uses funded armies with unchanged city value")
	nation.military_payment_ratio = 0
	state.refresh_derived()
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city = state.cities[nation.capital_city_id]
	var defender := sim._attach_city_garrison(battle)
	_check(defender != null and is_equal_approx(defender.combat_attack(), 5.0), "virtual garrison funding attack")
	_check(defender != null and is_equal_approx(float(defender.call("combat_defense")), 5.0), "virtual garrison funding defense")
	var full_power := ArmyPower.city_garrison_defense(state, (nation.id + 1) % state.nations.size(), battle.city.id)
	nation.military_payment_ratio = 1
	state.refresh_derived()
	_check(is_equal_approx(ArmyPower.city_garrison_defense(state, (nation.id + 1) % state.nations.size(), battle.city.id), full_power * 2), "ultimatum garrison uses same funding")
	var other := (nation.id + 1) % state.nations.size()
	state.nations[other].military_payment_ratio = 0
	state.nations[other].ruler_archetype = RulerProfile.BALANCED
	state.nations[other].ruler_traits.clear()
	state.transfer_army_ownership(army, other)
	_check(is_equal_approx(army.combat_attack(), base.x * 0.5), "ownership updates funding immediately")
	var peer := state.create_army(other, state.nations[other].capital_city_id, 15000)
	_check(peer != null and is_equal_approx(peer.combat_attack(), 5.0), "creation applies owner funding")
	sim._sync_battle_ruler_modifiers(battle)
	_check(is_equal_approx(defender.combat_attack(), 10.0), "live battle sync refreshes payment")
	_test_logs_and_history(state, sim, army, peer)
	_test_monthly_finance(state, sim, army)
	_test_mirror_and_annexation()
	_test_funded_sorting()
	sim.free()
	for message in failures:
		push_error(message)
	print("MILITARY_FUNDING checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_logs_and_history(state: GameState, sim: Simulation, army: Army, peer: Army) -> void:
	var history := PoliticalHistory.new()
	state.nations[0].military_payment_ratio = 0.25
	history.reset(state)
	state.nations[0].military_payment_ratio = 1
	_check(is_equal_approx(history.build_view_state(state, 0).nations[0].military_payment_ratio, 0.25), "history keeps old payment ratio")
	var field := Battle.new()
	field.side_a.append(army)
	field.side_a.append(peer)
	var opponent := Army.new()
	opponent.owner_nation = 0
	opponent.id = 9999
	opponent.size = 15000
	opponent.morale = 2
	field.side_b.append(opponent)
	sim._sync_battle_ruler_modifiers(field)
	_check(army.funding_multiplier == 0.5 and opponent.funding_multiplier == 1, "each participant uses own nation payment")
	Combat.clear_battle_log()
	Combat.battle_log_enabled = true
	CombatFixture.resolve_round(field)
	var records := Combat.battle_log.duplicate(true)
	state.nations[army.owner_nation].military_payment_ratio = 1
	sim._sync_battle_ruler_modifiers(field)
	var replay := CombatLog.replay_records(records)
	_check(bool(replay.ok), "funding log replays independently of current payment: %s" % str(replay))
	_check(records[0].combat_rules_version == 4 and records[0].participants_a[0].funding_multiplier == 0.5, "version 4 logs actual funding")
	var old := records.duplicate(true)
	old[0].combat_rules_version = 2
	_check(CombatLog.replay_records(old).errors[0].error == "incompatible_combat_rules", "version 2 explicitly rejected")
	records[0].participants_a[0].erase("funding_multiplier")
	_check(CombatLog.replay_records(records).errors[0].error == "missing_field", "incomplete funding logs rejected")
	Combat.battle_log_enabled = false
	Combat.clear_battle_log()
func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func _test_monthly_finance(state: GameState, sim: Simulation, army: Army) -> void:
	var owner := state.nations[army.owner_nation]
	var flows: Array[Dictionary] = []
	for nation in state.nations:
		flows.append({"military_upkeep": 100, "field_army_upkeep": 100, "garrison_upkeep": 0})
	for cash in [0, 50, 100, 200]:
		owner.treasury_gold = cash
		sim._resolve_military_finance(flows)
		state.refresh_derived()
		_check(owner.military_payment_ratio == minf(cash / 100.0, 1.0), "monthly actual payment ratio")
		_check(owner.treasury_gold == maxi(cash - 100, 0), "military payment never borrows or overpays")
		_check(army.funding_multiplier == Army.funding_from_payment(owner.military_payment_ratio), "month settlement updates derived army quality")
	flows[owner.id].military_upkeep = 0
	owner.treasury_gold = 0
	sim._resolve_military_finance(flows)
	state.refresh_derived()
	_check(owner.military_payment_ratio == 1 and army.funding_multiplier == 1, "no military cost defaults to full funding")
	var snapshot := NativeSnapshotBuilder.build(state)
	_check(snapshot.schema_version == NativeSnapshotBuilder.SCHEMA_VERSION and snapshot.nations.payment_ratio[owner.id] == 1, "schema 23 persists payment ratio")
	_check(not snapshot.armies.has("funding_multiplier"), "derived funding is not persisted")

func _test_mirror_and_annexation() -> void:
	var results: Array[Dictionary] = []
	for mirrored in [false, true]:
		var battle := Battle.new()
		for group in range(2):
			var side: Array[Army] = battle.side_b if (group == 0) == mirrored else battle.side_a
			for member in range(3):
				var army := Army.new()
				army.size = 10000 + member * 1000
				army.morale = 2
				army.funding_multiplier = Army.funding_from_payment((0.25 if group == 0 else 0.75) + member * 0.1)
				side.append(army)
		var rng := RandomNumberGenerator.new()
		rng.seed = 62013
		CombatFixture.resolve_round(battle)
		results.append({"a": battle.side_size(battle.side_a), "b": battle.side_size(battle.side_b), "ma": battle.side_a[0].morale, "mb": battle.side_b[0].morale})
	_check(results[0].a == results[1].b and results[0].b == results[1].a, "mixed funding casualties mirror exactly")
	_check(is_equal_approx(results[0].ma, results[1].mb) and is_equal_approx(results[0].mb, results[1].ma), "mixed funding shared morale mirrors")
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(62013)
	state.nations[0].military_payment_ratio = 0.5
	state.nations[0].ruler_archetype = RulerProfile.BALANCED
	state.nations[0].ruler_traits.clear()
	var army := state.create_army(1, state.nations[1].capital_city_id, 15000)
	var raw := Vector2(army.attack, army.defense)
	_check(state.annex_nation(0, 1), "annexation fixture succeeds")
	_check(army.owner_nation == 0 and army.funding_multiplier == 0.75, "annexed armies immediately use absorber payment")
	_check(Vector2(army.attack, army.defense) == raw, "annexation does not contaminate base attributes")

func _test_funded_sorting() -> void:
	var weak := Army.new()
	var strong := Army.new()
	weak.size = 15000
	strong.size = 15000
	weak.funding_multiplier = 0.5
	weak.morale = 2
	strong.morale = 2
	var side: Array[Army] = [weak, strong]
	Combat._canonicalize_side(side)
	_check(side[0] == strong, "physical sort uses funded attack")
	strong.attack = 5
	Combat._canonicalize_side(side)
	_check(side[0] == strong, "physical sort uses funded defense when attack ties")
	strong.defense = 5
	var priority := {weak: 0, strong: 1}
	Combat._canonicalize_side(side, priority)
	_check(side[0] == weak, "equal physical values respect frontline priority")
	Combat._canonicalize_side(side, priority)
	_check(side[0] == weak, "already ordered fast path preserves priority")
