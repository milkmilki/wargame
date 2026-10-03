extends SceneTree

var checks := 0
var failures: Array[String] = []


func _init() -> void:
	_test_shared_siege(0)
	_test_shared_siege(1)
	_test_side_eligibility()
	_test_city_defender_exclusion()
	_test_allied_challengers()
	_test_partial_peace()
	for message in failures:
		push_error("COALITION_SIEGE_FAIL: " + message)
	print("COALITION_SIEGE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _fixture() -> Dictionary:
	var state := GameState.new()
	state.rng.seed = 97131
	for owner in range(5):
		var nation := Nation.new()
		nation.id = owner
		nation.capital_city_id = owner * 4
		nation.treasury_gold = 1000000
		state.nations.append(nation)
		for offset in range(4):
			var city := City.new()
			city.id = state.cities.size()
			city.owner_nation = owner
			city.map_position = Vector2(offset * 10, owner * 10)
			city.food_storage = 1000000
			city.garrison_manpower = 1000 if offset % 2 == 0 else 0
			state.cities.append(city)
			state.adjacency[city.id] = [] as Array[int]
			state.region_ids.append(0)
			state.administrative_center_by_city.append(owner * 4 + (offset / 2) * 2)
			state.recognized_city_owners.append(owner)
		state.administrative_center_city_ids.append(owner * 4)
		state.administrative_center_city_ids.append(owner * 4 + 2)
		state._add_edge(owner * 4, owner * 4 + 1)
		state._add_edge(owner * 4 + 1, owner * 4 + 3)
		state._add_edge(owner * 4 + 3, owner * 4 + 2)
	for a in range(5):
		for b in range(a + 1, 5):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	state.cities[11].owner_nation = 0
	state.recognized_city_owners[11] = 0
	state._add_edge(1, 5)
	for city_id in [1, 5, 13, 17]:
		state._add_edge(city_id, 11)
	state.edge_of(11, 10).distance = 1
	state.edge_of(11, 10).max_manpower = 100000
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	var war_id := state.war_id_between(0, 2)
	state.merge_war_ids(war_id, state.war_id_between(1, 2))
	state.cities[10].garrison_manpower = 1000000
	var sim := Simulation.new()
	sim.setup(state)
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
	return {"state": state, "sim": sim, "war_id": war_id}


func _army(state: GameState, owner: int, size: int = 15000) -> Army:
	var army := Army.new()
	army.id = 97000 + state.armies.size()
	army.owner_nation = owner
	army.size = size
	army.max_size = size
	army.morale = 2.0
	army.max_morale = 2.0
	army.attack = 20
	army.defense = 20
	army.location_city = 11
	army.move_from = 11
	state.armies.append(army)
	return army


func _join(data: Dictionary, army: Army) -> Battle:
	var sim: Simulation = data.sim
	var state: GameState = data.state
	army.state = Army.State.MOVING
	army.move_to = 10
	army.move_progress = 1.0
	sim._start_or_join_siege(army, state.cities[10], state.edge_of(11, 10))
	return sim._siege_battle_of(state.cities[10])


func _front(data: Dictionary, armies: Array[Army]) -> CoalitionCampaignFront:
	var front := CoalitionCampaignFront.new()
	front.war_id = data.war_id
	front.center_city_id = 10
	front.mode = CoalitionCampaignFront.Mode.OFFENSE
	front.phase = CoalitionCampaignFront.Phase.ASSAULT_CENTER
	front.camp_city_id = 11
	front.staging_city_id = 11
	for army in armies:
		front.army_assignments[army.id] = 10
	data.state.register_campaign_front(front, [0, 1] as Array[int], 0)
	return front


func _test_shared_siege(first_owner: int) -> void:
	var data := _fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var first := _army(state, first_owner)
	var ally := _army(state, 1 - first_owner)
	var front := _front(data, [first, ally])
	var siege := _join(data, first)
	var original_claimant := siege.siege_claimant_nation
	var retreat_days := 0
	var regroup_decisions := 0
	for tick in range(60):
		state.day += 1
		if tick % 10 == 0:
			sim._manage_administrative_campaign(front)
			if front.phase != CoalitionCampaignFront.Phase.ASSAULT_CENTER:
				regroup_decisions += 1
		sim._advance_movement()
		if ally.state == Army.State.RETREATING or ally.forced_retreat:
			retreat_days += 1
	_check(retreat_days == 0, "allied besieger must not bounce from capital to camp (first=%d, retreat_days=%d)" % [first_owner, retreat_days])
	_check(regroup_decisions == 0, "ongoing coalition blockade keeps a stable capital-assault phase across planning decisions")
	_check(siege.side_a.has(first) and siege.side_a.has(ally), "both nations remain on the same besieging side")
	_check(ally.state == Army.State.FIGHTING and ally.battle_id == siege.id, "real arriving ally joins rather than administratively retreating")
	_check(not siege.finished and state.cities[10].owner_nation == 2, "insufficient siege force maintains a blockade without phantom capture")
	# A later real relief force must fight both allies before garrison assault.
	state.cities[10].garrison_manpower = 100
	state.garrison_revision += 1
	var defender := _army(state, 2, 10000)
	defender.location_city = 10
	defender.move_from = 10
	sim._reconcile_siege_city_defenders(siege)
	_check(siege.uses_field_combat_rules() and siege.side_b.has(defender)
		and siege.side_a.has(first) and siege.side_a.has(ally), "real relief engages the entire attacking coalition, separately from the virtual garrison")
	for tick in range(100):
		state.day += 1
		sim._advance_movement()
		if state.cities[10].owner_nation != 2:
			break
	_check(state.cities[10].owner_nation == original_claimant, "coalition capture keeps the existing occupation claim, not the alliance representative")
	_check(not front.combat_report_locked, "last real field engagement unlocks the shared front report")
	_check(first.state != Army.State.RETREATING and ally.state != Army.State.RETREATING, "victorious coalition does not send its partner back to camp")
	print("COALITION_SIEGE_METRIC first=%d blockade_days=60 rejected_retreat_days=%d captured_by=%d" % [first_owner, retreat_days, state.cities[10].owner_nation])
	sim.free()


func _test_side_eligibility() -> void:
	var data := _fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var siege := _join(data, _army(state, 0))
	state.set_diplomatic_relation(3, 2, GameState.DiplomaticRelation.WAR)
	state.merge_war_ids(data.war_id, state.war_id_between(3, 2))
	var unrelated := _army(state, 3)
	_join(data, unrelated)
	_check(not siege.has_army(unrelated), "sharing a war ID without the same alliance bloc does not permit coalition entry")
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.NEUTRAL)
	var neutral_ally := _army(state, 1)
	_join(data, neutral_ally)
	_check(not siege.has_army(neutral_ally), "neutral ally without this war cannot join siege")
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	var separate_war_ally := _army(state, 1)
	_join(data, separate_war_ally)
	_check(not siege.has_army(separate_war_ally), "alliance alone cannot merge unrelated wars into one siege side")
	sim.free()


