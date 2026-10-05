extends SceneTree
var valid := true
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var state := GameState.new()
	state.generate_grid_world(62002)
	var sim := Simulation.new()
	sim.setup(state)
	var cache := {}
	var report := DiplomacyAI.resource_report(state, 0, cache)
	_check(report.has("forecast") and report.forecast.has("gold_min_day"), "common report forecast")
	var capacity := DiplomacyAI.force_capacity_report(state, 0, -1, cache)
	_check(capacity.additional_armies >= 0, "capacity evaluates candidates")
	var action_cache := sim._new_diplomacy_action_cache(true)
	sim._prepare_diplomacy_mobilization_cache(action_cache)
	_check(bool(action_cache.get("__forecast_pending_supply", false)), "diplomatic action and mobilization cache retain pending supply phase")
	var before := state.nations[0].treasury_gold
	var flows := Simulation.monthly_gold_flows(state)
	var monthly := int(flows[0].balance)
	sim._resolve_economy()
	_check(state.nations[0].treasury_gold == maxi(before + monthly, 0), "forecast monthly cash agrees with settlement")
	_check(state.nations[0].last_court_expense_due == int(flows[0].court_expense_due), "published month expense")
	state.nations[0].treasury_gold = 10000000
	for city in state.warehouse_cities_of(0):
		city.food_storage = 100000
	state.refresh_derived()
	cache.clear()
	var ordinary := DiplomacyAI.resource_forecast(state, 0, -1, DiplomacyAI.FoodPosture.PEACE, cache)
	state.nations[0].ruler_archetype = RulerProfile.Archetype.GUARDIAN
	cache.clear()
	var guardian := DiplomacyAI.resource_forecast(state, 0, -1, DiplomacyAI.FoodPosture.PEACE, cache)
	_check(guardian.input.gold_months == 44 and guardian.input.food_months == 26, "one preference affects money and food")
	_check(ordinary.input.gold_months != guardian.input.gold_months, "preference visible")
	var snapshot := NativeSnapshotBuilder.build(state)
	_check(snapshot.schema_version == 22 and snapshot.nations.last_court_expense_paid[0] == state.nations[0].last_court_expense_paid, "snapshot includes settled expenses")
	sim.free()
	_test_fixed_settlement()
	_test_shared_commitments()
	_test_field_supply_oracle()
	_test_wartime_soft_reserve()
	await _test_shared_pool_frame_equivalence()
	print("resource_forecast_integration: %s" % ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

func _test_fixed_settlement() -> void:
	var state := GameState.new()
	state.generate_grid_world(62003)
	state.armies.clear()
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
		nation.trade_policy = RulerProfile.POLICY_ISOLATION
		nation.treasury_gold = 1000000
	for city in state.cities:
		city.garrison_manpower = 0
		city.food_storage = 0
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var sim := Simulation.new()
	sim.setup(state)
	state.day = 30
	var prediction := DiplomacyAI.resource_forecast(state, 0)
	var lowest_gold := state.nations[0].treasury_gold
	var lowest_food := state.nations[0].granary_food
	for day in range(31, 391):
		state.day = day
		if day % 30 == 0:
			sim._resolve_economy()
		lowest_gold = mini(lowest_gold, state.nations[0].treasury_gold)
		lowest_food = mini(lowest_food, state.nations[0].granary_food)
	_check(prediction.gold_end == state.nations[0].treasury_gold and prediction.food_end == state.nations[0].granary_food, "360-day fixed forecast matches real settlements")
	_check(prediction.gold_min == lowest_gold and prediction.food_min == lowest_food, "fixed forecast minimum agrees")
	sim.free()

func _test_shared_commitments() -> void:
	var state := GameState.new()
	state.generate_grid_world(62004)
	state.armies.clear()
	state.suzerainty[1] = {"overlord_id": 0, "tribute_rate": 0.25, "civil_war": false}
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
		nation.treasury_gold = 1000000
	for city in state.cities:
		city.garrison_manpower = 0
		city.food_storage = 0
	state.refresh_derived()
	var army := state.create_army(1, state.nations[1].capital_city_id, 1399, 15000)
	army.supply_food_debt = 0.8
	var cache := {}
	var before := DiplomacyAI.resource_forecast(state, 0, -1, DiplomacyAI.FoodPosture.PEACE, cache)
	var own_before := DiplomacyAI.resource_report(state, 1, cache)
	var offensive := DiplomacyAI.resource_forecast(state, 1, -1, DiplomacyAI.FoodPosture.OFFENSIVE_WAR, cache)
	var offensive_growth := DiplomacyAI.resource_forecast(state, 1, army.size + 202, DiplomacyAI.FoodPosture.OFFENSIVE_WAR, cache, {"base_upkeep_delta": 1, "field_food_delta": 50.0})
	_check(is_equal_approx(float(offensive_growth.change.field_food_delta), float(offensive.change.get("field_food_delta", 0)) + 50.0), "exact candidate increment preserves offensive deployment allowance")
	var monthly_flows: Array[Dictionary] = cache.monthly_gold_flows
	var old_upkeep := int(monthly_flows[1].field_army_upkeep)
	var old_size := army.size
	army.size = 1601
	DiplomacyAI.commit_force_change(state, 1, 202, cache, [{"army": army, "old_size": old_size}])
	var after := DiplomacyAI.resource_forecast(state, 0, -1, DiplomacyAI.FoodPosture.PEACE, cache)
	var own_after := DiplomacyAI.resource_report(state, 1, cache)
	_check(after.food_end < before.food_end, "subject refill reserves shared food immediately")
	_check(after.input.consumers[0].debt == 0.8, "commit does not discard existing fractional food debt")
	_check(own_after.monthly_war_cost == own_before.monthly_war_cost + 1, "refill uses per-army upkeep rounding")
	_check(monthly_flows[1].field_army_upkeep == old_upkeep, "commit does not mutate external monthly settlement snapshot")
	var current_count := int(own_after.forecast.input.army_count)
	var new_army := state.create_army(1, state.nations[1].capital_city_id, 15000, 15000)
	DiplomacyAI.commit_force_change(state, 1, 15000, cache, [{"army": new_army, "old_size": 0}])
	var next := DiplomacyAI.resource_forecast(state, 1, -1, DiplomacyAI.FoodPosture.PEACE, cache)
	_check(next.input.army_count == current_count + 1 and next.input.troops == 16601, "accepted creation updates troop and formation totals")
	_check(next.input.gold == state.nations[1].treasury_gold, "creation does not deduct cash")
	_check(next.input.field_food == DiplomacyAI.resource_forecast(state, 0, -1, DiplomacyAI.FoodPosture.PEACE, cache).input.field_food, "pool members see identical committed consumption")
	state.day += 1
	_check(DiplomacyAI.resource_forecast(state, 1, -1, DiplomacyAI.FoodPosture.PEACE, cache).input.day == state.day, "batch reports cannot leak across dates")

func _test_field_supply_oracle() -> void:
	var state := GameState.new()
	state.generate_grid_world(62005)
	state.armies.clear()
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
		nation.trade_policy = RulerProfile.POLICY_ISOLATION
		nation.treasury_gold = 1000000
	for city in state.cities:
		city.garrison_manpower = 0
		city.food_storage = 0
	var capital := state.cities[state.nations[0].capital_city_id]
	capital.food_storage = 1000
	var army := state.create_army(0, capital.id, 1000, 15000)
	army.supply_food_debt = 0.8
	var sim := Simulation.new()
	sim.setup(state)
	state.day = 179
	var pending := DiplomacyAI.resource_forecast(state, 0, -1, -1, {"__forecast_pending_supply": true})
	sim._resolve_supply()
	var prediction := DiplomacyAI.resource_forecast(state, 0)
	var minimum := state.nations[0].granary_food
	for day in range(180, 540):
		state.day = day
		if day % 30 == 0:
			sim._resolve_economy()
		sim._resolve_supply()
		minimum = mini(minimum, state.nations[0].granary_food)
	_check(prediction.food_end == state.nations[0].granary_food and prediction.food_min == minimum, "field debt and harvest event forecast match 360 real supply days")
	_check(pending.food_end == state.nations[0].granary_food and pending.food_min == minimum, "pre-supply batch reserves current-day consumption before rolling forward")
	sim.free()
func _test_wartime_soft_reserve() -> void:
	var state := GameState.new()
	state.generate_grid_world(62006)
	state.armies.clear()
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.nations[0].last_food_demand = 10000
	state.nations[0].food_demand_ema = 10000
	state.nations[0].ruler_archetype = RulerProfile.Archetype.GUARDIAN
	state.nations[0].treasury_gold = 1
	state.nations[0].unpaid_military_upkeep = 0
	for city in state.cities:
		city.garrison_manpower = 0
	state.refresh_derived()
	var flows := Simulation.monthly_gold_flows(state)
	flows[0].net_income = 25
	flows[0].court_expense_due = 10
	flows[0].military_upkeep = 10
	flows[0].field_army_upkeep = 10
	var policy := Simulation.gold_reserve_policy(state, 0, flows)
	_check(policy.forecast.input.field_food == 0, "historical food demand cannot create phantom armies after elimination")
	_check(policy.forecast.gold_gap > 0 and not policy.gold_shortage, "war fixture misses preference but survives the horizon")
	_check(not policy.has("required_upkeep_savings"), "fiscal demobilization path removed")
	state.nations[0].unpaid_military_upkeep = 5
	_check(not Simulation.gold_reserve_policy(state, 0, flows).has("required_upkeep_savings"), "arrears do not reintroduce fiscal demobilization")

func _test_shared_pool_frame_equivalence() -> void:
	var baseline: PackedByteArray
	for sliced in [false, true]:
		var state := GameState.new()
		state.generate_grid_world(62007)
		state.armies.clear()
		state.suzerainty[1] = {"overlord_id": 0, "tribute_rate": 0.25, "civil_war": false}
		state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
		for nation in state.nations:
			nation.ruler_archetype = RulerProfile.BALANCED
			nation.ruler_traits.clear()
			nation.treasury_gold = 0
		for city in state.cities:
			city.gold_per_month = 0
			city.garrison_manpower = 0
			if city.has_warehouse:
				city.food_storage = 100000
		state.refresh_derived()
		for nation_id in [0, 1]:
			state.create_army(nation_id, state.nations[nation_id].capital_city_id, 13999, 15000).supply_food_debt = 0.8
		var sim := Simulation.new()
		root.add_child(sim)
		sim.setup(state)
		sim.paused = true
		state.day = 30
		sim._resolve_economy({"trade": {}, "gold_flows": Simulation._monthly_gold_flows_from_trade(state, {})})
		for nation_id in [0, 1]:
			_check(state.nations[nation_id].military_payment_ratio < 1, "sync/frame fixture exercises actual underfunding")
		if sliced:
			await sim._resolve_reinforcements_over_frames()
		else:
			sim._resolve_reinforcements()
		for army in state.armies:
			_check(army.funding_multiplier == Army.funding_from_payment(state.nations[army.owner_nation].military_payment_ratio), "derived funding matches settled owner payment in sync/frame execution")
		var snapshot := var_to_bytes(NativeSnapshotBuilder.build(state))
		if sliced:
			_check(snapshot == baseline, "shared-pool monthly expense and refill match full native snapshot across sync/frame execution")
		else:
			baseline = snapshot
		sim.free()

func _check(value: bool, label: String) -> void:
	if not value:
		valid = false
		push_error(label)
