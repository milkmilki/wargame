extends SceneTree
## Ruler succession is a deterministic calendar event. Extreme archetypes
## must expose their advertised numerical and territorial behavior.

var _valid := true
const FamilyFixture = preload("res://tests/ruler_family_fixture.gd")


func _init() -> void:
	_test_reign_distribution()
	_test_capital_income_and_succession_relocation()
	_test_capital_relocation_always_prefers_zhou()
	_test_suzerainty_rulers_reuse_person_names()
	_test_extreme_modifiers()
	_test_modifier_query_isolation()
	_test_conqueror_war_benefits()
	_test_puppet_enfeoffment()
	_test_puppet_without_enfeoff_candidate()
	if not _valid:
		quit(1)
		return
	print("RULER_SUCCESSION_EXTREMES_OK")
	quit(0)


func _test_modifier_query_isolation() -> void:
	var nation := Nation.new()
	for archetype in RulerProfile.all_archetypes():
		nation.ruler_archetype = archetype
		for trait_id in RulerProfile.all_traits():
			nation.ruler_traits = [trait_id] as Array[String]
			var expected := RulerProfile.modifiers(nation)
			var edited := RulerProfile.modifiers(nation)
			edited[RulerProfile.KEY_OFFENSIVE_ALLOWED] = not bool(expected[RulerProfile.KEY_OFFENSIVE_ALLOWED])
			edited[RulerProfile.KEY_DEFENSE] = -100.0
			_check(RulerProfile.modifiers(nation) == expected, "mutable query results must not contaminate later profiles")
			_check(RulerProfile.offensive_allowed(nation) == bool(expected[RulerProfile.KEY_OFFENSIVE_ALLOWED]), "offensive eligibility agrees with full modifiers for every archetype and trait")
			_check(RulerProfile.offensive_allowed({"ruler_archetype": archetype, "ruler_traits": [trait_id]}) == bool(expected[RulerProfile.KEY_OFFENSIVE_ALLOWED]), "dictionary and nation eligibility remain equivalent")
			_check(RulerProfile.defense_multiplier(nation) == float(expected[RulerProfile.KEY_DEFENSE]), "single modifier query remains equivalent after another result was mutated")
	nation.ruler_traits.clear()
	nation.ruler_archetype = RulerProfile.GUARDIAN
	_check(not RulerProfile.offensive_allowed(nation), "profile edits immediately invalidate eligibility without a nation cache")
	nation.ruler_archetype = RulerProfile.CONQUEROR
	_check(RulerProfile.offensive_allowed(nation), "edited conqueror immediately regains offensive eligibility")
	_check(RulerProfile.offensive_allowed(-999) == RulerProfile.offensive_allowed(RulerProfile.BALANCED), "unknown archetype uses neutral policy")


func _test_capital_relocation_always_prefers_zhou() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(71240)
	var fu_pair := Vector2i(-1, -1)
	for city in state.cities:
		if city.is_dock or state.is_zhou_city(city.id):
			continue
		for neighbor_id in state.neighbors(city.id):
			var neighbor := state.cities[neighbor_id]
			var edge := state.edge_of(city.id, neighbor_id)
			if (
				neighbor.is_dock
				or state.is_zhou_city(neighbor_id)
				or edge == null
				or edge.max_manpower <= 0
			):
				continue
			fu_pair = Vector2i(city.id, neighbor_id)
			break
		if fu_pair.x >= 0:
			break
	var isolated_zhou := -1
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		if (
			center_id != fu_pair.x
			and center_id != fu_pair.y
			and not state.neighbors(fu_pair.x).has(center_id)
			and not state.neighbors(fu_pair.y).has(center_id)
		):
			isolated_zhou = center_id
			break
	_check(
		fu_pair.x >= 0 and isolated_zhou >= 0,
		"capital relocation fixture lacks disconnected zhou/fu components"
	)
	if fu_pair.x < 0 or isolated_zhou < 0:
		return
	var nation_id := 0
	var other_id := 1
	var planned_owners: Array[int] = []
	planned_owners.resize(state.cities.size())
	planned_owners.fill(other_id)
	planned_owners[fu_pair.x] = nation_id
	planned_owners[fu_pair.y] = nation_id
	planned_owners[isolated_zhou] = nation_id
	state.nations[nation_id].capital_city_id = -1
	var planned_capital := state._planned_territory_capital(
		nation_id, planned_owners
	)
	_check(
		planned_capital == isolated_zhou,
		"territory transaction preferred a larger fu component over an owned zhou"
	)
	for city in state.cities:
		city.owner_nation = planned_owners[city.id]
		city.is_capital = false
	state.nations[nation_id].capital_city_id = -1
	var relocated_capital := state.relocate_capital(nation_id)
	_check(
		relocated_capital == isolated_zhou,
		"direct capital relocation preferred a larger fu component over an owned zhou"
	)


