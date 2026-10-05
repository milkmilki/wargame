extends SceneTree

const Audit = preload("res://tests/royal_title_audit.gd")
const Politics = preload("res://tests/succession_audit.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	_test_direct_and_collateral()
	_test_twenty_generations()
	for failure in failures: push_error("ROYAL_TITLE_GENERATIONS_FAIL: " + failure)
	print("ROYAL_TITLE_GENERATIONS_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func fixture() -> GameState:
	var state := GameState.new()
	state.generate_grid_world(73004)
	state.region_ids.fill(-1)
	var land := state.land_cities_of(0)
	for index in range(land.size()): state.region_ids[land[index].id] = 10 if index < land.size() / 2 else 20
	EmpireStatus.reconcile(state)
	return state

func add_person(state: GameState, parent: int, rank: int, branch: int, adult: bool) -> int:
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var id := PrincePolitics._create_person(state, 0, parent, RoyalTitles.children(members, parent).size(), parent * 7919)
	RoyalTitles._grant(state, members[id], rank, 0, id if branch < 0 else branch, adult)
	members[id]["title_children_generated"] = true
	return id

func _test_direct_and_collateral() -> void:
	var state := fixture()
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var direct := {}
	for rank in [3, 2, 1]:
		var head := add_person(state, state.nations[0].ruler_person_id, rank, -1, true)
		var elder := add_person(state, head, rank - 1, head, false)
		members[elder].alive = false # Fixture: eldest child died before succession.
		var heir := add_person(state, head, rank - 1, head, false)
		direct[heir] = rank
	var childless := add_person(state, state.nations[0].ruler_person_id, 3, -1, true)
	var collateral := add_person(state, state.nations[0].ruler_person_id, 2, childless, true)
	var candidate := add_person(state, collateral, 1, childless, false)
	check(PrincePolitics.accede(state, 0), "real succession advances entire cohort")
	for heir in direct:
		check(members[heir].title_rank == direct[heir], "next living eldest inherits each original tier")
	check(members[candidate].title_rank == 3, "childless highest tier uses nearest collateral")
	check(not members[candidate].titles.has("郡王"), "one person cannot additionally inherit the lower title")
	check(Audit.inspect(state).is_empty(), "cohort and collateral allocation preserve title invariants")

func _test_twenty_generations() -> void:
	var state := fixture()
	state._random_ruler_profiles_enabled = true
	var sim := Simulation.new()
	sim.setup(state)
	var initial: int = RoyalTitles.report(state, 0).basis_points
	var founder := state.nations[0].empire_founder_person_id
	var peak := initial
	var started := Time.get_ticks_msec()
	for generation in range(20):
		var previous := state.nations[0].ruler_person_id
		state.day = RulerProfile.succession_due_day(state.nations[0], state.world_seed)
		sim._resolve_ruler_successions()
		check(state.nations[0].ruler_person_id != previous, "real simulation successor each generation")
		check(state.nations[0].empire_founder_person_id == founder, "founder remains immutable for twenty generations")
		check(Audit.inspect(state).is_empty(), "title audit each generation")
		check(Politics.inspect(state).errors.is_empty(), "political audit each generation")
		var snapshot := NativeSnapshotBuilder.build(state)
		check(NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(), "schema validates each generation")
		var census := RoyalTitles.report(state, 0)
		print("ROYAL_GENERATION %d people=%d bp=%d elapsed_ms=%d" % [generation + 1, state.next_family_person_id, int(census.basis_points), Time.get_ticks_msec() - started])
		peak = maxi(peak, int(census.basis_points))
		var persons := state.next_family_person_id
		RoyalTitles.reconcile(state)
		check(state.next_family_person_id == persons, "read/reconcile never rolls zero family again")
	check(peak > initial * 3, "low-tier multiplication expands long-term fiscal burden")
	var flow: Array[Dictionary] = [{"city_income": 10000, "trade_net_income": 0, "tribute_received": 0, "tribute_paid": 0, "military_upkeep": 0}]
	EconomyRules._finalize_balances(state, flow)
	check(flow[0].court_expense_rate > 1.0 and flow[0].court_expense_due > 10000, "accumulated expense can exceed all current income")
	state.nations[0].treasury_gold = 10000
	# Settlement accepts a full nation table; override just the tested nation's flow.
	var full := Simulation.monthly_gold_flows(state)
	full[0] = flow[0]
	sim._resolve_court_expenses(full)
	check(state.nations[0].treasury_gold == 0 and state.nations[0].last_court_expense_paid == 10000 and state.nations[0].last_court_expense_due > 10000, "greater-than-income due is retained without treasury debt")
	print("ROYAL_20_GENERATIONS people=%d initial_bp=%d peak_bp=%d elapsed_ms=%d" % [state.next_family_person_id, initial, peak, Time.get_ticks_msec() - started])
	sim.free()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
