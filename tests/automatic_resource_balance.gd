extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var state := GameState.new()
	state.generate_grid_world(61002)
	state.armies.clear()
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
		nation.trade_policy = RulerProfile.POLICY_ISOLATION
		nation.treasury_gold = 100
		nation.manpower_pool = 0
	for city in state.cities:
		city.gold_per_month = 0
		city.manpower_per_month = 0
		city.food_per_half_year = 0
		city.food_storage = 0
		city.garrison_manpower = 0
	state.warehouse_cities_of(0)[0].food_storage = 2500
	state.refresh_derived()
	var sim := Simulation.new()
	sim.setup(state)
	var valid := not sim.has_method("_resolve_annual_resource_balance")
	for end_day in [180, 360, 720]:
		var flows := Simulation.monthly_gold_flows(state)
		var expected_gold := maxi(state.nations[0].treasury_gold + int(flows[0].balance), 0)
		var expected_food := mini(state.nations[0].granary_food, state.food_storage_capacity(0))
		state.day = end_day - 1
		await sim._advance_day(false)
		valid = valid and state.nations[0].treasury_gold == expected_gold
		valid = valid and state.nations[0].manpower_pool == 0
		valid = valid and state.nations[0].granary_food == expected_food
	sim.free()
	if not valid:
		push_error("year settlement must not exchange resources")
	print("AUTOMATIC_RESOURCE_BALANCE_DISABLED=%s" % valid)
	quit(0 if valid else 1)