func _test_reign_distribution() -> void:
	var buckets: Array[Vector3i] = [
		Vector3i(1, 4, 20), Vector3i(5, 9, 20), Vector3i(10, 19, 30),
		Vector3i(20, 29, 15), Vector3i(30, 39, 8), Vector3i(40, 49, 4),
		Vector3i(50, 60, 3),
	]
	var counts: Array[int] = []
	counts.resize(61)
	counts.fill(0)
	var sample_count := 0
	for seed_value in [71237, 12345, 0, -71]:
		for nation_id in range(100):
			for revision in range(100):
				var years := RulerProfile.reign_years(seed_value, nation_id, revision)
				_check(years >= 1 and years <= 60, "weighted reign escaped 1..60 years")
				if years >= 1 and years <= 60:
					counts[years] += 1
				sample_count += 1
	for bucket in buckets:
		var bucket_count := 0
		for years in range(bucket.x, bucket.y + 1):
			bucket_count += counts[years]
		var observed := float(bucket_count) / sample_count
		_check(absf(observed - float(bucket.z) / 100.0) < 0.01,
			"reign bucket %d..%d expected %d%%, observed %.2f%%" % [
				bucket.x, bucket.y, bucket.z, observed * 100.0])
		var expected_per_year := float(bucket_count) / (bucket.y - bucket.x + 1)
		for years in range(bucket.x, bucket.y + 1):
			_check(counts[years] > 0, "every reign year must be attainable: %d" % years)
			_check(absf(counts[years] - expected_per_year) <= expected_per_year * 0.35,
				"reign years must be uniform within each bucket: %d" % years)


func _test_capital_income_and_succession_relocation() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(71239)
	state._random_ruler_profiles_enabled = true
	var nation: Nation = null
	var capital_candidates: Array[City] = []
	for candidate_nation in state.nations:
		var component := state._largest_owned_component(
			candidate_nation.id, state.land_cities_of(candidate_nation.id)
		)
		var centers: Array[City] = []
		for city in component:
			if state.is_zhou_city(city.id):
				centers.append(city)
		if centers.size() >= 2:
			nation = candidate_nation
			capital_candidates = centers
			break
	_check(nation != null, "capital relocation fixture has fewer than two owned zhou")
	if nation == null:
		return
	EquivariantOrder.sort_cities(capital_candidates, state, nation.id)
	var old_capital := capital_candidates[0]
	for city in state.cities:
		if city.owner_nation == nation.id:
			city.is_capital = false
	nation.capital_city_id = old_capital.id
	old_capital.is_capital = true
	var base_gold := old_capital.gold_per_month
	var expected_capital_addition := 0
	for city in state.land_cities_of(nation.id):
		if state.city_administrative_output_enabled(city.id):
			expected_capital_addition += city.gold_per_month
	expected_capital_addition = int(floor(
		float(expected_capital_addition) * 0.20
	))
	old_capital.set("capital_since_day", 0)
	state.day = 10 * RulerProfile.DAYS_PER_YEAR
	_check(
		Simulation.city_gold_output_before_governance(state, old_capital)
			== base_gold + expected_capital_addition,
		"capital did not receive twenty percent of national base city gold"
	)
	state.day = 60 * RulerProfile.DAYS_PER_YEAR
	_check(
		Simulation.city_gold_output_before_governance(state, old_capital)
			== base_gold + expected_capital_addition,
		"capital gold addition still changed with capital tenure"
	)

	# 州治优先且以稳定物理序裁决；当前首都就是首选州治时应保留。
	var due_day := RulerProfile.succession_due_day(nation, state.world_seed)
	state.day = due_day
	var simulation := Simulation.new()
	simulation.setup(state)
	simulation._resolve_ruler_successions()
	_check(
		nation.capital_city_id == old_capital.id,
		"ruler succession forced a capital move despite the old capital winning"
	)
	_check(
		int(old_capital.get("capital_since_day")) == 0,
		"retained capital lost its tenure start day"
	)

	# 旧都失去本国控制后，下一任继位迁往最大实控连通区中的首选州治。
	var other_nation_id := (nation.id + 1) % state.nations.size()
	old_capital.owner_nation = other_nation_id
	old_capital.is_capital = false
	state.recognized_city_owners[old_capital.id] = other_nation_id
	state.ownership_revision += 1
	var remaining_component := state._largest_owned_component(
		nation.id, state.land_cities_of(nation.id)
	)
	var remaining_centers: Array[City] = []
	for city in remaining_component:
		if state.is_zhou_city(city.id):
			remaining_centers.append(city)
	_check(not remaining_centers.is_empty(), "capital relocation fixture lost every owned zhou")
	if remaining_centers.is_empty():
		return
	EquivariantOrder.sort_cities(remaining_centers, state, nation.id)
	var successor_capital := remaining_centers[0]
	var next_due_day := RulerProfile.succession_due_day(
		nation, state.world_seed
	)
	state.day = next_due_day
	simulation._resolve_ruler_successions()
	_check(
		nation.capital_city_id == successor_capital.id,
		"ruler succession did not move to the newly highest-value capital"
	)
	_check(
		int(old_capital.get("capital_since_day")) == -1,
		"demoted capital retained its tenure start day"
	)
	_check(
		int(successor_capital.get("capital_since_day")) == next_due_day,
		"new capital did not start its tenure on the succession day"
	)
	state.day += 5 * RulerProfile.DAYS_PER_YEAR
	expected_capital_addition = 0
	for city in state.land_cities_of(nation.id):
		if state.city_administrative_output_enabled(city.id):
			expected_capital_addition += city.gold_per_month
	expected_capital_addition = int(floor(
		float(expected_capital_addition) * 0.20
	))
	_check(
		Simulation.city_gold_output_before_governance(
			state, successor_capital
		) == successor_capital.gold_per_month + expected_capital_addition,
		"new capital did not receive the national base city gold addition"
	)
	simulation.free()


