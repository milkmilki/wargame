extends SceneTree

var checks := 0
var failures := 0
const Direct = preload("res://tests/direct_center_camp.gd")


func _init() -> void:
	var state := fixture()
	check(state.campaign_minimum_launch_requirement(0, 1) == 9001, "ordinary strict 0.9V excludes R")
	check(state.campaign_attack_requirement(0, 1) == 300000, "R and field demand take maximum")
	check(state.campaign_prewar_launch_requirement(0, 1, 1) == 300000, "full modified R remains in prewar assembly")
	state.cities[1].garrison_manpower = 1000
	state.armies[0].size = 100000
	check(state.campaign_prewar_launch_requirement(0, 1, 1) == 200000, "prewar reserves full 2V")
	state.nations[0].ruler_archetype = RulerProfile.CONQUEROR
	check(state.campaign_minimum_launch_requirement(0, 1) == 45001, "conqueror strict 0.45V")
	check(state.campaign_prewar_launch_requirement(0, 1, 1) == 200000, "2V is not discounted")
	state.armies[0].size = 1
	check(state.campaign_minimum_launch_requirement(0, 1) == 1, "fractional boundary uses integer strict minimum")
	state.armies.clear()
	check(state.campaign_minimum_launch_requirement(0, 1) == 1, "V zero still needs real troops")
	check(state.campaign_prewar_launch_requirement(0, 1, 1) == 45000, "prewar keeps 45000 floor")
	for conqueror in [false, true]:
		for direct in [false, true]:
			_test_real_departure(conqueror, direct)
	_test_empty_and_recovery()
	_test_field_blockade_siege()
	_test_reinforcement_promises()
	_test_coalition_reinforcement()
	print("FIELD_MANPOWER_REQUIREMENTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func fixture() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	for id in range(2):
		var nation := Nation.new()
		nation.id = id
		nation.capital_city_id = id
		nation.ruler_archetype = RulerProfile.BALANCED
		state.nations.append(nation)
	for id in range(3):
		var city := City.new()
		city.id = id
		city.owner_nation = 0 if id == 0 else 1
		city.map_position = Vector2(id, 0)
		city.garrison_manpower = 100000 if id == 1 else 0
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		state.administrative_center_by_city.append(0 if id == 0 else 1)
		state.region_ids.append(0)
		state.recognized_city_owners.append(city.owner_nation)
	state.administrative_center_city_ids = [0, 1] as Array[int]
	state._add_edge(0, 1)
	state._add_edge(1, 2)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_war_objective(0, 1, 1, "field demand regression")
	var enemy := Army.new()
	enemy.id = 10
	enemy.owner_nation = 1
	enemy.location_city = 1
	enemy.size = 10000
	enemy.max_size = 100000
	state.armies.append(enemy)
	return state


func _test_real_departure(conqueror: bool, direct: bool) -> void:
	var state: GameState = Direct.fixture()
	state.nations[0].ruler_archetype = RulerProfile.CONQUEROR if conqueror else RulerProfile.BALANCED
	state.cities[3].garrison_manpower = 100000
	var target := 3
	if not direct:
		state.edge_of(2, 3).max_manpower = 0
		state._add_edge(2, 4)
		state.road_network_revision += 1
		target = 4
	var enemy: Army = Direct.army(state, 1, 3, 10000)
	var troop: Army = Direct.army(state, 0, 2, 4500 if conqueror else 9000)
	var front: CoalitionCampaignFront = Direct.front(state, [troop])
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_administrative_campaign(front)
	check(troop.state == Army.State.IDLE and front.phase == CoalitionCampaignFront.Phase.ASSEMBLE,
		"equal field boundary cannot depart conqueror=%s direct=%s" % [conqueror, direct])
	troop.size += 1
	sim._manage_administrative_campaign(front)
	check(troop.state == Army.State.MOVING and troop.ai_target_city == target,
		"one soldier over boundary issues real order below R and 45000")
	var force := sim._campaign_action_force(front, target, ActionCandidate.Kind.ATTACK)
	check(int(force.manpower) == troop.size and force.armies.size() == 1,
		"issued action counts each army once")
	enemy.size = 1000000
	sim._manage_administrative_campaign(front)
	check(troop.state == Army.State.MOVING and troop.ai_target_city == target,
		"higher demand does not revoke ongoing action")
	sim.free()


func _test_coalition_reinforcement() -> void:
	var state: GameState = Direct.fixture()
	state.nations[2].alive = true
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	var attacker: Army = Direct.army(state, 0, 3, 20000)
	var guard: Army = Direct.army(state, 1, 3, 5000)
	var ally: Army = Direct.army(state, 2, 3, 5000)
	var reserve: Army = Direct.army(state, 1, 4, 5000)
	var ally_reserve: Army = Direct.army(state, 2, 4, 5000)
	var incoming: Army = Direct.army(state, 2, 4, 4000)
	for troop in [attacker, guard, ally, reserve, ally_reserve]:
		troop.battle_group_id = troop.id
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city = state.cities[3]
	battle.siege_attacker_nation = 0
	battle.side_a = [attacker]
	battle.side_b = [guard, ally]
	for troop in [attacker, guard, ally]:
		troop.state = Army.State.FIGHTING
		troop.battle_id = battle.id
	var sim := Simulation.new()
	sim.setup(state)
	check(sim._execute_ai_candidate(incoming, ActionCandidate.make(
		ActionCandidate.Kind.REINFORCE, 1, "allied promise", 3)), "allied promise has an issued route")
	# End this engagement before unified allocation; an active field report
	# deliberately admits no new wave, including on first takeover.
	battle.finished = true
	for troop in [guard, ally]:
		troop.state = Army.State.IDLE
		troop.battle_id = -1
	var context := {"war_id": state.war_id_between(1, 0), "members": [1, 2] as Array[int],
		"enemy_ids": [0] as Array[int], "key": "coalition"}
	sim._refresh_component_defense_tasks(context)
	var front := state.campaign_front_for(1, 3, CoalitionCampaignFront.Mode.DEFENSE)
	check(front != null and incoming.campaign_front_id == front.front_id,
		"coalition actual arrivals and prior promise bind to one defense task")
	sim._allocate_coalition_fronts(context)
	if front != null:
		sim._execute_coalition_defense(front)
	sim._resolve_nearby_main_battle_reinforcements()
	var added := int(reserve.state == Army.State.MOVING) + int(ally_reserve.state == Army.State.MOVING)
	check(added == 1, "coalition arrival plus incoming fills one shared deficit without both nations adding reserves")
	var report: Dictionary = state.coalition_campaign_allocation(front.war_id, 1)["fronts"][front.front_id]
	check(int(report["rally_idle_arrived"]) == 10000 and int(report["assigned_effective"]) == 19000,
		"mixed coalition commitments share one front while incoming stays separate from arrival")
	sim._allocate_coalition_fronts(context)
	sim._resolve_nearby_main_battle_reinforcements()
	check(int(reserve.state == Army.State.MOVING) + int(ally_reserve.state == Army.State.MOVING) == 1,
		"next reinforcement pass respects earlier coalition promise")
	sim.free()


func _test_empty_and_recovery() -> void:
	var state: GameState = Direct.fixture()
	var front: CoalitionCampaignFront = Direct.front(state, [])
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_administrative_campaign(front)
	check(front.phase == CoalitionCampaignFront.Phase.ASSEMBLE, "zero threat cannot launch an empty cohort")
	var recovering: Army = Direct.army(state, 0, 2, 1000)
	recovering.campaign_front_id = front.front_id
	recovering.campaign_war_id = front.war_id
	front.army_assignments[recovering.id] = 2
	front.phase = CoalitionCampaignFront.Phase.HOLD_CAMP
	recovering.state = Army.State.RECOVERING
	sim._manage_administrative_campaign(front)
	check(recovering.state == Army.State.RECOVERING and front.phase == CoalitionCampaignFront.Phase.HOLD_CAMP,
		"V zero does not bypass recovery")
	recovering.state = Army.State.IDLE
	sim._manage_administrative_campaign(front)
	check(recovering.state == Army.State.MOVING and recovering.ai_target_city == 3,
		"one real recovered army can depart with V zero")
	sim.free()


func _test_field_blockade_siege() -> void:
	var state: GameState = Direct.fixture()
	state.cities[3].garrison_manpower = 30000
	var troop: Army = Direct.army(state, 0, 2, 9001)
	troop.attack = 100
	troop.defense = 100
	var enemy: Army = Direct.army(state, 1, 3, 10000)
	enemy.attack = 1
	enemy.defense = 1
	var front: CoalitionCampaignFront = Direct.front(state, [troop])
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_administrative_campaign(front)
	for day_index in range(30):
		sim._advance_movement()
		if sim._siege_battle_of(state.cities[3]) != null:
			break
	var battle: Battle = sim._siege_battle_of(state.cities[3])
	check(battle != null and battle.uses_field_combat_rules(), "below R force reaches a real city field battle")
	if battle == null:
		sim.free()
		return
	battle.ensure_opening_dice(state.world_seed, true)
	for round_index in range(100):
		sim._resolve_battles()
		if not battle.uses_field_combat_rules():
			break
	check(not battle.uses_field_combat_rules() and not battle.finished,
		"field victory preserves siege shell")
	var rounds := battle.round_no
	sim._resolve_battles()
	check(battle.round_no == rounds and battle.assault_dice.is_empty() and state.cities[3].owner_nation == 1,
		"insufficient R blockades without attacking guards")
	var reserve: Army = Direct.army(state, 0, 2, 100000)
	reserve.campaign_front_id = front.front_id
	reserve.campaign_war_id = front.war_id
	front.army_assignments[reserve.id] = 3
	sim._manage_administrative_campaign(front)
	for day_index in range(40):
		sim._advance_movement()
		sim._resolve_battles()
		if not battle.assault_dice.is_empty():
			break
	check(not battle.assault_dice.is_empty() and battle.round_no > rounds,
		"actual reinforcement arrival satisfies R and starts guard assault")
	print("FIELD_DEMAND_CHAIN bound=%d arrived=%d R=%d field_rounds=%d" % [
		state.campaign_committed_manpower(0, 3), sim._siege_assault_manpower(battle),
		state.campaign_attack_requirement(0, 3, false), rounds])
	sim.free()


func _test_reinforcement_promises() -> void:
	var state: GameState = Direct.fixture()
	var attacker: Army = Direct.army(state, 0, 3, 10000)
	var guard: Army = Direct.army(state, 1, 3, 9001)
	guard.attack = 1
	guard.defense = 1
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city = state.cities[3]
	battle.siege_attacker_nation = 0
	battle.side_a = [attacker]
	battle.side_b = [guard]
	var sim := Simulation.new()
	sim.setup(state)
	check(int(state.campaign_defense_context(1, 3, state.war_id_between(0, 1))["requirement"]) == 9001,
		"ordinary reinforcements use manpower regardless of combat attributes")
	var regional_enemy: Army = Direct.army(state, 0, 4, 10000)
	check(int(state.campaign_defense_context(1, 3, state.war_id_between(0, 1))["requirement"]) == 18001,
		"reinforcement V includes regional enemies outside the current engagement")
	regional_enemy.state = Army.State.RECOVERING
	check(int(state.campaign_defense_context(1, 3, state.war_id_between(0, 1))["requirement"]) == 9001,
		"regional recovering armies remain excluded from reinforcement V")
	regional_enemy.state = Army.State.IDLE
	regional_enemy.is_city_garrison = true
	check(int(state.campaign_defense_context(1, 3, state.war_id_between(0, 1))["requirement"]) == 9001,
		"virtual guards in the activity index never become reinforcement V")
	regional_enemy.is_city_garrison = false
	regional_enemy.owner_nation = 2
	state.nations[2].alive = true
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	check(int(state.campaign_defense_context(1, 3, state.war_id_between(0, 1))["requirement"]) == 9001,
		"defense reinforcement does not project an unrelated war into this battle")
	var context := {"war_id": state.war_id_between(0, 1), "members": [1] as Array[int],
		"enemy_ids": [0] as Array[int], "key": "defense"}
	battle.finished = true
	sim._refresh_component_defense_tasks(context)
	var front := state.campaign_front_for(1, 3, CoalitionCampaignFront.Mode.DEFENSE)
	check(front != null and sim._front_effective_manpower(front) == 9001,
		"unified task counts real local defense without virtual garrison")
	guard.size = 5000
	var incoming: Army = Direct.army(state, 1, 4, 5000)
	var order := ActionCandidate.make(ActionCandidate.Kind.REINFORCE, 1, "promise", 3)
	check(sim._execute_ai_candidate(incoming, order), "reinforcement promise requires a real order")
	sim._refresh_component_defense_tasks(context)
	var report: Dictionary = state.coalition_campaign_allocation(front.war_id, 1)["fronts"][front.front_id]
	check(int(report["assigned_effective"]) == 10000 and front.army_assignments.size() == 2,
		"valid incoming binds once alongside actual participants")
	check(int(report["rally_idle_arrived"]) == 5000,
		"incoming is not arrival or field combat force")
	state.edge_of(3, 4).max_manpower = 0
	sim._allocate_coalition_fronts(context)
	check(not state._campaign_has_live_route(incoming, 3),
		"broken route no longer forms a valid incoming promise")
	sim.free()
