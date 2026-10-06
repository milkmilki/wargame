extends SceneTree
## Shared dynastic ancestry must not transfer another country's political office.

const Audit = preload("res://tests/succession_audit.gd")
const FamilyFixture = preload("res://tests/ruler_family_fixture.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func fixture(foreign: bool = false) -> GameState:
	var state := GameState.new()
	state.world_seed = 23456
	var nation := Nation.new()
	nation.id = 0
	nation.alive = true
	nation.ruler_name = "张一"
	nation.capital_city_id = 0
	nation.manpower_pool = 100000
	nation.treasury_gold = 10000
	state.nations.append(nation)
	if foreign:
		var other := Nation.new()
		other.id = 1
		other.alive = true
		other.ruler_name = "李一"
		other.capital_city_id = 4
		other.manpower_pool = 100000
		other.treasury_gold = 10000
		state.nations.append(other)
	for id in range(8):
		var city := City.new()
		city.id = id
		city.name = "城%d" % id
		city.short_name = String.chr(0x4E00 + id)
		city.owner_nation = 1 if foreign and id >= 4 else 0
		city.coord = Vector2i(id, 0)
		city.map_position = Vector2(float(id) / 10.0, 0.5)
		city.is_capital = id == 0 or (foreign and id == 4)
		city.has_warehouse = city.is_capital
		city.food_storage = 1000000 if city.is_capital else 0
		city.gold_per_month = 10
		city.manpower_per_month = 10
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
	for id in range(7):
		var edge := Edge.new()
		edge.city_a = id
		edge.city_b = id + 1
		edge.max_manpower = Edge.STANDARD_MANPOWER
		edge.distance = 1
		state.edges.append(edge)
		state.edge_lookup[state.edge_key(id, id + 1)] = edge
		(state.adjacency[id] as Array[int]).append(id + 1)
		(state.adjacency[id + 1] as Array[int]).append(id)
	state.recognized_city_owners.resize(8)
	for city in state.cities:
		state.recognized_city_owners[city.id] = city.owner_nation
	state.rebuild_administrative_regions()
	# Explicit one-city states permit independent, valid land transactions.
	state.administrative_center_by_city = PackedInt32Array(range(8))
	state.administrative_center_city_ids = PackedInt32Array(range(8))
	state.administrative_region_ids = PackedInt32Array(range(8))
	state.administrative_region_count = 8
	state.administrative_region_revision += 1
	FamilyTree.ensure_all(state)
	for member_nation in state.nations:
		FamilyFixture.ensure_candidates(state, member_nation.id, 3)
	if foreign:
		state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	state.refresh_derived()
	return state

func enfeoff_next(state: GameState, nation_id: int) -> int:
	for center_id in state.administrative_center_city_ids:
		if state.cities[center_id].owner_nation != nation_id or state.cities[center_id].is_capital:
			continue
		var region := state.expand_enfeoff_to_administrative_states(nation_id, [center_id] as Array[int])
		if not region.is_empty():
			var subject := state.enfeoff(nation_id, region)
			if subject >= 0:
				return subject
	return -1

func add_army(state: GameState, nation_id: int, person_id: int) -> Army:
	var army := state.create_army(nation_id, state.nations[nation_id].capital_city_id, 1000)
	check(army != null, "fixture/create_army")
	if army != null:
		check(state.assign_main_army_to_independent_command(army) != null, "fixture/army_command")
		army.political_person_id = person_id
	return army

func test_shared_princes(dissolved: bool = false) -> void:
	var state := fixture()
	var subject := state.enfeoff(0, [4, 5, 6, 7] as Array[int])
	check(subject >= 0, "shared/first_real_enfeoff")
	if subject < 0:
		return
	var sovereign := state.nations[0]
	var vassal := state.nations[subject]
	FamilyFixture.ensure_candidates(state, subject)
	check(vassal.family_tree_id == sovereign.family_tree_id, "shared/same_tree")
	if dissolved:
		check(state._dissolve_suzerainty_system(0), "dissolved/real_dissolution")
		check(not state.is_vassal(subject), "dissolved/independent")
		check(vassal.family_tree_id == sovereign.family_tree_id, "dissolved/ancestry_retained")
	var expected := vassal.prince_person_ids[1]
	var protected_ids: Array[int] = []
	for person_id in sovereign.prince_person_ids:
		if PrincePolitics.eligible(PrincePolitics.person(state, 0, person_id)):
			protected_ids.append(person_id)
	var protected_members := {}
	for person_id in protected_ids:
		protected_members[person_id] = PrincePolitics.person(state, 0, person_id).duplicate(true)
	var armies: Array[Army] = []
	for index in range(5):
		var army := add_army(state, 0, protected_ids[index % protected_ids.size()])
		armies.append(army)
	var own_army := add_army(state, subject, expected)
	var own_crown := add_army(state, subject, vassal.crown_prince_person_id)
	check(Audit.inspect(state).errors.is_empty(), "shared/audit_before")
	var candidate := PrincePolitics.enfeoff_candidate(state, subject)
	check(candidate == expected, "shared/choose_own_non_crown_son got=%d expected=%d" % [candidate, expected])
	var new_subject := enfeoff_next(state, subject)
	check(new_subject >= 0, "shared/second_real_enfeoff")
	if new_subject < 0:
		return
	check(state.nations[new_subject].ruler_person_id == expected, "shared/new_ruler_correct")
	check(own_army.owner_nation == subject and own_army.political_person_id == -1, "shared/legitimate_own_patron_centralized")
	check(own_crown.owner_nation == subject and own_crown.political_person_id == vassal.crown_prince_person_id, "shared/own_crown_preserved")
	for person_id in protected_ids:
		check(PrincePolitics.person(state, 0, person_id) == protected_members[person_id], "shared/foreign_person_unchanged_%d" % person_id)
	for index in range(armies.size()):
		check(armies[index].owner_nation == 0 and armies[index].political_person_id == protected_ids[index % protected_ids.size()], "shared/foreign_army_unchanged_%d" % armies[index].id)
	var audit := Audit.inspect(state)
	check(audit.errors.is_empty(), "shared/audit_after " + str(audit.errors))

func test_foreign_ruler() -> void:
	var state := fixture()
	var subject := state.enfeoff(0, [4, 5, 6, 7] as Array[int])
	check(subject >= 0, "ruler/first_real_enfeoff")
	if subject < 0:
		return
	check(PrincePolitics.accede(state, 0), "ruler/real_accession")
	var ruler_id := state.nations[0].ruler_person_id
	var ruler_before := PrincePolitics.person(state, 0, ruler_id).duplicate(true)
	check(PrincePolitics.eligible(ruler_before), "ruler/eligible_unenfeoffed_monarch")
	var candidate := PrincePolitics.enfeoff_candidate(state, subject)
	check(candidate != ruler_id, "ruler/foreign_monarch_excluded")
	check(int(PrincePolitics.person(state, subject, candidate).get("title_payer_id", -1)) == subject, "ruler/only_domestic_relatives_eligible")
	check(int(PrincePolitics.person(state, subject, candidate).parent_id) == state.nations[subject].ruler_person_id, "ruler/foreign_brothers_excluded_choose_own_son")
	var new_subject := enfeoff_next(state, subject)
	check(new_subject >= 0, "ruler/second_real_enfeoff")
	if new_subject >= 0:
		check(state.nations[new_subject].ruler_person_id == candidate, "ruler/new_ruler_is_idle_brother")
	check(PrincePolitics.person(state, 0, ruler_id) == ruler_before, "ruler/foreign_monarch_unchanged")
	check(Audit.inspect(state).errors.is_empty(), "ruler/audit_after")

func test_conflict_candidates() -> void:
	var state := fixture()
	var subject := state.enfeoff(0, [4, 5, 6, 7] as Array[int])
	check(subject >= 0, "conflict/first_real_enfeoff")
	if subject < 0:
		return
	var parent := int(PrincePolitics.person(state, subject, state.nations[subject].ruler_person_id).parent_id)
	FamilyFixture.ensure_candidates(state, subject)
	# Isolate the conflict exclusion from ordinary current-prince exclusion:
	# participants belong to the shared dynasty but are outside either current generation.
	var challenger := PrincePolitics._create_person(state, 0, parent, -2)
	var crown := PrincePolitics._create_person(state, 0, parent, -1)
	var conflict := SuccessionConflict.new()
	conflict.nation_id = 0
	conflict.challenger_person_id = challenger
	conflict.crown_person_id = crown
	state.succession_conflicts[0] = conflict
	var challenger_before := PrincePolitics.person(state, 0, challenger).duplicate(true)
	var crown_before := PrincePolitics.person(state, 0, crown).duplicate(true)
	var expected := state.nations[subject].prince_person_ids[1]
	check(PrincePolitics.enfeoff_candidate(state, subject) == expected, "conflict/foreign_participants_excluded")
	var new_subject := enfeoff_next(state, subject)
	check(new_subject >= 0, "conflict/second_real_enfeoff")
	if new_subject >= 0:
		check(state.nations[new_subject].ruler_person_id == expected, "conflict/new_ruler_correct")
	check(PrincePolitics.person(state, 0, challenger) == challenger_before, "conflict/foreign_challenger_unchanged")
	check(PrincePolitics.person(state, 0, crown) == crown_before, "conflict/foreign_crown_unchanged")
	check(state.succession_conflicts.get(0) == conflict, "conflict/foreign_context_retained")
	check(Audit.inspect(state).errors.is_empty(), "conflict/audit_after")

func test_own_son_and_fallback() -> void:
	var state := fixture()
	var nation := state.nations[0]
	var expected := nation.prince_person_ids[1]
	var own_army := add_army(state, 0, expected)
	var crown_army := add_army(state, 0, nation.crown_prince_person_id)
	var subject := state.enfeoff(0, [4, 5, 6, 7] as Array[int])
	check(subject >= 0, "own/real_enfeoff")
	if subject >= 0:
		check(state.nations[subject].ruler_person_id == expected, "own/non_crown_son_reused")
	check(own_army.political_person_id == -1 and own_army.owner_nation == 0, "own/reused_son_army_centralized")
	check(crown_army.political_person_id == nation.crown_prince_person_id, "own/crown_army_preserved")
	check(Audit.inspect(state).errors.is_empty(), "own/audit_after")
	# No idle brothers or eligible younger sons remain: real fief creation
	# must refuse without fabricating a brother or consuming the crown prince.
	for id in nation.prince_person_ids:
		if id != nation.crown_prince_person_id and int(PrincePolitics.person(state, 0, id).get("enfeoffed_nation_id", -1)) < 0:
			PrincePolitics.person(state, 0, id).alive = false
	var crown_before := PrincePolitics.person(state, 0, nation.crown_prince_person_id).duplicate(true)
	var next_id := state.next_family_person_id
	var nation_count := state.nations.size()
	var owners: Array[int] = []
	for city in state.cities:
		owners.append(city.owner_nation)
	check(PrincePolitics.enfeoff_candidate(state, 0) == -1, "fallback/no_existing_person")
	var fallback_subject := enfeoff_next(state, 0)
	check(fallback_subject == -1, "fallback/real_enfeoff_refused")
	check(state.next_family_person_id == next_id, "fallback/no_fabricated_relative")
	check(state.nations.size() == nation_count, "fallback/no_fabricated_nation")
	for city in state.cities:
		check(city.owner_nation == owners[city.id] and state.recognized_owner_of(city.id) == owners[city.id], "fallback/territory_unchanged_%d" % city.id)
	check(PrincePolitics.person(state, 0, nation.crown_prince_person_id) == crown_before, "fallback/crown_unchanged")
	check(Audit.inspect(state).errors.is_empty(), "fallback/audit_after")

func test_own_conflict() -> void:
	var state := fixture()
	var nation := state.nations[0]
	var conflict := SuccessionConflict.new()
	conflict.nation_id = 0
	conflict.challenger_person_id = nation.prince_person_ids[1]
	conflict.crown_person_id = nation.crown_prince_person_id
	state.succession_conflicts[0] = conflict
	var expected := nation.prince_person_ids[2]
	var challenger_army := add_army(state, 0, conflict.challenger_person_id)
	var crown_army := add_army(state, 0, conflict.crown_person_id)
	check(PrincePolitics.enfeoff_candidate(state, 0) == expected, "own_conflict/busy_son_skipped")
	var subject := state.enfeoff(0, [4, 5, 6, 7] as Array[int])
	check(subject >= 0, "own_conflict/real_enfeoff")
	if subject >= 0:
		check(state.nations[subject].ruler_person_id == expected, "own_conflict/new_ruler_correct")
	check(challenger_army.political_person_id == conflict.challenger_person_id, "own_conflict/challenger_army_preserved")
	check(crown_army.political_person_id == conflict.crown_person_id, "own_conflict/crown_army_preserved")
	check(state.succession_conflicts.get(0) == conflict, "own_conflict/context_retained")
	check(Audit.inspect(state).errors.is_empty(), "own_conflict/audit_after")

func test_foreign_submission() -> void:
	var state := fixture(true)
	var nation := state.nations[1]
	var tree_id := nation.family_tree_id
	var ruler_id := nation.ruler_person_id
	var princes := nation.prince_person_ids.duplicate()
	var own_ruler := PrincePolitics.person(state, 1, ruler_id).duplicate(true)
	var sovereign_tree := FamilyTree.tree_for_nation(state, 0).duplicate(true)
	check(tree_id != state.nations[0].family_tree_id, "submission/separate_dynasties")
	check(state.accept_submission(0, 1), "submission/real_submission")
	check(nation.family_tree_id == tree_id and nation.ruler_person_id == ruler_id and nation.prince_person_ids == princes, "submission/foreign_lineage_retained")
	# Submission legitimately records a new royal title in the same person.
	var submitted_ruler := PrincePolitics.person(state, 1, ruler_id).duplicate(true)
	submitted_ruler.erase("titles")
	submitted_ruler.erase("current_title")
	own_ruler.erase("titles")
	own_ruler.erase("current_title")
	check(submitted_ruler == own_ruler, "submission/foreign_ruler_retained")
	var subject := state.enfeoff(1, [6, 7] as Array[int])
	check(subject >= 0, "submission/foreign_vassal_real_enfeoff")
	if subject >= 0:
		check(state.nations[subject].family_tree_id == tree_id and state.nations[subject].ruler_person_id == princes[1], "submission/new_relative_own_dynasty")
	check(FamilyTree.tree_for_nation(state, 0) == sovereign_tree, "submission/sovereign_dynasty_unchanged")
	check(Audit.inspect(state).errors.is_empty(), "submission/audit_after")

func run() -> void:
	test_shared_princes()
	test_shared_princes(true)
	test_foreign_ruler()
	test_conflict_candidates()
	test_own_son_and_fallback()
	test_own_conflict()
	test_foreign_submission()
	for failure in failures:
		push_error("ENFEOFF_SHARED_LINEAGE_FAIL: " + failure)
	print("ENFEOFF_SHARED_LINEAGE: checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
