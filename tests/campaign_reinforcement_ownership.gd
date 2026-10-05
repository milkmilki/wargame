extends SceneTree

const Direct = preload("res://tests/direct_center_camp.gd")
var checks := 0
var failures := 0

func _init() -> void:
	_test_unregistered_defense()
	_test_unregistered_siege_and_occupied_fu()
	_test_ordinary_entries()
	_test_locked_takeover()
	_test_incoming_takeover()
	_test_other_front_and_parallel_lock()
	_test_routes_wakeup_and_display()
	_test_succession_priority()
	_test_succession_nearby()
	print("CAMPAIGN_REINFORCEMENT_OWNERSHIP checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func component(state: GameState) -> Dictionary:
	return {"war_id": state.war_id_between(0, 1), "members": [1] as Array[int],
		"enemy_ids": [0] as Array[int], "key": "defense"}

func siege(state: GameState, attacker: Army, guard: Army = null) -> Battle:
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city = state.cities[3]
	battle.siege_attacker_nation = 0
	battle.side_a.append(attacker)
	attacker.state = Army.State.FIGHTING
	attacker.battle_id = battle.id
	if guard != null:
		battle.side_b.append(guard)
		guard.state = Army.State.FIGHTING
		guard.battle_id = battle.id
		battle.side_b_defends_city = true
	return battle

func _test_unregistered_defense() -> void:
	var state: GameState = Direct.fixture()
	Direct.army(state, 0, 4, 20000)
	var reserve: Army = Direct.army(state, 1, 5, 20000)
	var sim := Simulation.new()
	sim.setup(state)
	state.sync_campaign_pairs(state.coalition_campaign_components())
	var pair := state.find_campaign_pair(state.war_id_between(0, 1), 0, 1)
	check(pair != null, "real war creates opposing pair")
	if pair != null:
		pair.battlefields = [CoalitionCampaignPair.make_battlefield(0, -1),
			CoalitionCampaignPair.make_battlefield(6, -1)] as Array[Dictionary]
	check(sim._component_defense_centers([1] as Array[int], state.war_id_between(0, 1)).has(3),
		"third threatened state is discovered outside two active slots")
	sim._refresh_component_defense_tasks(component(state))
	var front := state.campaign_front_for(1, 3, CoalitionCampaignFront.Mode.DEFENSE)
	check(front != null, "unregistered invasion creates defense task")
	check(pair == null or pair.battlefields.size() == 2, "defense does not add active battlefield slot")
	if front != null:
		sim._allocate_coalition_fronts(component(state))
		sim._execute_coalition_defense(front)
		check(reserve.campaign_front_id == front.front_id and reserve.state == Army.State.MOVING,
			"new reserve binds before real march")
		check(front.campaign_pair_id == -1 and front.selection_reason == 0,
			"extra defense has no offense or cross-region privilege")
	state.armies[0].size = 0
	sim._refresh_component_defense_tasks(component(state))
	check(state.campaign_front_for(1, 3, CoalitionCampaignFront.Mode.DEFENSE) == null,
		"threat removal releases unlocked extra defense")
	sim.free()

func _test_unregistered_siege_and_occupied_fu() -> void:
	for besieged in [false, true]:
		var state: GameState = Direct.fixture()
		if besieged:
			# Siege still needs defense when the attacker contributes no field V.
			var attacker: Army = Direct.army(state, 0, 3, 1000)
			siege(state, attacker)
			attacker.state = Army.State.RECOVERING
		else:
			state.cities[4].owner_nation = 0
			state.ownership_revision += 1
		var reserve: Army = Direct.army(state, 1, 3, 15000)
		var sim := Simulation.new()
		sim.setup(state)
		sim._refresh_component_defense_tasks(component(state))
		var front := state.campaign_front_for(1, 3, CoalitionCampaignFront.Mode.DEFENSE)
		check(front != null, "unregistered siege or occupied Fu creates defense besieged=%s" % besieged)
		if front != null:
			check(sim._front_requirement(front) == GameState.INITIAL_HEAVY_ARMY_SIZE,
				"zero effective V retains minimum army for existing task")
			sim._allocate_coalition_fronts(component(state))
			check(reserve.campaign_front_id == front.front_id, "zero V defense binds actual reserve")
		sim.free()


func _test_other_front_and_parallel_lock() -> void:
	var state: GameState = Direct.fixture()
	var attacker: Army = Direct.army(state, 0, 3, 30000)
	var guard: Army = Direct.army(state, 1, 3, 5000)
	var reserve: Army = Direct.army(state, 1, 4, 30000)
	var other := state.create_campaign_front(state.war_id_between(0, 1), [1] as Array[int], 1, CoalitionCampaignFront.Mode.OFFENSE, 0)
	other.army_assignments[guard.id] = 3
	guard.campaign_front_id = other.front_id
	guard.campaign_war_id = other.war_id
	var battle := siege(state, attacker, guard)
	var parallel := state.new_battle(Battle.Kind.FIELD)
	parallel.edge = state.edge_of(3, 4)
	parallel.side_a = [attacker]
	parallel.side_b = [guard]
	var sim := Simulation.new()
	sim.setup(state)
	sim._refresh_component_defense_tasks(component(state))
	var front := state.campaign_front_for(1, 3, CoalitionCampaignFront.Mode.DEFENSE)
	check(front != null and front.combat_report_locked, "taskless defense freezes even when existing participant belongs to other front")
	check(guard.campaign_front_id == other.front_id, "takeover never steals valid other front")
	if front != null:
		sim._allocate_coalition_fronts(component(state))
		check(reserve.campaign_front_id != front.front_id, "other-front engagement blocks new defensive wave")
		battle.finished = true
		sim._finish_campaign_reports_for_battle(battle)
		check(front.combat_report_locked, "parallel same-war battle retains lock")
		parallel.finished = true
		sim._finish_campaign_reports_for_battle(parallel)
		check(not front.combat_report_locked, "last report releases lock")
	sim.free()

func _test_routes_wakeup_and_display() -> void:
	var state: GameState = Direct.fixture()
	var attacker: Army = Direct.army(state, 0, 2, 10000)
	var sim := Simulation.new()
	sim.setup(state)
	check(sim._execute_ai_candidate(attacker, ActionCandidate.make(ActionCandidate.Kind.ATTACK, 1, "incoming threat", 3)), "real attack issued")
	check(sim._ai_forced_nations.has(1), "attack wakes defender for next day")
	sim._refresh_component_defense_tasks(component(state))
	var front := state.campaign_front_for(1, 3, CoalitionCampaignFront.Mode.DEFENSE)
	check(front != null and int(state.campaign_defense_context(1, 3, state.war_id_between(0, 1))["enemy_manpower"]) == 10000, "touching road uses physical V")
	state.sync_campaign_pairs(state.coalition_campaign_components())
	if front != null:
		var display := "\n".join(MapRenderer.nation_detail_lines(state, 1))
		check(display.contains("额外防守"), "extra defense visible beside active slots")
	state.edge_of(2, 3).max_manpower = 0
	attacker.on_edge = false
	attacker.location_city = 0
	attacker.move_from = 0
	attacker.move_to = -1
	attacker.path = [1, 2, 3] as Array[int]
	check(not sim._component_defense_centers([1] as Array[int], state.war_id_between(0, 1)).has(3), "broken distant incoming does not retain defense")
	sim._refresh_component_defense_tasks(component(state))
	check(state.campaign_front_for(1, 3, CoalitionCampaignFront.Mode.DEFENSE) == null, "broken threat cleans task")
	sim.free()

func _test_succession_priority() -> void:
	var state: GameState = Direct.fixture()
	var attacker: Army = Direct.army(state, 0, 3, 30000)
	var guard: Army = Direct.army(state, 1, 3, 1000)
	var reserve: Army = Direct.army(state, 1, 4, 30000)
	var conflict := SuccessionConflict.new()
	conflict.nation_id = 1
	conflict.rebel_nation_id = 0
	conflict.capital_city_id = 3
	conflict.camp_city_id = 2
	conflict.war_id = state.war_id_between(0, 1)
	conflict.army_ids = [attacker.id]
	conflict.crown_army_ids = [guard.id, reserve.id]
	state.succession_conflicts[1] = conflict
	var battle := siege(state, attacker, guard)
	var sim := Simulation.new()
	sim.setup(state)
	var plan := CityDefensePlan.new()
	plan.view = sim._build_ai_view(1)
	sim._advance_priority_city_defense(battle, plan)
	check(reserve.state == Army.State.MOVING, "succession priority entry still dispatches real participant")
	check(reserve.campaign_front_id == -1 and sim._succession_battle_context(battle) == conflict, "succession dispatch stays isolated from ordinary fronts")
	sim.free()

func _test_succession_nearby() -> void:
	var state: GameState = Direct.fixture()
	var attacker: Army = Direct.army(state, 0, 3, 30000)
	var guard: Army = Direct.army(state, 1, 3, 1000)
	var reserve: Army = Direct.army(state, 1, 4, 30000)
	for troop in [attacker, guard, reserve]:
		troop.battle_group_id = troop.id
	var conflict := SuccessionConflict.new()
	conflict.nation_id = 1
	conflict.rebel_nation_id = 0
	conflict.capital_city_id = 3
	conflict.camp_city_id = 2
	conflict.war_id = state.war_id_between(0, 1)
	conflict.army_ids = [attacker.id]
	conflict.crown_army_ids = [guard.id, reserve.id]
	state.succession_conflicts[1] = conflict
	siege(state, attacker, guard)
	var sim := Simulation.new()
	sim.setup(state)
	sim._resolve_nearby_main_battle_reinforcements()
	check(reserve.state == Army.State.MOVING and reserve.ai_target_city == 3,
		"succession retains real nearby reinforcement dispatch")
	check(reserve.campaign_front_id == -1, "succession nearby entry remains outside ordinary fronts")
	sim.free()


func _test_ordinary_entries() -> void:
	var state: GameState = Direct.fixture()
	var attacker: Army = Direct.army(state, 0, 3, 30000)
	var guard: Army = Direct.army(state, 1, 3, 1000)
	var reserve: Army = Direct.army(state, 1, 4, 30000)
	for troop in [attacker, guard, reserve]:
		troop.battle_group_id = troop.id
	var battle := siege(state, attacker, guard)
	var sim := Simulation.new()
	sim.setup(state)
	sim._resolve_nearby_main_battle_reinforcements()
	check(reserve.state == Army.State.IDLE, "ordinary local battle cannot dispatch unbound reserve")
	var plan := CityDefensePlan.new()
	plan.view = sim._build_ai_view(1)
	sim._advance_priority_city_defense(battle, plan)
	check(reserve.state == Army.State.IDLE, "ordinary priority defense cannot dispatch unbound reserve")
	guard.size = 0
	battle.side_b.clear()
	sim._advance_priority_city_defense(battle, plan)
	check(reserve.state == Army.State.IDLE, "blockade cannot bypass defense allocator")
	sim.free()

func _test_locked_takeover() -> void:
	var state: GameState = Direct.fixture()
	var attacker: Army = Direct.army(state, 0, 3, 30000)
	var guard: Army = Direct.army(state, 1, 3, 5000)
	var reserve: Army = Direct.army(state, 1, 4, 30000)
	var battle := siege(state, attacker, guard)
	var sim := Simulation.new()
	sim.setup(state)
	sim._refresh_component_defense_tasks(component(state))
	var front := state.campaign_front_for(1, 3, CoalitionCampaignFront.Mode.DEFENSE)
	check(front != null, "battle takeover creates defense")
	if front != null:
		check(guard.campaign_front_id == front.front_id and guard.state == Army.State.FIGHTING,
			"takeover binds existing participant without rewriting battle")
		check(front.combat_report_locked and front.reported_effective_manpower == 5000,
			"first takeover freezes existing commitment")
		sim._allocate_coalition_fronts(component(state))
		check(reserve.campaign_front_id == -1, "first takeover cannot add one reinforcement wave")
		battle.side_b.clear()
		guard.state = Army.State.RECOVERING
		guard.battle_id = -1
		sim._finish_campaign_reports_for_battle(battle)
		check(not front.combat_report_locked, "blockade unlocks after field engagement ends")
		state.day += 1
		sim._allocate_coalition_fronts(component(state))
		check(reserve.campaign_front_id == front.front_id, "post-report blockade allocates real reserve")
	sim.free()

func _test_incoming_takeover() -> void:
	var state: GameState = Direct.fixture()
	Direct.army(state, 0, 3, 10000)
	var incoming: Army = Direct.army(state, 1, 4, 9001)
	var reserve: Army = Direct.army(state, 1, 5, 15000)
	var sim := Simulation.new()
	sim.setup(state)
	check(sim._execute_ai_candidate(incoming, ActionCandidate.make(
		ActionCandidate.Kind.REINFORCE, 1, "existing promise", 3)), "incoming has real issued route")
	var route := incoming.path.duplicate()
	sim._refresh_component_defense_tasks(component(state))
	var front := state.campaign_front_for(1, 3, CoalitionCampaignFront.Mode.DEFENSE)
	if front != null:
		check(incoming.campaign_front_id == front.front_id and incoming.path == route,
			"incoming promise adopted without route rewrite")
		sim._allocate_coalition_fronts(component(state))
		check(reserve.campaign_front_id == -1, "incoming promise prevents duplicate allocation")
		check(state.coalition_campaign_allocation(front.war_id, 1)["fronts"][front.front_id]["rally_idle_arrived"] == 0,
			"promise never counts as actual arrival")
	else:
		check(false, "incoming takeover needs discovered defense")
	sim.free()
