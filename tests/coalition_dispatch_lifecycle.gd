extends SceneTree

var checks := 0
var failures := 0


func _init() -> void:
	_test_due_component_includes_absent_member()
	_test_empty_snapshot_rejects_all_orders()
	_test_first_mobilization_fills_six_armies()
	_test_completed_defense_actually_counterattacks()
	_test_enemy_fu_recapture_without_field_army()
	_test_fu_recapture_selects_executable_frontier()
	_test_unreachable_bound_army_does_not_fill_gap()
	_test_existing_offense_is_not_reshuffled()
	_test_active_transfer_limit()
	_test_report_end_replans_tomorrow()
	_test_custom_policy_is_not_commanded()
	_test_new_army_outside_frozen_batch_is_not_commanded()
	_test_two_front_initial_floors()
	_test_offensive_reinforcement_binds_real_camp()
	_test_inflight_and_locked_bindings_are_preserved()
	_test_active_defense_donates_only_surplus()
	_test_taskless_locked_defense_waits_for_report()
	_test_expanded_batch_keeps_tick_start_freeze()
	_test_other_war_pool_is_not_mobilized()
	_test_live_incoming_and_invalid_route_context()
	_test_defense_context_does_not_mix_wars()
	_test_ordinary_arrival_waits_until_ten_day_cycle()
	_test_real_march_separates_travel_and_planning_wait()
	print("COALITION_DISPATCH_LIFECYCLE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _test_due_component_includes_absent_member() -> void:
	var state := _state()
	var defender := _army(state, 10, 0, 0, 30000)
	_army(state, 11, 1, 2, 10000)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [defender])
	var sim := Simulation.new()
	sim.setup(state)
	var enemy_view := sim._build_ai_view(1)
	var defense_plan := CityDefensePlan.new()
	defense_plan.view = enemy_view
	sim._run_ai_campaign_planning_phase(
		[1] as Array[int], {1: {"view": enemy_view, "defense_plan": defense_plan}},
		{1: {}}, {}, false, Time.get_ticks_usec()
	)
	sim._commit_ai_command_collection([1] as Array[int])
	check(defender.state == Army.State.MOVING and defender.ai_target_city == 2,
		"30000 assembled against 9001 demand must sortie even outside national rotation")
	check(front.phase == CoalitionCampaignFront.Phase.SORTIE,
		"a due coalition must receive a complete command batch")
	check(sim.ai_last_command_commit_failures == 0, "expanded coalition command batch must commit")
	print("COALITION_BATCH_METRIC assembled=30000 requirement=9001 outside_rotation_dispatched=%d commit_failures=%d" % [
		1 if defender.state == Army.State.MOVING else 0, sim.ai_last_command_commit_failures])
	sim.free()


func _test_empty_snapshot_rejects_all_orders() -> void:
	var state := _state()
	var army := _army(state, 20, 0, 0)
	var sim := Simulation.new()
	sim.setup(state)
	sim._begin_ai_command_collection({})
	var candidate := ActionCandidate.make(ActionCandidate.Kind.REINFORCE, 10.0, "empty batch", 1)
	check(not sim._queue_ai_candidate(army, candidate), "explicit empty batch must not mean all armies")
	sim._commit_ai_command_collection([0] as Array[int])
	check(army.state == Army.State.IDLE and army.path.is_empty(), "empty command batch must remain empty")
	sim.free()


func _test_first_mobilization_fills_six_armies() -> void:
	var state := _state()
	_army(state, 30, 1, 2, 99000)
	var reserves: Array[Army] = []
	for index in range(6):
		reserves.append(_army(state, 31 + index, 0, 0))
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [])
	var sim := Simulation.new()
	sim.setup(state)
	sim._allocate_coalition_fronts(_component(state, 0))
	check(front.army_assignments.size() == 6,
		"six unbound reserves must fill strict 89101 initial defense demand in one cycle")
	for army in reserves:
		check(army.campaign_front_id == front.front_id,
			"first mobilization does not spend the active-front transfer quota")
	print("COALITION_MOBILIZATION_METRIC required=89101 assigned=%d planning_cycles=1" % sim._front_effective_manpower(front))
	sim.free()


