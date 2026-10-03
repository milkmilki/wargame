extends SceneTree

var checks := 0
var failures := 0


func _init() -> void:
	_test_capital_proposal()
	_test_subject_frontier()
	_test_alliance_integration()
	_test_prewar_reachability()
	_test_objective_context_cache()
	_test_multilevel_subjects()
	_test_subject_water_routes()
	print("REGIONAL_EXPANSION_GATES_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_capital_proposal() -> void:
	var state := fixture(true)
	check(state.campaign_fronts.is_empty(), "capital proposal starts without a synthetic front")
	var objective := DiplomacyAI.select_war_objective(state, 0, 1)
	check(int(objective.get("city_id", -1)) == 28, "capital-only remnant is a legal proposal before binding")
	check(DiplomacyAI.war_desire(state, 0, 1) >= DiplomacyAI.WAR_DECLARE_SCORE, "capital-only remnant does not force willingness to negative infinity")
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(state, actions, {}, {}, 0, 1)
	check(actions.size() == 1 and int(actions[0].kind) == DiplomacyAI.Action.PREPARE_WAR, "capital-only remnant emits actual preparation")
	check(state.campaign_fronts.is_empty(), "proposing an objective does not manufacture a front")
	var sim := Simulation.new()
	sim.setup(state)
	check(sim._start_war_preparation(0, 1, {"objective_city": 28, "objective_center_city": 28}), "capital-only preparation can be started")
	state.cities[28].garrison_manpower = 1000000
	check(not DiplomacyAI.war_preparation_launch_allowed(state, 0), "legal proposal never bypasses actual assembly requirement")
	check(DiplomacyAI.administrative_tactical_target(state, 0, 1, 28) == -1, "tactical readiness keeps the existing bound-force gate")
	sim.free()
	state = fixture(true)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	sim = Simulation.new()
	sim.setup(state)
	var wartime := sim._cached_campaign_objective(0, 1, {})
	check(int(wartime.get("city_id", -1)) == 28, "wartime new-front proposal also needs no previous binding")
	sim.free()


func _test_subject_frontier() -> void:
	var state := fixture()
	state.cities[26].owner_nation = 2
	state.recognized_city_owners[26] = 2
	state.nations[2].strategic_region_anchor_city_id = 0
	state.suzerainty[2] = {"overlord_id": 0, "civil_war": false}
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	state.ownership_revision += 1
	check(not DiplomacyAI._direct_bordering_nation_ids(state, 0).has(1), "root fixture has no personal target border")
	check(DiplomacyAI.can_initiate_war_at_range(state, 0, 1), "peaceful subject frontier enables root declaration")
	var objective := DiplomacyAI.select_war_objective(state, 0, 1)
	check(int(objective.get("tactical_city_id", -1)) == 27, "root chooses actual subject-facing entry")
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(state, actions, {}, {}, 0, 1)
	check(actions.size() == 1 and int(actions[0].kind) == DiplomacyAI.Action.PREPARE_WAR, "root frontier produces actual preparation")
	actions.clear()
	DiplomacyAI._collect_war_actions(state, actions, {}, {}, 2, 3)
	check(actions.is_empty(), "subject AI remains excluded from ordinary proactive war")
	state.suzerainty.clear()
	state.diplomacy_revision += 1
	check(not DiplomacyAI.can_initiate_war_at_range(state, 0, 1), "ordinary ally border never grants declaration eligibility")


func _test_alliance_integration() -> void:
	var state := fixture()
	state.nations[1].strategic_region_anchor_city_id = 29
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	state.diplomatic_since_day[state._diplomacy_key(0, 1)] = 0
	check(DiplomacyAI.leave_alliance_desire(state, 0, 1) >= DiplomacyAI.LEAVE_ALLIANCE_SCORE, "regional remnant interest can outweigh ordinary alliance trust")
	var score := DiplomacyAI.leave_alliance_desire(state, 0, 1)
	var bonus := RegionalStrategy.integration_war_bonus(state, 0, 1)
	var expected := DiplomacyAI.unification_rivalry(state, 0, 1) + bonus \
		- DiplomacyAI.diplomatic_attitude(state, 0, 1) * DiplomacyAI.ATTITUDE_LEAVE_WEIGHT - 0.5
	check(is_equal_approx(score, expected), "integration enters alliance exit once without conqueror amplification")
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	state.nations[2].strategic_region_anchor_city_id = 0
	check(DiplomacyAI.leave_alliance_desire(state, 0, 1) < score, "common enemy still offsets integration interest")
	state.diplomatic_since_day[state._diplomacy_key(0, 1)] = state.day
	check(DiplomacyAI.leave_alliance_desire(state, 0, 1) == -INF, "integration leaves minimum alliance age intact")
	state.diplomatic_since_day[state._diplomacy_key(0, 1)] = 0
	state.suzerainty[1] = {"overlord_id": 0, "civil_war": false}
	state.diplomacy_revision += 1
	check(is_zero_approx(RegionalStrategy.integration_war_bonus(state, 0, 1)), "internal suzerainty receives no exit incentive")
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_leave_alliance_actions(state, actions, {}, {})
	check(actions.is_empty(), "internal suzerainty cannot be dismantled by the exit collector")


func _test_prewar_reachability() -> void:
	var state := fixture()
	state.cities[26].owner_nation = 2
	state.suzerainty[2] = {"overlord_id": 0, "civil_war": false}
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	state.ownership_revision += 1
	var cache := {}
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27, cache) == [26], "root stages on reachable subject territory")
	var fields: Dictionary = cache.get("prewar_path_fields", {})
	check(fields.size() == 1, "one connected deployment region builds only one path field")
	for _query in range(20):
		DiplomacyAI.war_preparation_staging_cities(state, 0, 27, cache)
	check((cache.get("prewar_path_fields", {}) as Dictionary).size() == 1, "repeated staging queries reuse source path field")
	state.edge_of(25, 26).max_manpower = 0
	state.road_network_revision += 1
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27, cache).is_empty(), "isolated subject enclave cannot pretend root armies can assemble")
	check(DiplomacyAI.select_war_objective(state, 0, 1, cache).is_empty(), "unreachable enclave creates no prewar objective")
	state.armies[0].location_city = 26
	state.armies[0].move_from = 26
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27).has(26), "real root detachment in enclave is a valid deployment source")
	state.armies[0].size = 0
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27).is_empty(), "dead detachment never creates a source")
	state.edge_of(25, 26).max_manpower = 30000
	state.road_network_revision += 1
	state.suzerainty[2]["civil_war"] = true
	state.diplomacy_revision += 1
	check(not DiplomacyAI.can_initiate_war_at_range(state, 0, 1, cache), "civil-war subject ceases to grant peaceful frontier")
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27, cache).is_empty(), "civil-war subject cannot be a prewar staging owner")


