extends SceneTree

var valid := true

func _init() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(62001)
	state.armies.clear()
	var sim := Simulation.new()
	sim.setup(state)
	for archetype in RulerProfile.all_archetypes():
		state.nations[0].ruler_archetype = archetype
		state.nations[0].ruler_traits = []
		var flows := Simulation.monthly_gold_flows(state)
		var expected_rate := 0.3
		if archetype in [RulerProfile.Archetype.CONQUEROR, RulerProfile.Archetype.REFORMER]:
			expected_rate = 0.1
		elif archetype in [RulerProfile.Archetype.INEPT, RulerProfile.Archetype.TYRANT]:
			expected_rate = 0.5
		_check(is_equal_approx(float(flows[0].get("court_expense_rate", -1)), expected_rate), "fixed archetype rate")
		var income := int(flows[0]["net_income"])
		_check(int(flows[0].get("court_expense_due", -1)) == int(floor(maxi(income, 0) * expected_rate)), "expense on net income")
		var city := state.land_cities_of(0)[0]
		var output := Simulation.city_gold_output(state, city)
		state.nations[0].ruler_traits = [RulerProfile.TRAIT_DILIGENT, RulerProfile.TRAIT_HARSH]
		_check(Simulation.city_gold_output(state, city) == output, "traits do not multiply gold")
	state.nations[0].treasury_gold = 2
	var due: Array[Dictionary] = []
	for nation in state.nations:
		due.append({"court_expense_rate": 0.3, "court_expense_due": 10})
	sim._resolve_court_expenses(due)
	_check(state.nations[0].treasury_gold == 0 and state.nations[0].last_court_expense_paid == 2, "payment capped without debt")
	_check(state.nations[0].last_court_expense_due == 10, "unpaid court cost does not conceal due expense")
	state.nations[0].ruler_archetype = RulerProfile.BALANCED
	var arithmetic: Array[Dictionary] = [{"city_income": 20, "trade_net_income": -40, "tribute_received": 5, "tribute_paid": 1, "military_upkeep": 7}]
	EconomyRules._finalize_balances(state, arithmetic)
	_check(arithmetic[0].court_expense_due == 0 and arithmetic[0].balance == -23, "negative net revenue generates no court debt")
	arithmetic[0].trade_net_income = 10
	EconomyRules._finalize_balances(state, arithmetic)
	_check(arithmetic[0].court_expense_due == 10 and arithmetic[0].income_after_court == 24 and arithmetic[0].balance == 17, "tribute and net trade enter base once with floor rounding")
	var history := PoliticalHistory.new()
	history.reset(state)
	state.day = 30
	state.nations[0].last_court_expense_rate = 0.5
	state.nations[0].last_court_expense_due = 99
	state.nations[0].last_court_expense_paid = 88
	history.maybe_capture(state)
	var old_view := history.build_view_state(state, 0)
	_check(is_equal_approx(old_view.nations[0].last_court_expense_rate, 0.3) and old_view.nations[0].last_court_expense_due == 10 and old_view.nations[0].last_court_expense_paid == 2, "history keeps actual old month instead of live ruler costs")
	var new_view := history.build_view_state(state, 1)
	_check(new_view.nations[0].last_court_expense_due == 99 and new_view.nations[0].last_court_expense_paid == 88, "history switching restores selected month")
	sim.free()
	print("court_expense: %s" % ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

func _check(value: bool, label: String) -> void:
	if not value:
		valid = false
		push_error(label)
