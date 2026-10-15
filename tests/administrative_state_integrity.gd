extends SceneTree

const Direct = preload("res://tests/direct_center_camp.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func enclave_fixture(whole_enclave: bool, mother_capital: int = 0) -> Dictionary:
	var state := GameState.new()
	state._reset_world(97015)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 3, false)
	state.day = 500
	var centers := [0, 0, 0, 3, 3, 5, 5, 7]
	for id in range(8):
		var city := City.new()
		city.id = id
		city.name = ["卫成", "卫南", "成都", "兴成", "日南", "邻成", "邻南", "中成"][id]
		city.short_name = ["卫", "卫南", "成都", "兴", "日南", "邻", "邻南", "中"][id]
		city.owner_nation = 0 if id < 5 else (1 if id < 7 else 2)
		city.map_position = Vector2(float(id) / 8., .5)
		city.food_storage = 20000 * (id + 1)
		city.food_per_half_year = 100000
		city.gold_per_month = 10000
		city.garrison_manpower = 0
		city.has_warehouse = id in [0, 3, 5, 7]
		state.cities.append(city)
		state.recognized_city_owners.append(city.owner_nation)
		state.administrative_center_by_city.append(centers[id])
		state.region_ids.append(0)
		state.adjacency[id] = [] as Array[int]
	state.administrative_center_city_ids = PackedInt32Array([0, 3, 5, 7])
	var pairs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(3, 4), Vector2i(5, 6), Vector2i(6, 7)]
	if whole_enclave:
		pairs.append_array([Vector2i(1, 2), Vector2i(4, 5)] as Array[Vector2i])
	else:
		# The geographic border graph cuts through one administrative state:
		# its seat and first fu are in the main component; its second fu is a
		# detached component bordering another sovereign. This is possible on
		# generated maps, but is not permission to cede the fu alone.
		pairs.append_array([Vector2i(0, 3), Vector2i(2, 5)] as Array[Vector2i])
	for pair in pairs:
		var edge := Edge.new()
		edge.city_a = pair.x
		edge.city_b = pair.y
		edge.distance = .1
		edge.max_manpower = 15000
		edge.base_max_manpower = 15000
		state.edges.append(edge)
		state.edge_lookup[GameState.edge_key(pair.x, pair.y)] = edge
		state.adjacency[pair.x].append(pair.y)
		state.adjacency[pair.y].append(pair.x)
	for id in range(3):
		state.nations[id].capital_city_id = [mother_capital, 5, 7][id]
		state.nations[id].manpower_pool = 10000
		state.nations[id].treasury_gold = 1000000
		state.nations[id].ruler_started_day = 0
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.refresh_derived()
	var sim := Simulation.new()
	sim.setup(state)
	return {"state": state, "sim": sim}


func draft_for(state: GameState) -> Dictionary:
	var owners: Array[int] = []
	var legal: Array[int] = []
	var sponsors: Array[int] = []
	for city in state.cities:
		owners.append(city.owner_nation)
		legal.append(state.recognized_owner_of(city.id))
		sponsors.append(city.occupation_sponsor_nation)
	return {"owners": owners, "legal": legal, "sponsors": sponsors,
		"operation_by_city": {}, "proposed_suzerainty": state.suzerainty.duplicate(true)}


func resources(state: GameState) -> Array[int]:
	var total_food := 0
	var total_gold := 0
	for city in state.cities:
		total_food += city.food_storage
	for nation in state.nations:
		total_gold += nation.treasury_gold
	return [total_food, total_gold] as Array[int]


func owned_and_legal(state: GameState, members: Array[int], owner: int) -> bool:
	for id in members:
		if state.cities[id].owner_nation != owner or state.recognized_owner_of(id) != owner:
			return false
	return true


func peace(sim: Simulation, a: int, b: int) -> bool:
	return sim._execute_diplomatic_action({"kind": DiplomacyAI.Action.MAKE_PEACE,
		"a": a, "b": b, "reason": "整州法理一致性回归"})


