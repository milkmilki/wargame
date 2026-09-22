extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(94201)
	var center_id := -1
	for center_value in state.administrative_center_city_ids:
		var candidate := int(center_value)
		if state.cities[candidate].owner_nation == 0:
			center_id = candidate
			break
	if center_id < 0:
		push_error("GARRISON_ECONOMY_FAILED no owned center")
		quit(1)
		return
	var nation := state.nations[0]
	nation.ruler_archetype = RulerProfile.BALANCED
	nation.ruler_traits.clear()
	var city := state.cities[center_id]
	city.garrison_manpower = GameState.ZHOU_GARRISON_CAPACITY
	var radius := RebellionSystem.administrative_radius(nation)
	var near_hops := {center_id: int(floor(radius))}
	var far_hop := int(ceil(radius)) + 2
	var far_hops := {center_id: far_hop}
	var near := Simulation.city_garrison_cost_report(
		state, 0, center_id, city.garrison_manpower, near_hops
	)
	var far := Simulation.city_garrison_cost_report(
		state, 0, center_id, city.garrison_manpower, far_hops
	)
	var capped := Simulation.city_garrison_cost_report(
		state,
		0,
		center_id,
		city.garrison_manpower,
		{center_id: int(ceil(radius)) + 100}
	)
	var unreachable := Simulation.city_garrison_cost_report(
		state, 0, center_id, city.garrison_manpower, {999999: 0}
	)
	var expected_excess := minf(float(far_hop) - radius, 5.0)
	var expected_logistics := 1.0 + expected_excess * 0.15
	var expected_near_gold := int(ceil(
		float(GameState.army_monthly_upkeep(city.garrison_manpower)) * 0.35
	))
	var expected_near_food := int(ceil(
		float(city.garrison_manpower) * Simulation.FOOD_PER_CAPITA * 0.50
	))
	var expected_far_gold := int(ceil(
		float(GameState.army_monthly_upkeep(city.garrison_manpower))
			* 0.35 * expected_logistics
	))
	var expected_far_food := int(ceil(
		float(city.garrison_manpower) * Simulation.FOOD_PER_CAPITA
			* 0.50 * expected_logistics
	))
	var core_hops := {center_id: 0}
	var neutral_core := Simulation.city_garrison_cost_report(
		state, 0, center_id, city.garrison_manpower, core_hops
	)
	nation.ruler_traits = [RulerProfile.TRAIT_FRUGAL]
	var frugal := Simulation.city_garrison_cost_report(
		state, 0, center_id, city.garrison_manpower, core_hops
	)
	nation.ruler_traits = [RulerProfile.TRAIT_LOGISTICIAN]
	var logistician := Simulation.city_garrison_cost_report(
		state, 0, center_id, city.garrison_manpower, core_hops
	)
	nation.ruler_traits = [RulerProfile.TRAIT_FEUDALIST]
	var feudal := Simulation.city_garrison_cost_report(
		state, 0, center_id, city.garrison_manpower, core_hops
	)
	nation.ruler_traits.clear()
	var flows := Simulation.monthly_gold_flows(state)
	var field_upkeep := state.nation_monthly_military_upkeep(0)
	var expected_garrison_upkeep := 0
	for center_value in state.administrative_center_city_ids:
		var owned_center := int(center_value)
		if state.cities[owned_center].owner_nation != 0:
			continue
		expected_garrison_upkeep += int(
			Simulation.city_garrison_cost_report(
				state,
				0,
				owned_center,
				state.cities[owned_center].garrison_manpower
			)["gold_upkeep"]
		)
	var region := state.administrative_members(center_id)
	var burden := DiplomacyAI.evaluate_region_burden(state, 0, region)
	var burden_ok := (
		int(burden["required_defense_troops"])
			== GameState.ZHOU_GARRISON_CAPACITY
		and int(burden["garrison_gold_upkeep"]) > 0
		and int(burden["monthly_food_demand"]) > 0
		and int(burden["distance_food_demand"]) >= 0
		and float(burden["burden_ratio"]) >= 0.0
	)
	for center_value in state.administrative_center_city_ids:
		var other_center := int(center_value)
		if other_center != center_id:
			state.cities[other_center].garrison_manpower = 0
	var demand := int(Simulation.city_garrison_cost_report(
		state, 0, center_id, city.garrison_manpower
	)["food_demand"])
	var holder_id := state.food_pool_holder(0)
	for warehouse in state.warehouse_cities_of(holder_id):
		warehouse.food_storage = 0
	var warehouses := state.warehouse_cities_of(holder_id)
	var available := demand / 2
	warehouses[0].food_storage = available
	state.refresh_derived()
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation._resolve_garrison_supply()
	var expected_supply_ratio := float(available) / float(demand)
	var settled_supply_ratio := city.garrison_supply_ratio
	var settled_food := state.nations[holder_id].granary_food
	var food_supply_ok := (
		settled_food == 0
		and is_equal_approx(settled_supply_ratio, expected_supply_ratio)
	)
	city.garrison_manpower = 10000
	city.garrison_supply_ratio = 0.5
	for center_value in state.administrative_center_city_ids:
		var other_center := int(center_value)
		if (
			other_center != center_id
			and state.cities[other_center].owner_nation == 0
		):
			state.cities[other_center].garrison_manpower = (
				state.city_garrison_capacity(other_center)
			)
	state.nations[0].military_payment_ratio = 0.8
	state.nations[0].manpower_pool = 2000
	state.reinforce_city_garrisons_monthly()
	var reinforcement_ok := (
		city.garrison_manpower == 10750
		and state.nations[0].manpower_pool == 1250
	)
	simulation.free()
	var valid := (
		is_equal_approx(float(near["logistics_multiplier"]), 1.0)
		and is_equal_approx(
			float(far["logistics_multiplier"]), expected_logistics
		)
		and int(near["gold_upkeep"]) == expected_near_gold
		and int(near["food_demand"]) == expected_near_food
		and int(far["gold_upkeep"]) == expected_far_gold
		and int(far["food_demand"]) == expected_far_food
		and is_equal_approx(float(capped["logistics_multiplier"]), 1.75)
		and is_equal_approx(float(unreachable["logistics_multiplier"]), 1.75)
		and int(frugal["gold_upkeep"]) < int(neutral_core["gold_upkeep"])
		and int(frugal["food_demand"]) == int(neutral_core["food_demand"])
		and int(logistician["gold_upkeep"])
			== int(neutral_core["gold_upkeep"])
		and int(logistician["food_demand"])
			< int(neutral_core["food_demand"])
		and int(feudal["gold_upkeep"]) == int(neutral_core["gold_upkeep"])
		and int(feudal["food_demand"]) == int(neutral_core["food_demand"])
		and int(flows[0]["field_army_upkeep"]) == field_upkeep
		and int(flows[0]["garrison_upkeep"]) == expected_garrison_upkeep
		and int(flows[0]["military_upkeep"])
			== field_upkeep + expected_garrison_upkeep
		and burden_ok
		and food_supply_ok
		and reinforcement_ok
	)
	if valid:
		print("GARRISON_ECONOMY_OK")
		quit(0)
		return
	push_error(
		"GARRISON_ECONOMY_FAILED near=%s far=%s capped=%s unreachable=%s core=%s frugal=%s logistician=%s feudal=%s flow=%s burden=%s food=%s ratio=%.3f/%.3f reinforce=%s manpower=%d/%d"
		% [
			str(near), str(far), str(capped), str(unreachable), str(neutral_core),
			str(frugal), str(logistician), str(feudal), str(flows[0]),
			str(burden), str(food_supply_ok),
			settled_supply_ratio, expected_supply_ratio,
			str(reinforcement_ok), city.garrison_manpower,
			state.nations[0].manpower_pool,
		]
	)
	quit(1)