func _test_suzerainty_rulers_reuse_person_names() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(71241, 2, 20)
	state._random_ruler_profiles_enabled = true
	var region: Array[int] = []
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		if state.cities[center_id].is_capital:
			continue
		var candidate := state.expand_enfeoff_to_administrative_states(
			0, [center_id] as Array[int]
		)
		if not candidate.is_empty():
			region = candidate
			break
	var enfeoff_person := PrincePolitics.enfeoff_candidate(state, 0)
	var enfeoff_name := str(PrincePolitics.person(state, 0, enfeoff_person).name)
	var subject_id := state.enfeoff(0, region)
	_check(subject_id >= 0, "identity fixture failed to create a complete-state vassal")
	if subject_id < 0:
		return
	var root := state.nations[0]
	var subject := state.nations[subject_id]
	_check(
		subject.ruler_person_id == enfeoff_person and subject.ruler_name == enfeoff_name
			and subject.family_tree_id == root.family_tree_id,
		"new vassal ruler did not reuse the existing relative identity"
	)

	var simulation := Simulation.new()
	simulation.setup(state)
	var subject_successor := subject.crown_prince_person_id
	var subject_successor_name := str(PrincePolitics.person(state, subject_id, subject_successor).name)
	var subject_due := RulerProfile.succession_due_day(
		subject, state.world_seed
	)
	root.ruler_started_day = subject_due
	state.day = subject_due
	simulation._resolve_ruler_successions()
	_check(
		subject.ruler_person_id == subject_successor and subject.ruler_name == subject_successor_name,
		"vassal succession did not reuse the existing crown prince identity"
	)

	root.ruler_started_day = state.day
	var root_due := RulerProfile.succession_due_day(root, state.world_seed)
	subject.ruler_started_day = root_due
	var root_successor := root.crown_prince_person_id
	var root_successor_name := str(PrincePolitics.person(state, 0, root_successor).name)
	state.day = root_due
	simulation._resolve_ruler_successions()
	_check(
		root.ruler_person_id == root_successor and root.ruler_name == root_successor_name
			and subject.ruler_name == subject_successor_name
			and subject.family_tree_id == root.family_tree_id,
		"overlord succession changed another ruler or broke the shared lineage"
	)
	simulation.free()


