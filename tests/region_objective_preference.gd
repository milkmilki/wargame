extends SceneTree
## Region completion must create a J-shaped objective preference without
## forbidding expansion into a region where the nation has no foothold.


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(91021)
	state.region_ids.resize(state.cities.size())
	state.region_ids.fill(2)
	for city_id in range(10):
		state.cities[city_id].owner_nation = 0
		state.region_ids[city_id] = 0
	state.cities[10].owner_nation = 1
	state.region_ids[10] = 0
	state.cities[11].owner_nation = 0
	state.region_ids[11] = 1
	state.cities[12].owner_nation = 1
	state.region_ids[12] = 1
	state.cities[13].owner_nation = 1
	state.region_ids[13] = 3
	state.region_count = 4
	state.ownership_revision += 1
	state.region_analysis_revision += 1

	var cache := {}
	var near_completion := DiplomacyAI.region_unification_objective_bonus(
		state, 0, 10, cache
	)
	var partial := DiplomacyAI.region_unification_objective_bonus(
		state, 0, 12, cache
	)
	var no_foothold := DiplomacyAI.region_unification_objective_bonus(
		state, 0, 13, cache
	)
	var valid := (
		near_completion > partial
		and partial > 0.0
		and is_equal_approx(no_foothold, 0.0)
		and near_completion <= DiplomacyAI.REGION_UNIFICATION_OBJECTIVE_BONUS
	)
	var integration_state := GameState.new()
	integration_state.generate_grid_world(91022)
	var reachable_targets: Array[int] = []
	for target_city in integration_state.cities_of(1):
		if not DiplomacyAI.staging_cities_for_objective(
			integration_state, 0, target_city.id
		).is_empty():
			reachable_targets.append(target_city.id)
	var preferred_city := reachable_targets[0] if not reachable_targets.is_empty() else -1
	if preferred_city >= 0:
		integration_state.region_ids.resize(integration_state.cities.size())
		for city in integration_state.cities:
			integration_state.region_ids[city.id] = city.id + 10
		for own_city in integration_state.cities_of(0):
			integration_state.region_ids[own_city.id] = 0
		integration_state.region_ids[preferred_city] = 0
		for target_city in integration_state.cities_of(1):
			target_city.gold_per_month = 10
			target_city.food_per_half_year = 100
			target_city.manpower_per_month = 10
			target_city.is_capital = false
			target_city.has_warehouse = false
			target_city.is_food_hub = false
			target_city.is_manpower_hub = false
		integration_state.armies.clear()
		integration_state.region_analysis_revision += 1
	var selected := DiplomacyAI.select_war_objective(
		integration_state, 0, 1
	)
	valid = (
		valid
		and reachable_targets.size() >= 2
		and int(selected.get("city_id", -1)) == preferred_city
		and str(selected.get("reason", "")).contains("区域统一值")
	)
	if valid:
		print(
			"REGION_OBJECTIVE_PREFERENCE_OK completion=%.3f partial=%.3f new=%.3f selected=%d"
			% [near_completion, partial, no_foothold, preferred_city]
		)
		quit(0)
		return
	push_error(
		"REGION_OBJECTIVE_PREFERENCE_FAILED completion=%.3f partial=%.3f new=%.3f preferred=%d selected=%s reachable=%s"
		% [
			near_completion, partial, no_foothold, preferred_city,
			str(selected), str(reachable_targets),
		]
	)
	quit(1)
