extends SceneTree

var failures: int = 0
var checks: int = 0


class RejectingSimulation extends Simulation:
	var rejected_ids: Array[int] = []

	func _execute_ai_candidate(
		army: Army, candidate: ActionCandidate,
		prepared_path: Array[int] = [], path_prevalidated: bool = false
	) -> bool:
		if rejected_ids.has(army.id):
			return false
		return super._execute_ai_candidate(army, candidate, prepared_path, path_prevalidated)


func _init() -> void:
	_test_empty_command_batch()
	for queued in [false, true]:
		_test_defense_regroups_at_center(queued)
		_test_busy_force_cannot_launch(queued)
		_test_offensive_readiness(queued)
		_test_shared_front_uses_each_owners_access(queued)
	_test_unreachable_sortie_waits_for_route()
	_test_stale_target_is_not_progress()
	_test_attack_interrupted_by_real_field_battle()
	_test_break_in_requires_available_force()
	_test_rejected_commands_do_not_consume_quota(false)
	_test_rejected_commands_do_not_consume_quota(true)
	print("CAMPAIGN_ACTION_READINESS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func _army_ids(state: GameState) -> Dictionary:
	var result := {}
	for army in state.armies:
		result[army.id] = true
	return result


func _test_empty_command_batch() -> void:
	var state := _state()
	var army := _army(state, 900, 0, 0)
	var sim := Simulation.new()
	sim.setup(state)
	sim._begin_ai_command_collection({})
	var order := ActionCandidate.make(ActionCandidate.Kind.REINFORCE, 1.0, "empty batch", 1)
	check(not sim._execute_ai_candidate(army, order), "an empty snapshot must not admit any army")
	sim._commit_ai_command_collection([0] as Array[int])
	check(army.state == Army.State.IDLE, "empty batch must not change movement")
	sim.free()


func _test_defense_regroups_at_center(queued: bool) -> void:
	var state := _state()
	var army_a := _army(state, 10, 0, 1)
	var army_b := _army(state, 11, 0, 1)
	_army(state, 12, 1, 2, 20000)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [army_a, army_b])
	var sim := Simulation.new()
	sim.setup(state)
	if queued:
		sim._begin_ai_command_collection(_army_ids(state))
	sim._execute_coalition_defense(front)
	check(front.phase == CoalitionCampaignFront.Phase.HOLD_AND_REINFORCE,
		"entering the state does not mean assembled at the center")
	if queued:
		sim._commit_ai_command_collection([0, 1] as Array[int])
	for army in [army_a, army_b]:
		check(army.ai_target_city == 0 and army.state == Army.State.MOVING,
			"defense forces in a Fu must assemble at the center first")
	sim.free()


func _test_busy_force_cannot_launch(queued: bool) -> void:
	var state := _state()
	var idle := _army(state, 20, 0, 0)
	var busy := _army(state, 21, 0, 0)
	busy.state = Army.State.FIGHTING
	_army(state, 22, 1, 2, 20000)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [idle, busy])
	var sim := Simulation.new()
	sim.setup(state)
	if queued:
		sim._begin_ai_command_collection(_army_ids(state))
	sim._execute_coalition_defense(front)
	check(front.phase == CoalitionCampaignFront.Phase.HOLD_AND_REINFORCE,
		"troops busy in another battle cannot satisfy the sortie threshold")
	check(idle.ai_target_city != 2, "insufficient executable force must not depart piecemeal")
	if queued:
		sim._commit_ai_command_collection([0, 1] as Array[int])
	busy.state = Army.State.IDLE
	var reinforcement := _army(state, 23, 0, 1)
	front.army_assignments[reinforcement.id] = 0
	reinforcement.campaign_front_id = front.front_id
	reinforcement.campaign_war_id = front.war_id
	if queued:
		sim._begin_ai_command_collection(_army_ids(state))
	sim._execute_coalition_defense(front)
	check(front.phase == CoalitionCampaignFront.Phase.SORTIE,
		"available assembled force must launch in this planning cycle")
	if queued:
		sim._commit_ai_command_collection([0, 1] as Array[int])
	for army in [idle, busy]:
		check(army.ai_target_city == 2 and army.state == Army.State.MOVING,
			"the threshold force must actually receive executable orders")
	check(reinforcement.ai_target_city == 0 and reinforcement.state == Army.State.MOVING,
		"later bound reinforcements must still assemble while the sortie is underway")
	check(sim.ai_last_command_commit_failures == 0, "validated orders must commit successfully")
	sim._execute_coalition_defense(front)
	check(front.phase == CoalitionCampaignFront.Phase.SORTIE,
		"an ongoing sortie must not return to assembling because troops left the center")
	sim.free()


