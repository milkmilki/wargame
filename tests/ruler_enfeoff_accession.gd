extends SceneTree

const PoliticsAudit = preload("res://tests/succession_audit.gd")
const TitlesAudit = preload("res://tests/royal_title_audit.gd")
const FamilyFixture = preload("res://tests/ruler_family_fixture.gd")
var failures: Array[String] = []
var checks := 0

class StaleAnnexState extends GameState:
	func annex_nation(absorber: int, absorbed: int, expected_ownership_revision: int = -1, stock_policy_overrides: Dictionary = {}) -> bool:
		return super.annex_nation(absorber, absorbed, expected_ownership_revision + 1, stock_policy_overrides)

func _init() -> void:
	_test_landed_accession(false)
	_test_landed_accession(true)
	_test_landed_accession(false, true)
	for failure in failures: push_error("RULER_ENFEOFF_ACCESSION_FAIL: " + failure)
	print("RULER_ENFEOFF_ACCESSION_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_landed_accession(reject: bool, scheduled: bool = false) -> void:
	var state: GameState = StaleAnnexState.new() if reject else GameState.new()
	state.generate_grid_world(73003)
	FamilyFixture.ensure_candidates(state, 0, 3)
	state.region_ids.fill(-1)
	var land := state.land_cities_of(0)
	for index in range(land.size()): state.region_ids[land[index].id] = 10 if index < land.size() / 2 else 20
	EmpireStatus.reconcile(state)
	var subject := -1
	for center in state.administrative_center_city_ids:
		if state.cities[center].owner_nation == 0 and center != state.nations[0].capital_city_id:
			subject = state.enfeoff(0, [center])
			if subject >= 0: break
	check(subject >= 0, "real fief created")
	if subject < 0: return
	var nation := state.nations[0]
	var old_ruler := nation.ruler_person_id
	var founder := nation.empire_founder_person_id
	var king := state.nations[subject].ruler_person_id
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var before_birth := state.next_family_person_id
	var original_children := RoyalTitles.children(members, king)
	PrincePolitics.ensure_generation(state, subject)
	PrincePolitics.ensure_generation(state, subject)
	check(bool(members[king].get("children_initialized", false)) and state.next_family_person_id == before_birth and RoyalTitles.children(members, king) == original_children, "landed ruler also fixes child count exactly once")
	# Only the landed king remains a possible successor in this dynasty.
	for member in members.values():
		if int(member.id) != king and int(member.id) != old_ruler:
			member["alive"] = false
			RoyalTitles.end_title(state, member, "death")
	var child := PrincePolitics._create_person(state, subject, king, 0)
	members[child]["children_initialized"] = true
	RoyalTitles._grant(state, members[child], 0, subject, int(members[king].title_branch_id), true)
	state.nations[subject].prince_person_ids.assign([child])
	state.nations[subject].crown_prince_person_id = child
	members[child]["crown"] = true

	members[king]["children_initialized"] = true
	members[old_ruler]["children_initialized"] = true
	nation.crown_prince_person_id = -1
	state.family_revision += 1
	var blood_parent := int(members[king].parent_id)
	state.nations[subject].treasury_gold = 321
	state.nations[subject].manpower_pool = 432
	var treasury := nation.treasury_gold
	var manpower := nation.manpower_pool
	var old_generation := nation.royal_generation
	var army := state.create_army(subject, state.nations[subject].capital_city_id, 1000)
	army.political_person_id = child
	if reject:
		var before := var_to_bytes(NativeSnapshotBuilder.build(state))
		check(not PrincePolitics.accede(state, 0), "stale real territory transaction rejects landed accession")
		check(var_to_bytes(NativeSnapshotBuilder.build(state)) == before, "rejected accession preserves all politics, territory, armies and assets")
		check(not state.has_meta("ruler_accession_in_progress"), "failed transition clears deferral guard")
		return
	if scheduled:
		state._random_ruler_profiles_enabled = true
		var sim := Simulation.new()
		sim.setup(state)
		state.day = maxi(RulerProfile.succession_due_day(nation, state.world_seed), RulerProfile.succession_due_day(state.nations[subject], state.world_seed))
		var previous_subject_generation := state.nations[subject].royal_generation
		sim._resolve_ruler_successions()
		check(state.nations[subject].royal_generation == previous_subject_generation, "same-day absorbed fief never runs a second succession")
		sim.free()
	else:
		check(PrincePolitics.accede(state, 0), "landed relative succeeds through actual accession")
	check(nation.ruler_person_id == king, "same person enters imperial office")
	check(int(members[king].parent_id) == blood_parent and nation.empire_founder_person_id == founder, "blood and Taizu remain unchanged")
	check(not state.nations[subject].alive and state.nations[subject].absorbed_into_nation_id == 0, "source fief is annexed and archived")
	check(nation.treasury_gold == treasury + 321 and nation.manpower_pool == manpower + 432, "fief assets transferred once")
	check(army.owner_nation == 0 and army.political_person_id == -1, "fief army transfers without obsolete patron")
	check(bool(members[child].alive) and nation.prince_person_ids.has(child), "incoming ruler children survive cohort transition and are reused")
	check(int(members[king].get("title_rank", -1)) == 0 and int(members[king].get("enfeoffed_nation_id", -1)) == -1 and int(members[king].get("office_nation_id", -1)) == 0, "one office and no double stipend")
	check(nation.royal_generation == old_generation + 1 and not bool(members[old_ruler].alive), "old reign and title cohort settle exactly once")
	check(PoliticsAudit.inspect(state).errors.is_empty() and TitlesAudit.inspect(state).is_empty(), "army and royal audits pass")
	check(NativeSnapshotBuilder.succession_validation_error(NativeSnapshotBuilder.build(state)).is_empty(), "snapshot validates final accession")
	var snapshot := NativeSnapshotBuilder.build(state)
	snapshot.nations.alive[subject] = 1
	snapshot.nations.ruler_person_ids[subject] = king
	check(not NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(), "native rejects one person in two active offices")
	snapshot = NativeSnapshotBuilder.build(state)
	for tree in snapshot.family_trees:
		if int(tree.id) != nation.family_tree_id: continue
		for member in tree.members:
			if int(member.id) == king: member.children_initialized = "false"
	check(not NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(), "native rejects malformed birth lifecycle flag")
	var accession_events := state.chronicle_events.filter(func(event): return event.kind == "ruler_succession" and int(event.actor_ids[0]) == 0)
	check(accession_events.size() == 1 and int(accession_events[0].annex_nation_id) == subject, "landed accession and annex record one event")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
