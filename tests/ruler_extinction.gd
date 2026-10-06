extends SceneTree
## Extinction selects existing relatives without generating people during reads.

var failures: Array[String] = []
var checks := 0
var politics: RefCounted = PrincePolitics.new()

func _init() -> void:
	_test_zero_births_are_final()
	_test_birth_distribution()
	_test_former_childless_title_holder()
	_test_crown_and_dead_crown_replacement()
	_test_direct_generation_and_senior_branch()
	_test_collateral_distance_rank_birth_and_id()
	_test_commoner_and_foreign_exclusion()
	_test_country_royal_without_titles()
	_test_remote_read_and_ancestral_chain()
	_test_extinct_title_branch_disappears()
	_test_crown_change_keeps_previously_granted_title()
	for failure in failures:
		push_error("RULER_EXTINCTION_FAIL: " + failure)
	print("RULER_EXTINCTION_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func fixture(empire: bool = true, seed_value: int = 91001) -> GameState:
	var state := GameState.new()
	state.world_seed = seed_value
	var nation := Nation.new()
	nation.id = 0
	nation.alive = true
	nation.name = "测试国"
	nation.ruler_name = "君主一"
	nation.capital_city_id = 0
	nation.family_tree_id = 0
	nation.ruler_person_id = 1
	nation.crown_prince_person_id = -1
	nation.state_level = EmpireStatus.EMPIRE if empire else EmpireStatus.COUNTRY
	nation.royal_titles_initialized = empire
	nation.empire_founder_person_id = 1 if empire else -1
	nation.empire_recognized_day = 0 if empire else -1
	state.nations.append(nation)
	var city := City.new()
	city.id = 0
	city.name = "测试城"
	city.owner_nation = 0
	city.is_capital = true
	state.cities.append(city)
	state.recognized_city_owners = PackedInt32Array([0])
	state.family_trees[0] = {"id": 0, "root_person_id": 0, "members": {
		0: member(0, -1, 0, false), 1: member(1, 0, 0, true)}}
	state.family_trees[0].members[0].child_ids = [1]
	state.family_trees[0].members[1].office_nation_id = 0
	state.family_trees[0].members[1].current_title = "测试帝" if empire else "测试君"
	state.next_family_tree_id = 1
	state.next_family_person_id = 2
	state.family_revision = 1
	return state

func member(id: int, parent: int, order: int, alive: bool) -> Dictionary:
	return {"id": id, "name": "人物%d" % id, "parent_id": parent, "child_ids": [],
		"birth_order": order, "alive": alive, "archetype": RulerProfile.BALANCED,
		"traits": [], "titles": [], "nation_ids": [], "enfeoffed_nation_id": -1,
		"children_initialized": true, "title_children_generated": true}

func add_person(state: GameState, parent: int, rank: int = 1, order: int = 0, alive: bool = true, payer: int = 0) -> int:
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var id := state.next_family_person_id
	state.next_family_person_id += 1
	var item := member(id, parent, order, alive)
	if state.nations[0].royal_titles_initialized:
		item.merge({"title_managed": true, "title_rank": rank, "title_payer_id": payer, "title_origin_nation_id": payer,
			"title_branch_id": id, "title_adult": true, "title_disabled": false,
			"current_title": RoyalTitles.NAMES[rank]})
	members[id] = item
	if members.has(parent): members[parent].child_ids.append(id)
	state.family_revision += 1
	return id

func selector(state: GameState) -> Dictionary:
	if not politics.has_method("select_successor"):
		check(false, "selector/API select_successor missing")
		return {}
	var before := state.family_trees.duplicate(true)
	var next_person := state.next_family_person_id
	var revision := state.family_revision
	var crown := state.nations[0].crown_prince_person_id
	var candidates := state.nations[0].prince_person_ids.duplicate()
	var result: Variant = politics.call("select_successor", state, 0)
	check(result is Dictionary, "selector returns a dictionary")
	check(state.family_trees == before and state.next_family_person_id == next_person and state.family_revision == revision, "selector cannot mutate or generate genealogy")
	check(state.nations[0].crown_prince_person_id == crown and state.nations[0].prince_person_ids == candidates, "selector cannot appoint crown or change candidates")
	return result if result is Dictionary else {}

func expect_choice(state: GameState, expected: int, source: String, label: String) -> bool:
	var result := selector(state)
	if result.is_empty(): return false
	check(int(result.get("person_id", -2)) == expected, label + "/person got=" + str(result))
	check(str(result.get("source", "")) == source, label + "/source")
	check(int(result.get("annex_nation_id", -2)) == -1, label + "/no annex for own relative")
	return int(result.get("person_id", -2)) == expected

func _test_zero_births_are_final() -> void:
	var state := fixture()
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var count := state.next_family_person_id
	PrincePolitics.ensure_generation(state, 0)
	PrincePolitics.ensure_generation(state, 0)
	check(state.next_family_person_id == count and RoyalTitles.children(members, 1).is_empty(), "zero/initialized childless ruler never rolls again")
	check(state.nations[0].prince_person_ids.is_empty() and state.nations[0].crown_prince_person_id == -1, "zero/no phantom crown for a childless ruler")

func _test_birth_distribution() -> void:
	var saw_zero := false
	for seed_value in range(91000, 91032):
		var state := fixture(false, seed_value)
		var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
		members[1]["children_initialized"] = false
		members[1].erase("title_children_generated")
		PrincePolitics.ensure_generation(state, 0)
		var child_count := RoyalTitles.children(members, 1).size()
		check(child_count in [0, 2, 3, 4, 5], "births/allowed child count")
		check(bool(members[1].get("children_initialized", false)), "births/actual ruler records one completed attempt")
		var next_person := state.next_family_person_id
		PrincePolitics.ensure_generation(state, 0)
		check(state.next_family_person_id == next_person, "births/repeated ensure creates nobody")
		if child_count == 0:
			saw_zero = true
			check(state.nations[0].crown_prince_person_id == -1, "births/zero result has no crown")
	check(saw_zero, "births/deterministic sample permits zero for actual rulers")

func _test_former_childless_title_holder() -> void:
	var state := fixture()
	var heir := add_person(state, 0, 2)
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	if not expect_choice(state, heir, "collateral", "former zero-family titled brother enters through collateral succession"): return
	var next_person := state.next_family_person_id
	check(PrincePolitics.accede(state, 0), "former zero-family titled person can accede")
	check(state.nations[0].ruler_person_id == heir, "former zero-family accession preserves exact person")
	check(state.next_family_person_id == next_person and RoyalTitles.children(members, heir).is_empty(), "former zero-family ruler must not receive fabricated children")
	check(state.nations[0].crown_prince_person_id == -1, "former zero-family ruler remains without crown")

func _test_extinct_title_branch_disappears() -> void:
	var state := fixture()
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var crown := add_person(state, 1, 0)
	members[crown]["crown"] = true
	members[crown]["title_adult"] = false
	state.nations[0].prince_person_ids.append(crown)
	state.nations[0].crown_prince_person_id = crown
	var extinct_head := add_person(state, 0, 3, 1)
	var dead_child := add_person(state, extinct_head, 2, 0, false)
	members[dead_child]["title_branch_id"] = extinct_head
	var other_head := add_person(state, 0, 1, 2)
	var other_child := add_person(state, other_head, 0)
	members[other_child]["title_branch_id"] = other_head
	members[other_child]["title_adult"] = false
	var next_person := state.next_family_person_id
	check(PrincePolitics.accede(state, 0), "title extinction/real paying ruler succession")
	check(not members[extinct_head].alive and bool(members[extinct_head].get("title_settled", false)), "title extinction/last living title holder dies and settles")
	check(int(members[other_child].title_rank) == 1 and int(members[other_child].title_branch_id) == other_head, "title extinction/another blood branch inherits only its own original title")
	var remaining := []
	for id in members:
		if int(members[id].get("title_branch_id", -1)) == extinct_head and RoyalTitles.effective_rank(state, members[id]) > 0:
			remaining.append(id)
	check(remaining.is_empty(), "title extinction/no direct or same-branch collateral means the old title disappears")
	check(RoyalTitles.report(state, 0).counts[3] == 0, "title extinction/no highest-title stipend remains")
	check(state.next_family_person_id == next_person, "title extinction/cannot fabricate a title heir for an extinct branch")
	check(members.has(extinct_head) and members.has(dead_child) and int(members[dead_child].parent_id) == extinct_head, "title extinction/pedigree survives after the title disappears")

func _test_crown_change_keeps_previously_granted_title() -> void:
	var state := fixture()
	# R already ruled a fief before entering the imperial throne. A former
	# non-crown son retains the same R/J grant cache when he becomes crown.
	state.nations[0].empire_founder_person_id = 0
	var old_crown := add_person(state, 1, 2, 0)
	var challenger := add_person(state, 1, 2, 1)
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	members[old_crown].merge({"crown": true, "title_adult": true,
		"title_grant_ruler_id": 1, "title_grant_rank": 2}, true)
	state.nations[0].prince_person_ids.assign([old_crown, challenger])
	state.nations[0].crown_prince_person_id = old_crown
	var conflict := SuccessionConflict.new()
	conflict.nation_id = 0
	conflict.crown_person_id = old_crown
	conflict.challenger_person_id = challenger
	conflict.capital_city_id = 0
	conflict.pending_outcome = SuccessionConflict.Outcome.CROWN_CHANGED
	state.succession_conflicts[0] = conflict
	check(SuccessionRules.finish(state, conflict), "crown restoration/real CROWN_CHANGED conflict settlement")
	check(state.nations[0].crown_prince_person_id == challenger and bool(members[challenger].get("crown", false)), "crown restoration/challenger becomes actual crown")
	check(not bool(members[old_crown].get("crown", false)), "crown restoration/previous crown flag cleared")
	check(int(members[old_crown].title_rank) == 2 and RoyalTitles.effective_rank(state, members[old_crown]) == 2, "deposed heir keeps original commandery title")
	check(bool(members[old_crown].title_adult), "deposed heir keeps adult family lifecycle")
	check(int(members[challenger].title_rank) == 2 and RoyalTitles.effective_rank(state, members[challenger]) == 2, "new heir retains existing virtual stipend")

func _test_crown_and_dead_crown_replacement() -> void:
	var state := fixture()
	var older := add_person(state, 1, 3, 0)
	var crown := add_person(state, 1, 3, 1)
	state.nations[0].prince_person_ids.assign([older, crown])
	state.nations[0].crown_prince_person_id = crown
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	members[crown]["crown"] = true
	members[crown]["title_rank"] = 0
	expect_choice(state, crown, "crown", "live crown overrides older direct son")
	members[crown].alive = false
	add_person(state, crown, 2, 0)
	if not expect_choice(state, older, "direct", "dead crown chooses nearest living direct generation"): return
	var founder := state.nations[0].empire_founder_person_id
	check(PrincePolitics.accede(state, 0), "dead crown does not block actual accession")
	check(state.nations[0].ruler_person_id == older and members[older].alive, "chosen direct person survives cohort advance and becomes ruler")
	check(state.nations[0].empire_founder_person_id == founder, "direct accession preserves original Taizu")

func _test_direct_generation_and_senior_branch() -> void:
	var state := fixture()
	var elder := add_person(state, 1, 3, 0, false)
	var younger := add_person(state, 1, 3, 1, false)
	# Creation order deliberately opposes the senior blood branch.
	var younger_grandson := add_person(state, younger, 2, 0)
	var elder_grandson := add_person(state, elder, 1, 4)
	expect_choice(state, elder_grandson, "direct", "direct/senior parent branch precedes grandchild personal birth order and rank")
	var great_grandson := add_person(state, elder_grandson, 3, 0)
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	members[elder_grandson].alive = false
	expect_choice(state, younger_grandson, "direct", "direct/nearest generation precedes elder branch great-grandson")
	check(great_grandson != younger_grandson, "direct/fixture distinct generations")
	var sibling_a := add_person(state, younger, 2, 0)
	expect_choice(state, younger_grandson, "direct", "direct/equal branch birth order uses lower person ID")
	check(sibling_a > younger_grandson, "direct/fixture ID tie is meaningful")

func _test_collateral_distance_rank_birth_and_id() -> void:
	var state := fixture()
	var near_duke := add_person(state, 0, 1, 5)
	var uncle := add_person(state, 0, 0, 0, false)
	add_person(state, uncle, 3, 0)
	expect_choice(state, near_duke, "collateral", "collateral/distance precedes higher rank")
	var near_prince := add_person(state, 0, 3, 9)
	expect_choice(state, near_prince, "collateral", "collateral/equal distance favors higher rank over birth order")
	var elder_prince := add_person(state, 0, 3, 2)
	expect_choice(state, elder_prince, "collateral", "collateral/equal distance and rank favors older birth order")
	add_person(state, 0, 3, 2)
	expect_choice(state, elder_prince, "collateral", "collateral/final tie uses lower person ID")

func _test_commoner_and_foreign_exclusion() -> void:
	var state := fixture()
	add_person(state, 1, 0, 0)
	var foreign := Nation.new()
	foreign.id = 1
	foreign.alive = true
	foreign.family_tree_id = 0
	state.nations.append(foreign)
	add_person(state, 0, 3, 0, true, 1)
	var disabled := add_person(state, 0, 3, 1)
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	members[disabled]["political_disqualified"] = true
	var allowed := add_person(state, 0, 1, 9)
	expect_choice(state, allowed, "collateral", "eligibility/titled domestic collateral excludes commoner direct son and foreign virtual prince")
	members[allowed].alive = false
	expect_choice(state, -1, "remote", "eligibility/no eligible titled relative requires remote fallback")

func _test_country_royal_without_titles() -> void:
	var state := fixture(false)
	var child := add_person(state, 1, 0, 0)
	expect_choice(state, child, "direct", "country/ordinary royal son needs no virtual title")
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	members[child].alive = false
	var brother := add_person(state, 0, 0, 0)
	expect_choice(state, brother, "collateral", "country/ordinary royal brother needs no virtual title")

func _test_remote_read_and_ancestral_chain() -> void:
	var state := fixture()
	var grandfather := add_person(state, 0, 0, 0, false)
	var father := add_person(state, grandfather, 0, 0, false)
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	members[0].child_ids.erase(1)
	members[1].parent_id = father
	members[father].child_ids.append(1)
	if not expect_choice(state, -1, "remote", "remote/selection only describes fallback without allocating person"): return
	var previous_id := state.nations[0].ruler_person_id
	var previous_depth := depth_to_root(members, previous_id)
	var founder := state.nations[0].empire_founder_person_id
	var old_members := members.duplicate(true)
	var next_person := state.next_family_person_id
	check(PrincePolitics.accede(state, 0), "remote/actual accession materializes a replacement only after selection")
	var incoming := state.nations[0].ruler_person_id
	check(incoming >= next_person and incoming != previous_id and members.has(incoming), "remote/new same-generation person becomes ruler")
	check(not members[previous_id].alive and bool(members[incoming].get("alive", false)), "remote/old ruler dies and replacement lives")
	check(depth_to_root(members, incoming) == previous_depth, "remote/replacement has same blood generation as previous ruler")
	check(int(members[incoming].parent_id) != previous_id, "remote/replacement is a distant branch rather than a fabricated son")
	check(state.nations[0].empire_founder_person_id == founder, "remote/fallback cannot establish another Taizu")
	for id in old_members:
		check(int(members[id].parent_id) == int(old_members[id].parent_id), "remote/old blood parent edges remain immutable")
	for id in members:
		var parent := int(members[id].parent_id)
		if parent >= 0:
			check(members.has(parent) and (members[parent].child_ids as Array).has(id), "remote/every generated blood edge is present in parent child cache")

func depth_to_root(members: Dictionary, person_id: int) -> int:
	var id := person_id
	var seen := {}
	var depth := 0
	while members.has(id) and not seen.has(id):
		if id == 0: return depth
		seen[id] = true
		id = int(members[id].parent_id)
		depth += 1
	return -1
