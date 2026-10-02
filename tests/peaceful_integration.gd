extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	var state := _world()
	if not state.has_method("accept_submission") or not state.has_method("annex_nations"):
		push_error("PEACEFUL_INTEGRATION_FAIL: missing transaction APIs")
		quit(1)
		return
	var graph := state.suzerainty.duplicate(true)
	graph[2] = {"overlord_id": 1, "tribute_rate": 0.25, "civil_war": false}
	graph[3] = {"overlord_id": 2, "tribute_rate": 0.25, "civil_war": false}
	_check(state.apply_territory_transaction([], {}, -1, graph).ok, "prepare nested polity")
	state.set_diplomatic_relation(1, 4, GameState.DiplomaticRelation.ALLIED)
	FamilyTree.ensure_all(state)
	var ruler := state.nations[1].ruler_name
	var title := state.nations[1].name
	var tree_id := state.nations[1].family_tree_id
	var person_id := state.nations[1].ruler_person_id
	var capital := state.nations[1].capital_city_id
	var started := state.nations[1].ruler_started_day
	var gold := state.nations[1].treasury_gold
	var manpower := state.nations[1].manpower_pool
	var old_food := _food(state)
	_check(state.call("accept_submission", 0, 1), "existing polity submits")
	_check(state.overlord_of(1) == 0 and state.overlord_of(2) == 1 and state.overlord_of(3) == 2, "retain nested hierarchy")
	_check(state.nations[1].family_tree_id == tree_id and state.nations[1].ruler_person_id == person_id, "retain independent lineage")
	_check(state.nations[1].ruler_name == ruler and state.nations[1].ruler_started_day == started, "retain ruler identity and reign")
	_check(state.nations[1].capital_city_id == capital and state.nations[1].treasury_gold == gold and state.nations[1].manpower_pool == manpower, "retain capital treasury manpower")
	_check(WorldNaming.nation_display_name(state, 1) == title + "王", "retain former national title")
	_check(WorldNaming.suzerainty_ruler_surname(state, 1) == WorldNaming.ruler_surname(ruler), "foreign vassal keeps own surname")
	_check(state.relation_between(1, 4) == GameState.DiplomaticRelation.NEUTRAL, "old external alliance removed")
	_check(_food(state) == old_food and state.food_pool_holder(3) == 0, "submission grain conserved")
	_check(state.suzerainty_structure_error().is_empty(), "submission structural invariants")
	var before := var_to_bytes(NativeSnapshotBuilder.build(state))
	_check(not state.call("accept_submission", 4, 1), "cannot resubmit another lords vassal")
	_check(before == var_to_bytes(NativeSnapshotBuilder.build(state)), "failed submission has no side effects")
	state = _world()
	FamilyTree.ensure_all(state)
	var old_trees := state.family_trees.duplicate(true)
	graph = state.suzerainty.duplicate(true)
	graph[2] = {"overlord_id": 1, "tribute_rate": 0.25, "civil_war": false}
	graph[3] = {"overlord_id": 2, "tribute_rate": 0.25, "civil_war": false}
	_check(state.apply_territory_transaction([], {}, -1, graph).ok, "prepare annexable polity")
	var totals := _resources(state)
	old_food = _food(state)
	var expected_size := 0
	for nation_id in [0, 1, 2, 3]:
		expected_size += state.nations[nation_id].treasury_gold
	var ownership := state.ownership_revision
	_check(state.call("annex_nations", 0, [1, 2, 3]), "whole polity annexes")
	_check(state.ownership_revision == ownership + 1, "one ownership commit")
	for nation_id in [1, 2, 3]:
		_check(not state.nations[nation_id].alive and not state.suzerainty.has(nation_id), "all submitted governments dissolved")
	for army in state.armies:
		_check(army.owner_nation not in [1, 2, 3], "all armies transferred")
	_check(state.nations[0].treasury_gold == expected_size and _resources(state) == totals, "gold manpower conserved")
	_check(_food(state) == old_food, "annexation food conserved")
	_check(state.family_trees == old_trees, "annexation does not merge or erase bloodlines")
	_check(state.suzerainty_structure_error().is_empty(), "annexation structural invariants")
	before = var_to_bytes(NativeSnapshotBuilder.build(state))
	_check(not state.call("annex_nations", 0, [4, -1]), "invalid batch rejected")
	_check(before == var_to_bytes(NativeSnapshotBuilder.build(state)), "invalid batch leaves state unchanged")
	_check(not state.call("annex_nations", 0, [4], state.ownership_revision - 1), "stale batch rejected")
	_check(before == var_to_bytes(NativeSnapshotBuilder.build(state)), "stale batch leaves state unchanged")
	state = _world()
	graph = {2: {"overlord_id": 0, "tribute_rate": 0.25, "civil_war": false}}
	_check(state.apply_territory_transaction([], {}, -1, graph).ok, "prepare vassal initiator")
	_check(state.accept_submission(2, 1) and state.overlord_of(1) == 2 and state.food_pool_holder(1) == 0, "foreign subject attaches to actual vassal initiator")
	if failures.is_empty():
		print("PEACEFUL_INTEGRATION_OK")
		quit(0)
	else:
		for failure in failures:
			push_error("PEACEFUL_INTEGRATION_FAIL: " + failure)
		quit(1)

func _world() -> GameState:
	var state := GameState.new()
	state.generate_grid_world(94602)
	var extra := Nation.new()
	extra.id = state.nations.size()
	extra.name = "测试"
	extra.short_name = "测试"
	extra.ruler_name = "赵外"
	state.nations.append(extra)
	for center_id in state.administrative_center_city_ids:
		if state.cities[center_id].owner_nation == 0 and center_id != state.nations[0].capital_city_id:
			var operations: Array[Dictionary] = []
			for city_id in state.administrative_members(center_id):
				operations.append({"city_id": city_id, "controller_id": extra.id, "legal_owner_id": extra.id})
			state.apply_territory_transaction(operations, {extra.id: center_id})
			break
	for a in range(state.nations.size()):
		state.nations[a].treasury_gold = 100 + a
		state.nations[a].manpower_pool = 100 + a
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	return state

func _resources(state: GameState) -> Vector2i:
	var total := Vector2i.ZERO
	for nation in state.nations:
		total += Vector2i(nation.treasury_gold, nation.manpower_pool)
	return total

func _food(state: GameState) -> int:
	var total := 0
	for city in state.cities:
		total += city.food_storage
	return total

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
