extends SceneTree

const Audit = preload("res://tests/succession_audit.gd")
const TitleAudit = preload("res://tests/royal_title_audit.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	_test_enfeoff_revoke()
	_test_late_recognition()
	_test_fief_becomes_empire()
	_test_foreign_annex(false)
	_test_foreign_annex(true)
	_test_finance_history()
	for failure in failures:
		push_error("ROYAL_TITLE_LIFECYCLE_FAIL: " + failure)
	print("ROYAL_TITLE_LIFECYCLE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func fixture() -> GameState:
	var state := GameState.new()
	state.generate_grid_world(73003)
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	return state

func promote(state: GameState, nation_id: int) -> void:
	state.region_ids.fill(-1)
	var land := state.land_cities_of(nation_id)
	for index in range(land.size()):
		state.region_ids[land[index].id] = 10 if index < land.size() / 2 else 20
	EmpireStatus.reconcile(state)
	check(state.nations[nation_id].state_level == 1, "two whole regions establish empire")

func enfeoff(state: GameState, nation_id: int) -> int:
	for center in state.administrative_center_city_ids:
		if state.cities[center].owner_nation == nation_id and center != state.nations[nation_id].capital_city_id:
			var result := state.enfeoff(nation_id, [center])
			if result >= 0:
				return result
	return -1

func _test_enfeoff_revoke() -> void:
	var state := fixture()
	promote(state, 0)
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var ids := members.keys()
	var subject := enfeoff(state, 0)
	check(subject >= 0, "actual enfeoffment succeeds")
	if subject < 0: return
	var king := state.nations[subject].ruler_person_id
	check(ids.has(king), "enfeoffment reuses original person")
	check(members[king].restorable_title_rank == 3 and RoyalTitles.effective_rank(state, members[king]) == 0, "fief replaces stipend while retaining qualification")
	var existing := RoyalTitles.children(members, king)
	for id in state.nations[subject].prince_person_ids:
		check(existing.has(id) and int(members[id].parent_id) == king, "fief candidates reuse actual children")
		if id != state.nations[subject].crown_prince_person_id:
			check(members[id].title_rank == 2, "fief junior lines use original rank minus one")
	var old_crown := state.nations[subject].crown_prince_person_id
	check(PrincePolitics.accede(state, subject), "actual fief succession")
	check(state.nations[subject].ruler_person_id == old_crown and members[old_crown].restorable_title_rank == 3, "real fief successor inherits restoration qualification")
	var blood := {}
	for id in members:
		blood[id] = int(members[id].parent_id)
	check(state.revoke_vassal(subject), "real revoke transaction succeeds")
	check(members[old_crown].title_rank == 3 and members[old_crown].current_title == "一字王", "revocation restores only current virtual title")
	check(state.nations[subject].absorbed_into_nation_id == 0, "annex archive records actual destination")
	check(TitleAudit.inspect(state).is_empty(), "revoke preserves cohorts of already reproducing families")
	for id in blood:
		check(int(members[id].parent_id) == int(blood[id]), "annex preserves every blood edge")
	check(Audit.inspect(state).errors.is_empty(), "fief transitions preserve army political attribution")
	var before := state.family_trees.duplicate(true)
	check(not state.annex_nations(0, [0]), "invalid annex rejected")
	check(state.family_trees == before, "failed annex has no genealogy effects")
	var adults: Array[int] = []
	for id in members:
		if members[id].get("title_payer_id", -1) == 0 and members[id].get("title_adult", false) and members[id].get("alive", true) and int(members[id].get("office_nation_id", -1)) < 0:
			adults.append(int(id))
	check(PrincePolitics.accede(state, 0), "overlord accession after withdrawal")
	for id in adults:
		check(not members[id].alive, "restored adult cohorts die at next paying ruler succession")

func _test_fief_becomes_empire() -> void:
	var state := fixture()
	promote(state, 0)
	var subject := enfeoff(state, 0)
	check(subject >= 0, "fief created for independent empire regression")
	if subject < 0: return
	state.set_diplomatic_relation(0, subject, GameState.DiplomaticRelation.WAR)
	check(state.annex_nation(subject, 0), "real fief counter-conquest of overlord")
	check(state.nations[subject].state_level == 1 and state.nations[subject].empire_founder_person_id == state.nations[subject].ruler_person_id, "independent former fief recognizes its own Taizu")
	for id in state.nations[subject].prince_person_ids:
		if id != state.nations[subject].crown_prince_person_id:
			check(PrincePolitics.person(state, subject, id).title_rank == 3, "new Taizu sons upgrade existing fief grants")
	check(PrincePolitics.accede(state, subject), "second emperor succeeds former fief Taizu")
	for id in state.nations[subject].prince_person_ids:
		if id != state.nations[subject].crown_prince_person_id:
			check(PrincePolitics.person(state, subject, id).title_rank == 2, "later emperor uses imperial formula")

func _test_late_recognition() -> void:
	var state := fixture()
	var subject := enfeoff(state, 0)
	check(subject >= 0, "pre-empire landed son")
	if subject < 0: return
	# The fief's territory counts toward its parent's peaceful integration.
	state.region_ids.fill(-1)
	for city in state.cities:
		if city.owner_nation in [0, subject] and not city.is_dock:
			state.region_ids[city.id] = 10 if city.owner_nation == 0 else 20
	EmpireStatus.reconcile(state)
	var member := PrincePolitics.person(state, subject, state.nations[subject].ruler_person_id)
	check(member.restorable_title_rank == 3, "Taizu retroactively qualifies already landed son")
	check(state.nations[subject].royal_titles_initialized, "country fief carries inherited institution")
	check(state.nations[subject].empire_founder_person_id == -1 and state.nations[subject].state_level == 0, "inherited institution creates no second Taizu")
	for id in state.nations[subject].prince_person_ids:
		check(int(PrincePolitics.person(state, subject, id).title_branch_id) == int(member.id), "retroactive landed qualification joins children to the original title branch")
	var first_root := int(member.id)
	check(PrincePolitics.accede(state, subject), "late-qualified fief succeeds")
	check(int(PrincePolitics.person(state, subject, state.nations[subject].ruler_person_id).title_branch_id) == first_root, "fief succession retains original title branch as well as rank")

func _test_foreign_annex(reverse: bool) -> void:
	var state := fixture()
	var attacker := 0
	var defender := 1
	var winner := defender if reverse else attacker
	var loser := attacker if reverse else defender
	promote(state, loser)
	var tree_id := state.nations[loser].family_tree_id
	var persons: Dictionary = state.family_trees[tree_id].members
	var ids := persons.keys()
	state.set_diplomatic_relation(attacker, defender, GameState.DiplomaticRelation.WAR)
	check(state.annex_nation(winner, loser), "real wartime annex including defender counterattack")
	check(state.nations[loser].family_tree_id == tree_id and state.family_trees[tree_id].members.keys() == ids, "foreign annex retains separate archive without births")
	check(RoyalTitles.report(state, loser).basis_points == 0, "extinct foreign dynasty stops expense")
	for member in persons.values():
		if member.get("title_payer_id", -1) == loser:
			check(member.get("title_disabled", false), "foreign title reproduction explicitly disabled")
	check(Audit.inspect(state).errors.is_empty(), "both victory directions release political army bindings")

func _test_finance_history() -> void:
	var state := fixture()
	var history := PoliticalHistory.new()
	history.reset(state)
	promote(state, 0)
	var report := RoyalTitles.report(state, 0)
	var flow: Array[Dictionary] = [{"city_income": 10000, "trade_net_income": 0, "tribute_received": 0, "tribute_paid": 0, "military_upkeep": 0}]
	EconomyRules._finalize_balances(state, flow)
	check(flow[0].court_expense_due == int(round(RulerProfile.court_expense_rate(state.nations[0]) * 10000.0)) + report.basis_points, "royal cost is additive to existing court rate")
	var view := history.build_view_state(state, 0)
	check(view.nations[0].state_level == 0 and view.nations[0].empire_founder_person_id == -1, "history cannot borrow later empire recognition")
	check(RoyalTitles.report(view, 0).basis_points == 0, "history cannot borrow later title census")
	var before := view.family_trees.duplicate(true)
	FamilyTree.ensure_all(view)
	EmpireStatus.reconcile(view)
	check(view.family_trees == before, "history readers cannot generate people or titles")
	var sim := Simulation.new()
	sim.setup(state)
	state.nations[0].treasury_gold = 2
	var monthly := Simulation.monthly_gold_flows(state)
	monthly[0] = flow[0]
	sim._resolve_court_expenses(monthly)
	check(state.nations[0].treasury_gold == 0 and state.nations[0].last_court_expense_paid == 2 and state.nations[0].last_court_expense_due == flow[0].court_expense_due, "royal court due remains visible when treasury cannot pay")
	check(state.nations[0].last_royal_expense_basis_points == report.basis_points, "real settlement stores royal breakdown")
	var snapshot := NativeSnapshotBuilder.build(state)
	check(NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(), "new native columns and title references validate")
	snapshot.nations.empire_founder_person_id[0] = -1
	check(not NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(), "native schema rejects missing founder")
	snapshot = NativeSnapshotBuilder.build(state)
	for tree in snapshot.family_trees:
		if int(tree.id) != state.nations[0].family_tree_id: continue
		for member in tree.members:
			if int(member.get("title_rank", 0)) > 0:
				member.title_payer_id = 1
				break
	check(not NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(), "native schema rejects cross-tree royal payer")
	state.generate_grid_world(73003)
	check(RoyalTitles.report(state, 0).basis_points == 0, "regenerated world cannot reuse old royal census")
	sim.free()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
