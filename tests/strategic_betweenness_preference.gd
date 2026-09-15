extends SceneTree
## Node betweenness is a strategic preference for defense and offense,
## without becoming a hard must-hold or reachability rule.


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(92031)
	state.node_betweenness.resize(state.cities.size())
	state.node_betweenness.fill(0.0)
	var low_city := state.cities[0]
	var high_city := state.cities[1]
	for city in [low_city, high_city]:
		city.gold_per_month = 10
		city.food_per_half_year = 100
		city.fort_strength = 0
		city.fort_strength_max = 0
		city.is_capital = false
		city.has_warehouse = false
		city.is_food_hub = false
		city.is_manpower_hub = false
	state.node_betweenness[high_city.id] = 0.4
	var base_values := StrategicMapSnapshot.build_base_city_values(state)
	var base_delta := (
		float(base_values[high_city.id]) - float(base_values[low_city.id])
	)
	var defense_bonus := CityDefensePlan.node_betweenness_structural_bonus(
		state, high_city.id
	)
	var snapshot := StrategicMapSnapshot.build(
		AiWorldView.build(state, 0)
	)
	var hard_value_unchanged := is_equal_approx(
		snapshot.value_of_city_without_betweenness(high_city.id),
		float(base_values[low_city.id])
	)

	var reachable_targets: Array[int] = []
	for target_city in state.cities_of(1):
		if not DiplomacyAI.staging_cities_for_objective(
			state, 0, target_city.id
		).is_empty():
			reachable_targets.append(target_city.id)
	if reachable_targets.size() < 2:
		push_error("STRATEGIC_BETWEENNESS_PREFERENCE_FAILED insufficient targets")
		quit(1)
		return
	for target_city in state.cities_of(1):
		target_city.gold_per_month = 10
		target_city.food_per_half_year = 100
		target_city.manpower_per_month = 10
		target_city.is_capital = false
		target_city.has_warehouse = false
		target_city.is_food_hub = false
		target_city.is_manpower_hub = false
	state.armies.clear()
	state.region_ids.resize(state.cities.size())
	for city in state.cities:
		state.region_ids[city.id] = city.id
	state.node_betweenness.fill(0.0)
	var preferred_city := reachable_targets[1]
	state.node_betweenness[preferred_city] = 1.0
	var selected := DiplomacyAI.select_war_objective(state, 0, 1)
	var valid := (
		is_equal_approx(
			base_delta,
			0.4 * StrategicMapSnapshot.NODE_BETWEENNESS_CITY_VALUE_WEIGHT
		)
		and is_equal_approx(
			defense_bonus,
			0.4 * CityDefensePlan.NODE_BETWEENNESS_STRUCTURAL_WEIGHT
		)
		and hard_value_unchanged
		and int(selected.get("city_id", -1)) == preferred_city
		and str(selected.get("reason", "")).contains("交通中心值")
	)
	if valid:
		print(
			"STRATEGIC_BETWEENNESS_PREFERENCE_OK base=%.2f defense=%.2f target=%d"
			% [base_delta, defense_bonus, preferred_city]
		)
		quit(0)
		return
	push_error(
		"STRATEGIC_BETWEENNESS_PREFERENCE_FAILED base=%.2f defense=%.2f preferred=%d selected=%s"
		% [base_delta, defense_bonus, preferred_city, str(selected)]
	)
	quit(1)
