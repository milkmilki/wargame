extends SceneTree

const RegionFixture = preload("res://tests/regional_strategy.gd")
const ExpansionFixture = preload("res://tests/regional_expansion_gates.gd")

var checks := 0
var failures := 0


func _init() -> void:
	_test_isolated_subject_frontier()
	_test_lost_target_recovery()
	_test_ownership_and_suzerainty_recovery()
	_test_owned_target_preserved()
	_test_accessible_target_preserved_without_troops()
	_test_subject_land_and_water_access()
	print("REGIONAL_ACCESS_RECOVERY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_isolated_subject_frontier() -> void:
	var state := _subject_fixture()
	state.edge_of(25, 26).max_manpower = 0
	state.road_network_revision += 1
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27).is_empty(),
		"isolated subject frontier has no reachable root deployment entrance")
	check(not DiplomacyAI.war_staging_cities_for_objective(state, 2, 27).is_empty(),
		"isolated subject can stage locally, reproducing the false root-frontier input")
	check(RegionalStrategy.choose_next_region(state, 0) == -1,
		"root cannot select a region only an isolated peaceful subject can attack")
	RegionalStrategy.update_target(state, 0)
	check(RegionalStrategy.target_region(state, 0) == 0,
		"completed domestic region is retained when all external frontiers are unreachable")


func _test_lost_target_recovery() -> void:
	var state := RegionFixture.fixture()
	state.nations[0].strategic_region_anchor_city_id = 2
	state.edge_of(0, 2).max_manpower = 0
	state.road_network_revision += 1
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 2).is_empty(),
		"old target has no deployable entrance after route loss")
	check(not DiplomacyAI.war_preparation_staging_cities(state, 0, 4).is_empty(),
		"another frontier remains deployable after old route loss")
	check(RegionalStrategy.update_target(state, 0),
		"unowned inaccessible unfinished target is reevaluated")
	check(RegionalStrategy.target_region(state, 0) == 2,
		"lost target switches to the remaining reachable region")
	var revision := state.regional_strategy_revision
	RegionalStrategy.update_target(state, 0)
	check(state.regional_strategy_revision == revision,
		"rechecking a reachable replacement does not churn strategy revision")
	state = RegionFixture.fixture()
	state.nations[0].strategic_region_anchor_city_id = 2
	for pair in [Vector2i(0, 2), Vector2i(1, 4)]:
		state.edge_of(pair.x, pair.y).max_manpower = 0
	state.road_network_revision += 1
	RegionalStrategy.update_target(state, 0)
	check(RegionalStrategy.target_region(state, 0) == 0,
		"lost target falls back to the largest controlled region when no frontier is reachable")


func _test_owned_target_preserved() -> void:
	for owner in [0, 1]:
		var state := RegionFixture.fixture()
		state.nations[0].strategic_region_anchor_city_id = 2
		if owner == 0:
			state.cities[2].owner_nation = 0
			state.ownership_revision += 1
		else:
			# A peaceful subject retains part of the target while the remaining city is foreign.
			state.cities[3].owner_nation = 2
			state.suzerainty[1] = {"overlord_id": 0, "civil_war": false}
			state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
			state.ownership_revision += 1
		for edge in state.edges:
			edge.max_manpower = 0
		state.road_network_revision += 1
		var anchor := state.nations[0].strategic_region_anchor_city_id
		RegionalStrategy.update_target(state, 0)
		check(state.nations[0].strategic_region_anchor_city_id == anchor,
			"partially controlled target survives inaccessible routes, owner=%d" % owner)


func _test_ownership_and_suzerainty_recovery() -> void:
	var state := RegionFixture.fixture()
	state.nations[0].strategic_region_anchor_city_id = 2
	RegionalStrategy.control(state)
	state.cities[0].owner_nation = 2
	state.ownership_revision += 1
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 2).is_empty(),
		"lost home border removes the actual entrance to the old target")
	RegionalStrategy.update_target(state, 0)
	var replacement := RegionalStrategy.target_region(state, 0)
	check(replacement != 1,
		"ownership revision replaces an inaccessible unowned target")
	var reachable := false
	for city in state.cities:
		if city.owner_nation != 0 and RegionalStrategy.city_region(state, city.id) == replacement:
			if not DiplomacyAI.war_preparation_staging_cities(state, 0, city.id).is_empty():
				reachable = true
	check(reachable, "ownership recovery selects a region with a real root deployment entrance")
	var repeated := RegionFixture.fixture()
	repeated.nations[0].strategic_region_anchor_city_id = 2
	RegionalStrategy.control(repeated)
	repeated.cities[0].owner_nation = 2
	repeated.ownership_revision += 1
	RegionalStrategy.update_target(repeated, 0)
	check(RegionalStrategy.target_region(repeated, 0) == replacement,
		"identical ownership loss chooses the same reachable replacement deterministically")
	state = _subject_fixture()
	state.nations[0].strategic_region_anchor_city_id = 28
	RegionalStrategy.control(state)
	check(not DiplomacyAI.war_preparation_staging_cities(state, 0, 27).is_empty(),
		"former subject corridor starts reachable")
	state.suzerainty.clear()
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.NEUTRAL)
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27).is_empty(),
		"subject independence removes the former borrowing corridor")
	RegionalStrategy.update_target(state, 0)
	check(RegionalStrategy.target_region(state, 0) == 2,
		"diplomacy revision replaces the now-isolated foreign target")