func _test_offensive_readiness(queued: bool) -> void:
	var state := _state()
	state._add_edge(2, 0)
	var army := _army(state, 30, 1, 2, 60000)
	army.state = Army.State.FIGHTING
	var front := _front(state, 1, CoalitionCampaignFront.Mode.OFFENSE, [army])
	front.camp_city_id = 2
	front.phase = CoalitionCampaignFront.Phase.HOLD_CAMP
	var sim := Simulation.new()
	sim.setup(state)
	check(sim._campaign_center_ready_manpower(front, true) == 0,
		"fighting at camp is not readiness to advance toward the center")
	if queued:
		sim._begin_ai_command_collection(_army_ids(state))
	sim._manage_administrative_campaign(front)
	check(front.phase != CoalitionCampaignFront.Phase.ASSAULT_CENTER,
		"offensive phase must not claim launch when every force is busy")
	if queued:
		sim._commit_ai_command_collection([0, 1] as Array[int])
	army.state = Army.State.IDLE
	if queued:
		sim._begin_ai_command_collection(_army_ids(state))
	sim._manage_administrative_campaign(front)
	check(front.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER,
		"ready camp force must launch without another arbitrary wait")
	if queued:
		sim._commit_ai_command_collection([0, 1] as Array[int])
	check(army.state == Army.State.MOVING and army.ai_target_city == 0,
		"offensive phase must correspond to actual movement")
	for cycle in range(3):
		sim._manage_administrative_campaign(front)
		check(front.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER
			and front.assault_stalled_days == 0, "real ongoing movement is progress")
	sim.free()


func _test_stale_target_is_not_progress() -> void:
	var state := _state()
	state.cities[3].owner_nation = 0
	var army := _army(state, 40, 1, 2)
	army.ai_target_city = 0
	var front := _front(state, 1, CoalitionCampaignFront.Mode.OFFENSE, [army])
	front.camp_city_id = 2
	front.phase = CoalitionCampaignFront.Phase.ASSAULT_CENTER
	var sim := Simulation.new()
	sim.setup(state)
	for cycle in range(Simulation.ASSAULT_STALLED_FALLBACK_DAYS):
		sim._manage_administrative_campaign(front)
	check(front.phase == CoalitionCampaignFront.Phase.HOLD_CAMP,
		"stale target without a path must not suppress corridor recovery")
	check(army.state == Army.State.IDLE and army.path.is_empty(),
		"a physically connected enemy corridor must not grant military transit")
	sim.free()


func _test_shared_front_uses_each_owners_access(queued: bool) -> void:
	var state := _state()
	for id in [2, 3]:
		var nation := Nation.new()
		nation.id = id
		nation.capital_city_id = 0 if id == 2 else 1
		state.nations.append(nation)
	state.cities[1].owner_nation = 3
	state.cities[3].owner_nation = 3
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(1, 3, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(2, 3, GameState.DiplomaticRelation.ALLIED)
	var blocked := _army(state, 60, 0, 0)
	var available := _army(state, 61, 2, 0)
	_army(state, 62, 1, 2, 10000)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [blocked, available])
	front.participant_nation_ids = [0, 2] as Array[int]
	var sim := Simulation.new()
	sim.setup(state)
	if queued:
		sim._begin_ai_command_collection(_army_ids(state))
	sim._execute_coalition_defense(front)
	if queued:
		sim._commit_ai_command_collection([0, 2, 1, 3] as Array[int])
	check(front.phase == CoalitionCampaignFront.Phase.SORTIE
		and available.state == Army.State.MOVING and available.ai_target_city == 2,
		"an inaccessible first army must not consume the accessible ally's dispatch quota")
	check(blocked.state == Army.State.IDLE and blocked.path.is_empty(),
		"shared fronts must not grant another member's transit rights")
	sim.free()


func _test_attack_interrupted_by_real_field_battle() -> void:
	var state := _state()
	state._add_edge(2, 0)
	var army := _army(state, 80, 1, 2)
	var enemy := _army(state, 81, 0, 0)
	var front := _front(state, 1, CoalitionCampaignFront.Mode.OFFENSE, [army])
	front.camp_city_id = 2
	front.phase = CoalitionCampaignFront.Phase.ASSAULT_CENTER
	var sim := Simulation.new()
	sim.setup(state)
	var battle := state.new_battle(Battle.Kind.FIELD)
	battle.edge = state.edge_of(2, 0)
	battle.side_a = [army]
	battle.side_b = [enemy]
	army.state = Army.State.FIGHTING
	army.on_edge = true
	army.move_from = 2
	army.move_to = 0
	army.ai_action = ActionCandidate.Kind.ATTACK
	army.ai_target_city = 0
	army.battle_id = battle.id
	for cycle in range(3):
		sim._manage_administrative_campaign(front)
		check(front.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER
			and front.assault_stalled_days == 0,
			"a real battle during an issued attack is ongoing action, not a stalled order")
	sim.free()