func test_enclave_plan(whole_enclave: bool) -> void:
	var data := enclave_fixture(whole_enclave)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var draft := draft_for(state)
	var rng_before := state.rng.state
	var moved := sim._plan_coalition_enclave_transfers(draft, [0, 1] as Array[int])
	if whole_enclave:
		check(moved == 2 and int(draft.owners[3]) == 1 and int(draft.owners[4]) == 1
			and int(draft.legal[3]) == 1 and int(draft.legal[4]) == 1,
			"a complete detached administrative state transfers both its seat and fu")
	else:
		check(moved == 0 and int(draft.owners[2]) == 0 and int(draft.legal[2]) == 0,
			"a detached fu of a retained state is not ceded alone: moved=%d owners=%s legal=%s" % [moved, draft.owners, draft.legal])
	check(owned_and_legal(state, [0, 1, 2, 3, 4] as Array[int], 0),
		"enclave planning leaves the live territory unchanged")
	check(state.rng.state == rng_before, "enclave planning consumes no simulation random draws")
	sim.free()


func test_enclave_real_peace(whole_enclave: bool, reverse: bool) -> void:
	var data := enclave_fixture(whole_enclave)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var before := resources(state)
	var neutral_before := [state.cities[7].owner_nation, state.recognized_owner_of(7),
		state.cities[7].food_storage, state.nations[2].treasury_gold]
	check(peace(sim, 1 if reverse else 0, 0 if reverse else 1), "actual coalition peace commits for either argument order")
	check(owned_and_legal(state, [0, 1, 2] as Array[int], 0), "peace never splits the retained administrative state")
	check(owned_and_legal(state, [3, 4] as Array[int], 1 if whole_enclave else 0),
		"peace transfers a complete enclave and otherwise retains the second state")
	check(not state.is_enemy(0, 1), "real enclave settlement clears the participating war")
	check(resources(state) == before, "enclave peace conserves physical food and treasury gold")
	check([state.cities[7].owner_nation, state.recognized_owner_of(7),
		state.cities[7].food_storage, state.nations[2].treasury_gold] == neutral_before,
		"unrelated neutral country retains territory and resources")
	var settled := [draft_for(state), resources(state), state.chronicle_events.size()]
	check(not peace(sim, 0, 1) and [draft_for(state), resources(state), state.chronicle_events.size()] == settled,
		"repeating a completed peace does not transfer resources or emit another final event")
	sim.free()


func rebellion_fixture(control: String) -> Dictionary:
	var state := Direct.fixture()
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	var rebel := state.start_regional_rebellion(0, [6, 7] as Array[int])
	check(rebel >= 0, "rebellion starts through a real whole-state uprising")
	# Model ordinary military recapture: legal title remains with the mother.
	# This deliberately does not directly recognize or eliminate the rebel.
	var retaken := 6 if control == "fu_only" else (7 if control == "seat_only" else -1)
	if retaken >= 0:
		var result := state.apply_territory_transaction([{
			"city_id": retaken, "controller_id": 0, "legal_owner_id": 0,
			"sponsor_id": -1, "reason": "regression_core_recaptured",
			"stock_policy": GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL,
		}] as Array[Dictionary])
		check(bool(result.get("ok", false)), "recapture uses the real territory transaction")
	state.day += 400
	state.refresh_derived()
	var sim := Simulation.new()
	sim.setup(state)
	return {"state": state, "sim": sim, "rebel": rebel}


func test_rebellion_direct(control: String) -> void:
	var data := rebellion_fixture(control)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var rebel: int = data.rebel
	var before := [draft_for(state), resources(state), state.chronicle_events.size()]
	var recognized := state.recognize_regional_rebellion(rebel)
	if control == "fu_only":
		check(not recognized and bool(state.rebellions[rebel].active)
			and not bool(state.rebellions[rebel].recognized),
			"direct recognition rejects a rebel retaining only a subordinate fu")
		check([draft_for(state), resources(state), state.chronicle_events.size()] == before,
			"rejected fu-only sovereignty changes no territory, stock or history")
	else:
		check(recognized and bool(state.rebellions[rebel].recognized), "a rebel holding the original seat can be recognized")
		check(owned_and_legal(state, [6, 7] as Array[int], rebel),
			"direct recognition transfers the entire original state, including a mother-retaken fu")
		check(resources(state) == before[1], "whole-state recognition conserves food and gold")
		var settled := [draft_for(state), resources(state), state.chronicle_events.size()]
		check(not state.recognize_regional_rebellion(rebel)
			and [draft_for(state), resources(state), state.chronicle_events.size()] == settled,
			"direct recognition is idempotent")
	sim.free()