func _test_objective_context_cache() -> void:
	var state := fixture(true)
	state.cities[27].owner_nation = 2
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	state.ownership_revision += 1
	var cache := {}
	var prewar := DiplomacyAI.select_war_objective(state, 0, 1, cache)
	var campaign := DiplomacyAI.select_war_objective(state, 0, 1, cache, -1, false, {}, false, DiplomacyAI.ObjectiveContext.CAMPAIGN)
	check(prewar.is_empty(), "ordinary ally staging is excluded from prewar proposals")
	check(int(campaign.get("tactical_city_id", -1)) == 28, "war coalition proposal retains allied staging access")
	state.suzerainty[2] = {"overlord_id": 0, "civil_war": false}
	state.diplomacy_revision += 1
	check(int(DiplomacyAI.select_war_objective(state, 0, 1, cache).get("tactical_city_id", -1)) == 28, "same cache refreshes after peaceful submission")
	state.suzerainty.clear()
	state.diplomacy_revision += 1
	check(DiplomacyAI.select_war_objective(state, 0, 1, cache).is_empty(), "same cache refreshes after subject exit")
	state.suzerainty[2] = {"overlord_id": 0, "civil_war": false}
	state.diplomacy_revision += 1
	var sim := Simulation.new()
	sim.setup(state)
	check(not sim._cached_campaign_objective(0, 1, cache).is_empty(), "campaign cache starts with valid proposal")
	state.edge_of(27, 28).max_manpower = 0
	state.edge_of(28, 29).max_manpower = 0
	state.road_network_revision += 1
	check(sim._cached_campaign_objective(0, 1, cache).is_empty(), "campaign objective cache refreshes after road interruption")
	sim.free()


func _test_multilevel_subjects() -> void:
	var state := fixture()
	var child := Nation.new()
	child.id = 3
	child.capital_city_id = 26
	state.nations.append(child)
	state.cities[26].owner_nation = 3
	state.recognized_city_owners[26] = 3
	state.administrative_center_by_city[26] = 26
	state.administrative_center_city_ids.append(26)
	state.suzerainty[2] = {"overlord_id": 0, "civil_war": false}
	state.suzerainty[3] = {"overlord_id": 2, "civil_war": false}
	for pair in [Vector2i(0, 2), Vector2i(0, 3), Vector2i(2, 3)]:
		state.set_diplomatic_relation(pair.x, pair.y, GameState.DiplomaticRelation.ALLIED)
	state.ownership_revision += 1
	state.administrative_region_revision += 1
	check(DiplomacyAI.can_initiate_war_at_range(state, 0, 1), "nested subject frontier is part of peaceful root territory")
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27) == [26], "nested subject supplies reachable root staging")
	state.suzerainty[2]["civil_war"] = true
	state.diplomacy_revision += 1
	check(not DiplomacyAI.can_initiate_war_at_range(state, 0, 1), "civil war splits the whole descendant frontier from root")
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27).is_empty(), "civil-war descendants cannot provide root staging")


