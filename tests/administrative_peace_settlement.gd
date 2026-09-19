extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(94002)
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var captured_center := -1
	var uncaptured_center := -1
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		if state.administrative_members(center_id).size() < 2:
			continue
		if captured_center < 0:
			captured_center = center_id
		elif uncaptured_center < 0:
			uncaptured_center = center_id
			break
	var valid := captured_center >= 0 and uncaptured_center >= 0
	var captured_members := state.administrative_members(captured_center)
	for city_id in captured_members:
		state.cities[city_id].owner_nation = 1
		state.recognized_city_owners[city_id] = 1
		state.cities[city_id].occupation_sponsor_nation = -1
	state.cities[captured_center].owner_nation = 0
	state.cities[captured_center].occupation_sponsor_nation = 0
	var lone_fu := -1
	for city_id in state.administrative_members(uncaptured_center):
		state.cities[city_id].owner_nation = 1
		state.recognized_city_owners[city_id] = 1
		state.cities[city_id].occupation_sponsor_nation = -1
		if city_id != uncaptured_center and lone_fu < 0:
			lone_fu = city_id
	state.cities[lone_fu].owner_nation = 0
	state.cities[lone_fu].occupation_sponsor_nation = 0
	state.ownership_revision += 1
	state.refresh_derived()
	var simulation := Simulation.new()
	simulation.setup(state)
	var plan := simulation._plan_coalition_peace(0, 1)
	var operations := {}
	for operation_value in plan.get("operations", []):
		var operation: Dictionary = operation_value
		operations[int(operation["city_id"])] = operation
	for city_id in captured_members:
		var operation: Dictionary = operations.get(city_id, {})
		valid = (
			valid
			and int(operation.get("controller_id", -1)) == 0
			and int(operation.get("legal_owner_id", -1)) == 0
			and str(operation.get("reason", ""))
				== "coalition_territory_recognized"
		)
	var lone_operation: Dictionary = operations.get(lone_fu, {})
	valid = (
		valid
		and int(lone_operation.get("controller_id", -1)) == 1
		and int(lone_operation.get("legal_owner_id", -1)) == 1
		and str(lone_operation.get("reason", ""))
			== "peace_occupation_restored"
	)
	if valid:
		print(
			"ADMINISTRATIVE_PEACE_SETTLEMENT_OK center=%d members=%s restored=%d"
			% [captured_center, str(captured_members), lone_fu]
		)
		quit(0)
		return
	push_error(
		"ADMINISTRATIVE_PEACE_SETTLEMENT_FAILED plan=%s center=%d members=%s restored=%d"
		% [str(plan), captured_center, str(captured_members), lone_fu]
	)
	quit(1)
