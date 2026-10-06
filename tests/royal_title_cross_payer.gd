extends SceneTree
const FamilyFixture = preload("res://tests/ruler_family_fixture.gd")
## Real fief transactions must not take another country's restored dynastic family.

var checks := 0
var failures: Array[String] = []

func _init() -> void:
	_test_restored_foreign_brother()
	_test_disabled_title_display()
	for failure in failures:
		push_error("ROYAL_TITLE_CROSS_PAYER_FAIL: " + failure)
	print("ROYAL_TITLE_CROSS_PAYER_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func fixture() -> GameState:
	var state := GameState.new()
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
	# Independently valid one-city states, as in enfeoff_shared_lineage.gd.
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

func enfeoff_next(state: GameState, nation_id: int) -> int:
	for center in state.administrative_center_city_ids:
		if state.cities[center].owner_nation == nation_id and center != state.nations[nation_id].capital_city_id and (state.adjacency[center] as Array).size() == 1:
			var result := state.enfeoff(nation_id, [center] as Array[int])
			if result >= 0: return result
	return -1

func _test_restored_foreign_brother() -> void:
	var state := fixture()
	check(state.nations[0].state_level == 1, "fixture recognizes empire through real region ownership")
	var a_land: Array[int] = []
	a_land.assign(range(1, 11))
	var d_land: Array[int] = []
	d_land.assign(range(11, 16))
	var a := state.enfeoff(0, a_land)
	var d := state.enfeoff(0, d_land)
	check(a >= 0 and d >= 0, "real sibling fiefs A and D created")
	if a < 0 or d < 0: return
	FamilyFixture.ensure_candidates(state, a, 3)
	var b := PrincePolitics.enfeoff_candidate(state, a)
	var members: Dictionary = FamilyTree.tree_for_nation(state, a).members
	var c := enfeoff_next(state, a)
	check(c >= 0 and state.nations[c].ruler_person_id == b, "real A sub-fief C reuses non-crown son B")
	if c < 0: return
	FamilyFixture.ensure_candidates(state, c)
	check(PrincePolitics.accede(state, a), "real A accession preserves B as C's actual ruler")
	FamilyFixture.ensure_candidates(state, a)
	check(int(members[b].parent_id) == int(members[state.nations[a].ruler_person_id].parent_id), "B is a real living brother of A's successor R")
	var children := RoyalTitles.children(members, b)
	check(children.size() >= 2, "real C has existing succession children")
	state.set_diplomatic_relation(d, c, GameState.DiplomaticRelation.WAR)
	check(state.annex_nation(d, c), "real same-tree D conquest of C")
	check(not state.nations[c].alive and int(members[b].title_payer_id) == d and int(members[b].enfeoffed_nation_id) < 0, "D restores B's virtual title and pays his family")
	var protected_payers := {}
	for id in children:
		protected_payers[id] = int(members[id].title_payer_id)
		check(protected_payers[id] == d, "C child transferred to actual absorber D")
	var candidate := PrincePolitics.enfeoff_candidate(state, a)
	check(candidate != b, "A must not nominate its brother B now paid by D; got=%d B=%d" % [candidate, b])
	var next := enfeoff_next(state, a)
	check(next >= 0, "A still has territory for a second real sub-fief")
	if next < 0: return
	check(state.nations[next].ruler_person_id != b, "A must choose an available member of its own country")
	check(int(members[b].title_payer_id) == d, "second A enfeoffment cannot transfer D's restored family head")
	var child_payers := []
	for id in children:
		child_payers.append(int(members[id].title_payer_id))
		check(int(members[id].title_payer_id) == int(protected_payers[id]), "second A enfeoffment cannot transfer D's existing child %d" % id)
	print("CROSS_PAYER_PATH A=%d D=%d old_C=%d new_C=%d B=%d candidate=%d head_payer=%d child_payers=%s" % [a, d, c, next, b, candidate, int(members[b].title_payer_id), str(child_payers)])

func _test_disabled_title_display() -> void:
	var state := GameState.new()
	state.generate_grid_world(73003)
	FamilyFixture.ensure_candidates(state, 0)
	state.region_ids.fill(-1)
	var land := state.land_cities_of(0)
	for index in range(land.size()): state.region_ids[land[index].id] = 10 if index < land.size() / 2 else 20
	EmpireStatus.reconcile(state)
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var root := int(FamilyTree.tree_for_nation(state, 0).root_person_id)
	var prince := state.nations[0].prince_person_ids[1]
	var original_title := str(members[prince].current_title)
	check(int(members[prince].title_rank) == 3, "foreign annex display fixture has a live virtual prince")
	state.set_diplomatic_relation(1, 0, GameState.DiplomaticRelation.WAR)
	check(state.annex_nation(1, 0), "real foreign-tree annex")
	check(int(members[prince].get("title_origin_nation_id", -1)) == -1 and RoyalTitles.effective_rank(state, members[prince]) == 0, "foreign annex terminates title without disabling political identity")
	check(FamilyTree.display_title(members[prince], prince, root) != original_title, "disabled virtual title must not display as an active prince title")
	check((members[prince].titles as Array).has(original_title), "foreign annex retains original title in historical archive")