func _test_city_defender_exclusion() -> void:
	var data := _fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	state.set_diplomatic_relation(3, 2, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(3, 0, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(4, 0, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(4, 2, GameState.DiplomaticRelation.WAR)
	var siege := _join(data, _army(state, 0))
	var defender := _army(state, 3)
	_join(data, defender)
	var challenger := _army(state, 4)
	_join(data, challenger)
	_check(siege.side_b.has(defender) and siege.side_b_defends_city, "city's allied relief remains on the defense side")
	_check(not siege.has_army(challenger), "hostile third-party challenger cannot mix with city defenders")
	sim.free()


func _test_allied_challengers() -> void:
	var data := _fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	state.set_diplomatic_relation(3, 4, GameState.DiplomaticRelation.ALLIED)
	for challenger in [3, 4]:
		state.set_diplomatic_relation(challenger, 0, GameState.DiplomaticRelation.WAR)
		state.set_diplomatic_relation(challenger, 2, GameState.DiplomaticRelation.WAR)
	state.merge_war_ids(state.war_id_between(3, 0), state.war_id_between(4, 0))
	var siege := _join(data, _army(state, 0))
	var first := _army(state, 3)
	var ally := _army(state, 4)
	_join(data, first)
	_join(data, ally)
	_check(siege.side_b.has(first) and siege.side_b.has(ally) and not siege.side_b_defends_city, "allied challengers share a separate hostile side")
	siege.winner_side = 2
	siege.finished = true
	sim._finish_siege_field_engagement(siege)
	_check(siege.side_a.has(first) and siege.side_a.has(ally), "coalition challenger takeover retains both nations")
	sim.free()


func _test_partial_peace() -> void:
	var data := _fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var first := _army(state, 0)
	var ally := _army(state, 1)
	var siege := _join(data, first)
	_join(data, ally)
	var survivor_size := ally.size
	var survivor_morale := ally.morale
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.NEUTRAL)
	sim._reconcile_battles_after_coalition_peace([0, 1] as Array[int], [2] as Array[int])
	_check(not siege.finished and siege.side_a.has(ally), "first nation's peace must not terminate its partner's ongoing siege")
	_check(ally.state == Army.State.FIGHTING and ally.battle_id == siege.id, "retained partner must not be repatriated by the full peace coordinator")
	_check(not siege.has_army(first) and first.battle_id != siege.id, "departing besieger loses every battle reference")
	_check(siege.siege_attacker_nation == 1 and siege.siege_claimant_nation == 1, "siege and occupation identity transfer to the remaining valid besieger")
	_check(ally.size == survivor_size and ally.morale == survivor_morale, "administrative coalition change has no extra casualty or morale penalty")
	sim.free()