func test_rebellion_real_peace(control: String, reverse: bool) -> void:
	var data := rebellion_fixture(control)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var rebel: int = data.rebel
	var before := resources(state)
	var neutral_before := [state.cities[5].owner_nation, state.recognized_owner_of(5),
		state.cities[5].food_storage, state.nations[2].treasury_gold]
	check(peace(sim, rebel if reverse else 0, 0 if reverse else rebel),
		"rebellion concludes through actual coalition peace in either argument order")
	var should_recognize := control != "fu_only"
	check(not bool(state.rebellions[rebel].active)
		and bool(state.rebellions[rebel].recognized) == should_recognize,
		"recognition outcome follows the original seat, never a residual fu")
	check(owned_and_legal(state, [6, 7] as Array[int], rebel if should_recognize else 0),
		"rebellion peace settles both legal title and controller for the entire state")
	check(state.nations[rebel].alive == should_recognize and not state.is_enemy(0, rebel),
		"a fu-only rebel is actually absorbed and the original war is released")
	check(resources(state) == before, "actual rebellion peace conserves physical food and treasury gold")
	check([state.cities[5].owner_nation, state.recognized_owner_of(5),
		state.cities[5].food_storage, state.nations[2].treasury_gold] == neutral_before,
		"rebellion settlement leaves a neutral country's title and stock untouched")
	var final_events := state.chronicle_events.filter(func(event: Dictionary):
		return (event.get("kind", "") == "rebellion" and event.get("actor_ids", []).has(rebel)
			and event.get("result", "") in ["recognized", "suppressed"]))
	check(final_events.size() == 1, "actual rebellion final event occurs exactly once")
	var settled := [draft_for(state), resources(state), state.chronicle_events.size()]
	check(not peace(sim, 0, rebel) and [draft_for(state), resources(state), state.chronicle_events.size()] == settled,
		"repeating rebellion peace does not resurrect rebels or duplicate stock/history")
	sim.free()


func test_direct_occupation_recognition(seat_captured: bool, reverse: bool) -> void:
	var state := Direct.fixture()
	# Nation 2 is the coalition member actually holding the captured seat.
	# Nation 3 remains neutral and has an existing legal prefecture in that
	# province. Whole-state settlement must not annex that third-party title.
	var neutral := Nation.new()
	neutral.id = 3
	neutral.capital_city_id = 6
	neutral.treasury_gold = 999999
	state.nations.append(neutral)
	for id in [6, 7]:
		state.cities[id].owner_nation = 3
		state.recognized_city_owners[id] = 3
	var neutral_fu := City.new()
	neutral_fu.id = state.cities.size()
	neutral_fu.owner_nation = 3
	neutral_fu.food_storage = 12345
	state.cities.append(neutral_fu)
	state.recognized_city_owners.append(3)
	state.administrative_center_by_city.append(3)
	state.region_ids.append(0)
	state.adjacency[neutral_fu.id] = [] as Array[int]
	state._add_edge(3, neutral_fu.id)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	var capture := 3 if seat_captured else 4
	var result := state.apply_territory_transaction([{
		"city_id": capture, "controller_id": 2, "legal_owner_id": 1,
		"sponsor_id": 0, "stock_policy": GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL,
		"reason": "regression_allied_occupation",
	}] as Array[Dictionary])
	check(bool(result.get("ok", false)), "allied military occupation uses a real transaction")
	var before := resources(state)
	var neutral_before := [state.cities[neutral_fu.id].owner_nation,
		state.recognized_owner_of(neutral_fu.id), state.cities[neutral_fu.id].food_storage,
		state.nations[3].treasury_gold]
	var settled := {GameState.edge_key(0, 1): true, GameState.edge_key(1, 2): true}
	var friendly: Array[int] = [0, 2]
	var hostile: Array[int] = [1]
	if reverse:
		state.recognize_coalition_occupied_territory(hostile, friendly, settled)
	else:
		state.recognize_coalition_occupied_territory(friendly, hostile, settled)
	check(owned_and_legal(state, [3, 4] as Array[int], 2 if seat_captured else 1),
		"direct coalition entry follows the actual seat controller and restores fu-only occupation")
	check([state.cities[neutral_fu.id].owner_nation,
		state.recognized_owner_of(neutral_fu.id), state.cities[neutral_fu.id].food_storage,
		state.nations[3].treasury_gold] == neutral_before,
		"direct coalition entry preserves neutral third-party law within the same province")
	check(resources(state) == before, "direct coalition recognition conserves food and gold")
	var after := [draft_for(state), resources(state)]
	check(state.recognize_coalition_occupied_territory([0, 2] as Array[int], [1] as Array[int], settled).is_empty()
		and [draft_for(state), resources(state)] == after,
		"repeating direct recognition does not recredit captured stock")


