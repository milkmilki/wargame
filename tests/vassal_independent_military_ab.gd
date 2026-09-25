extends SceneTree
## A/B diagnostic: equal-territory peaceful vassals versus independent nations.

const SEED: int = 9142026
const FORCE_DAYS: int = 360
const WAR_DAYS: int = 3600
const SUBJECT_IDS: Array[int] = [1, 2, 3]
const FORCE_SUBJECT_IDS: Array[int] = [1, 2]

var _force_parity_passed: bool = false


func _init() -> void:
	print("==== Vassal / independent military A/B ====")
	var force_a := _build_state(true, false, FORCE_SUBJECT_IDS)
	var force_b := _build_state(false, false, [])
	_configure_external_war(force_a)
	_configure_external_war(force_b)
	_assert_equal_start(force_a, force_b)
	print("\n-- Controlled 360-day external war --")
	_run_force_pair(force_a, force_b)

	print("\n-- Internal war opportunity (diplomacy enabled) --")
	var war_a := _build_state(true, true, SUBJECT_IDS)
	var war_b := _build_state(false, true, [])
	_run_war_pair(war_a, war_b)
	print("force parity gate=%s" % ("PASS" if _force_parity_passed else "FAIL"))
	quit(0 if _force_parity_passed else 1)


func _build_state(
	as_vassals: bool,
	aggressive: bool,
	vassal_ids: Array[int]
) -> GameState:
	var state := GameState.new()
	state.generate_grid_world(SEED)
	# Keep the generated one-LINE-per-city baseline, but return all mobile MAIN
	# formations to manpower. Both arms must rebuild their field force.
	var retained_armies: Array[Army] = []
	for army in state.armies:
		if army.is_line_role():
			retained_armies.append(army)
		else:
			state.nations[army.owner_nation].manpower_pool += army.size
	state.armies = retained_armies
	for nation in state.nations:
		nation.battle_groups.clear()
		nation.food_demand_ema = 0.0
		nation.trade_policy = RulerProfile.POLICY_ISOLATION
		nation.ai_aggression = 2.0 if aggressive else 1.0
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				a, b, GameState.DiplomaticRelation.NEUTRAL
			)
	if as_vassals:
		_convert_to_one_realm(state, vassal_ids)
	state.refresh_derived()
	assert(state.territory_structure_valid())
	assert(state.suzerainty_structure_valid())
	return state


func _convert_to_one_realm(
	state: GameState,
	vassal_ids: Array[int]
) -> void:
	var root_id := 0
	var combined_food := 0
	var system_ids: Array[int] = [root_id]
	system_ids.append_array(vassal_ids)
	for nation_id in system_ids:
		for warehouse_id in state.nations[nation_id].warehouse_city_ids:
			combined_food += state.cities[warehouse_id].food_storage
	for subject_id in vassal_ids:
		state.suzerainty[subject_id] = {
			"overlord_id": root_id,
			"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
			"created_day": state.day,
			"last_centralization_day": -1,
			"civil_war": false,
		}
		for warehouse_id in state.nations[subject_id].warehouse_city_ids:
			state.cities[warehouse_id].has_warehouse = false
			state.cities[warehouse_id].food_storage = 0
		state.nations[subject_id].warehouse_city_ids.clear()
	for i in range(system_ids.size()):
		for j in range(i + 1, system_ids.size()):
			state.set_diplomatic_relation(
				system_ids[i], system_ids[j],
				GameState.DiplomaticRelation.ALLIED
			)
	var root_capital := state.nations[root_id].capital_city_id
	state.cities[root_capital].has_warehouse = true
	state.cities[root_capital].food_storage = combined_food
	state.nations[root_id].warehouse_city_ids = [root_capital] as Array[int]


func _configure_external_war(state: GameState) -> void:
	var target_city := state.nations[3].capital_city_id
	for attacker_id in [0, 1, 2]:
		for ally_id in [0, 1, 2]:
			if attacker_id < ally_id:
				state.set_diplomatic_relation(
					attacker_id, ally_id,
					GameState.DiplomaticRelation.ALLIED
				)
		state.set_diplomatic_relation(
			attacker_id, 3, GameState.DiplomaticRelation.WAR
		)
		state.set_war_objective(
			attacker_id, 3, target_city, "A/B controlled frontier war"
		)
	state.refresh_derived()


func _assert_equal_start(a: GameState, b: GameState) -> void:
	var total_a := _realm_totals(a)
	var total_b := _realm_totals(b)
	assert(total_a == total_b, "A/B initial realm resources differ: %s vs %s" % [total_a, total_b])
	for nation_id in SUBJECT_IDS:
		assert(
			a.land_cities_of(nation_id).size() == b.land_cities_of(nation_id).size()
		)
		assert(a.nations[nation_id].manpower_pool == b.nations[nation_id].manpower_pool)
		assert(a.nations[nation_id].treasury_gold == b.nations[nation_id].treasury_gold)
		assert(_troops(a, nation_id) == _troops(b, nation_id))
	print("initial totals=%s" % str(total_a))


func _run_force_pair(a: GameState, b: GameState) -> void:
	var sim_a := Simulation.new()
	var sim_b := Simulation.new()
	root.add_child(sim_a)
	root.add_child(sim_b)
	sim_a.setup(a)
	sim_b.setup(b)
	a.uses_heightmap = true
	b.uses_heightmap = true
	sim_a.diplomacy_enabled = false
	sim_b.diplomacy_enabled = false
	_print_force_snapshot(0, a, b, sim_a, sim_b)
	for day in range(1, FORCE_DAYS + 1):
		sim_a._advance_day()
		sim_b._advance_day()
		if day in [90, 180, FORCE_DAYS]:
			_print_force_snapshot(day, a, b, sim_a, sim_b)
	sim_a.free()
	sim_b.free()


