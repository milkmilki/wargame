extends SceneTree
## Annual resource balancing is deterministic economic settlement, not an AI
## action. It must conserve gold-equivalent value and respect the annual cap.

var _valid := true


func _init() -> void:
	var manpower_zero := ResourceBalanceRules.plan(
		100, 0, 2500, 40, true
	)
	_check(int(manpower_zero["manpower_delta"]) > 0, "zero manpower was not replenished")
	_check(int(manpower_zero["transferred_value"]) <= 10, "annual income cap was exceeded")
	_check(_value_delta(manpower_zero) == 0, "manpower conversion minted value")

	var treasury_zero := ResourceBalanceRules.plan(
		0, 5000, 2500, 40, true
	)
	_check(int(treasury_zero["gold_delta"]) > 0, "zero treasury was not replenished")
	_check(_value_delta(treasury_zero) == 0, "treasury conversion minted value")

	var balanced := ResourceBalanceRules.plan(
		20, 1000, 500, 1000, true
	)
	_check(int(balanced["transferred_value"]) == 0, "balanced reserves were moved")

	var state := GameState.new()
	state.generate_grid_world(61001)
	for nation in state.nations:
		nation.treasury_gold = 0
		nation.manpower_pool = 0
	for warehouse in state.warehouse_cities_of(0):
		warehouse.food_storage = 2500
	state.refresh_derived()
	var simulation := Simulation.new()
	simulation.setup(state)
	var reports: Array[Dictionary] = []
	for nation in state.nations:
		reports.append({"net_income": 40})
	var food_before := state.nations[0].granary_food
	simulation._resolve_annual_resource_balance(reports)
	_check(state.nations[0].treasury_gold > 0, "integration did not fund treasury")
	_check(state.nations[0].manpower_pool > 0, "integration did not fund manpower")
	_check(state.nations[0].granary_food < food_before, "food donor was not consumed")
	simulation.free()

	var no_warehouse := GameState.new()
	no_warehouse.generate_grid_world(61003)
	for city in no_warehouse.cities_of(0):
		city.has_warehouse = false
		city.food_storage = 0
	no_warehouse.nations[0].warehouse_city_ids.clear()
	no_warehouse.nations[0].treasury_gold = 100
	no_warehouse.nations[0].manpower_pool = 0
	no_warehouse.refresh_derived()
	var no_warehouse_simulation := Simulation.new()
	no_warehouse_simulation.setup(no_warehouse)
	no_warehouse_simulation._resolve_annual_resource_balance(reports)
	var no_warehouse_record: Dictionary = no_warehouse.nations[0].get_meta(
		&"last_automatic_resource_balance", {}
	)
	_check(
		int(no_warehouse_record.get("food", -1)) == 0,
		"nation without a warehouse attempted a food conversion"
	)
	no_warehouse_simulation.free()

	var cadence_state := GameState.new()
	cadence_state.generate_grid_world(61002)
	cadence_state.armies.clear()
	for city in cadence_state.cities:
		city.gold_per_month = 0
		city.manpower_per_month = 0
		city.food_per_half_year = 0
		city.food_storage = 0
	cadence_state.nations[0].treasury_gold = 100
	cadence_state.nations[0].manpower_pool = 0
	var cadence_warehouse := cadence_state.warehouse_cities_of(0)[0]
	cadence_warehouse.food_storage = 2500
	cadence_state.refresh_derived()
	var cadence_simulation := Simulation.new()
	cadence_simulation.setup(cadence_state)
	cadence_state.day = Simulation.DAYS_PER_HALF_YEAR - 1
	cadence_simulation._advance_day(false)
	_check(
		not cadence_state.nations[0].has_meta(
			&"last_automatic_resource_balance"
		),
		"half-year settlement triggered annual conversion"
	)
	cadence_state.day = Simulation.DAYS_PER_YEAR - 1
	cadence_simulation._advance_day(false)
	_check(
		cadence_state.nations[0].has_meta(
			&"last_automatic_resource_balance"
		),
		"year-end settlement did not trigger conversion"
	)
	cadence_simulation.free()

	var large_state := GameState.new()
	large_state.generate_world(12345, 40, 500)
	var large_simulation := Simulation.new()
	large_simulation.setup(large_state)
	var large_reports: Array[Dictionary] = []
	for nation in large_state.nations:
		large_reports.append({"net_income": 500})
		if nation.id % 3 == 0:
			nation.manpower_pool = 0
		elif nation.id % 3 == 1:
			nation.treasury_gold = 0
	var benchmark_started := Time.get_ticks_usec()
	large_simulation._resolve_annual_resource_balance(large_reports)
	var benchmark_ms := float(
		Time.get_ticks_usec() - benchmark_started
	) / 1000.0
	_check(benchmark_ms < 50.0, "500-city annual balance exceeded 50ms")
	print("AUTOMATIC_RESOURCE_BALANCE_500_CITY_MS=%.2f" % benchmark_ms)
	large_simulation.free()

	if not _valid:
		quit(1)
		return
	print("AUTOMATIC_RESOURCE_BALANCE_OK")
	quit(0)


func _value_delta(plan: Dictionary) -> int:
	return (
		int(plan["gold_delta"])
		+ int(plan["manpower_delta"]) / ResourceBalanceRules.MANPOWER_PER_GOLD
		+ int(plan["food_delta"]) / ResourceBalanceRules.FOOD_PER_GOLD
	)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_valid = false
	push_error("AUTOMATIC_RESOURCE_BALANCE_FAILED: " + message)
