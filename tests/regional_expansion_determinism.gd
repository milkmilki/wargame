extends SceneTree

const Fixtures = preload("res://tests/regional_expansion_gates.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_direct_base_execution_equivalence()
	var synchronous := _fixture(false)
	var sliced := _fixture(false)
	var mirrored := _fixture(true)
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(synchronous.state, actions, {}, {}, 0, 1)
	var mirrored_actions: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(mirrored.state, mirrored_actions, {}, {}, 0, 1)
	_check(str(actions) == str(mirrored_actions), "mirroring and reversing armies preserve expansion proposal")
	_check(actions.size() == 1, "subject-frontier fixture emits exactly one preparation")
	if actions.is_empty():
		_finish([synchronous, sliced, mirrored])
		return
	synchronous.sim._commit_diplomacy_actions(actions.duplicate(true))
	await sliced.sim._commit_diplomacy_actions_over_frames(actions.duplicate(true))
	_check(_snapshot(synchronous.state) == _snapshot(sliced.state), "synchronous and frame-sliced preparation have identical full snapshots")
	mirrored.sim._commit_diplomacy_actions(mirrored_actions)
	for context in [synchronous, sliced, mirrored]:
		var state: GameState = context.state
		for army in state.armies:
			if army.owner_nation == 0:
				army.location_city = 26
				army.move_from = 26
		context.sim._manage_war_preparation_assembly(0)
	_check(_pool_signature(synchronous.state) == _pool_signature(mirrored.state), "mirroring and interchangeable army order preserve prewar pool composition")
	actions.clear()
	DiplomacyAI._collect_existing_war_preparation(synchronous.state, 0, actions, {})
	_check(actions.size() == 1 and int(actions[0].kind) == DiplomacyAI.Action.ISSUE_ULTIMATUM, "subject-frontier preparation reaches ultimatum")
	if not actions.is_empty():
		synchronous.sim._commit_diplomacy_actions(actions.duplicate(true))
		await sliced.sim._commit_diplomacy_actions_over_frames(actions.duplicate(true))
		_check(_snapshot(synchronous.state) == _snapshot(sliced.state), "synchronous and frame-sliced ultimatum preserve identical full state")
	_finish([synchronous, sliced, mirrored])


func _test_direct_base_execution_equivalence() -> void:
	var fixtures = preload("res://tests/direct_center_camp.gd")
	var contexts: Array[Dictionary] = []
	for mode in range(3):
		var state := fixtures.fixture()
		var guards: Array[Army] = []
		for _index in range(3):
			var troop := fixtures.army(state, 0, 2)
			troop.attack = 1
			troop.defense = 1
			guards.append(troop)
		var front := fixtures.front(state, guards)
		front.phase = CoalitionCampaignFront.Phase.HOLD_CAMP
		for _index in range(4):
			fixtures.army(state, 1, 3)
		if mode == 2:
			for city in state.cities:
				city.map_position.x = 1.0 - city.map_position.x
			state.armies.reverse()
		var sim := Simulation.new()
		root.add_child(sim)
		sim.setup(state)
		sim.paused = true
		sim.diplomacy_enabled = false
		contexts.append({"state": state, "sim": sim})
	for _day in range(35):
		contexts[0].sim._advance_day()
		await contexts[1].sim._advance_day(true)
		contexts[2].sim._advance_day()
		_check(_snapshot(contexts[0].state) == _snapshot(contexts[1].state), "direct-base pursuit and counterattack have identical synchronous/sliced native snapshots")
		_check(_physical_campaign_snapshot(contexts[0].state) == _physical_campaign_snapshot(contexts[2].state), "reflection and interchangeable army reorder preserve rear bases, physical bindings, battlefield succession and cooldowns")
	_check(contexts[0].state.cities[2].owner_nation == 1, "equivalence chain must reach real rear-base capture")
	for context in contexts:
		context.sim.free()


func _physical_campaign_snapshot(state: GameState) -> Dictionary:
	var snapshot := NativeSnapshotBuilder.build(state)
	var fronts: Dictionary = snapshot["campaign_fronts"].duplicate(true)
	fronts.erase("assignment_army_ids")
	fronts.erase("assignment_targets")
	var bindings: Array = []
	var front_ids := state.campaign_fronts.keys()
	front_ids.sort()
	for front_id in front_ids:
		var records: Array[String] = []
		var front: CoalitionCampaignFront = state.campaign_fronts[front_id]
		for troop in state.armies:
			if front.army_assignments.has(troop.id):
				records.append(str([front.army_assignments[troop.id], troop.owner_nation,
					troop.size, troop.max_size, troop.morale, troop.state,
					troop.location_city, troop.on_edge, troop.move_from, troop.move_to,
					troop.move_progress, troop.path, troop.ai_action, troop.ai_target_city]))
		records.sort()
		bindings.append([front_id, records])
	return {"fronts": fronts, "pairs": snapshot["campaign_pairs"], "bindings": bindings}


func _fixture(mirror: bool) -> Dictionary:
	var state := Fixtures.fixture()
	state.cities[26].owner_nation = 2
	state.recognized_city_owners[26] = 2
	state.suzerainty[2] = {"overlord_id": 0, "civil_war": false}
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	state.ownership_revision += 1
	if mirror:
		for city in state.cities:
			city.map_position.x = 29.0 - city.map_position.x
		state.armies.reverse()
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.paused = true
	sim.diplomacy_enabled = false
	return {"state": state, "sim": sim}


func _snapshot(state: GameState) -> PackedByteArray:
	return var_to_bytes(NativeSnapshotBuilder.build(state))


func _pool_signature(state: GameState) -> Array[String]:
	var result: Array[String] = []
	for army in state.armies:
		if state.nations[0].war_preparation_army_ids.has(army.id):
			result.append(str([army.owner_nation, army.location_city, army.size, army.max_size, army.morale, army.state]))
	result.sort()
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _finish(contexts: Array) -> void:
	for context in contexts:
		context.sim.free()
	print("REGIONAL_EXPANSION_DETERMINISM_RESULT failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
