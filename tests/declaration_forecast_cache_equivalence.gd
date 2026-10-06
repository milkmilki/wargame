extends "res://tests/ultimatum_e2e.gd"
## Fresh submission checks may reuse only the exact trade/fiscal forecast.
## Resource inputs, arrival, and food debt must still read current GameState.


func _run() -> void:
	var fixture: Dictionary
	var state: GameState
	var sim: Simulation
	for step in range(6):
		fixture = _fixture(UltimatumRules.Outcome.REFUSE)
		state = fixture.state
		sim = fixture.sim
		_check(DiplomacyAI.war_preparation_launch_allowed(state, 0, {}), "initial healthy launch step=%d" % step)
		# Warm the simulation forecast before mutating a dynamic dependency.
		sim._seed_trade_forecast({})
		match step:
			1:
				state.nations[0].treasury_gold = 0
			2:
				state.armies[0].size -= 101
				state.armies[0].supply_food_debt = 0.9999
			3:
				state.cities[state.nations[0].capital_city_id].food_storage = 100
			4:
				state.cities[fixture.center].garrison_manpower += 1000
			5:
				for army in state.armies:
					if army.owner_nation == 0:
						army.state = Army.State.RECOVERING
		var cold := {}
		var seeded := sim._seed_trade_forecast({})
		_check(not seeded.has("__forecast_pending_supply"), "submission keeps post-supply forecast convention")
		for nation in state.nations:
			_check(
				DiplomacyAI.resource_report(state, nation.id, cold)
					== DiplomacyAI.resource_report(state, nation.id, seeded),
				"fresh resource report step=%d nation=%d" % [step, nation.id]
			)
		_check(
			DiplomacyAI.war_preparation_launch_allowed(state, 0, {})
				== DiplomacyAI.war_preparation_launch_allowed(state, 0, sim._seed_trade_forecast({})),
			"fresh launch permission step=%d" % step
		)
		if step in [3, 5]:
			_check(not DiplomacyAI.war_preparation_launch_allowed(state, 0, seeded), "depleted food or absent assembly rejects step=%d" % step)
			var rejected := {
				"kind": DiplomacyAI.Action.DECLARE_WAR, "a": 0, "b": 1,
				"objective_city": fixture.entry,
				"objective_center_city": fixture.center,
			}
			_check(not sim._execute_diplomatic_action(rejected), "actual declaration rejects changed state step=%d" % step)
			_check(not state.is_enemy(0, 1), "rejected changed state remains peaceful step=%d" % step)
		sim.free()

	fixture = _fixture(UltimatumRules.Outcome.REFUSE)
	state = fixture.state
	sim = fixture.sim
	var ready_actions: Array[Dictionary] = []
	DiplomacyAI._collect_existing_war_preparation(state, 0, ready_actions, {})
	_check(not ready_actions.is_empty(), "healthy fixture has a ready action")
	if not ready_actions.is_empty():
		var ready: Dictionary = ready_actions[0].duplicate(true)
		ready.kind = DiplomacyAI.Action.DECLARE_WAR
		sim._seed_trade_forecast({})
		_check(sim._execute_diplomatic_action(ready) and state.is_enemy(0, 1), "fresh seeded declaration succeeds")
		_check(not sim._execute_diplomatic_action(ready), "declaration commits only once")
	sim.free()

	# Exercise the actual declaration entry after warming a formerly valid plan.
	fixture = _fixture(UltimatumRules.Outcome.REFUSE)
	state = fixture.state
	sim = fixture.sim
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_existing_war_preparation(state, 0, actions, {})
	_check(not actions.is_empty(), "valid preparation creates an action")
	if not actions.is_empty():
		var declaration: Dictionary = actions[0].duplicate(true)
		declaration.kind = DiplomacyAI.Action.DECLARE_WAR
		sim._seed_trade_forecast({})
		for city in state.cities:
			if city.owner_nation == 0:
				city.food_storage = 0
		_check(not sim._execute_diplomatic_action(declaration), "warm forecast cannot hide food exhaustion at submission")
		_check(not state.is_enemy(0, 1), "rejected declaration leaves peace intact")
		_check(state.nations[0].war_preparation_target_nation == 1, "rejected declaration retains preparation")
	sim.free()
	print("DECLARATION_FORECAST_CACHE_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
