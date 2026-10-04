extends SceneTree

var failures: Array[String] = []
var synchronous_submission: PackedByteArray

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for outcome in [UltimatumRules.Outcome.ANNEX, UltimatumRules.Outcome.SUBMIT, UltimatumRules.Outcome.REFUSE]:
		var fixture := _fixture(outcome)
		var state: GameState = fixture.state
		var sim: Simulation = fixture.sim
		state.nations[0].treasury_gold = 0
		state.nations[0].unpaid_military_upkeep = 100
		var actions: Array[Dictionary] = []
		DiplomacyAI._collect_existing_war_preparation(state, 0, actions, {})
		_check(actions.size() == 1 and int(actions[0].kind) == DiplomacyAI.Action.ISSUE_ULTIMATUM, "zero-cash ready preparation emits ultimatum")
		if not actions.is_empty():
			var actor_tree := state.nations[1].family_tree_id
			_check(sim._execute_diplomatic_action(actions[0]), "ultimatum commits")
			var event: Dictionary = state.diplomatic_history[-1]
			_check(int(event.get("action", -1)) == DiplomacyAI.Action.ISSUE_ULTIMATUM and int(event.ultimatum.outcome) == outcome, "expected logged outcome")
			_check(state.nations[0].war_preparation_target_nation == -1, "preparation released")
			if outcome == UltimatumRules.Outcome.ANNEX:
				_check(not state.nations[1].alive and not state.nations[2].alive, "whole target polity annexed")
				_check(state.family_trees.has(actor_tree), "former family archived")
			elif outcome == UltimatumRules.Outcome.SUBMIT:
				_check(state.overlord_of(1) == 0 and state.nations[1].family_tree_id == actor_tree, "submission retains dynasty")
				_check(not state.chronicle_events.is_empty() and str(state.chronicle_events[-1].text).ends_with("，封" + state.nations[1].name) and state.nations[1].name.ends_with("王"), "submission chronicle preserves full royal title")
				synchronous_submission = var_to_bytes(NativeSnapshotBuilder.build(state))
			else:
				_check(state.is_enemy(0, 1), "refusal declares war")
				var front := state.campaign_front_for(0, fixture.center)
				_check(front != null and front.phase == CoalitionCampaignFront.Phase.BREAK_IN and not front.army_assignments.is_empty(), "refusal immediately transfers assembled armies")
				var entered := false
				for day_index in range(120):
					sim._advance_day()
					for army in state.armies:
						if army.owner_nation == 0 and army.is_at_city_node(fixture.entry):
							entered = true
					if entered:
						break
				_check(entered, "refusing war actually enters enemy territory")
			if outcome != UltimatumRules.Outcome.REFUSE:
				_check(state.war_id_between(0, 1) < 0 and state.campaign_fronts.is_empty(), "acceptance never creates war or fronts")
			_check(not sim._execute_diplomatic_action(actions[0]), "ultimatum cannot be committed twice")
		sim.free()
	var fixture := _fixture(UltimatumRules.Outcome.SUBMIT)
	var state: GameState = fixture.state
	var sim: Simulation = fixture.sim
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_existing_war_preparation(state, 0, actions, {})
	if actions.is_empty():
		push_error("ULTIMATUM_E2E_FAIL: no ready action")
		sim.free()
		quit(1)
		return
	var stale := {"kind": DiplomacyAI.Action.PREPARE_WAR, "a": 1, "b": 3, "objective_city": state.nations[3].capital_city_id}
	sim._commit_diplomacy_actions([actions[0], stale])
	_check(state.overlord_of(1) == 0 and state.nations[1].war_preparation_target_nation == -1, "changed identity invalidates queued preparation")
	sim.free()
	fixture = _fixture(UltimatumRules.Outcome.SUBMIT)
	state = fixture.state
	sim = fixture.sim
	actions.clear()
	DiplomacyAI._collect_existing_war_preparation(state, 0, actions, {})
	for army in state.armies:
		if army.owner_nation == 0:
			army.state = Army.State.RECOVERING
	_check(not sim._execute_diplomatic_action(actions[0]) and state.overlord_of(1) < 0 and not state.is_enemy(0, 1), "commit revalidates physical assembly")
	sim.free()
	fixture = _fixture(UltimatumRules.Outcome.SUBMIT)
	state = fixture.state
	sim = fixture.sim
	state.nations[0].treasury_gold = 0
	state.nations[0].unpaid_military_upkeep = 100
	actions.clear()
	DiplomacyAI._collect_existing_war_preparation(state, 0, actions, {})
	await sim._commit_diplomacy_actions_over_frames(actions)
	_check(state.overlord_of(1) == 0 and state.nations[0].war_preparation_target_nation == -1, "sliced submission matches synchronous execution")
	_check(synchronous_submission == var_to_bytes(NativeSnapshotBuilder.build(state)), "sliced submission full snapshot equals synchronous snapshot")
	sim.free()
	fixture = _fixture(UltimatumRules.Outcome.SUBMIT)
	state = fixture.state
	sim = fixture.sim
	state.set_diplomatic_relation(1, 3, GameState.DiplomaticRelation.ALLIED)
	var border_city := -1
	for pair in state.territorial_border_pairs():
		if state.cities[pair.x].owner_nation == 1 and state.cities[pair.y].owner_nation == 3:
			border_city = pair.y
			break
	var expatriate := _army(946060, 1, border_city, 5000)
	var former_ally := _army(946061, 3, state.nations[1].capital_city_id, 1000)
	state.armies.append(expatriate)
	state.armies.append(former_ally)
	actions.clear()
	DiplomacyAI._collect_existing_war_preparation(state, 0, actions, {})
	_check(not actions.is_empty(), "foreign deployment fixture can issue ultimatum")
	if not actions.is_empty():
		_check(sim._execute_diplomatic_action(actions[0]), "foreign deployment submission commits")
		_check(expatriate.diplomatic_repatriation and expatriate.size == 5000 and is_equal_approx(expatriate.morale, 1.0), "former external deployment repatriates without routing damage")
		_check(former_ally.diplomatic_repatriation and former_ally.size == 1000, "old ally withdraws from submitted territory")
	sim.free()
	fixture = _fixture(UltimatumRules.Outcome.SUBMIT)
	state = fixture.state
	sim = fixture.sim
	state.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.WAR)
	var existing_war := state.war_id_between(0, 3)
	actions.clear()
	DiplomacyAI._collect_existing_war_preparation(state, 0, actions, {})
	_check(not actions.is_empty(), "wartime initiator can issue valid ultimatum")
	if not actions.is_empty():
		_check(sim._execute_diplomatic_action(actions[0]), "wartime submission commits")
		_check(state.is_enemy(1, 3) and state.war_id_between(1, 3) == existing_war, "new foreign vassal inherits existing war id")
	sim.free()
	fixture = _fixture(UltimatumRules.Outcome.SUBMIT)
	state = fixture.state
	sim = fixture.sim
	state.day += DiplomacyAI.WAR_PREPARATION_MAX_DAYS
	state.nations[0].war_preparation_unready_since_day = -1
	state.nations[0].manpower_pool = 0
	state.cities[fixture.center].garrison_manpower = 100000
	actions.clear()
	DiplomacyAI._collect_existing_war_preparation(state, 0, actions, {})
	_check(actions.is_empty() and not DiplomacyAI.war_preparation_launch_allowed(state, 0), "deadline cannot bypass manpower resource qualification")
	state.nations[0].manpower_pool = 100000
	state.nations[0].war_preparation_unready_since_day = -1
	actions.clear()
	DiplomacyAI._collect_existing_war_preparation(state, 0, actions, {})
	_check(not actions.is_empty(), "best effort ultimatum emitted at deadline")
	if not actions.is_empty():
		_check(sim._execute_diplomatic_action(actions[0]), "deadline uses same ultimatum path")
	sim.free()
	if failures.is_empty():
		print("ULTIMATUM_E2E_OK")
		quit(0)
	else:
		for failure in failures:
			push_error("ULTIMATUM_E2E_FAIL: " + failure)
		quit(1)

