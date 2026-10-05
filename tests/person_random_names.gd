extends SceneTree
## New names may collide; political and dynastic identity remains person-id based.

const Audit = preload("res://tests/succession_audit.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func lineage_fixture() -> GameState:
	var state := GameState.new()
	state.world_seed = 23456
	state.rng.seed = 23456
	var nation := Nation.new()
	nation.id = 0
	nation.alive = true
	nation.ruler_name = "张一"
	state.nations.append(nation)
	FamilyTree.ensure_all(state)
	return state

func valid_person_name(person_name: String) -> bool:
	if person_name.length() not in [2, 3]:
		return false
	for index in range(person_name.length()):
		var code := person_name.unicode_at(index)
		if code < 0x4E00 or code > 0x9FFF:
			return false
	return true

func test_large_generation() -> void:
	var state := lineage_fixture()
	var before := state.rng.state
	var parent := state.nations[0].ruler_person_id
	var surnames := {}
	var lengths := {}
	var invalid: Array[String] = []
	var sample_count := 3000 if OS.get_cmdline_user_args().has("--mass-names") else 256
	for order in range(sample_count):
		var id := PrincePolitics._create_person(state, 0, parent, order)
		var person_name := str(PrincePolitics.person(state, 0, id).name)
		if not valid_person_name(person_name) and invalid.size() < 5:
			invalid.append(person_name)
		surnames[person_name.left(1)] = true
		lengths[person_name.length()] = true
	check(invalid.is_empty(), "generation/%d_names_are_2_or_3_han_chars examples=" % sample_count + str(invalid))
	check(surnames.size() > 1, "generation/surnames_vary_in_same_family")
	check(lengths.has(2) and lengths.has(3), "generation/one_and_two_char_given_names")
	check(state.rng.state == before, "generation/simulation_rng_unchanged")
	print("PERSON_RANDOM_NAMES_SAMPLE: count=%d surnames=%d lengths=%s invalid_examples=%s" % [sample_count, surnames.size(), str(lengths.keys()), str(invalid)])
	var ruler_invalid: Array[String] = []
	for salt in range(3000):
		var person_name := RulerProfile.ruler_name_for(23456, 0, salt)
		if not valid_person_name(person_name) and ruler_invalid.size() < 5:
			ruler_invalid.append(person_name)
		check(person_name == RulerProfile.ruler_name_for(23456, 0, salt), "ruler/same_input_deterministic_%d" % salt)
	check(ruler_invalid.is_empty(), "ruler/3000_names_are_2_or_3_han_chars examples=" + str(ruler_invalid))
	check(state.rng.state == before, "ruler/simulation_rng_unchanged")

func test_same_input_same_name_distinct_ids() -> void:
	var state := lineage_fixture()
	var before := state.rng.state
	var parent := state.nations[0].ruler_person_id
	var first := PrincePolitics._create_person(state, 0, parent, 9999)
	var first_name := str(PrincePolitics.person(state, 0, first).name)
	for repeat in range(5):
		var other := PrincePolitics._create_person(state, 0, parent, 9999)
		check(first != other, "collision/distinct_id_%d" % repeat)
		check(str(PrincePolitics.person(state, 0, other).name) == first_name, "collision/same_input_name_not_rewritten_%d" % repeat)
	var independent := lineage_fixture()
	var repeated := PrincePolitics._create_person(independent, 0, independent.nations[0].ruler_person_id, 9999)
	check(str(PrincePolitics.person(independent, 0, repeated).name) == first_name, "collision/independent_state_deterministic")
	check(state.rng.state == before, "collision/simulation_rng_unchanged")

func test_initial_names_preserve_duplicates() -> void:
	var state := GameState.new()
	state.rng.seed = 23456
	for id in range(3):
		var nation := Nation.new()
		nation.id = id
		nation.alive = true
		nation.ruler_name = " 李安 " if id == 2 else "李安"
		state.nations.append(nation)
	var before := state.rng.state
	WorldNaming.assign_initial_names(state, 23456)
	for nation in state.nations:
		check(nation.ruler_name == "李安", "initial/duplicate_existing_name_preserved_%d" % nation.id)
	check(state.rng.state == before, "initial/simulation_rng_unchanged")
	WorldNaming.assign_initial_names(state, 23456)
	for nation in state.nations:
		check(nation.ruler_name == "李安", "initial/repeated_call_preserves_duplicate_%d" % nation.id)

func transaction_fixture() -> GameState:
	var state := lineage_fixture()
	state.nations[0].capital_city_id = 0
	state.nations[0].manpower_pool = 100000
	state.nations[0].treasury_gold = 10000
	for id in range(8):
		var city := City.new()
		city.id = id
		city.name = "城%d" % id
		city.short_name = String.chr(0x4E00 + id)
		city.owner_nation = 0
		city.coord = Vector2i(id, 0)
		city.map_position = Vector2(float(id) / 10.0, 0.5)
		city.is_capital = id == 0
		city.has_warehouse = id == 0
		city.food_storage = 1000000 if id == 0 else 0
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
	state.recognized_city_owners.fill(0)
	state.rebuild_administrative_regions()
	state.administrative_center_by_city = PackedInt32Array(range(8))
	state.administrative_center_city_ids = PackedInt32Array(range(8))
	state.administrative_region_ids = PackedInt32Array(range(8))
	state.administrative_region_count = 8
	state.administrative_region_revision += 1
	state.refresh_derived()
	return state

func add_army(state: GameState, person_id: int) -> Army:
	var army := state.create_army(0, 0, 1000)
	check(army != null, "transaction/create_army")
	if army != null:
		check(state.assign_main_army_to_independent_command(army) != null, "transaction/army_command")
		army.political_person_id = person_id
	return army

func test_duplicate_name_accession_and_enfeoff() -> void:
	var state := transaction_fixture()
	var nation := state.nations[0]
	var original_ids := nation.prince_person_ids.duplicate()
	for id in original_ids:
		PrincePolitics.person(state, 0, id).name = "李安"
	var crown := nation.crown_prince_person_id
	var brother: int = original_ids[1]
	var army := add_army(state, brother)
	check(PrincePolitics.accede(state, 0), "transaction/real_accession")
	check(nation.ruler_person_id == crown and nation.ruler_name == "李安", "transaction/crown_id_and_name_reused")
	check(army.political_person_id == -1, "transaction/old_generation_centralized")
	for id in nation.prince_person_ids:
		PrincePolitics.person(state, 0, id).name = "李安"
	var new_crown := nation.crown_prince_person_id
	var crown_before := PrincePolitics.person(state, 0, new_crown).duplicate(true)
	var ruler_before := PrincePolitics.person(state, 0, crown).duplicate(true)
	army.political_person_id = brother
	var crown_army := add_army(state, new_crown)
	check(PrincePolitics.enfeoff_candidate(state, 0) == brother, "transaction/duplicate_named_brother_selected_by_id")
	var subject := state.enfeoff(0, [4, 5, 6, 7] as Array[int])
	check(subject >= 0, "transaction/real_enfeoff")
	if subject >= 0:
		check(state.nations[subject].ruler_person_id == brother and state.nations[subject].ruler_name == "李安", "transaction/brother_id_and_name_reused")
		check(state.nations[subject].family_tree_id == nation.family_tree_id, "transaction/shared_lineage_preserved")
	check(army.political_person_id == -1 and army.owner_nation == 0, "transaction/selected_person_army_centralized")
	check(crown_army.political_person_id == new_crown and crown_army.owner_nation == 0, "transaction/same_name_other_id_army_untouched")
	check(PrincePolitics.person(state, 0, new_crown) == crown_before, "transaction/same_name_other_id_person_untouched")
	check(PrincePolitics.person(state, 0, crown) == ruler_before, "transaction/same_name_ruler_untouched")
	check(Audit.inspect(state).errors.is_empty(), "transaction/succession_audit_passes")

func run() -> void:
	test_large_generation()
	test_same_input_same_name_distinct_ids()
	test_initial_names_preserve_duplicates()
	test_duplicate_name_accession_and_enfeoff()
	for failure in failures:
		push_error("PERSON_RANDOM_NAMES_FAIL: " + failure)
	print("PERSON_RANDOM_NAMES: checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