func _test_completed_defense_actually_counterattacks() -> void:
	var state := _state()
	var army := _army(state, 40, 0, 0, 60000)
	var defense := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [army])
	var old_front_id := defense.front_id
	var war_id := defense.war_id
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_coalition_campaigns()
	check(state.campaign_front(old_front_id) == null,
		"initial diplomatic objective without a real task must not retain defense")
	var current := state.campaign_front(army.campaign_front_id)
	check(current != null and current.mode == CoalitionCampaignFront.Mode.OFFENSE,
		"released defense troop must actually bind a counteroffensive, not only create an empty front")
	check(army.campaign_war_id == war_id, "counteroffensive preserves the original war pool")
	check(army.state == Army.State.MOVING and army.ai_target_city != 0,
		"released defender must receive a real counterattack rally or attack command")
	print("COALITION_COUNTERATTACK_METRIC defense_release_to_order_days=0 within_same_planning_cycle=true")
	sim.free()


func _test_enemy_fu_recapture_without_field_army() -> void:
	var state := _state()
	state.cities[2].owner_nation = 1
	var army := _army(state, 50, 0, 0)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [army])
	var sim := Simulation.new()
	sim.setup(state)
	sim._execute_coalition_defense(front)
	check(army.state == Army.State.MOVING and army.ai_target_city == 2,
		"enemy-held Fu is a real recapture task even with no enemy field army")
	check(sim._front_requirement(front) == GameState.INITIAL_HEAVY_ARMY_SIZE,
		"unguarded enemy Fu uses the existing one-army fallback")
	sim.free()


func _test_fu_recapture_selects_executable_frontier() -> void:
	var state := _state()
	state.cities[1].owner_nation = 1
	state.cities[2].owner_nation = 1
	var targets: Array[int] = [1, 2]
	EquivariantOrder.sort_city_ids(targets, state, 0, 0)
	state.edges.clear()
	state.edge_lookup.clear()
	for city_id in state.adjacency:
		state.adjacency[city_id] = [] as Array[int]
	state._add_edge(0, targets[1])
	state._add_edge(targets[1], targets[0])
	var army := _army(state, 51, 0, 0)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [army])
	var sim := Simulation.new()
	sim.setup(state)
	sim._execute_coalition_defense(front)
	check(army.state == Army.State.MOVING and army.ai_target_city == targets[1],
		"recapture must attack the executable frontier Fu before the blocked higher-ranked Fu")
	sim.free()


func _test_unreachable_bound_army_does_not_fill_gap() -> void:
	var state := _state()
	var neutral := Nation.new()
	neutral.id = 2
	neutral.capital_city_id = 1
	state.nations.append(neutral)
	state.cities[1].owner_nation = 2
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.NEUTRAL)
	# The graph is connected, but the only route from Fu2 to center0 crosses neutral Fu1.
	var blocked := _army(state, 60, 0, 2, 30000)
	var reserve := _army(state, 61, 0, 0)
	_army(state, 62, 1, 0, 10000)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [blocked])
	var sim := Simulation.new()
	sim.setup(state)
	sim._allocate_coalition_fronts(_component(state, 0))
	check(blocked.campaign_front_id == -1 and not front.army_assignments.has(blocked.id),
		"idle troop without military access to real receiving point must leave state binding")
	check(blocked.campaign_war_id == front.war_id, "unreachable troop stays in its original war pool")
	check(reserve.campaign_front_id == front.front_id,
		"unreachable state-local troops must not block an accessible reserve from filling demand")
	print("COALITION_REACHABILITY_METRIC unreachable_gap_occupants=%d" % [1 if blocked.campaign_front_id >= 0 else 0])
	sim.free()