func _test_unreachable_sortie_waits_for_route() -> void:
	var state := _state()
	state.cities[1].owner_nation = 1
	var army := _army(state, 70, 0, 0)
	_army(state, 71, 1, 2, 10000)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [army])
	var sim := Simulation.new()
	sim.setup(state)
	for cycle in range(3):
		sim._execute_coalition_defense(front)
		check(front.phase == CoalitionCampaignFront.Phase.HOLD_AND_REINFORCE,
			"a route blocked by an enemy Fu must not produce a phantom sortie")
	state._add_edge(0, 2)
	state.road_network_revision += 1
	sim._execute_coalition_defense(front)
	check(front.phase == CoalitionCampaignFront.Phase.SORTIE
		and army.state == Army.State.MOVING, "opening the route must enable immediate real dispatch")
	sim.free()


func _test_rejected_commands_do_not_consume_quota(reject_all: bool) -> void:
	var state := _state()
	var first := _army(state, 90, 0, 0)
	var second := _army(state, 91, 0, 0)
	_army(state, 92, 1, 2, 10000)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [first, second])
	front.phase = CoalitionCampaignFront.Phase.SORTIE
	var sim := RejectingSimulation.new()
	sim.rejected_ids.append(90)
	if reject_all:
		sim.rejected_ids.append(91)
	sim.setup(state)
	sim._execute_coalition_defense(front)
	check(first.state == Army.State.IDLE, "rejected orders must not count as real departure")
	if reject_all:
		check(front.phase == CoalitionCampaignFront.Phase.HOLD_AND_REINFORCE,
			"no accepted action must leave the defense in rallying, not a stale sortie")
	else:
		check(front.phase == CoalitionCampaignFront.Phase.SORTIE
			and second.state == Army.State.MOVING,
			"a failed first command must not prevent trying the next ready army")
	sim.free()


func _test_break_in_requires_available_force() -> void:
	var state := _state()
	state.cities[1].owner_nation = 1
	state.cities[2].owner_nation = 0
	state.cities[3].owner_nation = 0
	state.administrative_center_by_city[1] = 1
	state.administrative_center_city_ids.append(1)
	var army := _army(state, 50, 1, 1, 60000)
	army.state = Army.State.FIGHTING
	var front := _front(state, 1, CoalitionCampaignFront.Mode.OFFENSE, [army])
	front.staging_city_id = 1
	front.tactical_target_city_ids = [2] as Array[int]
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_administrative_campaign(front)
	check(front.phase == CoalitionCampaignFront.Phase.ASSEMBLE,
		"busy staging troops must not launch the entry attack")
	army.state = Army.State.IDLE
	sim._manage_administrative_campaign(front)
	check(front.phase == CoalitionCampaignFront.Phase.BREAK_IN
		and army.state == Army.State.MOVING and army.ai_target_city == 2,
		"available staging force must launch the entry attack")
	sim.free()


func _state() -> GameState:
	var state := GameState.new()
	for id in range(2):
		var nation := Nation.new()
		nation.id = id
		nation.capital_city_id = 0 if id == 0 else 2
		state.nations.append(nation)
	for id in range(4):
		var city := City.new()
		city.id = id
		city.owner_nation = 0 if id < 2 else 1
		city.map_position = Vector2(id, 0)
		city.garrison_manpower = 1000 if id == 0 else 0
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		state.administrative_center_by_city.append(0)
		state.region_ids.append(0)
		state.recognized_city_owners.append(city.owner_nation)
	state.administrative_center_city_ids.append(0)
	for pair in [[0, 1], [1, 2], [0, 3], [3, 2]]:
		state._add_edge(pair[0], pair[1])
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_war_objective(1, 0, 0, "action readiness")
	return state


func _army(state: GameState, id: int, owner: int, location: int, size: int = 15000) -> Army:
	var army := Army.new()
	army.id = id
	army.owner_nation = owner
	army.location_city = location
	army.size = size
	army.max_size = size
	state.armies.append(army)
	return army


func _front(state: GameState, owner: int, mode: int, armies: Array[Army]) -> CoalitionCampaignFront:
	var front := CoalitionCampaignFront.new()
	front.center_city_id = 0
	front.mode = mode
	front.war_id = state.war_id_between(0, 1)
	for army in armies:
		front.army_assignments[army.id] = 0
	return state.register_campaign_front(front, [owner] as Array[int], owner)
