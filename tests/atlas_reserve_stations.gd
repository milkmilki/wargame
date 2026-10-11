extends "res://tests/atlas_daily_reserves.gd"
## Regression for repeated peacetime redeployment. Uses real paths and orders.

func run() -> void:
	for queued in [false, true]:
		_locked(queued, false)
		_locked(queued, true)
		_incoming(queued)
		_station(queued, false)
		_station(queued, true)
		_preparation(queued)
		_commit_station(queued)
		_return_home(queued)
		_blocked_home(queued)
	_queued_failure()
	_planned()
	for failure in failures: printerr("RESERVE_STATION_FAIL ", failure)
	print("RESERVE_STATION_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func plan_for(state: GameState) -> CityDefensePlan:
	var view := CountingView.new()
	view.state = state; view.nation_id = 0; view.day = state.day
	var plan := CityDefensePlan.new(); plan.view = view
	return plan

func begin(state: GameState, queued: bool) -> Simulation:
	var sim := Simulation.new(); sim.setup(state)
	if queued:
		var ids := {}
		for army in state.armies: ids[army.id] = true
		sim._begin_ai_command_collection(ids)
	return sim

func finish(sim: Simulation, queued: bool) -> void:
	if queued: sim._commit_ai_command_collection([0] as Array[int])

func _locked(queued: bool, deployment: bool) -> void:
	var state := fixture("locks")
	for _i in range(4):
		add_army(state, 0, 0)
		if deployment: state.armies.back().defensive_deployment_until_day = 190
		else: state.armies.back().ai_order_until_day = 130
	var sim := begin(state, queued); var plan := plan_for(state)
	check(not sim._balance_national_reserves(0, plan), "commit/deployment locks prevent redeployment")
	finish(sim, queued)
	check(state.armies.all(func(a): return a.state == Army.State.IDLE), "locked reserves stay stationary")
	check(plan.view.fields == 0, "locked reserves need no route search")
	sim.free()

func _incoming(queued: bool) -> void:
	var state := fixture("incoming")
	for city in [0, 0, 2, 2, 4, 4]: add_army(state, 0, city)
	# Two reserves are already travelling to each of the other states.
	for index in range(2, 6):
		var army := state.armies[index]
		army.ai_target_city = army.location_city; army.location_city = 0
		army.state = Army.State.MOVING; army.on_edge = true
		army.ai_action = ActionCandidate.Kind.REINFORCE
	var sim := begin(state, queued); var plan := plan_for(state)
	check(not sim._balance_national_reserves(0, plan), "inbound reserves count at destination: 2/2/2")
	finish(sim, queued)
	check(state.armies[0].state == Army.State.IDLE and state.armies[1].state == Army.State.IDLE, "no second wave caused by temporarily empty destination")
	check(plan.view.fields == 0, "balanced inbound deployment needs no route search")
	sim.free()

func _station(queued: bool, lost: bool) -> void:
	var state := fixture("station")
	for _i in range(4):
		add_army(state, 0, 0)
		state.assign_main_army_to_independent_command(state.armies.back())
		var group := state.battle_group_by_id(0, state.armies.back().battle_group_id)
		group.reserve_target_city = 5 if lost else 0
	var sim := begin(state, queued); var plan := plan_for(state)
	var changed := sim._balance_national_reserves(0, plan)
	finish(sim, queued)
	check(changed == lost, "valid home stays fixed; lost home can be reassigned")
	for army in state.armies:
		var group := state.battle_group_by_id(0, army.battle_group_id)
		check(group.reserve_target_city != 5, "enemy-held home is not retained")
		if not lost: check(army.state == Army.State.IDLE, "imbalance alone does not move established reserves")
	sim.free()

func _preparation(queued: bool) -> void:
	var state := fixture("preparation")
	for _i in range(4):
		add_army(state, 0, 0)
		state.nations[0].war_preparation_army_ids.append(state.armies.back().id)
	var sim := begin(state, queued)
	check(not sim._balance_national_reserves(0, plan_for(state)), "prewar assembly is not redistributed")
	finish(sim, queued)
	check(state.armies.all(func(a): return a.state == Army.State.IDLE), "assembled troops remain at staging")
	sim.free()

func _commit_station(queued: bool) -> void:
	var state := fixture("commit")
	for _i in range(4):
		add_army(state, 0, 0)
		state.assign_main_army_to_independent_command(state.armies.back())
	var sim := begin(state, queued)
	check(sim._balance_national_reserves(0, plan_for(state)), "new reserves receive an initial deployment")
	if queued:
		for intent in sim._ai_command_buffer:
			check(state.battle_group_by_id(0, intent.army.battle_group_id).reserve_target_city == -1, "queued orders do not publish station before execution")
	finish(sim, queued)
	for army in state.armies:
		var group := state.battle_group_by_id(0, army.battle_group_id)
		var expected := army.ai_target_city if army.state == Army.State.MOVING else 0
		check(group.reserve_target_city == expected, "successful order/current deployment persists station")
	# After arrival and all locks expire, a new imbalance must not reverse orders.
	state.day = 300
	for army in state.armies:
		army.state = Army.State.IDLE; army.on_edge = false; army.move_to = -1
		var home := state.battle_group_by_id(0, army.battle_group_id).reserve_target_city
		if home >= 0: army.location_city = home
		army.path.clear()
	check(not sim._balance_national_reserves(0, plan_for(state)), "settled stations remain fixed after lock expires")
	sim.free()

func _return_home(queued: bool) -> void:
	var state := fixture("return_home")
	add_army(state, 0, 4)
	state.assign_main_army_to_independent_command(state.armies[0])
	var group := state.battle_group_by_id(0, state.armies[0].battle_group_id)
	group.reserve_target_city = 0
	var sim := begin(state, queued)
	check(sim._balance_national_reserves(0, plan_for(state)), "released reserve can return to its established station")
	finish(sim, queued)
	check(state.armies[0].ai_target_city == 0 and group.reserve_target_city == 0, "return route preserves original home")
	sim.free()

func _blocked_home(queued: bool) -> void:
	var state := fixture("disconnected")
	add_army(state, 0, 0)
	state.assign_main_army_to_independent_command(state.armies[0])
	var group := state.battle_group_by_id(0, state.armies[0].battle_group_id)
	group.reserve_target_city = 4
	var sim := begin(state, queued); var plan := plan_for(state)
	check(not sim._balance_national_reserves(0, plan), "unreachable station does not create an illegal order")
	finish(sim, queued)
	check(group.reserve_target_city == 0, "disconnected reserve settles at reachable current station")
	var next_plan := plan_for(state)
	check(not sim._balance_national_reserves(0, next_plan) and next_plan.view.fields == 0, "blocked station is not searched every AI cycle")
	sim.free()

func _queued_failure() -> void:
	var state := fixture("failure")
	for _i in range(4):
		add_army(state, 0, 0)
		state.assign_main_army_to_independent_command(state.armies.back())
	var sim := begin(state, true)
	check(sim._balance_national_reserves(0, plan_for(state)), "failure fixture prepares reserve commands")
	var rejected: Array[Army] = []
	for intent in sim._ai_command_buffer:
		rejected.append(intent.army)
		intent.army.state = Army.State.FIGHTING
	finish(sim, true)
	check(sim.ai_last_command_commit_failures == rejected.size(), "state change rejects buffered deployment")
	for army in rejected:
		check(state.battle_group_by_id(0, army.battle_group_id).reserve_target_city == -1, "rejected order leaves home unassigned")
	sim.free()

func _planned() -> void:
	var state := fixture("planned")
	for _i in range(4): add_army(state, 0, 0)
	var sim := begin(state, true)
	for army in state.armies: sim._ai_planned_armies[army.id] = true
	check(not sim._balance_national_reserves(0, plan_for(state)), "another planned action takes precedence over balancing")
	sim._clear_ai_command_collection(); sim.free()
