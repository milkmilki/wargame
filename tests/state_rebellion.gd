extends SceneTree

var failures: int = 0


func _init() -> void:
	_test_monthly_state_uprising()
	_test_one_fu_cannot_rebel()
	_test_state_direction_and_foreign_control()
	_test_locks_and_cooldown()
	_test_adjacent_states_stay_separate()
	_test_transaction_scope()
	_test_rebellion_ends_old_city_battle()
	_test_counter_reset_and_snapshot()
	_test_mirrored_uprisings()
	print("STATE_REBELLION_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)


func _test_monthly_state_uprising() -> void:
	var state := fixture()
	var events: Array[Dictionary] = []
	for month in range(1, 4):
		state.day = month * 30
		events = RebellionSystem.resolve_month(state)
		if month < 3:
			check(events.is_empty(), "wait for three low-loyalty state months")
			check(state.cities[2].get("administrative_rebellion_progress") == month, "center stores state progress")
	check(events.size() == 1, "one state creates one uprising")
	if events.size() != 1:
		return
	var rebel := int(events[0].get("rebel_id", -1))
	check(events[0].get("city_ids") == [2, 3, 4], "uprising contains center and every owned Fu")
	check(state.nations[rebel].capital_city_id == 2, "rebel capital is the state center")
	for city_id in [2, 3, 4]:
		check(state.cities[city_id].owner_nation == rebel and state.recognized_owner_of(city_id) == 0, "control changes but legal title stays")
	check(state.cities[2].get("administrative_rebellion_progress") == 0, "new owner does not inherit rebellion progress")
	check(state.cities[7].owner_nation == 0 and state.cities[8].owner_nation == 0, "dock and inactive land stay outside uprising")
	check(state.nations[0].alive and state.territory_structure_valid(), "parent and territory remain valid")
	var snapshot := NativeSnapshotBuilder.build(state)
	check(snapshot["cities"].has("administrative_rebellion_progress"), "native snapshot records state progress")


func _test_one_fu_cannot_rebel() -> void:
	var state := fixture()
	state.cities[2].loyalty = 75.0
	state.cities[4].loyalty = 75.0
	for month in range(1, 5):
		state.day = month * 30
		check(RebellionSystem.resolve_month(state).is_empty(), "one unhappy Fu does not take a loyal state")
	check(state.cities[3].rebellion_progress >= 3, "city discontent remains independently tracked")
	check(state.cities[2].get("administrative_rebellion_progress") == 0, "state average clears progress")
	state.cities[2].loyalty = 0.0
	state.cities[4].loyalty = 0.0
	state.day += 30
	check(RebellionSystem.resolve_month(state).is_empty(), "state needs its own fresh three-month period")


func _test_state_direction_and_foreign_control() -> void:
	var state := fixture()
	state.cities[2].loyalty_target_nation = 1
	state.cities[4].owner_nation = 1
	state.recognized_city_owners[4] = 1
	state.ownership_revision += 1
	var events: Array[Dictionary] = []
	for month in range(1, 4):
		state.day = month * 30
		events = RebellionSystem.resolve_month(state)
	check(events.size() == 1 and str(events[0].get("kind", "")) == "loyalty_target_restored", "center determines whole-state political direction")
	check(state.cities[2].owner_nation == 1 and state.cities[3].owner_nation == 1, "owned Fu follows center despite different city preferences")
	check(state.nations.size() == 2 and state.cities[4].owner_nation == 1, "third-party land is not reallocated")
	state = fixture()
	state.cities[2].owner_nation = 1
	state.recognized_city_owners[2] = 1
	state.ownership_revision += 1
	for month in range(1, 4):
		state.day = month * 30
		RebellionSystem.resolve_month(state)
	check(state.cities[3].owner_nation == 0 and state.cities[4].owner_nation == 0, "Fu cannot form a rebel state without its center")


func _test_locks_and_cooldown() -> void:
	var state := fixture()
	state.recognized_city_owners[3] = 1
	state.cities[3].occupation_sponsor_nation = 0
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	for month in range(1, 5):
		state.day = month * 30
		check(RebellionSystem.resolve_month(state).is_empty(), "wartime occupied Fu locks the state")
	check(state.cities[2].get("administrative_rebellion_progress") == 0, "occupation lock cannot accumulate hidden state progress")
	state = fixture()
	state.cities[4].rebellion_cooldown_until_day = 120
	for month in range(1, 4):
		state.day = month * 30
		check(RebellionSystem.resolve_month(state).is_empty(), "any owned Fu cooldown locks the state")
	state.day = 120
	check(RebellionSystem.resolve_month(state).is_empty(), "cooldown expiry starts a fresh period")
	check(state.cities[2].get("administrative_rebellion_progress") == 1, "state progress resumes after cooldown")
	state = fixture()
	for city_id in [0, 1]:
		state.cities[city_id].loyalty = 0.0
	for month in range(1, 4):
		state.day = month * 30
		RebellionSystem.resolve_month(state)
	check(state.cities[0].owner_nation == 0 and state.cities[1].owner_nation == 0, "capital state does not become an independent local rebel")


func _test_adjacent_states_stay_separate() -> void:
	var state := fixture()
	state.cities[5].loyalty = 0.0
	var events: Array[Dictionary] = []
	for month in range(1, 4):
		state.day = month * 30
		events = RebellionSystem.resolve_month(state)
	check(events.size() == 2, "adjacent low-loyalty states create separate uprisings")
	check(state.cities[2].owner_nation != state.cities[5].owner_nation, "connected roads do not merge state rebellions")
	state = fixture()
	state.edge_of(2, 3).max_manpower = 0
	for month in range(1, 4):
		state.day = month * 30
		events = RebellionSystem.resolve_month(state)
	check(events.size() == 1 and events[0].get("city_ids") == [2, 3, 4], "road closure alone does not split an existing administrative state")


func _test_transaction_scope() -> void:
	var state := fixture()
	check(state.start_regional_rebellion(0, [2, 3]) == -1, "partial-state creation is rejected")
	check(state.start_regional_rebellion(0, [2, 3, 4, 5]) == -1, "cross-state creation is rejected")
	check(state.start_regional_rebellion(0, [0, 1]) == -1, "capital state creation is rejected")
	check(state.nations.size() == 2, "rejected transactions do not create nations")
	state.cities[2].loyalty_target_nation = 1
	check(not state.restore_regional_loyalty_target(0, 1, [2]), "partial-state restoration is rejected")
	check(state.restore_regional_loyalty_target(0, 1, [4, 2, 3]), "whole-state restoration follows center")


func _test_rebellion_ends_old_city_battle() -> void:
	var state := fixture()
	state.day = 90
	state.cities[2].administrative_rebellion_progress = 2
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var battle := Battle.new()
	battle.id = 9
	battle.kind = Battle.Kind.SIEGE
	battle.city = state.cities[2]
	battle.side_b_defends_city = true
	var defender := Army.new()
	defender.id = 10
	defender.owner_nation = 0
	defender.location_city = 2
	defender.state = Army.State.FIGHTING
	defender.battle_id = 9
	defender.size = 15000
	defender.max_size = 15000
	defender.morale = 100.0
	var attacker := Army.new()
	attacker.id = 11
	attacker.owner_nation = 1
	attacker.location_city = 2
	attacker.state = Army.State.FIGHTING
	attacker.battle_id = 9
	attacker.size = 15000
	attacker.max_size = 15000
	attacker.morale = 100.0
	battle.side_a.append(attacker)
	battle.side_b.append(defender)
	state.armies.append_array([defender, attacker])
	state.battles.append(battle)
	var simulation := Simulation.new()
	simulation.setup(state)
	simulation._resolve_monthly_rebellions()
	check(state.cities[2].owner_nation == 2, "besieged legal state may politically rebel")
	check(battle.finished and not battle.has_army(defender), "old defenders are removed from obsolete siege")
	check(defender.size == 15000 and defender.battle_id == -1, "administrative departure causes no rout loss or stale reference")
	simulation.free()


func _test_counter_reset_and_snapshot() -> void:
	var state := fixture()
	var city := state.cities[2]
	city.administrative_rebellion_progress = 2
	var snapshot := NativeSnapshotBuilder.build(state)
	check(snapshot["cities"]["administrative_rebellion_progress"][2] == 2, "snapshot records exact state counter")
	var definition := MapDefinition.from_state(state)
	check(not definition["cities"][2].has("administrative_rebellion_progress"), "map export excludes runtime state counter")
	city.unrest = 100.0 - city.loyalty
	city.rebellion_cooldown_until_day = state.day + RebellionSystem.REBELLION_COOLDOWN_DAYS
	city.last_loyalty_reason = "state_reset"
	var result := state.apply_territory_transaction([{
		"city_id": 2, "controller_id": 0, "legal_owner_id": 0,
		"reset_political_target": true, "reason": "state_reset",
	}] as Array[Dictionary])
	check(bool(result.get("changed", false)) and city.administrative_rebellion_progress == 0, "political reset is not a no-op when only state counter differs")
	city.administrative_rebellion_progress = 3
	state.rebuild_administrative_regions()
	check(city.administrative_rebellion_progress == 0, "partition rebuild clears old state counter")
	state = fixture()
	var sections := MapRenderer.city_detail_sections(state, 0)
	var capital_explained := false
	for section in sections:
		for line in section["lines"]:
			capital_explained = capital_explained or str(line).contains("首都州不参与地方独立")
	check(capital_explained, "capital state exemption is visible")


func _test_mirrored_uprisings() -> void:
	var original := fixture()
	var mirrored := fixture()
	original.cities[5].loyalty = 0.0
	mirrored.cities[5].loyalty = 0.0
	for city in mirrored.cities:
		city.map_position.x = 1.0 - city.map_position.x
	for month in range(1, 4):
		original.day = month * 30
		mirrored.day = original.day
		RebellionSystem.resolve_month(original)
		RebellionSystem.resolve_month(mirrored)
	for city_id in range(original.cities.size()):
		check(original.cities[city_id].owner_nation == mirrored.cities[city_id].owner_nation, "mirrored uprising ordering preserves political identity")
		check(original.cities[city_id].administrative_rebellion_progress == mirrored.cities[city_id].administrative_rebellion_progress, "mirrored state counters match")


static func fixture() -> GameState:
	var state := GameState.new()
	for nation_id in range(2):
		var nation := Nation.new()
		nation.id = nation_id
		nation.capital_city_id = 0 if nation_id == 0 else 6
		nation.treasury_gold = 1000
		nation.manpower_pool = 3000
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
		state.nations.append(nation)
	for city_id in range(9):
		var city := City.new()
		city.id = city_id
		city.name = "City%d" % city_id
		city.owner_nation = 1 if city_id == 6 else 0
		city.map_position = Vector2(float(city_id) / 9.0, 0.5)
		city.is_capital = city_id in [0, 6]
		city.has_warehouse = city.is_capital
		city.food_storage = 100 if city.is_capital else 0
		city.gold_per_month = 10
		city.food_per_half_year = 300
		city.manpower_per_month = 100
		city.loyalty = 0.0 if city_id in [2, 3, 4] else 75.0
		city.loyalty_target_nation = city.owner_nation
		city.is_dock = city_id == 7
		city.politically_active = city_id != 8
		state.cities.append(city)
		state.recognized_city_owners.append(city.owner_nation)
		state.adjacency[city_id] = [] as Array[int]
	for city_id in range(6):
		var edge := Edge.new()
		edge.city_a = city_id
		edge.city_b = city_id + 1
		edge.max_manpower = 20000
		state.edges.append(edge)
		state.adjacency[city_id].append(city_id + 1)
		state.adjacency[city_id + 1].append(city_id)
		state.edge_lookup[state._edge_key(city_id, city_id + 1)] = edge
	state.administrative_center_by_city = PackedInt32Array([0, 0, 2, 2, 2, 5, 6, -1, -1])
	state.administrative_region_ids = PackedInt32Array([0, 0, 1, 1, 1, 2, 3, -1, -1])
	state.administrative_center_city_ids = PackedInt32Array([0, 2, 5, 6])
	state.administrative_region_count = 4
	state.region_ids = PackedInt32Array([0, 0, 0, 0, 0, 0, 1, -1, -1])
	state.refresh_derived()
	return state
