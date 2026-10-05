extends SceneTree

const Fixtures = preload("res://tests/regional_expansion_gates.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_expansion(true, false, false)
	_run_expansion(true, false, true)
	_run_expansion(false, true, true)
	_run_expansion(false, true, true, true)
	_run_expansion(false, false, true, false, true)
	_test_direct_center_deployment()
	_test_stale_submission()
	print("REGIONAL_EXPANSION_E2E_RESULT failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _run_expansion(capital_only: bool, subject_frontier: bool, refusal: bool, river_crossing: bool = false, center_frontier: bool = false) -> void:
	var state := Fixtures.fixture(capital_only)
	if center_frontier:
		# The map remains connected, but the only fu can only be reached
		# through its hostile zhou center, not as the initial attack target.
		state.edge_of(26, 27).max_manpower = 0
		state._add_edge(26, 28)
		state.road_network_revision += 1
	for nation in state.nations:
		nation.ruler_started_day = state.day
	var warehouse_ids: Array[int] = [25, 28, 29]
	for owner in range(3):
		state.cities[warehouse_ids[owner]].has_warehouse = true
		state.nations[owner].warehouse_city_ids.assign([warehouse_ids[owner]])
	if subject_frontier:
		state.cities[26].owner_nation = 2
		state.recognized_city_owners[26] = 2
		state.suzerainty[2] = {"overlord_id": 0, "civil_war": false}
		state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
		state.ownership_revision += 1
	if river_crossing:
		_subject_crossing(state)
	if refusal:
		# A target already fighting an independent third party cannot submit.
		_add_third_party_war(state)
		state.nations[0].ruler_archetype = RulerProfile.BALANCED
		for army in state.armies:
			if army.owner_nation == 0:
				army.ruler_attack_multiplier = 1.0
				army.ruler_defense_multiplier = 1.0
				army.ruler_morale_multiplier = 1.0
			elif army.owner_nation == 1:
				army.size = 45000
				army.max_size = 45000
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.diplomacy_enabled = false
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(state, actions, {}, {}, 0, 1)
	_check(actions.size() == 1, "legal expansion emits preparation")
	if actions.is_empty():
		sim.free()
		return
	_check(sim._execute_diplomatic_action(actions[0]), "proposed preparation commits")
	var nation := state.nations[0]
	if center_frontier:
		_check(nation.war_preparation_objective_city == 28,
			"rear fu does not prevent selecting the directly reachable zhou")
	var staging := nation.war_preparation_staging_city_id
	_check(state.cities[staging].owner_nation == (2 if subject_frontier else 0), "staging belongs to the expected peaceful polity member")
	_check(DiplomacyAI.war_preparation_arrived_troops(state, 0) == 0, "armies must physically march before ultimatum")
	var started_day := state.day
	var marched := false
	for _step in range(120):
		sim._manage_war_preparation_assembly(0)
		for army_id in nation.war_preparation_army_ids:
			var army := state.armies.filter(func(candidate: Army) -> bool: return candidate.id == army_id)[0] as Army
			_check(army.owner_nation == 0, "prewar pool never draws subject or ally troops")
			marched = marched or army.on_edge or not army.path.is_empty()
		if DiplomacyAI.war_preparation_ready(state, 0):
			break
		sim._advance_day()
	_check(marched and state.day > started_day, "assembly uses real movement rather than relocation")
	_check(DiplomacyAI.war_preparation_ready(state, 0), "own armies arrive and satisfy actual assembly requirement")
	# Manual assembly uses the same per-batch reservation set as normal AI.
	# Finish that batch before submitting the new diplomatic action.
	sim._clear_ai_command_collection()
	actions.clear()
	DiplomacyAI._collect_existing_war_preparation(state, 0, actions, {})
	_check(actions.size() == 1 and int(actions[0].kind) == DiplomacyAI.Action.ISSUE_ULTIMATUM, "real assembly yields ultimatum")
	if actions.is_empty():
		sim.free()
		return
	var assembly_days := state.day - started_day
	_check(sim._execute_diplomatic_action(actions[0]), "ultimatum commits after actual movement")
	var outcome := int(state.diplomatic_history[-1].get("ultimatum", {}).get("outcome", -1))
	_check(outcome == (UltimatumRules.Outcome.REFUSE if refusal else UltimatumRules.Outcome.ANNEX), "fixture reaches the intended ultimatum outcome")
	var entry := 28 if capital_only or center_frontier else 27
	var entered := false
	if refusal:
		_check(state.is_enemy(0, 1), "refusal starts actual war")
		if center_frontier:
			var launched := state.campaign_front_for(0, 28, CoalitionCampaignFront.Mode.OFFENSE)
			_check(launched != null and launched.camp_city_id == staging,
				"direct prepared launch establishes its actual assembly node as base")
			_check(sim._campaign_entry_fu(0, 28, [0] as Array[int]) == -1,
				"rear fu is not an accessible initial entry")
			var departing := 0
			for army in state.armies:
				if army.owner_nation == 0 and army.ai_target_city == 28 and army.ai_action == ActionCandidate.Kind.ATTACK and (army.on_edge or not army.path.is_empty()):
					departing += army.size
			_check(departing > 0, "prepared armies receive real direct-zhou attack orders in the declaration round")
		for _step in range(600):
			sim._advance_day()
			for army in state.armies:
				entered = entered or (army.owner_nation == 0 and army.is_at_city_node(entry))
			if state.food_pool_holder(state.cities[28].owner_nation) == 0:
				break
		_check(entered, "assembled troops enter the actual target state")
		_check(state.food_pool_holder(state.cities[28].owner_nation) == 0, "refusal chain reaches actual polity capital capture without changing occupation attribution")
	else:
		_check(not state.nations[1].alive and state.cities[28].owner_nation == 0, "accepted ultimatum peacefully integrates capital remnant")
		_check(not state.is_enemy(0, 1) and state.campaign_fronts.is_empty(), "peaceful integration does not create fake battle tasks")
	_check(state.nations[0].war_preparation_target_nation == -1, "prewar commands are released after launch")
	print("REGIONAL_EXPANSION_CHAIN capital_only=%s subject_frontier=%s river=%s center_frontier=%s outcome=%d assembly_days=%d entered=%s capital_owner=%d elapsed_days=%d" % [
		capital_only, subject_frontier, river_crossing, center_frontier, outcome, assembly_days, entered, state.cities[28].owner_nation, state.day - started_day])
	sim.free()


func _test_direct_center_deployment() -> void:
	for scenario in range(3):
		var state := Fixtures.fixture()
		state.edge_of(26, 27).max_manpower = 0
		state._add_edge(26, 28)
		state.road_network_revision += 1
		state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
		if scenario == 1:
			state.cities[28].garrison_manpower = 1000000
		elif scenario == 2:
			state.edge_of(26, 28).max_manpower = 0
			state.road_network_revision += 1
		var front := state.create_campaign_front(
			state.war_id_between(0, 1), [0] as Array[int], 0,
			CoalitionCampaignFront.Mode.OFFENSE, 28)
		front.staging_city_id = 26
		for army in state.armies:
			if army.owner_nation == 0:
				army.location_city = 26
				army.move_from = 26
				army.campaign_war_id = front.war_id
				army.campaign_front_id = front.front_id
				front.army_assignments[army.id] = 26
		var sim := Simulation.new()
		sim.setup(state)
		_check(sim._campaign_entry_fu(0, 28, [0] as Array[int]) < 0,
			"direct-center fixture has no legal fu entry")
		sim._manage_administrative_campaign(front)
		var departing := false
		for army in state.armies:
			departing = departing or (army.owner_nation == 0 and army.ai_target_city == 28 and army.ai_action == ActionCandidate.Kind.ATTACK and (army.on_edge or not army.path.is_empty()))
		_check(departing == (scenario != 2),
			"regular direct-center deployment still requires ready troops and an actual route (scenario %d)" % scenario)
		_check(front.phase == (CoalitionCampaignFront.Phase.ASSAULT_CENTER if scenario != 2 else CoalitionCampaignFront.Phase.ASSEMBLE),
			"direct-center phase follows actual deployment, not existence of a rear fu")
		sim.free()


func _subject_crossing(state: GameState) -> void:
	state.edge_of(26, 27).max_manpower = 0
	var dock := City.new()
	dock.id = state.cities.size()
	dock.owner_nation = 1
	dock.is_dock = true
	dock.map_position = Vector2(26.5, 0)
	state.cities.append(dock)
	state.adjacency[dock.id] = [] as Array[int]
	state.recognized_city_owners.append(1)
	state.region_ids.append(-1)
	state.administrative_center_by_city.append(-1)
	for bank in [26, 27]:
		state._add_edge(bank, dock.id)
		var edge := state.edge_of(bank, dock.id)
		edge.kind = Edge.Kind.LANDING
		edge.max_manpower = Edge.WATER_MANPOWER
	state.road_network_revision += 1
	state.ownership_revision += 1


func _add_third_party_war(state: GameState) -> void:
	var nation := Nation.new()
	nation.id = 3
	var city_id := state.cities.size()
	nation.capital_city_id = city_id
	nation.strategic_region_anchor_city_id = city_id
	nation.ruler_started_day = state.day
	nation.treasury_gold = 1000000
	state.nations.append(nation)
	var city := City.new()
	city.id = city_id
	city.owner_nation = 3
	city.map_position = Vector2(30, 1)
	city.food_storage = 1000000
	state.cities.append(city)
	state.adjacency[city_id] = [] as Array[int]
	state.region_ids.append(1)
	state.administrative_center_by_city.append(city_id)
	state.administrative_center_city_ids.append(city_id)
	state.recognized_city_owners.append(3)
	state._add_edge(29, city_id)
	for member_id in range(3):
		state.set_diplomatic_relation(member_id, 3, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(1, 3, GameState.DiplomaticRelation.WAR)
	state.ownership_revision += 1
	state.administrative_region_revision += 1
	state.region_analysis_revision += 1


func _test_stale_submission() -> void:
	var state := Fixtures.fixture()
	state.cities[26].owner_nation = 2
	state.suzerainty[2] = {"overlord_id": 0, "civil_war": false}
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	state.ownership_revision += 1
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(state, actions, {}, {}, 0, 1)
	_check(not actions.is_empty(), "subject frontier initially proposes preparation")
	var sim := Simulation.new()
	sim.setup(state)
	state.suzerainty.clear()
	state.diplomacy_revision += 1
	if not actions.is_empty():
		_check(not sim._execute_diplomatic_action(actions[0]), "submission revalidates loss of peaceful frontier")
	_check(state.nations[0].war_preparation_target_nation == -1, "rejected stale preparation leaves no state")
	sim.free()
	state = Fixtures.fixture()
	actions.clear()
	DiplomacyAI._collect_war_actions(state, actions, {}, {}, 0, 1)
	_check(not actions.is_empty(), "conqueror initially proposes ordinary expansion")
	sim = Simulation.new()
	sim.setup(state)
	state.nations[0].ruler_archetype = RulerProfile.DIPLOMAT
	if not actions.is_empty():
		_check(not sim._execute_diplomatic_action(actions[0]), "preparation commit revalidates a newly forbidden ruler")
	_check(state.nations[0].war_preparation_target_nation == -1, "forbidden ruler gets no stale prewar command pool")
	sim.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