func _test_existing_offense_is_not_reshuffled() -> void:
	var state := _state()
	state.administrative_center_city_ids.append(5)
	state.administrative_center_by_city[5] = 5
	var troops: Array[Army] = []
	for index in range(6):
		troops.append(_army(state, 70 + index, 0, 0))
	var established := _front(state, 0, CoalitionCampaignFront.Mode.OFFENSE, troops)
	established.center_city_id = 3
	established.staging_city_id = 2
	established.had_forces = true
	var other := _front(state, 0, CoalitionCampaignFront.Mode.OFFENSE, [])
	other.center_city_id = 5
	other.staging_city_id = 2
	other.had_forces = true
	var sim := Simulation.new()
	sim.setup(state)
	sim._allocate_coalition_fronts(_component(state, 0))
	check(established.army_assignments.size() == 6 and other.army_assignments.is_empty(),
		"ordinary demand changes must not repeatedly reshuffle two established offensive fronts")
	sim.free()


func _test_active_transfer_limit() -> void:
	var state := _state()
	var troops: Array[Army] = []
	for index in range(9):
		troops.append(_army(state, 90 + index, 0, 0))
	_army(state, 99, 1, 2, 72000)
	var source := _front(state, 0, CoalitionCampaignFront.Mode.OFFENSE, troops)
	source.center_city_id = 3
	source.staging_city_id = 2
	source.had_forces = true
	var defense := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [])
	var sim := Simulation.new()
	sim.setup(state)
	sim._allocate_coalition_fronts(_component(state, 0))
	check(defense.army_assignments.size() == 3,
		"transfers from an active offense into defense must still respect three-army quota")
	check(source.army_assignments.size() == 6, "quota must preserve remaining source assignments")
	print("COALITION_TRANSFER_METRIC active_transfers=%d maximum=3" % defense.army_assignments.size())
	sim.free()


func _test_report_end_replans_tomorrow() -> void:
	var state := _state()
	var defender := _army(state, 110, 0, 0)
	var enemy := _army(state, 111, 1, 2, 24000)
	var reserve := _army(state, 112, 0, 0)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [defender])
	var sim := Simulation.new()
	sim.setup(state)
	var battle := state.new_battle(Battle.Kind.FIELD)
	battle.edge = state.edge_of(1, 2)
	battle.side_a = [defender]
	battle.side_b = [enemy]
	defender.state = Army.State.FIGHTING
	sim._lock_campaign_reports_for_battle(battle)
	defender.size = 5000
	defender.state = Army.State.IDLE
	battle.finished = true
	sim._finish_campaign_reports_for_battle(battle)
	sim._manage_coalition_campaigns()
	check(reserve.campaign_front_id == -1, "field battle ending must not refill the same day")
	state.day += 1
	sim._manage_coalition_campaigns()
	check(reserve.campaign_front_id == front.front_id,
		"today's planning must not swallow tomorrow's postbattle reinforcement wake")
	sim.free()


func _state() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.rng.seed = 96322
	for id in range(2):
		var nation := Nation.new()
		nation.id = id
		nation.capital_city_id = 0 if id == 0 else 3
		state.nations.append(nation)
	for id in range(6):
		var city := City.new()
		city.id = id
		city.owner_nation = 0 if id < 3 else 1
		city.map_position = Vector2(id, 0)
		city.garrison_manpower = 1000 if id in [0, 3] else 0
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		state.administrative_center_by_city.append(0 if id < 3 else 3)
		state.region_ids.append(0)
		state.recognized_city_owners.append(city.owner_nation)
	state.administrative_center_city_ids = [0, 3] as Array[int]
	for pair in [[0, 1], [1, 2], [2, 4], [4, 3], [3, 5]]:
		state._add_edge(pair[0], pair[1])
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_war_objective(1, 0, 0, "dispatch lifecycle")
	return state


func _test_custom_policy_is_not_commanded() -> void:
	var state := _state()
	var army := _army(state, 120, 0, 1, 30000)
	_army(state, 121, 1, 2, 10000)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [army])
	var sim := Simulation.new()
	sim.setup(state)
	sim.ai_policy_overrides[0] = func(_s: GameState, _n: int, _sim: Simulation) -> void: pass
	sim._run_ai_campaign_planning_phase([] as Array[int], {}, {}, {}, false, Time.get_ticks_usec())
	sim._commit_ai_command_collection([] as Array[int])
	check(army.state == Army.State.IDLE and army.path.is_empty(),
		"due coalition must not commandeer custom-policy countries")
	sim._execute_coalition_defense(front)
	check(army.state == Army.State.IDLE and army.path.is_empty(),
		"direct campaign execution must also respect custom-policy ownership")
	sim.free()