func test_partial_state_cannot_start_rebellion() -> void:
	var state := Direct.fixture()
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	# The parent still owns the seat but a separate legal sovereign owns its
	# subordinate prefecture. Passing the parent's subset is not a whole-state
	# uprising. The rejection must happen before creating a ruler or armies.
	state.cities[7].owner_nation = 2
	state.recognized_city_owners[7] = 2
	state.ownership_revision += 1
	state.refresh_derived()
	var rng_before := state.rng.state
	var before := [draft_for(state), resources(state), state.nations.size(),
		state.armies.size(), state.rebellions.duplicate(true), state.chronicle_events.size()]
	var rebel := state.start_regional_rebellion(0, [6] as Array[int])
	check(rebel == -1, "a parent-controlled subset of a split state cannot become a new partial-state rebellion")
	check([draft_for(state), resources(state), state.nations.size(), state.armies.size(),
		state.rebellions.duplicate(true), state.chronicle_events.size()] == before,
		"rejected partial-state uprising creates no country, army, territory, stocks or history")
	check(state.rng.state == rng_before, "rejecting a partial-state uprising consumes no simulation randomness")


func test_external_fu_claim_defers_whole_state(fu_controller: int) -> void:
	var state := Direct.fixture()
	for id in [6, 7]:
		state.cities[id].owner_nation = 1
		state.recognized_city_owners[id] = 1
	state.nations[1].capital_city_id = 6
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	var external_war := state.war_id_between(1, 2)
	var occupied := state.apply_territory_transaction([{
		"city_id": 3, "controller_id": 0, "legal_owner_id": 1,
		"sponsor_id": 0, "stock_policy": GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL,
		"reason": "regression_settling_seat_occupation",
	}, {
		"city_id": 4, "controller_id": fu_controller, "legal_owner_id": 1,
		"sponsor_id": 2, "stock_policy": GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL,
		"reason": "regression_unsettled_external_fu_occupation",
	}] as Array[Dictionary])
	check(bool(occupied.get("ok", false)), "same-state internal and external occupations use a real transaction")
	state.refresh_derived()
	var before := resources(state)
	var claim_before := [state.cities[4].owner_nation, state.recognized_owner_of(4),
		state.cities[4].occupation_sponsor_nation]
	var sim := Simulation.new()
	sim.setup(state)
	var kind := "ordinary peace"
	check(peace(sim, 0, 1),
		kind + " concludes the internal/selected war while external war continues")
	check(state.recognized_owner_of(3) == 1 and state.recognized_owner_of(4) == 1,
		kind + " cannot split a unified legal state around an unsettled external fu claim")
	check(state.cities[3].owner_nation == 1 and state.cities[3].occupation_sponsor_nation == -1,
		kind + " restores its own temporary seat occupation when whole-state cession is deferred")
	check([state.cities[4].owner_nation, state.recognized_owner_of(4),
		state.cities[4].occupation_sponsor_nation] == claim_before,
		kind + " preserves the external fu controller, sponsor and legal title")
	check(state.is_enemy(1, 2) and state.war_id_between(1, 2) == external_war,
		kind + " preserves the independent external war")
	check(resources(state) == before, kind + " conserves physical food and treasury gold")
	sim.free()


