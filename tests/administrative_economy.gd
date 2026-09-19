extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(94001)
	var fu_id := -1
	for city in state.cities:
		if state.is_fu_city(city.id) and city.gold_per_month > 0:
			fu_id = city.id
			break
	var valid := fu_id >= 0
	var center_id := state.administrative_center_of(fu_id)
	var fu := state.cities[fu_id] if fu_id >= 0 else null
	var original_center_owner := (
		state.cities[center_id].owner_nation if center_id >= 0 else -1
	)
	var potential_before := (
		CityOutputRules.city_potential_gold_output(state, fu) if fu != null else 0
	)
	var actual_before := (
		Simulation.city_gold_output(state, fu) if fu != null else 0
	)
	if valid:
		state.cities[center_id].owner_nation = (fu.owner_nation + 1) % state.nations.size()
	var blocked_gold := Simulation.city_gold_output(state, fu) if fu != null else -1
	var blocked_food := Simulation.city_food_output(state, fu) if fu != null else -1
	var blocked_manpower := (
		Simulation.city_manpower_output(state, fu) if fu != null else -1
	)
	var potential_blocked := (
		CityOutputRules.city_potential_gold_output(state, fu) if fu != null else -1
	)
	if valid:
		state.cities[center_id].owner_nation = original_center_owner
	var restored := Simulation.city_gold_output(state, fu) if fu != null else -1
	valid = (
		valid
		and actual_before > 0
		and potential_before > 0
		and blocked_gold == 0
		and blocked_food == 0
		and blocked_manpower == 0
		and potential_blocked == potential_before
		and restored == actual_before
	)
	if valid:
		print(
			"ADMINISTRATIVE_ECONOMY_OK fu=%d center=%d actual=%d potential=%d"
			% [fu_id, center_id, actual_before, potential_before]
		)
		quit(0)
		return
	push_error(
		"ADMINISTRATIVE_ECONOMY_FAILED fu=%d center=%d actual=%d blocked=%d/%d/%d potential=%d/%d restored=%d"
		% [
			fu_id, center_id, actual_before, blocked_gold, blocked_food,
			blocked_manpower, potential_before, potential_blocked, restored,
		]
	)
	quit(1)