func _test_new_army_outside_frozen_batch_is_not_commanded() -> void:
	var state := _state()
	var old_army := _army(state, 130, 0, 0)
	var frozen := {old_army.id: true}
	var new_army := _army(state, 131, 0, 0)
	var sim := Simulation.new()
	sim.setup(state)
	sim._begin_ai_command_collection(frozen)
	var candidate := ActionCandidate.make(ActionCandidate.Kind.REINFORCE, 10.0, "frozen batch", 1)
	check(not sim._queue_ai_candidate(new_army, candidate),
		"army created after the frozen snapshot must not receive same-batch orders")
	check(sim._queue_ai_candidate(old_army, candidate), "frozen original army remains eligible")
	sim._commit_ai_command_collection([0] as Array[int])
	check(old_army.state == Army.State.MOVING and new_army.state == Army.State.IDLE,
		"command commit respects frozen army identity")
	sim.free()


func _test_two_front_initial_floors() -> void:
	var state := _state()
	state.administrative_center_city_ids.append(5)
	state.administrative_center_by_city[5] = 5
	var first := _front(state, 0, CoalitionCampaignFront.Mode.OFFENSE, [])
	first.staging_city_id = 2
	var second := _front(state, 0, CoalitionCampaignFront.Mode.OFFENSE, [])
	second.center_city_id = 5
	second.staging_city_id = 2
	for index in range(6):
		_army(state, 140 + index, 0, 0)
	var sim := Simulation.new()
	sim.setup(state)
	sim._allocate_coalition_fronts(_component(state, 0))
	check(first.army_assignments.size() == 3 and second.army_assignments.size() == 3,
		"90000 initially unbound troops must fill both 45000 offensive floors in one cycle")
	sim.free()


func _test_offensive_reinforcement_binds_real_camp() -> void:
	var state := _state()
	state.cities[4].owner_nation = 0
	var front := _front(state, 0, CoalitionCampaignFront.Mode.OFFENSE, [])
	front.staging_city_id = 2
	front.camp_city_id = 4
	front.phase = CoalitionCampaignFront.Phase.HOLD_CAMP
	var army := _army(state, 150, 0, 0)
	var sim := Simulation.new()
	sim.setup(state)
	sim._allocate_coalition_fronts(_component(state, 0))
	check(int(front.army_assignments.get(army.id, -1)) == 4,
		"new camp reinforcement must bind camp directly, not use center as hidden marker")
	sim._manage_administrative_campaign(front)
	check(army.state == Army.State.MOVING and army.ai_target_city == 4,
		"direct camp binding must execute a real camp reinforcement order")
	sim.free()


func _test_inflight_and_locked_bindings_are_preserved() -> void:
	var state := _state()
	var moving := _army(state, 160, 0, 2)
	moving.state = Army.State.MOVING
	moving.on_edge = true
	moving.move_from = 2
	moving.move_to = 1
	moving.path = [1, 0] as Array[int]
	var idle := _army(state, 161, 0, 2)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [moving, idle])
	front.combat_report_locked = true
	front.reported_effective_manpower = 30000
	front.reported_requirement = 30000
	var neutral := Nation.new()
	neutral.id = 2
	neutral.capital_city_id = 1
	state.nations.append(neutral)
	state.cities[1].owner_nation = 2
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.NEUTRAL)
	var sim := Simulation.new()
	sim.setup(state)
	sim._allocate_coalition_fronts(_component(state, 0))
	check(moving.campaign_front_id == front.front_id and moving.move_to == 1,
		"unreachable in-flight troop must preserve its current leg and front")
	check(idle.campaign_front_id == front.front_id,
		"locked combat report must prevent reachability-driven binding migration")
	front.combat_report_locked = false
	state.day += 1
	sim._allocate_coalition_fronts(_component(state, 0))
	check(moving.campaign_front_id == front.front_id and moving.move_to == 1,
		"after unlocking an in-flight troop still must not repeatedly turn around")
	sim.free()


