extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(94003)
	var chosen_center := -1
	var attacker_city := -1
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		for member_id in state.administrative_members(center_id):
			for neighbor in state.neighbors(member_id):
				if state.administrative_center_of(neighbor) != center_id:
					chosen_center = center_id
					attacker_city = neighbor
					break
			if chosen_center >= 0:
				break
		if chosen_center >= 0:
			break
	for city in state.cities:
		if city.is_dock:
			continue
		city.owner_nation = 2
		state.recognized_city_owners[city.id] = 2
	for member_id in state.administrative_members(chosen_center):
		state.cities[member_id].owner_nation = 1
		state.recognized_city_owners[member_id] = 1
	state.cities[attacker_city].owner_nation = 0
	state.recognized_city_owners[attacker_city] = 0
	state.ownership_revision += 1
	state.refresh_derived()
	var objective := DiplomacyAI.select_war_objective(state, 0, 1)
	var tactical := int(objective.get("tactical_city_id", -1))
	var valid := (
		not objective.is_empty()
		and int(objective.get("city_id", -1)) == chosen_center
		and int(objective.get("administrative_center_city_id", -1))
			== chosen_center
		and state.is_zhou_city(chosen_center)
		and tactical >= 0
		and state.cities[tactical].owner_nation == 1
		and state.administrative_center_of(tactical) == chosen_center
		and not DiplomacyAI.staging_cities_for_objective(
			state, 0, tactical
		).is_empty()
	)
	if valid:
		print(
			"ADMINISTRATIVE_AI_OBJECTIVE_OK center=%d tactical=%d"
			% [chosen_center, tactical]
		)
		quit(0)
		return
	push_error(
		"ADMINISTRATIVE_AI_OBJECTIVE_FAILED center=%d attacker=%d objective=%s"
		% [chosen_center, attacker_city, str(objective)]
	)
	quit(1)
