extends SceneTree

var failures := 0


func _init() -> void:
	var state := _fixture()
	check(RegionalStrategy.regions_are_adjacent(state, 0, 0), "same trade region is eligible")
	check(RegionalStrategy.regions_are_adjacent(state, 0, 1), "land border connects adjacent regions")
	check(not RegionalStrategy.regions_are_adjacent(state, 0, 2), "two trade borders are not adjacent")
	var owners: Array[int] = []
	for city in state.cities:
		owners.append(city.owner_nation)
	owners[0] = 1
	owners[2] = 1
	check(state._planned_territory_capital(0, owners) == 1,
		"lost capital may remain in its former trade region")
	owners[1] = 1
	owners[2] = 0
	check(state._planned_territory_capital(0, owners) == 2,
		"lost capital picks the adjacent region before the distant center")
	owners[2] = 1
	check(state._planned_territory_capital(0, owners) == 3,
		"lost capital may flee to a distant region when none is nearby")
	owners[3] = 1
	owners[4] = 0
	check(state._planned_territory_capital(0, owners) == 4,
		"without any state center the surviving land city becomes capital")
	state.cities[1].owner_nation = 1
	state.cities[2].owner_nation = 1
	state.ownership_revision += 1
	check(state.relocate_capital(0) == 0,
		"valid old capital cannot move directly to a distant region")
	state.cities[2].owner_nation = 0
	state.ownership_revision += 1
	check(state.relocate_capital(0) != 3,
		"an adjacent candidate prevents a distant voluntary move")
	state.cities[2].owner_nation = 1
	state.cities[0].owner_nation = 1
	state.ownership_revision += 1
	check(state.relocate_capital(0) == 3,
		"direct forced relocation retains the emergency distant fallback")
	var land_only := _fixture()
	for city_id in [0, 2, 3]:
		land_only.cities[city_id].owner_nation = 1
	land_only.administrative_center_by_city[1] = 0
	land_only.nations[0].capital_city_id = 1
	land_only.cities[1].is_capital = true
	land_only.ownership_revision += 1
	land_only.administrative_region_revision += 1
	check(land_only.relocate_capital(0) == 1,
		"a surviving ordinary-city capital is not moved without any state center")
	_test_region_cache_and_crossing()
	_test_territory_commit()
	print("CAPITAL_REGION_RELOCATION_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)


func _test_region_cache_and_crossing() -> void:
	var state := _fixture()
	var before := RegionalStrategy.geometry_build_count
	RegionalStrategy.regions_are_adjacent(state, 0, 1)
	state.cities[2].owner_nation = 1
	state.ownership_revision += 1
	RegionalStrategy.regions_are_adjacent(state, 0, 1)
	check(RegionalStrategy.geometry_build_count == before + 1,
		"ownership changes do not rebuild geographic adjacency")
	state.region_ids[2] = 2
	state.region_analysis_revision += 1
	check(RegionalStrategy.regions_are_adjacent(state, 0, 2),
		"trade region edits invalidate adjacency")
	state.region_ids[2] = 1
	state.region_analysis_revision += 1
	var bridge := state.edge_of(0, 2)
	bridge.max_manpower = 0
	state.road_network_revision += 1
	check(not RegionalStrategy.regions_are_adjacent(state, 0, 1),
		"blocked land border invalidates region adjacency")
	state._add_edge(0, 5)
	state._add_edge(2, 5)
	state.cities[5].is_dock = true
	state.edge_of(0, 5).kind = Edge.Kind.LANDING
	state.edge_of(2, 5).kind = Edge.Kind.LANDING
	state.edge_of(0, 5).max_manpower = 50000
	state.edge_of(2, 5).max_manpower = 50000
	state.road_network_revision += 1
	check(RegionalStrategy.regions_are_adjacent(state, 0, 1),
		"two banks of one dock share a local region border")


func _test_territory_commit() -> void:
	var state := _fixture()
	state.nations[0].warehouse_city_ids.append(0)
	state.cities[0].has_warehouse = true
	state.cities[0].food_storage = 1000
	var result := state.transfer_city_control(0, 1)
	check(bool(result.get("ok", false)), "capital capture commits atomically")
	if not bool(result.get("ok", false)):
		return
	check(state.nations[0].capital_city_id == 1 or state.nations[0].capital_city_id == 2,
		"capital capture chooses a nearby state center")
	check(state.cities[state.nations[0].capital_city_id].is_capital,
		"new capital is flagged by territory commit")
	check(state.nations[0].warehouse_city_ids.has(state.nations[0].capital_city_id),
		"new capital joins the nation's warehouse index")
	var remote := _fixture()
	for city_id in [1, 2]:
		check(bool(remote.transfer_city_control(city_id, 1).get("ok", false)),
			"remove neighboring capital candidates")
	check(bool(remote.transfer_city_control(0, 1).get("ok", false)),
		"capture capital when only a distant state remains")
	check(remote.nations[0].capital_city_id == 3,
		"territory transaction uses the distant emergency fallback")
	var no_center := _fixture()
	for city_id in [1, 2, 3]:
		check(bool(no_center.transfer_city_control(city_id, 1).get("ok", false)),
			"remove all alternate state centers")
	check(bool(no_center.transfer_city_control(0, 1).get("ok", false)),
		"capture capital when only an ordinary land city remains")
	check(no_center.nations[0].capital_city_id == 4,
		"territory transaction falls back to a land city without state centers")


func _fixture() -> GameState:
	var state := GameState.new()
	for id in range(2):
		var nation := Nation.new()
		nation.id = id
		nation.capital_city_id = 0 if id == 0 else 5
		state.nations.append(nation)
	state.region_ids = PackedInt32Array([0, 0, 1, 2, 2, 3])
	state.administrative_center_by_city = PackedInt32Array([0, 1, 2, 3, 3, 5])
	state.administrative_center_city_ids = PackedInt32Array([0, 1, 2, 3, 5])
	state.administrative_region_ids = PackedInt32Array([0, 1, 2, 3, 3, 4])
	for id in range(6):
		var city := City.new()
		city.id = id
		city.owner_nation = 1 if id == 5 else 0
		city.map_position = Vector2(float(id) / 8.0, 0.3)
		city.is_capital = id in [0, 5]
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		state.recognized_city_owners.append(city.owner_nation)
	for pair in [Vector2i(0, 1), Vector2i(0, 2), Vector2i(2, 3), Vector2i(3, 4)]:
		state._add_edge(pair.x, pair.y)
		state.edge_of(pair.x, pair.y).kind = Edge.Kind.LAND
		state.edge_of(pair.x, pair.y).max_manpower = 50000
	return state