func _test_accessible_target_preserved_without_troops() -> void:
	var state := _subject_fixture()
	state.nations[0].strategic_region_anchor_city_id = 28
	state.nations[0].manpower_pool = 0
	for army in state.armies:
		army.size = 0
	check(not DiplomacyAI.war_preparation_staging_cities(state, 0, 27).is_empty(),
		"deployment geography stays reachable with no current armies or manpower")
	var anchor := state.nations[0].strategic_region_anchor_city_id
	var revision := state.regional_strategy_revision
	RegionalStrategy.update_target(state, 0)
	check(state.nations[0].strategic_region_anchor_city_id == anchor,
		"zero manpower does not replace an accessible unfinished target")
	check(state.regional_strategy_revision == revision,
		"zero manpower does not invalidate unchanged strategy")
	state.nations[0].strategic_region_anchor_city_id = 0
	check(RegionalStrategy.choose_next_region(state, 0) == 1,
		"new target selection uses geography rather than current field strength")


func _test_subject_land_and_water_access() -> void:
	var state := _subject_fixture()
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27) == [26],
		"reachable peaceful subject bank is a valid root staging entrance")
	check(RegionalStrategy.choose_next_region(state, 0) == 1,
		"reachable subject land frontier is selected despite no personal root border")
	state = _subject_fixture()
	state.edge_of(26, 27).max_manpower = 0
	state.edge_of(28, 29).max_manpower = 0
	var dock := _dock(state, 1)
	_water_edge(state, 26, dock, Edge.Kind.LANDING)
	_water_edge(state, 27, dock, Edge.Kind.LANDING)
	state.road_network_revision += 1
	state.ownership_revision += 1
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27) == [26],
		"local water crossing preserves the root entrance through a subject bank")
	check(RegionalStrategy.choose_next_region(state, 0) == 1,
		"region selection accepts the same local crossing as ordinary declaration")
	state = _subject_fixture()
	state.edge_of(26, 27).max_manpower = 0
	state.edge_of(28, 29).max_manpower = 0
	dock = _dock(state, 2)
	_water_edge(state, 26, dock, Edge.Kind.LANDING)
	var enemy_dock := _dock(state, 1)
	_water_edge(state, dock, enemy_dock, Edge.Kind.RIVER)
	_water_edge(state, 27, enemy_dock, Edge.Kind.LANDING)
	state.road_network_revision += 1
	state.ownership_revision += 1
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27) == [dock],
		"legal river expedition has a reachable source dock")
	check(RegionalStrategy.choose_next_region(state, 0) == 1,
		"region selection accepts legal expedition without direct territorial adjacency")
	state.edge_of(dock, enemy_dock).max_manpower = 0
	state.road_network_revision += 1
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27).is_empty(),
		"broken river invalidates the actual root entrance")
	check(RegionalStrategy.choose_next_region(state, 0) == -1,
		"broken river also removes the strategic candidate")


func _subject_fixture() -> GameState:
	var state := ExpansionFixture.fixture()
	state.cities[26].owner_nation = 2
	state.recognized_city_owners[26] = 2
	state.administrative_center_by_city[26] = 26
	state.administrative_center_city_ids.append(26)
	state.region_ids[26] = 2
	state.region_ids[27] = 1
	state.region_ids[28] = 1
	state.region_ids[29] = 2
	state.nations[0].strategic_region_anchor_city_id = 0
	state.suzerainty[2] = {"overlord_id": 0, "civil_war": false}
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	state.ownership_revision += 1
	state.administrative_region_revision += 1
	state.region_analysis_revision += 1
	return state


func _dock(state: GameState, owner: int) -> int:
	var city := City.new()
	city.id = state.cities.size()
	city.owner_nation = owner
	city.is_dock = true
	state.cities.append(city)
	state.adjacency[city.id] = [] as Array[int]
	state.administrative_center_by_city.append(-1)
	state.region_ids.append(-1)
	state.recognized_city_owners.append(owner)
	return city.id


func _water_edge(state: GameState, a: int, b: int, kind: int) -> void:
	state._add_edge(a, b)
	state.edge_of(a, b).kind = kind
	state.edge_of(a, b).max_manpower = Edge.WATER_MANPOWER


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