func _test_active_defense_donates_only_surplus() -> void:
	var state := _state()
	var troops: Array[Army] = []
	for index in range(6):
		troops.append(_army(state, 170 + index, 0, 0))
	_army(state, 176, 1, 2, 10000)
	var defense := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, troops)
	var offense := _front(state, 0, CoalitionCampaignFront.Mode.OFFENSE, [])
	offense.staging_city_id = 2
	var sim := Simulation.new()
	sim.setup(state)
	sim._allocate_coalition_fronts(_component(state, 0))
	check(offense.army_assignments.size() == 3,
		"active defense may donate idle surplus to counterattack within transfer quota")
	check(defense.army_assignments.size() == 3,
		"counterattack must leave defense force above the actual 9001 requirement")
	sim.free()


func _test_taskless_locked_defense_waits_for_report() -> void:
	var state := _state()
	var army := _army(state, 180, 0, 0)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [army])
	front.combat_report_locked = true
	front.reported_effective_manpower = army.size
	front.reported_requirement = army.size
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_coalition_campaigns()
	check(state.campaign_front(front.front_id) == front and army.campaign_front_id == front.front_id,
		"taskless defense must wait for its final field report before releasing troops")
	sim.free()


func _test_expanded_batch_keeps_tick_start_freeze() -> void:
	var state := _state()
	var original := _army(state, 190, 0, 1)
	var frozen := {original.id: true}
	var created_later := _army(state, 191, 0, 0, 30000)
	_army(state, 192, 1, 2, 10000)
	_front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [created_later])
	var sim := Simulation.new()
	sim.setup(state)
	sim._run_ai_campaign_planning_phase(
		[] as Array[int], {}, {}, {}, false, Time.get_ticks_usec(), frozen
	)
	sim._commit_ai_command_collection([] as Array[int])
	check(created_later.state == Army.State.IDLE and created_later.path.is_empty(),
		"adding all due coalition members must not add armies created after tick-start freeze")
	sim.free()


func _test_other_war_pool_is_not_mobilized() -> void:
	var state := _state()
	state.administrative_center_city_ids.append(1)
	state.administrative_center_by_city[1] = 1
	state.administrative_center_by_city[2] = 1
	var third := Nation.new()
	third.id = 2
	third.capital_city_id = 5
	state.nations.append(third)
	state.cities[5].owner_nation = 2
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.NEUTRAL)
	state.set_war_objective(0, 2, 5, "separate pool")
	var protected := _army(state, 200, 0, 1, 90000)
	protected.campaign_war_id = state.war_id_between(0, 2)
	var reserve := _army(state, 201, 0, 1)
	_army(state, 202, 1, 2, 10000)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [], 1)
	var sim := Simulation.new()
	sim.setup(state)
	sim._allocate_coalition_fronts(_component(state, 0))
	check(protected.campaign_front_id == -1
		and protected.campaign_war_id == state.war_id_between(0, 2),
		"ordinary mobilization must not cross into a separate war pool")
	check(reserve.campaign_front_id == front.front_id,
		"same-war demand must be filled by available national reserve instead")
	sim.free()


func _test_live_incoming_and_invalid_route_context() -> void:
	var state := _state()
	var enemy := _army(state, 210, 1, 3, 10000)
	enemy.state = Army.State.MOVING
	enemy.ai_action = ActionCandidate.Kind.ATTACK
	enemy.ai_target_city = 2
	enemy.path = [4, 2] as Array[int]
	var war_id := state.war_id_between(0, 1)
	var context := state.campaign_defense_context(0, 0, war_id)
	check(bool(context["active"]) and bool(context["incoming"]) and not bool(context["invaded"]),
		"valid live incoming route is a defense task before enemy crosses the state boundary")
	check(int(context["enemy_manpower"]) == 0 and int(context["requirement"]) == GameState.INITIAL_HEAVY_ARMY_SIZE,
		"distant live incoming keeps the task with one-army fallback without pretending physical V")
	enemy.state = Army.State.IDLE
	enemy.path.clear()
	context = state.campaign_defense_context(0, 0, war_id)
	check(not bool(context["active"]) and int(context["requirement"]) == 0,
		"stale idle attack target is not a permanent defense task")
	enemy.state = Army.State.MOVING
	enemy.ai_target_city = 1
	enemy.path = [4, 2, 1] as Array[int]
	context = state.campaign_defense_context(0, 0, war_id)
	check(not bool(context["active"]),
		"physically connected incoming route without access across an intermediate enemy city is invalid")
	enemy.ai_target_city = 2
	enemy.path = [5, 2] as Array[int]
	context = state.campaign_defense_context(0, 0, war_id)
	check(not bool(context["active"]), "broken edge in an old route does not retain defense")


