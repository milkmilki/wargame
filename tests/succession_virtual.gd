extends SceneTree

const Fixture = preload("res://tests/succession_chain.gd")
var failures: Array[String] = []
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func run() -> void:
	var state: GameState = Fixture.fixture()
	var nation := state.nations[0]
	var challenger := nation.prince_person_ids[1]
	PrincePolitics.person(state, 0, challenger).archetype = RulerProfile.CONQUEROR
	var a := state.create_army(0, 1, 6000)
	a.political_person_id = challenger
	a.path.assign([0, 2])
	var b := state.create_army(0, 2, 10000)
	b.political_person_id = nation.crown_prince_person_id
	var central := state.create_army(0, 0, 15000)
	central.political_person_id = -1
	var info := SuccessionRules.proposal(state, 0, challenger)
	check(int(info.get("requirement", -1)) == 5000, "threshold_only_crown_force")
	var rng_state := state.rng.state
	var battle_counter := state._next_battle_id
	check(SuccessionRules.begin_preparation(state, 0, challenger), "private_battle_created")
	if state.succession_conflicts.has(0):
		var conflict: SuccessionConflict = state.succession_conflicts[0]
		check(conflict.launched(), "no_map_preparation_phase")
		check(not state.army_reserved_for_succession(a), "no_real_army_reservation")
		check(state.nations.size() == 1 and state.battles.is_empty(), "private_namespace")
		var sim := Simulation.new()
		sim.setup(state)
		for i in range(100):
			state.day += 1
			sim._update_succession_conflicts()
			check(a.size == 6000 and b.size == 10000 and a.path == [0, 2], "real_troops_unchanged_%d" % i)
			if not state.succession_conflicts.has(0): break
		check(state.succession_conflicts.is_empty(), "resolved")
		check(state._next_battle_id == battle_counter and state.rng.state == rng_state, "independent_rng_and_ids")
		sim.free()
	for failure in failures: push_error("SUCCESSION_VIRTUAL_FAIL: " + failure)
	print("SUCCESSION_VIRTUAL: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
