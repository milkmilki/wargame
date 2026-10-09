extends SceneTree

var checks := 0
var failures := 0


func _init() -> void:
	var strategy = load("res://scripts/core/regional_strategy.gd")
	check(strategy.has_method("integration_war_bonus"), "regional integration bonus must exist")
	if not strategy.has_method("integration_war_bonus"):
		finish()
		return
	var state := fixture()
	var bonus := float(strategy.integration_war_bonus(state, 0, 1))
	check(is_equal_approx(bonus, 0.8 + 2.2 * pow(27.0 / 29.0, 2)), "27/29 completion bonus")
	check(bonus > 2.7 and bonus <= 3.0, "last regional remnant receives strong bounded benefit")
	var geometry_builds := RegionalStrategy.geometry_build_count
	for _query in range(20):
		strategy.integration_war_bonus(state, 0, 1)
	check(RegionalStrategy.geometry_build_count == geometry_builds, "bonus reuses geographic index")
	state.cities[26].owner_nation = 1
	state.ownership_revision += 1
	check(float(strategy.integration_war_bonus(state, 0, 1)) < bonus, "completion incentive increases with progress")
	state.cities[28].owner_nation = 2
	state.ownership_revision += 1
	check(float(strategy.integration_war_bonus(state, 0, 1)) > float(strategy.integration_war_bonus(state, 0, 2)), "larger outstanding share receives larger benefit")
	state.region_ids[28] = 9
	state.region_analysis_revision += 1
	check(is_zero_approx(float(strategy.integration_war_bonus(state, 0, 2))), "outside region has no integration bonus")
	state.suzerainty[1] = {"overlord_id": 0, "civil_war": false}
	state.diplomacy_revision += 1
	check(is_zero_approx(float(strategy.integration_war_bonus(state, 0, 1))), "peaceful vassal integration has no war incentive")
	state.suzerainty[1]["civil_war"] = true
	state.diplomacy_revision += 1
	check(float(strategy.integration_war_bonus(state, 0, 1)) > 0.0, "civil war separates the integration systems")
	_test_diplomacy_cache()
	_test_legal_preparation_and_gates()
	_test_wartime_counteroffense_policy()
	finish()


func _test_diplomacy_cache() -> void:
	var ai = load("res://scripts/ai/diplomacy_ai.gd")
	check(ai.has_method("_cached_integration_war_bonus"), "diplomacy uses a batch-cached integration benefit")
	if not ai.has_method("_cached_integration_war_bonus"):
		return
	var state := fixture()
	var cache := {}
	var before := float(ai._cached_integration_war_bonus(state, 0, 1, cache))
	check(is_equal_approx(before, float(ai._cached_integration_war_bonus(state, 0, 1, cache))), "repeated query is equivalent")
	state.nations[0].strategic_region_anchor_city_id = 28
	state.cities[28].owner_nation = 2
	state.cities[27].owner_nation = 2
	state.ownership_revision += 1
	state.region_ids[28] = 4
	state.region_analysis_revision += 1
	state.regional_strategy_revision += 1
	check(is_zero_approx(float(ai._cached_integration_war_bonus(state, 0, 1, cache))), "strategy change invalidates cached bonus")
	state.nations[0].strategic_region_anchor_city_id = 0
	state.regional_strategy_revision += 1
	state.cities[27].owner_nation = 0
	state.ownership_revision += 1
	check(is_zero_approx(float(ai._cached_integration_war_bonus(state, 0, 1, cache))), "completed region clears cached benefit")


func _test_legal_preparation_and_gates() -> void:
	var state := fixture()
	for nation in state.nations:
		nation.treasury_gold = 1000000
		nation.manpower_pool = 1000000
		nation.granary_food = 1000000
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
	state.day = 1000
	for owner in [0, 1]:
		var army := Army.new()
		army.id = owner
		army.owner_nation = owner
		army.location_city = 26 + owner
		army.move_from = army.location_city
		army.size = 15000
		army.max_size = 15000
		army.morale = 100.0
		state.armies.append(army)
	var cache := {}
	var score := DiplomacyAI.war_desire(state, 0, 1, cache)
	if score == -INF:
		print("INTEGRATION_GATE_DIAGNOSTIC range=%s declaration=%s objective=%s resources=%s" % [
			DiplomacyAI.can_initiate_war_at_range(state, 0, 1, {}), state.can_alliance_declare_war(0, 1),
			DiplomacyAI.select_war_objective(state, 0, 1), DiplomacyAI.resource_report(state, 0)])
	check(score >= DiplomacyAI.WAR_DECLARE_SCORE, "legal regional remnant passes declaration willingness")
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(state, actions, {}, {}, 0, 1)
	check(actions.any(func(action: Dictionary) -> bool:
		return int(action["kind"]) == DiplomacyAI.Action.PREPARE_WAR), "willingness creates a real preparation action")
	state.nations[0].ruler_archetype = RulerProfile.DIPLOMAT
	check(DiplomacyAI.war_desire(state, 0, 1, {}) == -INF, "diplomat's ordinary conquest remains forbidden")
	state.nations[0].ruler_archetype = RulerProfile.BALANCED
	state.truce_until_day[state._diplomacy_key(0, 1)] = state.day + 90
	check(DiplomacyAI.war_desire(state, 0, 1, {}) == -INF, "integration cannot bypass truce")
	print("REGIONAL_INTEGRATION_METRIC integrated=27 total=29 bonus=%.6f desire=%.6f preparation_actions=%d" % [
		float(load("res://scripts/core/regional_strategy.gd").integration_war_bonus(state, 0, 1)), score, actions.size()])


func _test_wartime_counteroffense_policy() -> void:
	var state := fixture()
	state.nations[0].ruler_archetype = RulerProfile.DIPLOMAT
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_war_objective(0, 1, 28, "original declaration under previous ruler")
	var sim := Simulation.new()
	sim.setup(state)
	var component: Dictionary = {}
	for candidate in state.coalition_campaign_components():
		if (candidate["members"] as Array[int]).has(0):
			component = candidate
	check(sim._select_component_objective(component, {}, {}).is_empty(), "war counteroffense does not give diplomat ordinary conquest permission")
	state.recognized_city_owners[27] = 0
	state.ownership_revision += 1
	check(not sim._select_component_objective(component, {}, {}).is_empty(), "diplomat retains existing legal reclamation exception")
	sim.free()


func fixture() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	for id in range(3):
		var nation := Nation.new()
		nation.id = id
		nation.capital_city_id = 0 if id == 0 else 28
		nation.strategic_region_anchor_city_id = 0
		state.nations.append(nation)
	for id in range(29):
		var city := City.new()
		city.id = id
		city.owner_nation = 0 if id < 27 else 1
		city.map_position = Vector2(id, 0)
		city.gold_per_month = 1000
		city.food_per_half_year = 100000
		city.manpower_per_month = 1000
		city.garrison_manpower = 1000
		state.cities.append(city)
		if id in [0, 28]:
			city.has_warehouse = true
			city.food_storage = 1000000
			state.nations[city.owner_nation].warehouse_city_ids.append(id)
		state.adjacency[id] = [] as Array[int]
		state.region_ids.append(0)
		state.administrative_center_by_city.append(28 if id == 27 else id)
		if id != 27:
			state.administrative_center_city_ids.append(id)
		state.recognized_city_owners.append(city.owner_nation)
		if id > 0:
			state._add_edge(id - 1, id)
	for a in range(3):
		for b in range(a + 1, 3):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	return state


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func finish() -> void:
	print("REGIONAL_INTEGRATION_DESIRE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