func _test_defense_context_does_not_mix_wars() -> void:
	var state := _state()
	var third := Nation.new()
	third.id = 2
	third.capital_city_id = 5
	state.nations.append(third)
	state.cities[5].owner_nation = 2
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	state.set_war_objective(0, 2, 5, "context isolation")
	_army(state, 220, 2, 2, 30000)
	state.cities[1].owner_nation = 2
	var foreign_siege := state.new_battle(Battle.Kind.SIEGE)
	foreign_siege.city = state.cities[0]
	foreign_siege.siege_attacker_nation = 2
	var first_context := state.campaign_defense_context(0, 0, state.war_id_between(0, 1))
	check(not bool(first_context["active"]) and int(first_context["requirement"]) == 0,
		"other-war invader, enemy Fu and siege must not create this war's defense requirement")
	var second_context := state.campaign_defense_context(0, 0, state.war_id_between(0, 2))
	check(bool(second_context["invaded"]) and bool(second_context["besieged"])
		and (second_context["enemy_fu_ids"] as Array[int]) == [1],
		"actual war receives its own invasion, siege and occupied-Fu context")
	check(int(second_context["requirement"]) == 27001,
		"other-war siege must not double count real invading manpower")
	var sim := Simulation.new()
	sim.setup(state)
	check(sim._defense_sortie_target_city(0, 0, state.war_id_between(0, 1)) == -1,
		"defense execution must not select an invader from another war")
	check(sim._component_defense_centers([0] as Array[int], state.war_id_between(0, 1)).is_empty(),
		"component defense discovery must use its explicit war ID, not unrelated enemies")
	sim.free()


func _test_ordinary_arrival_waits_until_ten_day_cycle() -> void:
	var state := _state()
	var first := _army(state, 230, 0, 1, 7500)
	var second := _army(state, 231, 0, 1, 7500)
	_army(state, 232, 1, 2, 10000)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [first, second])
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_coalition_campaigns()
	check(first.state == Army.State.MOVING and first.ai_target_city == 0,
		"before actual arrival defenders must receive a rally order")
	for army in [first, second]:
		army.location_city = 0
		army.state = Army.State.IDLE
		army.on_edge = false
		army.path.clear()
		army.ai_order_until_day = 0
	for day in range(1, Simulation.AI_DECISION_INTERVAL_DAYS):
		state.day = day
		sim._manage_coalition_campaigns()
		check(first.state == Army.State.IDLE and first.location_city == 0,
			"ordinary arrival must not add daily campaign replanning")
	state.day = Simulation.AI_DECISION_INTERVAL_DAYS
	sim._manage_coalition_campaigns()
	check(first.state == Army.State.MOVING and first.ai_target_city == 2
		and front.phase == CoalitionCampaignFront.Phase.SORTIE,
		"ready assembled defenders must sortie at the normal tenth-day cycle")
	sim.free()


