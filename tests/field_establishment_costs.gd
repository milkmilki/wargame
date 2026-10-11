extends SceneTree
## A live field formation pays for its establishment, not surviving soldiers.
const Grid = preload("res://tests/support/grid_world.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture(sizes: Array) -> GameState:
	var state := Grid.new(); state.generate_world(77191, 3, 18)
	state.armies.clear(); state.day = 30; state.trade_enabled = false
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED; nation.ruler_traits.clear()
		nation.treasury_gold = 1000000; nation.manpower_pool = 50000
	for city in state.cities:
		city.garrison_manpower = 0
		if city.has_warehouse: city.food_storage = 1000000
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	for size in sizes:
		var army := state.create_army(0, state.nations[0].capital_city_id, int(size), 15000)
		assert(army != null)
	state.refresh_derived()
	return state

func run() -> void:
	var full := fixture([15000]); var injured := fixture([3000])
	check(injured.nation_monthly_military_upkeep(0) == full.nation_monthly_military_upkeep(0), "injury does not reduce monthly gold cost")
	check(TradeNetwork._projected_army_monthly_food_demand(injured.armies[0], injured.nations[0]) == TradeNetwork._projected_army_monthly_food_demand(full.armies[0], full.nations[0]), "trade food projection reserves full establishment")
	var full_sim := Simulation.new(); full_sim.setup(full)
	var injured_sim := Simulation.new(); injured_sim.setup(injured)
	check(Simulation.monthly_gold_flows(injured)[0].field_army_upkeep == Simulation.monthly_gold_flows(full)[0].field_army_upkeep, "settlement and upkeep query agree")
	var full_before := full._food_pool_stock(0); var injured_before := injured._food_pool_stock(0)
	for _day in range(30): full_sim._resolve_supply(); injured_sim._resolve_supply()
	check(full_before - full._food_pool_stock(0) == injured_before - injured._food_pool_stock(0), "30 actual supply settlements charge wounded/full formations equally")
	check(injured.nations[0].last_food_demand == full.nations[0].last_food_demand, "actual reported monthly food demand does not fall after injury")
	var forecast := DiplomacyAI.resource_forecast(injured, 0)
	var full_forecast := DiplomacyAI.resource_forecast(full, 0)
	check(forecast.input.base_upkeep == full_forecast.input.base_upkeep and forecast.input.field_food == full_forecast.input.field_food, "forecast input agrees with full-cost settlement")
	check(DiplomacyAI.force_capacity_report(injured, 0).additional_armies == DiplomacyAI.force_capacity_report(full, 0).additional_armies, "casualties cannot open new formation budget")
	var at_full := DiplomacyAI.resource_forecast(injured, 0, 15000)
	check(at_full.food_end == forecast.food_end and at_full.gold_end == forecast.gold_end, "forecasting refill to establishment does not charge maintenance twice")
	var cache := {}; var before := DiplomacyAI.resource_forecast(injured, 0, -1, -1, cache)
	injured.armies[0].size += 1500
	DiplomacyAI.commit_force_change(injured, 0, 1500, cache, [{"army": injured.armies[0], "old_size": 3000}])
	var after := DiplomacyAI.resource_forecast(injured, 0, -1, -1, cache)
	check(after.input.field_food == before.input.field_food and after.input.base_upkeep == before.input.base_upkeep, "accepted refill spends manpower without double counting maintenance")
	check(after.food_end == before.food_end and after.gold_end == before.gold_end, "refill does not change the reserved food/cash forecast")
	var previous_count := int(after.input.army_count)
	var created := injured.create_army(0, injured.nations[0].capital_city_id, 3000, 15000)
	DiplomacyAI.commit_force_change(injured, 0, 3000, cache, [{"army": created, "old_size": 0}])
	var added := DiplomacyAI.resource_forecast(injured, 0, -1, -1, cache)
	check(added.input.army_count == previous_count + 1 and added.input.base_upkeep == after.input.base_upkeep + GameState.army_monthly_upkeep(15000), "new understrength formation commits one full gold budget")
	check(added.input.field_food > after.input.field_food, "new formation adds food cost")
	full_sim.free(); injured_sim.free()
	_recovery()
	_gold_gate()
	_disband()
	_zero_and_garrison()
	_siege()
	_actual_refill()
	for failure in failures: printerr("ESTABLISHMENT_COST_FAIL ", failure)
	print("ESTABLISHMENT_COST_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _recovery() -> void:
	var debts: Array = []
	for size in [15000, 3000]:
		var state := fixture([size]); var sim := Simulation.new(); sim.setup(state)
		var army := state.armies[0]; army.state = Army.State.RECOVERING; army.morale = army.max_morale - 0.001
		sim._recover_garrisoned_army(army)
		debts.append(army.supply_food_debt)
		sim.free()
	check(is_equal_approx(debts[0], debts[1]), "recovery uses full establishment even with few survivors")
	check(float(debts[0]) > 0.1, "near-complete morale recovery does not discount daily maintenance")

func _gold_gate() -> void:
	var state := fixture([3000])
	state.nations[0].treasury_gold = 0
	for city in state.cities: city.gold_per_month = 0
	state.refresh_derived()
	var forecast := DiplomacyAI.resource_forecast(state, 0)
	check(forecast.gold_shortage, "gold gate fixture predicts a shortage")
	check(DiplomacyAI.force_capacity_report(state, 0).additional_armies == 0, "cannot create new formations if gold forecast fails")

func _disband() -> void:
	var state := fixture([15000, 3000, 8000]); var sim := Simulation.new(); sim.setup(state)
	var view := AiWorldView.build(state, 0); var threat := ThreatField.build(view)
	var original := state.armies.map(func(a): return a.size)
	var changed := sim._demobilize_for_food_security(view, threat, {"required_savings": 1.0, "annual_surplus": -12.0, "runway_years": 1.0, "posture": 0, "required_campaign_years": 1.0, "forecast": {"food_deficit": 12}}, 1)
	check(changed, "budget pressure may release an idle formation")
	check(state.armies.filter(func(a): return a.size > 0).size() >= 1, "demobilization retains a national field reserve")
	for i in range(state.armies.size()): check(state.armies[i].size == original[i] or state.armies[i].size == 0, "reducing headcount alone cannot claim maintenance savings")
	sim.free()

func _zero_and_garrison() -> void:
	var state := fixture([3000]); var army := state.armies[0]
	army.size = 0
	check(state.nation_monthly_military_upkeep(0) == 0, "destroyed formation releases gold cost")
	check(TradeNetwork._projected_army_monthly_food_demand(army, state.nations[0]) == 0, "destroyed formation has no food demand")
	army.size = 3000; army.is_city_garrison = true
	check(state.nation_monthly_military_upkeep(0) == GameState.army_monthly_upkeep(3000), "garrison exception retains existing actual-headcount cost")

func _siege() -> void:
	for garrison in [false, true]:
		for size in [15000, 3000]:
			var state := fixture([size]); var army := state.armies[0]
			army.is_city_garrison = garrison; army.state = Army.State.FIGHTING; army.battle_id = 88
			var battle := Battle.new(); battle.id = 88; battle.kind = Battle.Kind.SIEGE
			battle.city = state.cities[army.location_city]; battle.side_b_defends_city = true; battle.side_b.append(army)
			state.battles.append(battle)
			var sim := Simulation.new(); sim.setup(state); var before := battle.city.food_storage
			for _day in range(30):
				sim._build_supply_plan_for_army(army, [0, 0, 0] as Array[int])
				sim._drain_siege_food()
			var expected := 30 if garrison else 68
			check(before - battle.city.food_storage == expected, "besieged field formation pays full local maintenance; virtual city clock stays unchanged")
			if not garrison:
				battle.city.food_storage = 0
				var debt := army.supply_food_debt
				var demand := [0, 0, 0] as Array[int]
				check(sim._build_supply_plan_for_army(army, demand).is_empty(), "empty siege remains isolated instead of adding an outside ration")
				check(demand[0] == 0 and army.supply_food_debt == debt, "empty siege does not double-count demand or fractional debt")
			sim.free()

func _actual_refill() -> void:
	var state := fixture([3000]); var sim := Simulation.new(); sim.setup(state)
	var manpower_before := state.nations[0].manpower_pool
	var upkeep_before := state.nation_monthly_military_upkeep(0)
	sim._resolve_reinforcements()
	check(state.armies[0].size == 4500 and state.nations[0].manpower_pool == manpower_before - 1500, "real monthly refill restores ten percent and charges manpower")
	check(state.nation_monthly_military_upkeep(0) == upkeep_before, "real monthly refill does not add maintenance to already-charged ranks")
	sim.free()