func _test_subject_water_routes() -> void:
	var state := fixture()
	state.cities[26].owner_nation = 2
	state.suzerainty[2] = {"overlord_id": 0, "civil_war": false}
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	state.edge_of(26, 27).max_manpower = 0
	var dock := _dock(state, 1)
	_water_edge(state, 26, dock, Edge.Kind.LANDING)
	_water_edge(state, 27, dock, Edge.Kind.LANDING)
	state.road_network_revision += 1
	state.ownership_revision += 1
	check(DiplomacyAI.can_initiate_war_at_range(state, 0, 1), "subject bank grants local crossing border even through enemy-owned dock")
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27) == [26], "local crossing stages on peaceful subject bank")
	state.edge_of(27, dock).max_manpower = 0
	state.cities[dock].owner_nation = 2
	var enemy_dock := _dock(state, 1)
	_water_edge(state, dock, enemy_dock, Edge.Kind.RIVER)
	_water_edge(state, 27, enemy_dock, Edge.Kind.LANDING)
	state.cities[29].owner_nation = 1
	state.road_network_revision += 1
	state.ownership_revision += 1
	var cache := {}
	check(not DiplomacyAI._expansion_bordering_nation_ids(state, 0, cache).has(1), "multi-dock river chain never grants territorial adjacency")
	check(DiplomacyAI.can_initiate_war_at_range(state, 0, 1, cache), "existing expedition fallback accepts reachable subject source dock")
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27, cache) == [dock], "expedition freezes reachable subject dock, not foreign bank")
	state.edge_of(dock, enemy_dock).max_manpower = 0
	state.road_network_revision += 1
	check(not DiplomacyAI.can_initiate_war_at_range(state, 0, 1, cache), "water interruption invalidates expedition eligibility")
	check(DiplomacyAI.war_preparation_staging_cities(state, 0, 27, cache).is_empty(), "water interruption invalidates cached staging")


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


static func fixture(capital_only: bool = false) -> GameState:
	var state := GameState.new()
	state.rng.seed = state.world_seed
	state.day = 3650
	for owner in range(3):
		var nation := Nation.new()
		nation.id = owner
		nation.capital_city_id = [0, 28, 29][owner]
		nation.strategic_region_anchor_city_id = 0 if owner < 2 else 29
		nation.treasury_gold = 1000000
		nation.manpower_pool = 1000000
		nation.granary_food = 1000000
		nation.ruler_archetype = RulerProfile.CONQUEROR if owner == 0 else RulerProfile.BALANCED
		nation.ruler_traits.clear()
		state.nations.append(nation)
	for id in range(30):
		var owner := 0 if id < (28 if capital_only else 27) else (1 if id < 29 else 2)
		var center := 0 if id < 27 else (28 if id < 29 else 29)
		var city := City.new()
		city.id = id
		city.owner_nation = owner
		city.map_position = Vector2(id, 0)
		city.gold_per_month = 1000
		city.food_per_half_year = 100000
		city.manpower_per_month = 1000
		city.food_storage = 1000000
		if id == state.nations[owner].capital_city_id:
			city.has_warehouse = true
			state.nations[owner].warehouse_city_ids.append(id)
		city.garrison_manpower = 1000 if id == center else 0
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		state.region_ids.append(0 if id < 29 else 1)
		state.administrative_center_by_city.append(center)
		state.recognized_city_owners.append(owner)
		if id == center:
			state.administrative_center_city_ids.append(id)
		if id > 0:
			state._add_edge(id - 1, id)
	for a in range(3):
		for b in range(a + 1, 3):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	for owner in range(3):
		for formation in range(6 if owner == 0 else 1):
			var army := Army.new()
			army.id = state.armies.size()
			army.owner_nation = owner
			army.location_city = [25, 28 if capital_only else 27, 29][owner]
			army.move_from = army.location_city
			army.size = 15000
			army.max_size = 15000
			army.morale = 2.0
			army.max_morale = 2.0
			army.ruler_attack_multiplier = RulerProfile.attack_multiplier(state.nations[owner])
			army.ruler_defense_multiplier = RulerProfile.defense_multiplier(state.nations[owner])
			army.ruler_morale_multiplier = RulerProfile.morale_multiplier(state.nations[owner])
			state.armies.append(army)
	return state


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
