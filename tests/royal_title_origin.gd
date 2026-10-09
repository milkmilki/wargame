extends SceneTree
## State-based regression of heir identity and titles across real nation transactions.
const FamilyFixture = preload("res://tests/ruler_family_fixture.gd")

var checks := 0
var failures: Array[String] = []

func _init() -> void:
	_test_heir_identity_and_accession()
	_test_enfeoffment_and_return()
	_test_migrated_household_lifetime()
	_test_twice_annexed_archive_household()
	_test_refounded_domestic_grandchildren()
	_test_new_untitled_children_lifetime()
	_test_shared_tree_boundaries_and_new_founder()
	_test_failed_transactions_are_atomic()
	_test_native_source_validation()
	for failure in failures:
		push_error("ROYAL_TITLE_ORIGIN_FAIL: " + failure)
	print("ROYAL_TITLE_ORIGIN_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func fixture() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.world_seed = 73003
	var nation := Nation.new()
	nation.id = 0
	nation.alive = true
	nation.ruler_name = "张一"
	nation.capital_city_id = 0
	nation.manpower_pool = 100000
	nation.treasury_gold = 10000
	state.nations.append(nation)
	for id in range(20):
		var city := City.new()
		city.id = id
		city.name = "城%d" % id
		city.short_name = String.chr(0x4E00 + id)
		city.owner_nation = 0
		city.coord = Vector2i(id, 0)
		city.map_position = Vector2(float(id) / 20.0, 0.5)
		city.is_capital = id == 0
		city.has_warehouse = city.is_capital
		city.food_storage = 1000000 if city.is_capital else 0
		city.gold_per_month = 10
		city.manpower_per_month = 10
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		if id > 0:
			var parent := 1 if id in range(2, 11) else (11 if id in range(12, 16) else 0)
			var edge := Edge.new()
			edge.city_a = parent
			edge.city_b = id
			edge.max_manpower = Edge.STANDARD_MANPOWER
			edge.distance = 1
			state.edges.append(edge)
			state.edge_lookup[state.edge_key(parent, id)] = edge
			(state.adjacency[parent] as Array[int]).append(id)
			(state.adjacency[id] as Array[int]).append(parent)
	state.recognized_city_owners.resize(20)
	state.recognized_city_owners.fill(0)
	state.rebuild_administrative_regions()
	state.administrative_center_by_city = PackedInt32Array(range(20))
	state.administrative_center_city_ids = PackedInt32Array(range(20))
	state.administrative_region_ids = PackedInt32Array(range(20))
	state.administrative_region_count = 20
	state.administrative_region_revision += 1
	state.region_ids = PackedInt32Array()
	for id in range(20): state.region_ids.append(10 if id < 10 else 20)
	FamilyTree.ensure_all(state)
	FamilyFixture.ensure_candidates(state, 0, 3)
	state.refresh_derived()
	EmpireStatus.reconcile(state)
	return state

func history_count(members: Dictionary) -> int:
	var total := 0
	for member in members.values(): total += (member.get("title_history", []) as Array).size()
	return total

func check_ended_title(member: Dictionary, source: int, title: String, reason: String) -> void:
	var found := false
	for record in member.get("title_history", []):
		if int(record.get("origin_nation_id", -1)) == source and str(record.get("title", "")) == title and str(record.get("end_reason", "")) == reason:
			found = true
			check(int(record.get("rank", 0)) > 0, "ended title keeps its historical rank")
			check(not str(record.get("origin_nation_name", "")).is_empty(), "ended title keeps source nation name")
			check(int(record.get("end_day", -1)) >= int(record.get("start_day", 0)), "ended title has an ordered lifetime")
	check(found, "historical title %s ends for %s, source=%d" % [title, reason, source])

func _test_heir_identity_and_accession() -> void:
	var state := fixture()
	var nation := state.nations[0]
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var heir := nation.crown_prince_person_id
	var sons := nation.prince_person_ids.duplicate()
	for id in sons:
		check(RoyalTitles.effective_rank(state, members[id]) == 3, "every domestic Taizu son, including heir, holds prince rank")
		check(int(members[id].get("title_origin_nation_id", -1)) == 0 and int(members[id].get("title_payer_id", -1)) == 0, "active grant source and affiliation agree")
		check(bool(members[id].get("children_initialized", false)), "heir and siblings both initialize their family exactly once")
	check(int(RoyalTitles.report(state, 0).counts[3]) == sons.size(), "stipend census counts heir alongside brothers")
	var prior := members.duplicate(true)
	var history_before := history_count(members)
	var next_id := state.next_family_person_id
	var service = load("res://scripts/core/prince_politics.gd")
	check(service.has_method("set_heir"), "political heir has a unified identity updater")
	if service.has_method("set_heir"):
		service.call("set_heir", state, 0, sons[1])
		RoyalTitles.reconcile(state)
		for id in sons:
			check(members[id].get("title_rank", 0) == prior[id].get("title_rank", 0) and members[id].get("current_title", "") == prior[id].get("current_title", ""), "appointment and deposition preserve existing title")
			check(members[id].get("child_ids", []) == prior[id].get("child_ids", []), "identity update keeps original birth result")
		check(bool(members[sons[1]].get("crown", false)) and not bool(members[heir].get("crown", false)), "identity updater changes only the selected heir flag")
		service.call("set_heir", state, 0, heir)
	for repeat in range(3): RoyalTitles.reconcile(state)
	check(history_count(members) == history_before and state.next_family_person_id == next_id, "repeated identity and title reconciliation adds no history or children")
	var heir_title := str(members[heir].get("current_title", ""))
	var heir_children := RoyalTitles.children(members, heir)
	check(PrincePolitics.accede(state, 0), "real titled heir accession succeeds")
	check(nation.ruler_person_id == heir and int(members[heir].get("title_rank", 0)) == 0, "incoming monarch loses his original virtual title")
	check_ended_title(members[heir], 0, heir_title, "accession")
	for child in heir_children:
		check(bool(members[child].get("alive", false)), "incoming monarch's existing children survive cohort settlement")
		check(RoyalTitles.effective_rank(state, members[child]) == 2, "second emperor's children use uniform commandery grants")

func _test_enfeoffment_and_return() -> void:
	var state := fixture()
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var candidate := PrincePolitics.enfeoff_candidate(state, 0)
	var title := str(members[candidate].get("current_title", ""))
	var original_children := RoyalTitles.children(members, candidate)
	var princes_before := int(RoyalTitles.report(state, 0).counts[3])
	var original_history := history_count(members)
	var subject := state.enfeoff(0, [2] as Array[int])
	check(subject >= 0 and state.nations[subject].ruler_person_id == candidate, "actual new-country enfeoffment reuses a titled son")
	if subject < 0: return
	check(not state.nations[subject].royal_titles_initialized and state.nations[subject].state_level == 0, "new country does not inherit mother country's institution")
	check(RoyalTitles.children(members, candidate) == original_children, "becoming a real ruler preserves existing children and zero-child results")
	check(int(RoyalTitles.report(state, 0).counts[3]) == princes_before - 1, "mother country does not replace emigrant's ended princely grant")
	check_ended_title(members[candidate], 0, title, "enfeoffment")
	var migrated: Array[int] = []
	for id in members:
		if int(members[id].get("title_payer_id", -1)) == subject and bool(members[id].get("alive", true)):
			migrated.append(int(id))
			check(int(members[id].get("title_rank", 0)) == 0 and int(members[id].get("title_origin_nation_id", -1)) == -1, "migrated household loses foreign virtual grants")
	check(RoyalTitles.report(state, subject).basis_points == 0, "non-empire new country pays zero royal stipend")
	check(history_count(members) >= original_history, "termination preserves title records")
	var history_after := history_count(members)
	for repeat in range(3): EmpireStatus.reconcile(state)
	check(history_count(members) == history_after, "coordinator does not reactivate or duplicate ended foreign titles")
	check(state.revoke_vassal(subject), "real revocation rejoins household")
	for id in migrated:
		check(int(members[id].get("title_payer_id", -1)) == 0, "return updates affiliation to receiving country")
		check(int(members[id].get("title_rank", 0)) == 0 and RoyalTitles.effective_rank(state, members[id]) == 0, "return does not restore former foreign title")
	check_ended_title(members[candidate], 0, title, "enfeoffment")
	check(int(RoyalTitles.report(state, 0).counts[3]) == princes_before - 1, "return does not restore a princely stipend in mother country's census")

func _test_shared_tree_boundaries_and_new_founder() -> void:
	var state := fixture()
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var a_land: Array[int] = []
	a_land.assign(range(1, 11))
	var d_land: Array[int] = []
	d_land.assign(range(11, 16))
	var a := state.enfeoff(0, a_land)
	var d := state.enfeoff(0, d_land)
	check(a >= 0 and d >= 0, "two real sibling countries share one genealogy")
	if a < 0 or d < 0: return
	FamilyFixture.ensure_candidates(state, a, 3)
	var c := state.enfeoff(a, [2] as Array[int])
	check(c >= 0, "non-empire country creates real sub-fief")
	if c < 0: return
	FamilyFixture.ensure_candidates(state, c, 2)
	var c_king := state.nations[c].ruler_person_id
	var c_children := RoyalTitles.children(members, c_king)
	var a_members := {}
	for id in members:
		if int(members[id].get("title_payer_id", -1)) == a: a_members[id] = members[id].duplicate(true)
	state.set_diplomatic_relation(d, c, GameState.DiplomaticRelation.WAR)
	check(state.annex_nation(d, c), "real same-genealogy foreign-country annexation")
	for id in [c_king] + c_children:
		check(int(members[id].get("title_payer_id", -1)) == d and int(members[id].get("title_rank", 0)) == 0, "absorbed household affiliates to absorber without restoring title")
	for id in a_members:
		check(members[id] == a_members[id], "annexation does not change other country's household %d" % id)
	check(PrincePolitics.enfeoff_candidate(state, a) != c_king, "foreign household cannot become original country's enfeoffment candidate")
	check(not state.nations[d].royal_titles_initialized and RoyalTitles.report(state, d).basis_points == 0, "same-tree annex does not transfer title institution")
	FamilyFixture.ensure_candidates(state, d, 2)
	state.set_diplomatic_relation(0, d, GameState.DiplomaticRelation.WAR)
	check(state.annex_nation(d, 0), "real defending vassal counter-conquest removes former overlord")
	check(state.nations[d].state_level == 1 and state.nations[d].empire_founder_person_id == state.nations[d].ruler_person_id, "independent new empire recognizes its own founder")
	for id in state.nations[d].prince_person_ids:
		check(RoyalTitles.effective_rank(state, members[id]) == 3 and int(members[id].get("title_origin_nation_id", -1)) == d, "new founder grants own sons domestic titles, including heir")
		var domestic_history := false
		for record in members[id].get("title_history", []):
			if int(record.get("origin_nation_id", -1)) == d and int(record.get("rank", 0)) == 3 and int(record.get("end_day", -2)) == -1:
				domestic_history = true
		check(domestic_history, "newly valid grant has an open history entry from actual new empire")
	for id in a_members:
		check(members[id] == a_members[id], "new empire promotion does not regrant another nation's household %d" % id)
	check(NativeSnapshotBuilder.succession_validation_error(NativeSnapshotBuilder.build(state)).is_empty(), "native retains ended historical sources even after source nation is extinct")

func _test_migrated_household_lifetime() -> void:
	var state := fixture()
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var candidate := PrincePolitics.enfeoff_candidate(state, 0)
	# A known waiting child of this family, alongside naturally generated siblings.
	var waiting := PrincePolitics._create_person(state, 0, candidate, RoyalTitles.children(members, candidate).size())
	RoyalTitles._grant(state, members[waiting], 2, 0, candidate, false)
	var subject := state.enfeoff(0, [2] as Array[int])
	check(subject >= 0, "migrated household starts with an existing waiting generation")
	if subject < 0: return
	FamilyFixture.ensure_candidates(state, subject, 3)
	var incoming := state.nations[subject].crown_prince_person_id
	check(incoming != waiting, "known waiting sibling is not selected as incoming ruler")
	check(PrincePolitics.accede(state, subject), "untitled non-empire heir remains politically eligible")
	check(bool(members[waiting].get("alive", false)) and bool(members[waiting].get("title_adult", false)), "migrated untitled waiting family advances to adult cohort")
	var birth_result := RoyalTitles.children(members, waiting)
	RoyalTitles.reconcile(state)
	check(RoyalTitles.children(members, waiting) == birth_result and birth_result.is_empty(), "foreign ended rank does not trigger adult reproduction")
	FamilyFixture.ensure_candidates(state, subject, 2)
	check(PrincePolitics.accede(state, subject), "second ordinary-country real succession succeeds")
	check(not bool(members[waiting].get("alive", true)), "no-institution migrated adult dies with next real ruler")
	check(str(members[waiting].get("death_title", "")) == "无爵" and FamilyTree.display_title(members[waiting], waiting, -1, state) == "无爵", "death freezes untitled status rather than restoring pre-migration title")
	check(not state.nations[subject].royal_titles_initialized and RoyalTitles.report(state, subject).basis_points == 0, "life advancement never reenables old institution or expense")

func _test_native_source_validation() -> void:
	var state := fixture()
	var snapshot := NativeSnapshotBuilder.build(state)
	check(int(snapshot.get("schema_version", 0)) == NativeSnapshotBuilder.SCHEMA_VERSION, "native schema retains title source and history in the current version")
	check(NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(), "native accepts active title on political heir")
	var edited := false
	for tree in snapshot.family_trees:
		for member in tree.members:
			if int(member.get("title_rank", 0)) > 0:
				member["title_origin_nation_id"] = 99
				edited = true
				break
		if edited: break
	check(edited, "source validation fixture includes a real effective title")
	check(not NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(), "native rejects active foreign source even when payer is valid")

func _test_twice_annexed_archive_household() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(73003)
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	FamilyFixture.ensure_candidates(state, 0, 3)
	FamilyFixture.ensure_candidates(state, 1, 2)
	FamilyFixture.ensure_candidates(state, 2, 2)
	state.region_ids.fill(-1)
	var land := state.land_cities_of(0)
	for index in range(land.size()): state.region_ids[land[index].id] = 10 if index < land.size() / 2 else 20
	EmpireStatus.reconcile(state)
	var archive_tree := state.nations[0].family_tree_id
	var members: Dictionary = state.family_trees[archive_tree].members
	var old_prince := state.nations[0].prince_person_ids[1]
	var waiting := PrincePolitics._create_person(state, 0, old_prince, RoyalTitles.children(members, old_prince).size())
	RoyalTitles._grant(state, members[waiting], 2, 0, old_prince, false)
	var original_title := str(members[waiting].current_title)
	state.set_diplomatic_relation(1, 0, GameState.DiplomaticRelation.WAR)
	check(state.annex_nation(1, 0), "first actual foreign annex retains defeated genealogy as archive")
	check(int(members[waiting].get("title_payer_id", -1)) == 1, "first absorber assumes archived household affiliation")
	state.set_diplomatic_relation(2, 1, GameState.DiplomaticRelation.WAR)
	check(state.annex_nation(2, 1), "second actual foreign annex absorbs holder of archived household")
	check(int(members[waiting].get("title_payer_id", -1)) == 2, "second absorber also migrates already archived foreign genealogy")
	check(state.family_trees.has(archive_tree) and state.nations[0].family_tree_id == archive_tree, "repeated annex keeps original blood tree accessible")
	check(RoyalTitles.effective_rank(state, members[waiting]) == 0 and int(members[waiting].get("title_origin_nation_id", -1)) == -1, "repeated annex never restores archived old title")
	check_ended_title(members[waiting], 0, original_title, "annexation")
	FamilyFixture.ensure_candidates(state, 2, 2)
	check(PrincePolitics.accede(state, 2), "new archive owner completes first real accession")
	check(bool(members[waiting].get("alive", false)) and bool(members[waiting].get("title_adult", false)), "archived waiting family advances at actual owner's first accession")
	FamilyFixture.ensure_candidates(state, 2, 2)
	check(PrincePolitics.accede(state, 2), "new archive owner completes second real accession")
	check(not bool(members[waiting].get("alive", true)), "archived untitled adult dies at actual owner's next accession")
	check(NativeSnapshotBuilder.succession_validation_error(NativeSnapshotBuilder.build(state)).is_empty(), "twice-annexed archive preserves native political and historical invariants")

func _test_refounded_domestic_grandchildren() -> void:
	var state := fixture()
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var candidate := PrincePolitics.enfeoff_candidate(state, 0)
	var children := RoyalTitles.children(members, candidate)
	while children.size() < 2:
		var id := PrincePolitics._create_person(state, 0, candidate, children.size())
		RoyalTitles._grant(state, members[id], 2, 0, candidate, false)
		children.append(id)
	var son := children[0]
	var childless_son := children[1]
	# Explicit initialized household with known grandchildren and a sibling's zero result.
	RoyalTitles._grant(state, members[son], 2, 0, candidate, true)
	var grandchildren: Array[int] = []
	for order in range(2):
		var id := PrincePolitics._create_person(state, 0, son, order)
		RoyalTitles._grant(state, members[id], 1, 0, candidate, false)
		grandchildren.append(id)
	RoyalTitles.set_member(state, members[son], "children_initialized", true)
	RoyalTitles.set_member(state, members[son], "title_children_generated", true)
	check(RoyalTitles.children(members, childless_son).is_empty(), "fixture's second son has no existing children")
	RoyalTitles.set_member(state, members[childless_son], "children_initialized", true)
	RoyalTitles.set_member(state, members[childless_son], "title_children_generated", true)
	var subject := state.enfeoff(0, [2] as Array[int])
	check(subject >= 0, "initialized grandchild household migrates through real enfeoffment")
	if subject < 0: return
	for id in [son, childless_son] + grandchildren:
		check(int(members[id].get("title_rank", 0)) == 0 and int(members[id].get("title_origin_nation_id", -1)) == -1, "all migrating generations lose foreign source grants")
	state.set_diplomatic_relation(0, subject, GameState.DiplomaticRelation.WAR)
	check(state.annex_nation(subject, 0), "real vassal counter-conquest establishes a new independent empire")
	check(state.nations[subject].empire_founder_person_id == candidate, "new nation's actual ruler becomes its own Taizu")
	for id in state.nations[subject].prince_person_ids:
		check(RoyalTitles.effective_rank(state, members[id]) == 3 and int(members[id].get("title_origin_nation_id", -1)) == subject, "new founder's domestic sons all receive domestic prince grants")
	for id in grandchildren:
		check(RoyalTitles.effective_rank(state, members[id]) == 2 and int(members[id].get("title_origin_nation_id", -1)) == subject, "already initialized domestic grandchildren receive rank two under new source")
		check(int(members[id].get("title_branch_id", -1)) == son, "new grandchild grant belongs to new father's branch, not ended foreign branch")
	check(RoyalTitles.children(members, son) == grandchildren, "new-source grant reuses existing grandchildren without regeneration")
	check(RoyalTitles.children(members, childless_son).is_empty() and bool(members[childless_son].get("children_initialized", false)), "new-source grant preserves initialized zero-child result")
	var inherited_title := str(members[son].get("current_title", ""))
	PrincePolitics.set_heir(state, subject, childless_son)
	check(PrincePolitics.accede(state, subject), "real accession by childless brother settles new domestic title families")
	check(not bool(members[son].get("alive", true)), "new domestic title holder dies with old ruler")
	check(RoyalTitles.effective_rank(state, members[grandchildren[0]]) == 3 and int(members[grandchildren[0]].get("title_origin_nation_id", -1)) == subject and str(members[grandchildren[0]].get("current_title", "")) == inherited_title, "eldest grandchild inherits exact new-source prince title through real accession")
	check(RoyalTitles.children(members, childless_son).is_empty(), "childless titled family remains childless after becoming actual emperor")

func _test_new_untitled_children_lifetime() -> void:
	var state := fixture()
	var subject := state.enfeoff(0, [2] as Array[int])
	check(subject >= 0, "ordinary landed country created for new-child cohort regression")
	if subject < 0: return
	FamilyFixture.ensure_candidates(state, subject, 2)
	check(PrincePolitics.accede(state, subject), "ordinary country's first actual accession creates a new ruler generation")
	FamilyFixture.ensure_candidates(state, subject, 2)
	var members: Dictionary = FamilyTree.tree_for_nation(state, subject).members
	var new_ruler := state.nations[subject].ruler_person_id
	var waiting := state.nations[subject].prince_person_ids[1]
	check(int(members[waiting].get("parent_id", -1)) == new_ruler and waiting != state.nations[subject].crown_prince_person_id, "fixture chooses new ruler's untitled non-heir son")
	check(int(members[waiting].get("title_rank", 0)) == 0 and int(members[waiting].get("title_payer_id", -1)) == subject, "new ordinary-country child has affiliation without a title")
	var existing_children := RoyalTitles.children(members, new_ruler)
	PrincePolitics.ensure_generation(state, subject)
	PrincePolitics.ensure_generation(state, subject)
	check(RoyalTitles.children(members, new_ruler) == existing_children, "repeated political initialization reuses the actual ruler's birth result")
	check(PrincePolitics.accede(state, subject), "ordinary country completes next actual accession")
	check(bool(members[waiting].get("alive", false)) and bool(members[waiting].get("title_adult", false)), "new untitled non-heir child survives father's death and advances to adult")
	var next_person := state.next_family_person_id
	RoyalTitles.reconcile(state)
	check(RoyalTitles.children(members, waiting).is_empty() and state.next_family_person_id == next_person, "new untitled adult does not reproduce extra collateral children")
	FamilyFixture.ensure_candidates(state, subject, 2)
	check(PrincePolitics.accede(state, subject), "ordinary country completes third actual accession")
	check(not bool(members[waiting].get("alive", true)), "new untitled adult dies at next ruler change instead of living permanently")
	check(not state.nations[subject].royal_titles_initialized and RoyalTitles.report(state, subject).basis_points == 0, "new-child lifecycle operates without institution or stipend")

func _test_failed_transactions_are_atomic() -> void:
	var state := fixture()
	var before := state.family_trees.duplicate(true)
	var gold := state.nations[0].treasury_gold
	check(state.enfeoff(0, [0] as Array[int]) < 0, "capital enfeoffment is rejected")
	check(not state.annex_nations(0, [0]), "self-annexation is rejected")
	check(state.family_trees == before and state.nations[0].treasury_gold == gold, "failed real transactions leave titles, history, genealogy and resources unchanged")
