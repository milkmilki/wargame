extends SceneTree

var failures: int = 0


func _init() -> void:
	var state := _fixture()
	for nation_id in [0, 1, 2, 3]:
		state.set_diplomatic_relation(nation_id, 9, GameState.DiplomaticRelation.WAR)
	state.day = DiplomacyAI.MIN_NEUTRAL_DAYS + 360
	_test_alliance_score_without_direct_war_or_border_bonus(state)
	_check_pair(state, 0, 1, true, "weak nations may unite against common enemy")
	_check_pair(state, 2, 3, false, "great powers cannot ally merely because of a common enemy")
	_check_pair(state, 0, 2, false, "great power does not accept a small ally")
	state.nations[2].ruler_archetype = RulerProfile.DIPLOMAT
	_check_pair(state, 2, 3, false, "diplomatic ruler cannot bypass strength cap")
	state.nations[2].ruler_archetype = RulerProfile.BALANCED
	# A vassal with a small personal army belongs to its powerful peaceful root.
	state.suzerainty[4] = {"overlord_id": 2, "civil_war": false}
	state.diplomacy_revision += 1
	_check_pair(state, 0, 4, false, "small vassal cannot disguise a strong suzerainty system")
	state.suzerainty[5] = {"overlord_id": 4, "civil_war": false}
	state.diplomacy_revision += 1
	_check_pair(state, 0, 5, false, "nested vassal uses the same root strength")
	state.suzerainty[4]["civil_war"] = true
	state.diplomacy_revision += 1
	check(DiplomacyAI._alliance_can_reach_acceptance(state, 0, 4), "civil war separates the weak rebel bloc")
	# Existing alliances remain a lifecycle decision, not an automatic dissolution.
	state.set_diplomatic_relation(2, 3, GameState.DiplomaticRelation.ALLIED)
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_alliance_actions(state, actions, {}, {})
	check(state.is_allied(2, 3), "new-alliance scoring does not dissolve existing relations")
	_test_late_equal_powers()
	_test_action_paths_and_cache_invalidation()
	print("WEAK_BLOC_ALLIANCE_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)


func _test_alliance_score_without_direct_war_or_border_bonus(state: GameState) -> void:
	var cache := {}
	var a := 0
	var b := 1
	check(DiplomacyAI._common_enemy_count(state, a, b, cache) == 1,
		"fixture includes a common wartime enemy")
	check(DiplomacyAI._frontier_edges(state, a, b, cache) > 0,
		"fixture includes a shared border")
	var own_power := DiplomacyAI._national_power(state, a, cache)
	var target_power := DiplomacyAI._national_power(state, b, cache)
	var imbalance := absf(log(maxf(own_power, 1.0) / maxf(target_power, 1.0)))
	var expected := (
		0.35
		+ minf(DiplomacyAI._shared_threat(state, a, b, cache) * 0.35, 0.80)
		+ maxf(1.0 - imbalance, 0.0) * 0.55
		+ DiplomacyAI._alliance_frontier_release_value(state, a, b, cache)
		+ DiplomacyAI.diplomatic_attitude(state, a, b, cache)
			* DiplomacyAI.ATTITUDE_ALLIANCE_WEIGHT
		- DiplomacyAI.unification_rivalry(state, a, b, cache)
	) * RulerProfile.alliance_multiplier(state.nations[a])
	check(is_equal_approx(DiplomacyAI.alliance_willingness(state, a, b, cache), expected),
		"common enemy and shared border carry no direct alliance bonus")


func _check_pair(state: GameState, a: int, b: int, accepted: bool, label: String) -> void:
	var cache := {}
	var score_a := DiplomacyAI.alliance_willingness(state, a, b, cache)
	var score_b := DiplomacyAI.alliance_willingness(state, b, a, cache)
	check((minf(score_a, score_b) >= DiplomacyAI.ALLIANCE_ACCEPT_SCORE) == accepted,
		"%s scores=%.3f/%.3f" % [label, score_a, score_b])
	if not accepted:
		check(not DiplomacyAI._alliance_can_reach_acceptance(state, a, b, cache), "prefilter rejects " + label)
	for direction in [Vector2i(a, b), Vector2i(b, a)]:
		var prefilter_cache := {}
		var possible := DiplomacyAI._alliance_can_reach_acceptance(state, direction.x, direction.y, prefilter_cache)
		var score := DiplomacyAI.alliance_willingness(state, direction.x, direction.y, prefilter_cache)
		check(possible or score < DiplomacyAI.ALLIANCE_ACCEPT_SCORE, "prefilter remains conservative " + label)
	var reuse_size := cache.size()
	DiplomacyAI.alliance_willingness(state, a, b, cache)
	check(cache.size() == reuse_size, "same pair reuses batch cache " + label)


func _test_late_equal_powers() -> void:
	var state := _fixture()
	for nation in state.nations:
		nation.alive = nation.id < 2
	for city in state.cities:
		city.owner_nation = city.id % 2
	for army in state.armies:
		army.owner_nation = army.id % 2
		army.size = 100000
	state.ownership_revision += 1
	state.diplomacy_revision += 1
	state.day = DiplomacyAI.MIN_NEUTRAL_DAYS + 360
	_check_pair(state, 0, 1, false, "two equal endgame powers are not treated as weak")


func _test_action_paths_and_cache_invalidation() -> void:
	var state := _fixture()
	for nation_id in [0, 1, 2, 3]:
		state.set_diplomatic_relation(nation_id, 9, GameState.DiplomaticRelation.WAR)
	state.day = DiplomacyAI.MIN_NEUTRAL_DAYS + 360
	var unfiltered: Array[Dictionary] = []
	var filtered: Array[Dictionary] = []
	DiplomacyAI.alliance_acceptance_prefilter_disabled = true
	DiplomacyAI._collect_alliance_actions(state, unfiltered, {}, {})
	DiplomacyAI.alliance_acceptance_prefilter_disabled = false
	DiplomacyAI._collect_alliance_actions(state, filtered, {}, {})
	check(str(unfiltered) == str(filtered), "alliance actions are identical with prefilter enabled")
	check(not filtered.is_empty(), "weak-bloc alliance remains available")
	for action in filtered:
		check(int(action["a"]) not in [2, 3] and int(action["b"]) not in [2, 3], "collector never proposes a great-power alliance")
	var preparation_actions: Array[Dictionary] = []
	check(not DiplomacyAI._collect_preparation_alliance(state, 2, 9, preparation_actions, {}), "strong preparing nation cannot recruit an ally")
	check(DiplomacyAI._collect_preparation_alliance(state, 0, 9, preparation_actions, {}), "weak preparing nation can recruit a weak ally")
	var cache := {}
	var score := DiplomacyAI.alliance_willingness(state, 0, 1, cache)
	check(score >= DiplomacyAI.ALLIANCE_ACCEPT_SCORE, "initial pair eligible before political change")
	state.suzerainty[1] = {"overlord_id": 2, "civil_war": false}
	state.diplomacy_revision += 1
	check(DiplomacyAI.alliance_willingness(state, 0, 1, cache) < DiplomacyAI.ALLIANCE_ACCEPT_SCORE,
		"reused score cache follows changed suzerainty")
	check(not DiplomacyAI._alliance_can_reach_acceptance(state, 0, 1, cache), "prefilter follows changed suzerainty")


func _fixture() -> GameState:
	var state := GameState.new()
	var ids := PackedInt32Array()
	for id in range(10):
		ids.append(id)
		var nation := Nation.new()
		nation.id = id
		nation.capital_city_id = id
		nation.treasury_gold = 10000
		nation.manpower_pool = 100000
		state.nations.append(nation)
		var city := City.new()
		city.id = id
		city.owner_nation = id
		city.is_capital = true
		city.map_position = Vector2(id % 5, id / 5)
		city.garrison_manpower = 1000
		state.cities.append(city)
		state.recognized_city_owners.append(id)
		state.adjacency[id] = [] as Array[int]
		var army := Army.new()
		army.id = id
		army.owner_nation = id
		army.size = 100000 if id in [2, 3] else 10000
		army.max_size = army.size
		army.location_city = id
		state.armies.append(army)
	state.region_ids = ids.duplicate()
	state.administrative_center_by_city = ids.duplicate()
	state.administrative_center_city_ids = ids.duplicate()
	state.administrative_region_ids = ids.duplicate()
	for a in range(10):
		for b in range(a + 1, 10):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
			state._add_edge(a, b)
			var edge := state.edge_of(a, b)
			edge.kind = Edge.Kind.LAND
			edge.max_manpower = 50000
	RegionalStrategy.initialize_targets(state)
	return state