func test_rebellion_parent_annexed_by_third_country() -> void:
	var data := rebellion_fixture("whole")
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var rebel: int = data.rebel
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	var before := resources(state)
	check(state.annex_nation(2, 0), "third-country victory annexes the rebellion's mother through the real transaction")
	check(not state.nations[0].alive, "the rebellion's original mother is actually eliminated")
	state.prune_rebellions()
	check(not bool(state.rebellions[rebel].active) or int(state.rebellions[rebel].parent_id) != 0,
		"pruning cannot leave an active rebellion referencing an eliminated mother")
	check(state.rebellion_structure_valid(), "third-country annexation and pruning leave a valid rebellion lifecycle")
	check(state.recognized_owner_of(6) == state.recognized_owner_of(7),
		"resolving an eliminated mother does not split its original rebellion state")
	check(resources(state) == before, "mother-country annexation and rebel pruning conserve food and gold")
	var after := [draft_for(state), resources(state), state.chronicle_events.size(), state.rebellions.duplicate(true)]
	state.prune_rebellions()
	check([draft_for(state), resources(state), state.chronicle_events.size(), state.rebellions.duplicate(true)] == after,
		"repeated pruning after mother annexation is idempotent")
	sim.free()


func test_original_chengdu_transfer_chain() -> void:
	# The original run split an uprising state in a different war's peace:
	# uprising -> mother retakes one detached fu -> unrelated peace invokes
	# enclave cleanup -> that fu must remain in the original legal state.
	var data := enclave_fixture(false, 3)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var started_day := state.day
	var rebel := state.start_regional_rebellion(0, [0, 1, 2] as Array[int])
	check(rebel >= 0, "original-chain rebellion starts from a full state outside the mother's capital")
	if rebel < 0:
		sim.free()
		return
	var rebellion_war_started := state.relation_since(0, rebel)
	state.day = started_day + 41
	var recapture := state.transfer_city_control(2, 0, -1,
		GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL, "regression_chengdu_mother_retake")
	check(bool(recapture.get("ok", false)) and state.cities[2].owner_nation == 0,
		"mother retakes only the detached prefecture through actual transfer_city_control")
	check(state.cities[0].owner_nation == rebel and state.cities[1].owner_nation == rebel
		and state.recognized_owner_of(0) == 0 and state.recognized_owner_of(2) == 0,
		"military recapture leaves whole-state original legal title intact")
	state.day = started_day + 150
	var before_peace := resources(state)
	check(peace(sim, 0, 1), "mother settles an unrelated neighbor war through real MAKE_PEACE")
	check(state.cities[2].owner_nation == 0 and state.recognized_owner_of(2) == 0,
		"unrelated peace enclave cleanup never gifts the recovered prefecture to its neighbor")
	check(state.recognized_owner_of(0) == 0 and state.recognized_owner_of(1) == 0,
		"unrelated peace preserves unified legal title of the still-contested uprising state")
	check(state.is_enemy(0, rebel) and state.relation_since(0, rebel) == rebellion_war_started
		and int(state.rebellions[rebel].started_day) == started_day
		and state.regional_rebellion_peace_locked(0, rebel),
		"unrelated peace preserves the original uprising war, start day and one-year lock")
	check(resources(state) == before_peace, "unrelated peace in the original chain conserves food and gold")
	var locked := [draft_for(state), resources(state), state.chronicle_events.size()]
	check(not peace(sim, 0, rebel) and [draft_for(state), resources(state), state.chronicle_events.size()] == locked,
		"the unfinished one-year lock rejects early recognition without side effects")
	state.day = started_day + RebellionSystem.REGIONAL_REBELLION_MIN_WAR_DAYS
	var before_recognition := resources(state)
	check(peace(sim, 0, rebel), "the original mother and rebel settle through real peace when the lock expires")
	check(owned_and_legal(state, [0, 1, 2] as Array[int], rebel),
		"the seat-holding rebel receives its entire uprising state including the recovered prefecture")
	check(not state.is_enemy(0, rebel) and not bool(state.rebellions[rebel].active)
		and bool(state.rebellions[rebel].recognized), "the original uprising ends with completed recognition")
	check(resources(state) == before_recognition, "whole-state recognition in the original chain conserves food and gold")
	var final_events := state.chronicle_events.filter(func(event: Dictionary):
		return (event.get("kind", "") == "rebellion" and event.get("actor_ids", []).has(rebel)
			and event.get("result", "") == "recognized"))
	check(final_events.size() == 1, "the complete original chain emits exactly one rebellion recognition result")
	var settled := [draft_for(state), resources(state), state.chronicle_events.size()]
	state.prune_rebellions()
	check(not peace(sim, 0, rebel)
		and [draft_for(state), resources(state), state.chronicle_events.size()] == settled,
		"repeated cleanup after the original chain cannot duplicate titles, resources or final history")
	sim.free()


