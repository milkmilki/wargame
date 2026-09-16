extends SceneTree
## 宗藩凝聚力只驱动体系解体；藩王不独立发动战争。

var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_cohesion_uses_legal_territory()
	_test_vassals_do_not_prepare_independent_wars()
	_test_low_cohesion_year_dissolves_into_alliance()
	_test_cohesion_recovery_resets_timer()
	_finish()


func _test_cohesion_uses_legal_territory() -> void:
	var fixture := _fixture()
	var state: GameState = fixture["state"]
	var root := int(fixture["root"])
	var subject_a := int(fixture["subject_a"])
	var subject_b := int(fixture["subject_b"])
	var direct_count := 0
	var system_count := 0
	for city in state.land_cities():
		var legal_owner := state.recognized_owner_of(city.id)
		if legal_owner in [root, subject_a, subject_b]:
			system_count += 1
		if legal_owner == root:
			direct_count += 1
	var expected := float(direct_count) / float(system_count)
	_check(
		is_equal_approx(state.suzerainty_cohesion(subject_a), expected),
		"凝聚力必须按宗主直辖法理陆城占体系法理陆城的比例计算"
	)
	var occupied_city := state.land_cities_of(subject_a)[0]
	var legal_before := state.recognized_owner_of(occupied_city.id)
	occupied_city.owner_nation = int(fixture["outsider"])
	state.ownership_revision += 1
	_check(
		state.recognized_owner_of(occupied_city.id) == legal_before
			and is_equal_approx(
				state.suzerainty_cohesion(subject_a), expected
			),
		"临时控制权变化不得改变宗藩凝聚力"
	)


func _test_vassals_do_not_prepare_independent_wars() -> void:
	var fixture := _fixture()
	var state: GameState = fixture["state"]
	var subject_a := int(fixture["subject_a"])
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(
		state, actions, {}, {}, subject_a, subject_a + 1
	)
	_check(
		actions.is_empty(),
		"藩王不得独立生成备战或宣战行动"
	)


func _test_low_cohesion_year_dissolves_into_alliance() -> void:
	var fixture := _fixture()
	var state: GameState = fixture["state"]
	var root := int(fixture["root"])
	var subject_a := int(fixture["subject_a"])
	var subject_b := int(fixture["subject_b"])
	var nested_subject := int(fixture["outsider"])
	state.suzerainty[nested_subject] = {
		"overlord_id": subject_a,
		"tribute_rate": 0.2,
		"created_day": 0,
		"last_centralization_day": -1,
		"civil_war": false,
	}
	state.set_diplomatic_relation(
		subject_a, nested_subject, GameState.DiplomaticRelation.ALLIED
	)
	for nation_id in [subject_a, subject_b, nested_subject]:
		state.nations[nation_id].name_kind = WorldNaming.KIND_VASSAL
	var root_capital := state.nations[root].capital_city_id
	state.cities[root_capital].has_warehouse = true
	state.cities[root_capital].food_storage = 900
	state.nations[root].warehouse_city_ids = [root_capital]
	state.ownership_revision += 1
	state.refresh_derived()
	var food_before := _total_city_food(state)
	var started_day := 100
	state.day = started_day
	_check(
		state.advance_suzerainty_dissolution().is_empty(),
		"低凝聚力首日只能开始解体计时"
	)
	state.day = started_day + GameState.VASSAL_SYSTEM_DISSOLUTION_DAYS - 1
	_check(
		state.advance_suzerainty_dissolution().is_empty()
			and state.is_vassal(subject_a),
		"低凝聚力未满一年时宗藩体系必须保留"
	)
	state.day += 1
	var dissolved := state.advance_suzerainty_dissolution()
	var members := [root, subject_a, subject_b, nested_subject]
	var all_independent_and_allied := true
	for member_id in members:
		all_independent_and_allied = (
			all_independent_and_allied
			and not state.is_vassal(member_id)
			and state.nations[member_id].name_kind
				!= WorldNaming.KIND_VASSAL
		)
	for first in range(members.size()):
		for second in range(first + 1, members.size()):
			all_independent_and_allied = (
				all_independent_and_allied
				and state.is_allied(members[first], members[second])
			)
	_check(
		dissolved == ([root] as Array[int])
			and all_independent_and_allied
			and state.suzerainty_structure_valid(),
		"低凝聚力持续一年后必须解散整棵宗藩树并形成共同联盟"
	)
	_check(
		_total_city_food(state) == food_before,
		"宗藩解体和粮仓拆分必须保持粮食守恒"
	)


func _test_cohesion_recovery_resets_timer() -> void:
	var fixture := _fixture()
	var state: GameState = fixture["state"]
	var root := int(fixture["root"])
	var subject_a := int(fixture["subject_a"])
	var legal_snapshot := state.recognized_city_owners.duplicate()
	state.day = 100
	state.advance_suzerainty_dissolution()
	for city in state.land_cities():
		if state.suzerainty_root(state.recognized_owner_of(city.id)) == root:
			state.recognized_city_owners[city.id] = root
	state.ownership_revision += 1
	state.day = 200
	state.advance_suzerainty_dissolution()
	state.recognized_city_owners = legal_snapshot
	state.ownership_revision += 1
	state.day = 201
	state.advance_suzerainty_dissolution()
	state.day = 460
	_check(
		state.advance_suzerainty_dissolution().is_empty()
			and state.is_vassal(subject_a),
		"凝聚力恢复到阈值后必须清零旧解体计时"
	)


func _fixture() -> Dictionary:
	var state := GameState.new()
	state.generate_grid_world(95001)
	var subject_a := -1
	var subject_b := -1
	for edge in state.edges:
		var owner_a := state.cities[edge.city_a].owner_nation
		var owner_b := state.cities[edge.city_b].owner_nation
		if owner_a != owner_b:
			subject_a = owner_a
			subject_b = owner_b
			break
	var remaining: Array[int] = []
	for nation in state.nations:
		if nation.id not in [subject_a, subject_b]:
			remaining.append(nation.id)
	var root := remaining[0]
	var outsider := remaining[1]
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	state.suzerainty = {
		subject_a: _subject_record(root),
		subject_b: _subject_record(root),
	}
	for member_id in [subject_a, subject_b]:
		state.set_diplomatic_relation(
			root, member_id, GameState.DiplomaticRelation.ALLIED
		)
	state.set_diplomatic_relation(
		subject_a, subject_b, GameState.DiplomaticRelation.ALLIED
	)
	state.ownership_revision += 1
	return {
		"state": state,
		"root": root,
		"subject_a": subject_a,
		"subject_b": subject_b,
		"outsider": outsider,
	}


func _subject_record(overlord_id: int) -> Dictionary:
	return {
		"overlord_id": overlord_id,
		"tribute_rate": 0.2,
		"created_day": 0,
		"last_centralization_day": -1,
		"civil_war": false,
	}


func _total_city_food(state: GameState) -> int:
	var total := 0
	for city in state.cities:
		total += city.food_storage
	return total


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("VASSAL_COHESION_DISSOLUTION_OK checks=", _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("VASSAL_COHESION_DISSOLUTION_FAIL: " + failure)
	quit(1)
