extends SceneTree

class CountingGameState extends "res://tests/support/grid_world.gd":
	var alliance_queries: int = 0

	func alliance_bloc(nation_id: int, alive_only: bool = true) -> Array[int]:
		alliance_queries += 1
		return super.alliance_bloc(nation_id, alive_only)

func _init() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
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
	valid = _test_resistance_reuses_batch_alliance() and valid
	if valid:
		print("DIPLOMACY_OBJECTIVE_BATCH_CACHE_OK")
		quit(0)
		return
	push_error(
		"DIPLOMACY_OBJECTIVE_BATCH_CACHE_FAIL initial=%s cached=%s refreshed=%s"
		% [str(initial), str(cached), str(refreshed)]
	)
	quit(1)


func _test_resistance_reuses_batch_alliance() -> bool:
	var state := CountingGameState.new()
	state.generate_grid_world(76002)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	var centers := state.administrative_center_city_ids
	var expected: Array[int] = []
	for center in centers:
		expected.append(state.campaign_siege_requirement(0, center))
	state.alliance_queries = 0
	var cache := {}
	var valid := true
	for index in range(centers.size()):
		valid = DiplomacyAI._cached_campaign_siege_requirement(state, 0, centers[index], cache) == expected[index] and valid
	valid = state.alliance_queries == 1 and valid
	if not valid:
		push_error("resistance batch must construct the alliance once, got %d calls" % state.alliance_queries)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	var changed := DiplomacyAI._cached_campaign_siege_requirement(state, 0, centers[0], cache)
	valid = changed == state.campaign_siege_requirement(0, centers[0]) and valid
	return valid


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
