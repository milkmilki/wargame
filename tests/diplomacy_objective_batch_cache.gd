extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_world(76001, 12)
	var fixture := _find_staging_fixture(state)
	if fixture.is_empty():
		push_error("DIPLOMACY_OBJECTIVE_BATCH_CACHE_FAIL: no staging fixture")
		quit(1)
		return
	var nation_id := int(fixture["nation_id"])
	var objective_city := int(fixture["objective_city"])
	var blocked_neighbor := int(fixture["neighbor"])
	var edge := state.edge_of(blocked_neighbor, objective_city)
	var evaluation_cache := {}
	var initial := DiplomacyAI.staging_cities_for_objective(
		state, nation_id, objective_city, evaluation_cache
	)
	edge.max_manpower = 0
	var cached := DiplomacyAI.staging_cities_for_objective(
		state, nation_id, objective_city, evaluation_cache
	)
	state.road_network_revision += 1
	var refreshed := DiplomacyAI.staging_cities_for_objective(
		state, nation_id, objective_city, evaluation_cache
	)
	var valid := (
		initial.has(blocked_neighbor)
		and cached == initial
		and not refreshed.has(blocked_neighbor)
	)
	if valid:
		print("DIPLOMACY_OBJECTIVE_BATCH_CACHE_OK")
		quit(0)
		return
	push_error(
		"DIPLOMACY_OBJECTIVE_BATCH_CACHE_FAIL initial=%s cached=%s refreshed=%s"
		% [str(initial), str(cached), str(refreshed)]
	)
	quit(1)


func _find_staging_fixture(state: GameState) -> Dictionary:
	for nation in state.nations:
		for city in state.cities:
			if city.owner_nation == nation.id:
				continue
			for neighbor in state.neighbors(city.id):
				var edge := state.edge_of(neighbor, city.id)
				if (
					edge != null
					and edge.max_manpower > 0
					and state.has_military_access(
						nation.id, state.cities[neighbor].owner_nation
					)
				):
					return {
						"nation_id": nation.id,
						"objective_city": city.id,
						"neighbor": neighbor,
					}
	return {}