func _test_extreme_modifiers() -> void:
	var conqueror := RulerProfile.modifiers(RulerProfile.CONQUEROR)
	var guardian := RulerProfile.modifiers(RulerProfile.GUARDIAN)
	_check(
		is_equal_approx(float(conqueror[RulerProfile.KEY_ATTACK]), 5.0)
		and is_equal_approx(float(conqueror[RulerProfile.KEY_MORALE]), 2.0)
		and is_equal_approx(float(conqueror[RulerProfile.KEY_DEFENSE]), 5.0)
		and is_equal_approx(float(conqueror[RulerProfile.KEY_UPKEEP]), 0.5)
		and is_equal_approx(float(conqueror[RulerProfile.KEY_WAR_BENEFIT]), 2.0)
		and is_equal_approx(
			float(conqueror[RulerProfile.KEY_OFFENSIVE_INTERVAL]), 0.5
		),
		"conqueror military multipliers do not match the extreme profile"
	)
	var conqueror_army := Army.new()
	conqueror_army.size = 100
	conqueror_army.attack = 10
	conqueror_army.ruler_attack_multiplier = float(
		conqueror[RulerProfile.KEY_ATTACK]
	)
	_check(
		is_equal_approx(conqueror_army.combat_attack(), 50.0)
			and is_equal_approx(
				Combat._frontline_attack([{
					"army": conqueror_army,
					"committed": 100,
					"size_before": 100,
				}], 1.0),
				5000.0
			),
		"conqueror attack multiplier did not reach frontline firepower"
	)
	_check(
		is_equal_approx(float(guardian[RulerProfile.KEY_TRADE]), 2.0),
		"guardian trade multiplier is not 2.0"
	)


func _test_conqueror_war_benefits() -> void:
	_check(
		is_equal_approx(
			DiplomacyAI._war_desire_score(3.0, 0.5, 0.75, 0.25, 2.0),
			5.5
		),
		"conqueror did not double only positive war benefits"
	)


func _test_puppet_enfeoffment() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(84521, 2, 60)
	# This repeated-grant scenario requires existing relatives, independent
	# of the separately tested natural possibility of a childless monarch.
	FamilyFixture.ensure_candidates(state, 0, 5)
	var ruler := state.nations[0]
	ruler.ruler_archetype = RulerProfile.PUPPET
	ruler.ruler_traits.clear()
	var capital_center := state.administrative_center_of(ruler.capital_city_id)
	var capital_state_members := state.administrative_members(capital_center)
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	_check(RoyalTitles.children(members, ruler.ruler_person_id).size() == 5, "puppet repeated-grant fixture has exactly five biological children")
	# This political test uses a pre-existing collateral family large enough
	# for every non-capital state. The unknown ancestor is a test placeholder,
	# not an actual monarch subject to the separate 0/2/3/4/5 birth rule.
	var non_capital_states := {}
	for city in state.land_cities_of(0):
		var center := state.administrative_center_of(city.id)
		if center != capital_center:
			non_capital_states[center] = true
	var sibling_parent := int(members[ruler.ruler_person_id].parent_id)
	var sibling_offset := RoyalTitles.children(members, sibling_parent).size()
	for order in range(non_capital_states.size()):
		var brother := PrincePolitics._create_person(state, 0, sibling_parent, sibling_offset + order)
		RoyalTitles.set_member(state, members[brother], "children_initialized", true)
	var initial_cities := state.land_cities_of(0).size()
	var has_foreign_frontier := false
	var forced_frontier_city := -1
	var forced_frontier_owner := -1
	for pair in state.territorial_border_pairs():
		var owner_a := state.cities[pair.x].owner_nation
		var owner_b := state.cities[pair.y].owner_nation
		if [owner_a, owner_b].has(0) and [owner_a, owner_b].has(1):
			has_foreign_frontier = true
			break
	if not has_foreign_frontier:
		for pair in state.territorial_border_pairs():
			var foreign_city := (
				pair.y if state.cities[pair.x].owner_nation == 0 else pair.x
			)
			var home_city := pair.x if foreign_city == pair.y else pair.y
			if (
				state.cities[home_city].owner_nation != 0
				or foreign_city in capital_state_members
			):
				continue
			forced_frontier_city = foreign_city
			forced_frontier_owner = state.cities[foreign_city].owner_nation
			state.cities[foreign_city].owner_nation = 1
			has_foreign_frontier = true
			state.ownership_revision += 1
			state.refresh_derived()
			break
	_check(has_foreign_frontier, "puppet fixture could not establish a foreign frontier")
	_check(
		initial_cities > capital_state_members.size(),
		"puppet fixture does not have enough direct cities"
	)
	state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	var wartime_actions: Array[Dictionary] = []
	DiplomacyAI._collect_enfeoff_actions(
		state, wartime_actions, {}, {}
	)
	var wartime_enfeoff := false
	for action in wartime_actions:
		wartime_enfeoff = wartime_enfeoff or (
			int(action.get("kind", -1)) == DiplomacyAI.Action.ENFEOFF
			and int(action.get("a", -1)) == 0
		)
	_check(
		DiplomacyAI._overlord_under_war_pressure(state, 0, {})
			and not wartime_enfeoff,
		"puppet ruler must not enfeoff during war pressure"
	)
	if forced_frontier_city >= 0:
		state.cities[forced_frontier_city].owner_nation = forced_frontier_owner
		state.ownership_revision += 1
		state.refresh_derived()
	state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.NEUTRAL
	)
	var grants := 0
	while (
		state.land_cities_of(0).size()
			> capital_state_members.size()
		and grants < 32
	):
		var actions: Array[Dictionary] = []
		DiplomacyAI._collect_enfeoff_actions(state, actions, {}, {})
		var selected: Dictionary = {}
		for action in actions:
			if (
				int(action.get("kind", -1)) == DiplomacyAI.Action.ENFEOFF
				and int(action.get("a", -1)) == 0
			):
				selected = action
				break
		if selected.is_empty():
			break
		var region: Array[int] = []
		for city_value in selected.get("region_cities", []):
			region.append(int(city_value))
		var subject_id := state.enfeoff(0, region)
		_check(subject_id >= 0, "puppet enfeoff transaction failed")
		if subject_id < 0:
			break
		grants += 1
	_check(
		grants >= 2,
		"puppet ruler could not enfeoff repeatedly without advancing world time"
	)
	var direct_city_ids: Array[int] = []
	for city in state.land_cities_of(0):
		direct_city_ids.append(city.id)
	direct_city_ids.sort()
	capital_state_members.sort()
	_check(
		direct_city_ids == capital_state_members,
		"puppet ruler did not retain exactly the capital state: initial=%d direct=%s capital_state=%s grants=%d"
		% [initial_cities, str(direct_city_ids), str(capital_state_members), grants]
	)
	var capital_hops := RebellionSystem.capital_hops(state, 0)
	var reachable_land := 0
	for city in state.land_cities_of(0):
		if capital_hops.has(city.id):
			reachable_land += 1
	_check(
		reachable_land == state.land_cities_of(0).size(),
		"puppet ruler left a disconnected direct core: reachable=%d direct=%d"
		% [reachable_land, state.land_cities_of(0).size()]
	)
	var centralize_actions: Array[Dictionary] = []
	DiplomacyAI._collect_centralization_actions(
		state, centralize_actions, {}, {}
	)
	_check(centralize_actions.is_empty(), "puppet ruler attempted to revoke a vassal")


