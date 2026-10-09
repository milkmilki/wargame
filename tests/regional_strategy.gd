extends SceneTree

var failures: int = 0


func _init() -> void:
	var script = load("res://scripts/core/regional_strategy.gd")
	if script == null:
		push_error("REGIONAL_STRATEGY_MISSING")
		quit(1)
		return
	var state := fixture()
	script.initialize_targets(state)
	check(script.target_region(state, 0) == 0, "initial owned region")
	check(script.integration_report(state, 0)["complete"], "owned region complete")
	check(not script.allows_objective(state, 0, 2), "outside ordinary goal rejected")
	state.recognized_city_owners[2] = 0
	state.ownership_revision += 1
	check(script.allows_objective(state, 0, 2), "legal reclamation allowed")
	state.recognized_city_owners[2] = 1
	state.ownership_revision += 1
	check(is_zero_approx(script.rivalry(state, 0, 1)), "separate interests have no rivalry")
	script.update_target(state, 0)
	check(script.target_region(state, 0) == 1, "ordinary monarch selects next region without waiting for succession")
	state.nations[0].ruler_traits = [RulerProfile.TRAIT_MARTIAL]
	script.update_target(state, 0)
	check(script.target_region(state, 0) == 1, "martial monarch selects similar neighbor")
	var anchor: int = state.nations[0].strategic_region_anchor_city_id
	state.nations[0].capital_city_id = 4
	script.update_target(state, 0)
	check(state.nations[0].strategic_region_anchor_city_id == anchor, "capital move preserves goal")
	state.region_ids[2] = 7
	state.region_ids[3] = 7
	state.region_analysis_revision += 1
	check(script.target_region(state, 0) == 7, "renumbering follows anchor")
	state.administrative_center_by_city[3] = 2
	state.region_ids[3] = 9
	state.administrative_region_revision += 1
	check(script.city_region(state, 3) == 7, "whole state follows its center")
	state.suzerainty[1] = {"overlord_id": 0, "civil_war": false}
	state.diplomacy_revision += 1
	check(script.integration_report(state, 0)["complete"], "peaceful vassal territory counts")
	state.suzerainty[1]["civil_war"] = true
	state.diplomacy_revision += 1
	check(not script.integration_report(state, 0)["complete"], "civil war splits integration")
	for latitude in [0.0, 18.0, 25.0, 40.0, 65.0, 90.0]:
		check(is_equal_approx(script.latitude_output_multiplier(latitude), script.latitude_output_multiplier(-latitude)), "latitude symmetry")
	check(is_equal_approx(script.latitude_output_multiplier(25.0), 1.0), "temperate peak")
	check(script.latitude_output_multiplier(0.0) < 1.0, "equatorial penalty")
	check(script.latitude_output_multiplier(90.0) > 0.0, "polar nonzero floor")
	check(script.latitude_output_multiplier(0.0) <= 0.35, "stronger low-latitude differentiation")
	check(script.latitude_output_multiplier(18.0) <= 0.60, "tropical margins below suitable latitudes")
	check(script.latitude_output_multiplier(45.0) <= 0.50, "higher latitude differentiation begins before polar regions")
	check(script.latitude_output_multiplier(65.0) <= 0.15, "stronger cold-latitude differentiation")
	_test_policy_and_snapshots()
	_test_succession_and_traits()
	_test_expansion_exclusions()
	_test_cache_identity()
	_test_partition_rebuild_cache()
	_test_environment_and_blocked_neighbors()
	_test_initialization_and_completion()
	_test_conqueror_economic_preference()
	_test_nested_suzerainty_index()
	_test_siege_budget_cache()
	print("REGIONAL_STRATEGY_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)


func _test_policy_and_snapshots() -> void:
	var state := fixture()
	RegionalStrategy.initialize_targets(state)
	var simulation := Simulation.new()
	simulation.state = state
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	check(not simulation._execute_diplomatic_action({"kind": DiplomacyAI.Action.DECLARE_WAR,
		"a": 0, "b": 1, "objective_city": 2}), "commit rejects outside declaration")
	check(not simulation._start_war_preparation(0, 1, {"objective_city": 2}), "outside preparation rejected")
	state.nations[0].war_preparation_target_nation = 1
	state.nations[0].war_preparation_objective_city = 2
	state.nations[0].war_preparation_objective_center_city = 2
	state.nations[0].war_preparation_started_day = -1000
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_existing_war_preparation(state, 0, actions, {})
	check(not actions.is_empty() and int(actions[0]["kind"]) == DiplomacyAI.Action.CANCEL_WAR_PREPARATION,
		"timeout cannot bypass region qualification")
	var before := RegionalStrategy.geometry_build_count
	RegionalStrategy.integration_report(state, 0)
	state.cities[2].owner_nation = 0
	state.ownership_revision += 1
	RegionalStrategy.integration_report(state, 0)
	check(RegionalStrategy.geometry_build_count == before, "ownership preserves geometry cache")
	var history := PoliticalHistory.new()
	history.reset(state)
	var old_anchor := state.nations[0].strategic_region_anchor_city_id
	state.nations[0].strategic_region_anchor_city_id = 2
	state.regional_strategy_revision += 1
	var historic := history.build_view_state(state, 0)
	check(historic.nations[0].strategic_region_anchor_city_id == old_anchor, "historical target preserved")
	var snapshot := NativeSnapshotBuilder.build(state)
	check((snapshot["nations"]["strategic_region_anchors"] as PackedInt32Array)[0] == 2, "native target encoded")
	simulation.free()


func _test_succession_and_traits() -> void:
	for trait_id in [RulerProfile.TRAIT_MARTIAL, RulerProfile.TRAIT_AMBITIOUS]:
		var state := fixture()
		RegionalStrategy.initialize_targets(state)
		state.nations[0].ruler_traits = [trait_id]
		RegionalStrategy.update_target(state, 0)
		check(RegionalStrategy.target_region(state, 0) == 1, "expansion trait " + trait_id)
	var state := fixture()
	RegionalStrategy.initialize_targets(state)
	RegionalStrategy.update_target(state, 0, true)
	check(RegionalStrategy.target_region(state, 0) == 1, "ordinary successor may choose next region")
	RegionalStrategy.update_target(state, 0, true)
	check(RegionalStrategy.target_region(state, 0) == 1, "unfinished goal inherited")
	state.nations[0].ruler_archetype = RulerProfile.GUARDIAN
	state.nations[0].ruler_traits = [RulerProfile.TRAIT_MARTIAL]
	state.nations[0].strategic_region_anchor_city_id = 0
	RegionalStrategy.update_target(state, 0)
	check(RegionalStrategy.target_region(state, 0) == 0, "offensive prohibition wins")
	state.administrative_center_by_city[3] = 2
	state.recognized_city_owners[3] = 0
	state.administrative_region_revision += 1
	state.ownership_revision += 1
	check(DiplomacyAI._ruler_allows_war_objective(state, 0, 2), "legal Fu recovery permits its state target")
	state.recognized_city_owners[3] = 1
	state.ownership_revision += 1
	state.nations[0].ruler_archetype = RulerProfile.CONQUEROR
	RegionalStrategy.update_target(state, 0)
	check(RegionalStrategy.target_region(state, 0) == 1, "conqueror expands")
	for id in [2, 3]:
		state.cities[id].owner_nation = 0
	state.ownership_revision += 1
	RegionalStrategy.update_target(state, 0)
	check(RegionalStrategy.target_region(state, 0) == 2, "conqueror continues across multiple regions")
	for edge in state.edges:
		edge.max_manpower = 0
	state.road_network_revision += 1
	RegionalStrategy.update_target(state, 0)
	check(RegionalStrategy.target_region(state, 0) == RegionalStrategy.initial_region(state, 0),
		"fully inaccessible unowned unfinished goal falls back to the current controlled region")


func _test_expansion_exclusions() -> void:
	for archetype in RulerProfile.ARCHETYPE_IDS:
		for trait_id in [""] + RulerProfile.TRAIT_IDS:
			var state := fixture()
			var nation := state.nations[0]
			nation.ruler_archetype = archetype
			if trait_id != "":
				nation.ruler_traits = [trait_id]
			RegionalStrategy.initialize_targets(state)
			var expected: bool = RulerProfile.offensive_allowed(nation) and trait_id != RulerProfile.TRAIT_CAUTIOUS
			var label := "%d/%s" % [archetype, trait_id]
			check(RegionalStrategy.can_expand(nation) == expected, "expansion exclusion policy " + label)
			RegionalStrategy.update_target(state, 0)
			check(RegionalStrategy.target_region(state, 0) == (1 if expected else 0), "completion switches only eligible ruler " + label)
			RegionalStrategy.update_target(state, 0, true)
			check(RegionalStrategy.target_region(state, 0) == (1 if expected else 0), "succession obeys new ruler exclusions " + label)
	var state := fixture()
	var nation := state.nations[0]
	nation.ruler_archetype = RulerProfile.CONQUEROR
	nation.ruler_traits = [RulerProfile.TRAIT_CAUTIOUS, RulerProfile.TRAIT_AMBITIOUS]
	RegionalStrategy.initialize_targets(state)
	RegionalStrategy.update_target(state, 0)
	check(RegionalStrategy.target_region(state, 0) == 0, "cautious wins over conqueror and ambitious")
	check(RegionalStrategy.allows_objective(state, 0, 0), "cautious still permits goals in its existing region")
	nation.ruler_archetype = RulerProfile.BALANCED
	nation.ruler_traits.clear()
	RegionalStrategy.update_target(state, 0)
	var anchor := nation.strategic_region_anchor_city_id
	var revision := state.regional_strategy_revision
	RegionalStrategy.update_target(state, 0)
	check(nation.strategic_region_anchor_city_id == anchor and state.regional_strategy_revision == revision,
		"unfinished new region does not switch or invalidate repeatedly")
	for id in [2, 3]:
		state.cities[id].owner_nation = 0
	state.ownership_revision += 1
	RegionalStrategy.update_target(state, 0)
	check(RegionalStrategy.target_region(state, 0) == 2, "ordinary ruler continues after completing its second region")


func _test_cache_identity() -> void:
	var state := fixture()
	RegionalStrategy.initialize_targets(state)
	state.nations[0].strategic_region_anchor_city_id = 2
	state.nations[1].strategic_region_anchor_city_id = 4
	var edge := Edge.new()
	edge.city_a = 2
	edge.city_b = 4
	edge.max_manpower = 100000
	state.edges.append(edge)
	state.adjacency[2].append(4)
	state.adjacency[4].append(2)
	state.edge_lookup[state._edge_key(2, 4)] = edge
	state.road_network_revision += 1
	var simulation := Simulation.new()
	simulation.state = state
	var cache := {}
	var outside := simulation._cached_campaign_objective(0, 2, cache)
	var inside := simulation._cached_campaign_objective(1, 2, cache)
	check(outside.is_empty() and not inside.is_empty(), "shared cache distinguishes proposing nation")
	simulation.free()


func _test_environment_and_blocked_neighbors() -> void:
	var state := fixture()
	RegionalStrategy.initialize_targets(state)
	state.nations[0].ruler_traits = [RulerProfile.TRAIT_MARTIAL]
	for edge in state.edges:
		edge.max_manpower = 0
	state.road_network_revision += 1
	RegionalStrategy.update_target(state, 0)
	check(RegionalStrategy.target_region(state, 0) == 0, "no reachable neighbor preserves completed goal")
	for id in [0, 1]:
		state.cities[id].map_position.y = 0.5
	for id in [2, 3]:
		state.cities[id].map_position.y = 0.0
	RegionalStrategy.invalidate_geometry(state)
	check(RegionalStrategy.similarity(state, 0, 1) < 0.5, "polar and equatorial regions differ")
	state.uses_heightmap = false
	RegionalStrategy.invalidate_geometry(state)
	check(is_equal_approx(RegionalStrategy.similarity(state, 0, 1), 1.0), "nongeographic fixtures are neutral")


func _test_partition_rebuild_cache() -> void:
	var state := fixture()
	RegionalStrategy.initialize_targets(state)
	var cache := {}
	check(DiplomacyAI._cached_war_objective(state, 0, 1, cache).is_empty(), "old partition rejects target")
	var old_revision := state.regional_strategy_revision
	state.rebuild_region_analysis(0.01)
	check(state.regional_strategy_revision > old_revision, "trade rebuild invalidates strategy version")
	var fresh := DiplomacyAI.select_war_objective(state, 0, 1)
	check(not fresh.is_empty(), "merged trade region permits target")
	check(DiplomacyAI._cached_war_objective(state, 0, 1, cache) == fresh, "objective cache follows rebuilt region")
	old_revision = state.regional_strategy_revision
	state.rebuild_administrative_regions()
	check(state.regional_strategy_revision > old_revision, "state rebuild invalidates strategy version")


func _test_siege_budget_cache() -> void:
	var state := fixture()
	state.administrative_center_by_city[3] = 2
	state.administrative_region_revision += 1
	state.cities[2].garrison_manpower = 1000
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	var cache := {}
	check(DiplomacyAI._cached_campaign_siege_requirement(state, 0, 2, cache) == 3000, "R cache before alliance")
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	check(DiplomacyAI._cached_campaign_siege_requirement(state, 0, 2, cache) == 1000, "R cache follows diplomatic changes")
	check(DiplomacyAI._cached_alliance_bloc(state, 0, cache) == [0, 1], "bloc cache follows diplomatic changes")
	state.cities[2].garrison_manpower = 500
	state.garrison_revision += 1
	check(DiplomacyAI._cached_campaign_siege_requirement(state, 1, 2, cache) == 500, "shared R cache follows garrison changes")


func _test_initialization_and_completion() -> void:
	var state := fixture()
	state.cities[2].owner_nation = 0
	state.cities[3].owner_nation = 0
	state.ownership_revision += 1
	RegionalStrategy.initialize_targets(state)
	check(RegionalStrategy.target_region(state, 0) == 0, "initial tie prefers capital region")
	state.cities[1].owner_nation = 1
	state.ownership_revision += 1
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	check(not RegionalStrategy.integration_report(state, 0)["complete"], "ordinary ally does not complete integration")
	state.cities[1].is_dock = true
	RegionalStrategy.invalidate_geometry(state)
	check(RegionalStrategy.integration_report(state, 0)["complete"], "dock does not block integration")
	state.cities[1].is_dock = false
	state.cities[1].politically_active = false
	RegionalStrategy.invalidate_geometry(state)
	check(RegionalStrategy.integration_report(state, 0)["complete"], "inactive land does not block integration")
	state.nations[0].strategic_region_anchor_city_id = 99
	RegionalStrategy.update_target(state, 0)
	check(RegionalStrategy.target_region(state, 0) == 1, "invalid anchor restores largest owned region")
	state.nations[0].alive = false
	RegionalStrategy.update_target(state, 0)
	check(state.nations[0].strategic_region_anchor_city_id == -1, "elimination clears target")


func _test_conqueror_economic_preference() -> void:
	var state := fixture()
	RegionalStrategy.initialize_targets(state)
	for id in [4, 5]:
		state.cities[id].gold_per_month *= 10
		state.cities[id].food_per_half_year *= 10
		state.cities[id].manpower_per_month *= 10
	RegionalStrategy.invalidate_geometry(state)
	state.nations[0].ruler_traits = [RulerProfile.TRAIT_MARTIAL]
	check(RegionalStrategy.choose_next_region(state, 0) == 1, "martial ruler favors environmental match")
	state.nations[0].ruler_archetype = RulerProfile.CONQUEROR
	check(RegionalStrategy.choose_next_region(state, 0) == 2, "conqueror may prefer richer dissimilar neighbor")


func _test_nested_suzerainty_index() -> void:
	var state := fixture()
	state.suzerainty[2] = {"overlord_id": 1, "civil_war": false}
	state.suzerainty[1] = {"overlord_id": 0, "civil_war": false}
	state.diplomacy_revision += 1
	for nation in state.nations:
		check(RegionalStrategy.control(state)["roots"][nation.id] == state.food_pool_holder(nation.id), "nested peaceful root matches food partition")
	state.suzerainty[1]["civil_war"] = true
	state.diplomacy_revision += 1
	for nation in state.nations:
		check(RegionalStrategy.control(state)["roots"][nation.id] == state.food_pool_holder(nation.id), "nested civil war root matches food partition")
	state.suzerainty.clear()
	state.suzerainty[0] = {"overlord_id": 1, "civil_war": false}
	state.suzerainty[1] = {"overlord_id": 2, "civil_war": false}
	state.diplomacy_revision += 1
	for nation in state.nations:
		check(RegionalStrategy.control(state)["roots"][nation.id] == 2, "parent chains may run against nation iteration order")


static func fixture() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.uses_heightmap = true
	for id in range(3):
		var nation := Nation.new()
		nation.id = id
		nation.capital_city_id = id * 2
		state.nations.append(nation)
	state.region_ids = PackedInt32Array([0, 0, 1, 1, 2, 2])
	state.administrative_center_by_city = PackedInt32Array([0, 1, 2, 3, 4, 5])
	state.administrative_center_city_ids = PackedInt32Array([0, 1, 2, 3, 4, 5])
	state.administrative_region_ids = PackedInt32Array([0, 1, 2, 3, 4, 5])
	for id in range(6):
		var city := City.new()
		city.id = id
		city.owner_nation = id / 2
		city.map_position = Vector2(float(id) / 6.0, 0.32 if id < 4 else 0.21)
		city.terrain_height = 0.1 if id < 4 else 0.8
		city.gold_per_month = 100
		city.food_per_half_year = 600
		city.manpower_per_month = 100
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		state.recognized_city_owners.append(city.owner_nation)
	for pair in [Vector2i(0, 1), Vector2i(0, 2), Vector2i(2, 3), Vector2i(1, 4), Vector2i(4, 5)]:
		var edge := Edge.new()
		edge.city_a = pair.x
		edge.city_b = pair.y
		edge.kind = Edge.Kind.LAND
		edge.max_manpower = 100000
		state.edges.append(edge)
		state.adjacency[pair.x].append(pair.y)
		state.adjacency[pair.y].append(pair.x)
		state.edge_lookup[state._edge_key(pair.x, pair.y)] = edge
	return state