func _test_real_march_separates_travel_and_planning_wait() -> void:
	var state := _state()
	state.edge_of(0, 1).distance = 4
	var first := _army(state, 240, 0, 1, 7500)
	var second := _army(state, 241, 0, 1, 7500)
	_army(state, 242, 1, 2, 10000)
	var front := _front(state, 0, CoalitionCampaignFront.Mode.DEFENSE, [first, second])
	var sim := Simulation.new()
	sim.setup(state)
	var arrival_day := -1
	var action_day := -1
	for day in range(31):
		state.day = day
		if day > 0:
			sim._advance_movement()
		if arrival_day < 0 and first.is_at_city_node(0) and second.is_at_city_node(0):
			arrival_day = day
		var due := sim._prepare_coalition_campaign_batch()
		var own_due: Array[Dictionary] = []
		for component in due:
			if (component["members"] as Array[int]).has(0):
				own_due.append(component)
		sim._manage_coalition_campaigns(own_due)
		if front.phase == CoalitionCampaignFront.Phase.SORTIE:
			action_day = day
			break
	check(arrival_day > 0 and action_day >= arrival_day, "real movement must finish before the assembled sortie")
	check(action_day >= 0 and action_day - arrival_day < Simulation.AI_DECISION_INTERVAL_DAYS,
		"only real travel and at most the normal ten-day planning wait remain")
	print("COALITION_TRAVEL_METRIC arrival_day=%d sortie_day=%d travel_days=%d planning_wait_days=%d" % [
		arrival_day, action_day, arrival_day, action_day - arrival_day])
	sim.free()


func _army(state: GameState, id: int, owner: int, location: int, size: int = 15000) -> Army:
	var army := Army.new()
	army.id = id
	army.owner_nation = owner
	army.location_city = location
	army.size = size
	army.max_size = maxi(size, GameState.INITIAL_HEAVY_ARMY_SIZE)
	state.armies.append(army)
	return army


func _front(state: GameState, owner: int, mode: int, troops: Array[Army], center_id: int = -1) -> CoalitionCampaignFront:
	if center_id < 0:
		center_id = 0 if mode == CoalitionCampaignFront.Mode.DEFENSE else 3
	var front := state.create_campaign_front(
		state.war_id_between(0, 1), [owner] as Array[int], owner, mode,
		center_id
	)
	for army in troops:
		army.campaign_front_id = front.front_id
		army.campaign_war_id = front.war_id
		front.army_assignments[army.id] = front.center_city_id
	if mode == CoalitionCampaignFront.Mode.DEFENSE:
		_register_enemy_battlefield(state, front)
	return front


func _register_enemy_battlefield(state: GameState, defense: CoalitionCampaignFront) -> void:
	if not bool(state.campaign_defense_context(defense.anchor_nation_id, defense.center_city_id, defense.war_id)["active"]):
		return
	state.sync_campaign_pairs(state.coalition_campaign_components())
	var pair := state.find_campaign_pair(defense.war_id, defense.anchor_nation_id, 1)
	if pair == null:
		return
	for slot in pair.battlefields:
		if int(slot["center_city_id"]) == defense.center_city_id:
			return
	var attackers: Array[Army] = []
	for army in state.armies:
		if army.owner_nation == 1 and army.campaign_war_id in [-1, defense.war_id] and army.campaign_front_id < 0:
			attackers.append(army)
	var offense: CoalitionCampaignFront = null
	if not attackers.is_empty():
		offense = state.create_campaign_front(defense.war_id, [1] as Array[int], 1,
			CoalitionCampaignFront.Mode.OFFENSE, defense.center_city_id)
		offense.campaign_pair_id = pair.pair_id
		offense.battlefield_slot = pair.battlefields.size()
		offense.staging_city_id = 3
		offense.phase = CoalitionCampaignFront.Phase.BREAK_IN
		offense.tactical_target_city_ids = [2] as Array[int]
		for army in attackers:
			army.campaign_war_id = defense.war_id
			army.campaign_front_id = offense.front_id
			offense.army_assignments[army.id] = 2
	# A residual enemy-held Fu keeps the old battlefield occupied even after
	# its offensive force has left; this is recapture, not a third task.
	pair.battlefields.append(CoalitionCampaignPair.make_battlefield(defense.center_city_id,
		offense.front_id if offense != null else -1, 1))


func _component(state: GameState, owner: int) -> Dictionary:
	for component in state.coalition_campaign_components():
		if (component["members"] as Array[int]).has(owner):
			return component
	return {}