func _print_force_snapshot(
	day: int,
	a: GameState,
	b: GameState,
	sim_a: Simulation,
	sim_b: Simulation
) -> void:
	for nation_id in FORCE_SUBJECT_IDS:
		var report_a := sim_a._food_security_report(nation_id)
		var report_b := sim_b._food_security_report(nation_id)
		print(
			(
				"day=%d nation=%d cities_A/B=%d/%d "
				+ "A[vassal troops=%d armies=%d mp=%d gold=%d direct_food=%d "
				+ "pool_stock=%d prod=%.1f demand=%.1f affordable=%d] "
				+ "B[independent troops=%d armies=%d mp=%d gold=%d food=%d "
				+ "stock=%d prod=%.1f demand=%.1f affordable=%d]"
			) % [
				day,
				nation_id,
				a.land_cities_of(nation_id).size(),
				b.land_cities_of(nation_id).size(),
				_troops(a, nation_id),
				a.active_army_count(nation_id),
				a.nations[nation_id].manpower_pool,
				a.nations[nation_id].treasury_gold,
				a.nations[nation_id].granary_food,
				report_a["stock"],
				report_a["monthly_production"],
				report_a["monthly_demand"],
				report_a["affordable_troops"],
				_troops(b, nation_id),
				b.active_army_count(nation_id),
				b.nations[nation_id].manpower_pool,
				b.nations[nation_id].treasury_gold,
				b.nations[nation_id].granary_food,
				report_b["stock"],
				report_b["monthly_production"],
				report_b["monthly_demand"],
				report_b["affordable_troops"],
			]
		)
	print(
		"day=%d compared_total A=%d B=%d ratio=%.3f" % [
			day,
			_troops_for_ids(a, FORCE_SUBJECT_IDS),
			_troops_for_ids(b, FORCE_SUBJECT_IDS),
			float(_troops_for_ids(a, FORCE_SUBJECT_IDS))
				/ float(maxi(_troops_for_ids(b, FORCE_SUBJECT_IDS), 1)),
		]
	)
	if day == 90:
		var ratio := (
			float(_troops_for_ids(a, FORCE_SUBJECT_IDS))
			/ float(maxi(_troops_for_ids(b, FORCE_SUBJECT_IDS), 1))
		)
		_force_parity_passed = ratio >= 0.8 and ratio <= 1.3


func _run_war_pair(a: GameState, b: GameState) -> void:
	var sim_a := Simulation.new()
	var sim_b := Simulation.new()
	root.add_child(sim_a)
	root.add_child(sim_b)
	sim_a.setup(a)
	sim_b.setup(b)
	var previous_a := _war_pairs(a, true)
	var previous_b := _war_pairs(b, false)
	var declarations_a := 0
	var declarations_b := 0
	var war_days_a := 0
	var war_days_b := 0
	for _day in range(WAR_DAYS):
		sim_a._advance_day()
		sim_b._advance_day()
		var current_a := _war_pairs(a, true)
		var current_b := _war_pairs(b, false)
		declarations_a += _new_pair_count(previous_a, current_a)
		declarations_b += _new_pair_count(previous_b, current_b)
		war_days_a += current_a.size()
		war_days_b += current_b.size()
		previous_a = current_a
		previous_b = current_b
	print(
		(
			"%d-day internal result A[vassal declarations=%d pair-war-days=%d] "
			+ "B[independent declarations=%d pair-war-days=%d]"
		) % [
			WAR_DAYS, declarations_a, war_days_a, declarations_b, war_days_b,
		]
	)
	print(
		"final subject troops A=%d B=%d; living realms A=%d B=%d" % [
			_subject_troops(a), _subject_troops(b),
			_living_count(a), _living_count(b),
		]
	)
	sim_a.free()
	sim_b.free()


func _war_pairs(state: GameState, vassal_only: bool) -> Dictionary:
	var result := {}
	var ids: Array[int] = SUBJECT_IDS.duplicate()
	if not vassal_only:
		ids = [0, 1, 2, 3] as Array[int]
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a := ids[i]
			var b := ids[j]
			if state.is_enemy(a, b):
				result["%d:%d" % [a, b]] = true
	return result


func _new_pair_count(previous: Dictionary, current: Dictionary) -> int:
	var count := 0
	for key in current:
		if not previous.has(key):
			count += 1
	return count


func _realm_totals(state: GameState) -> Dictionary:
	var manpower := 0
	var gold := 0
	var food := 0
	var troops := 0
	for nation in state.nations:
		manpower += nation.manpower_pool
		gold += nation.treasury_gold
		food += nation.granary_food
		troops += _troops(state, nation.id)
	return {"manpower": manpower, "gold": gold, "food": food, "troops": troops}


func _subject_troops(state: GameState) -> int:
	return _troops_for_ids(state, SUBJECT_IDS)


func _troops_for_ids(state: GameState, nation_ids: Array[int]) -> int:
	var total := 0
	for nation_id in nation_ids:
		total += _troops(state, nation_id)
	return total


func _troops(state: GameState, nation_id: int) -> int:
	var total := 0
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			total += army.size
	return total


func _living_count(state: GameState) -> int:
	var count := 0
	for nation in state.nations:
		if nation.alive:
			count += 1
	return count