func _fixture(outcome: int) -> Dictionary:
	var state := GameState.new()
	state.generate_grid_world(94604)
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var entry := -1
	var staging := -1
	for pair in state.territorial_border_pairs():
		if state.cities[pair.x].owner_nation == 0 and state.cities[pair.y].owner_nation == 1:
			staging = pair.x
			entry = pair.y
			break
	var center := state.administrative_center_of(entry)
	if outcome == UltimatumRules.Outcome.ANNEX:
		var keep := [center, entry]
		var child_keep := [state.nations[2].capital_city_id]
		var operations: Array[Dictionary] = []
		for city in state.cities:
			var owner := 1 if keep.has(city.id) else (2 if child_keep.has(city.id) else 0)
			operations.append({"city_id": city.id, "controller_id": owner, "legal_owner_id": owner,
				"stock_policy": GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL})
		var transaction := state.apply_territory_transaction(operations, {1: center})
		_check(transaction.ok, "annexation fixture transaction: " + str(transaction))
		transaction = state.apply_territory_transaction([], {}, -1, {2: {"overlord_id": 1, "tribute_rate": 0.25, "civil_war": false}})
		_check(transaction.ok, "annexation fixture graph: " + str(transaction))
	state.region_ids.fill(0)
	state.region_analysis_revision += 1
	RegionalStrategy.invalidate_geometry(state)
	state.day = DiplomacyAI.MIN_NEUTRAL_DAYS
	state.armies.clear()
	state.battles.clear()
	for nation in state.nations:
		nation.manpower_pool = 100000
		nation.treasury_gold = 1000000
		if nation.capital_city_id >= 0:
			state.cities[nation.capital_city_id].food_storage = 1000000
			state.cities[nation.capital_city_id].garrison_manpower = 5000
	for index in range(4):
		var army := _army(946040 + index, 0, staging, 15000)
		state.armies.append(army)
	if outcome == UltimatumRules.Outcome.REFUSE:
		state.armies.append(_army(946050, 1, center, 30000))
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.diplomacy_enabled = false
	_check(sim._start_war_preparation(0, 1, {"objective_city": entry, "objective_center_city": center, "mobilization_armies": 0}), "valid preparation starts")
	# Include all four already assembled armies to exercise the high-score branch.
	state.nations[0].war_preparation_army_ids = [946040, 946041, 946042, 946043]
	return {"state": state, "sim": sim, "entry": entry, "center": center, "staging": staging}

func _army(id: int, owner: int, city: int, size: int) -> Army:
	var army := Army.new()
	army.id = id
	army.owner_nation = owner
	army.location_city = city
	army.size = size
	army.max_size = size
	army.attack = 10
	army.defense = 10
	army.morale = 1.0
	army.supply_ratio = 1.0
	return army

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