func _test_puppet_without_enfeoff_candidate() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(84521, 2, 60)
	var nation := state.nations[0]
	nation.ruler_archetype = RulerProfile.PUPPET
	nation.ruler_traits.clear()
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	for id in nation.prince_person_ids:
		RoyalTitles.set_member(state, members[id], "alive", false)
		RoyalTitles.set_member(state, members[id], "crown", false)
	nation.prince_person_ids.clear()
	nation.crown_prince_person_id = -1
	RoyalTitles.set_member(state, members[nation.ruler_person_id], "children_initialized", true)
	_check(PrincePolitics.enfeoff_candidate(state, 0) == -1, "childless puppet fixture has no existing fief candidate")
	var core := DiplomacyAI.puppet_capital_state_city_ids(state, 0)
	var region := DiplomacyAI.next_enfeoff_region(state, 0, core.size(), state.land_cities_of(0).size(), false, {})
	_check(not region.is_empty() and not DiplomacyAI._overlord_under_war_pressure(state, 0, {}), "childless puppet is peaceful and still owns grantable territory")
	var next_person_before := state.next_family_person_id
	var trees_before := state.family_trees.duplicate(true)
	var princes_before := nation.prince_person_ids.duplicate()
	var revision_before := state.family_revision
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_enfeoff_actions(state, actions, {}, {})
	var enfeoff_proposed := false
	for action in actions:
		enfeoff_proposed = enfeoff_proposed or (int(action.get("kind", -1)) == DiplomacyAI.Action.ENFEOFF and int(action.get("a", -1)) == 0)
	_check(not enfeoff_proposed, "childless puppet must not propose fief creation without an existing candidate")
	_check(state.next_family_person_id == next_person_before and state.family_trees == trees_before and state.family_revision == revision_before and nation.prince_person_ids == princes_before and nation.crown_prince_person_id == -1, "fief proposal evaluation must not create people or mutate the fixed family")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_valid = false
	push_error("RULER_SUCCESSION_EXTREMES_FAILED: " + message)