func test_direct_rebel_recognition_preserves_external_fu_claim() -> void:
	var data := rebellion_fixture("whole")
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var rebel: int = data.rebel
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	var external_war_started := state.relation_since(0, 2)
	var occupied := state.transfer_city_control(7, 2, 2,
		GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL, "regression_external_occupation_of_rebel_fu")
	check(bool(occupied.get("ok", false)), "external occupation of a rebel-state fu uses the real control transaction")
	var before := [draft_for(state), resources(state), state.rebellions.duplicate(true),
		state.chronicle_events.duplicate(true), state.nations[rebel].name, state.nations[rebel].name_kind]
	var rng_before := state.rng.state
	check(not state.recognize_regional_rebellion(rebel),
		"direct rebel recognition defers the whole state while another war owns a valid fu occupation")
	check([draft_for(state), resources(state), state.rebellions.duplicate(true),
		state.chronicle_events.duplicate(true), state.nations[rebel].name, state.nations[rebel].name_kind] == before,
		"deferred direct recognition preserves all titles, controllers, sponsor claims, stocks and political history")
	check(state.is_enemy(0, 2) and state.relation_since(0, 2) == external_war_started
		and state.is_enemy(0, rebel), "deferred recognition preserves both independent external war and the original uprising")
	check(state.rng.state == rng_before, "deferred direct recognition consumes no simulation random draws")
	sim.free()


func test_recognition_transfers_recaptured_fu_stock(direct: bool) -> void:
	var data := rebellion_fixture("seat_only")
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var rebel: int = data.rebel
	for city in state.cities: city.food_storage = 0
	state.cities[0].food_storage = 1000
	state.cities[6].food_storage = 2000
	state.cities[7].food_storage = 137
	state.refresh_derived()
	var before := resources(state)
	check(state.recognize_regional_rebellion(rebel) if direct else peace(sim, 0, rebel),
		"direct/coalition recognition commits the returning prefecture's real stock transfer")
	check(state.nations[0].granary_food == 1000 and state.nations[rebel].granary_food == 2137,
		"the returned fu's 137 grain follows the whole-state recipient rather than its former controller")
	check(resources(state) == before and owned_and_legal(state, [6, 7] as Array[int], rebel),
		"whole-state recognition preserves total stocks while assigning the correct legal owner")
	sim.free()


func run() -> void:
	for whole in [false, true]:
		test_enclave_plan(whole)
		for reverse in [false, true]:
			test_enclave_real_peace(whole, reverse)
	for control in ["fu_only", "seat_only", "whole"]:
		test_rebellion_direct(control)
		for reverse in [false, true]:
			test_rebellion_real_peace(control, reverse)
	for seat_captured in [false, true]:
		for reverse in [false, true]:
			test_direct_occupation_recognition(seat_captured, reverse)
	test_partial_state_cannot_start_rebellion()
	test_external_fu_claim_defers_whole_state(2)
	test_rebellion_parent_annexed_by_third_country()
	test_original_chengdu_transfer_chain()
	test_direct_rebel_recognition_preserves_external_fu_claim()
	test_recognition_transfers_recaptured_fu_stock(false)
	test_recognition_transfers_recaptured_fu_stock(true)
	for failure in failures:
		push_error("ADMINISTRATIVE_STATE_INTEGRITY_FAIL: " + failure)
	print("ADMINISTRATIVE_STATE_INTEGRITY checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
