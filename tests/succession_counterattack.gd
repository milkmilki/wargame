extends SceneTree
const Chain = preload("res://tests/succession_chain.gd")
var failures: Array[String] = []
func _init() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
func run() -> void:
	var state: GameState = Chain.fixture()
	var nation := state.nations[0]
	var prince := nation.prince_person_ids[1]
	PrincePolitics.person(state, 0, prince).archetype = RulerProfile.CONQUEROR
	PrincePolitics.person(state, 0, nation.crown_prince_person_id).archetype = RulerProfile.CONQUEROR
	var rebel := state.create_army(0, 1, 15000)
	rebel.political_person_id = prince
	rebel.attack = 1
	rebel.defense = 10
	rebel.morale = 0.3
	var reserve := state.create_army(0, 1, 3000)
	reserve.political_person_id = prince
	var crown := state.create_army(0, 0, 15000)
	crown.political_person_id = nation.crown_prince_person_id
	crown.attack = 1
	crown.defense = 10
	var crown_reserve := state.create_army(0, 0, 15000)
	crown_reserve.political_person_id = nation.crown_prince_person_id
	crown_reserve.attack = 1
	state.edge_of(0, 1).distance = 1.0
	check(SuccessionRules.begin_preparation(state, 0, prince), "qualifies")
	var conflict: SuccessionConflict = state.succession_conflicts[0]
	check(SuccessionRules.launch(state, conflict), "launch")
	reserve.state = Army.State.RECOVERING
	reserve.morale = 0.0
	var sim := Simulation.new()
	sim.setup(state)
	var routed := false
	var camp_taken := false
	var crown_moved := false
	for tick in range(600):
		state.day += 1
		sim._plan_succession_conflicts()
		sim._resolve_supply()
		sim._advance_movement()
		if OS.get_environment("SUCCESSION_TRACE") == "1":
			print("day=%d rebel=%d/%d city=%d edge=%s morale=%.3f crown=%d/%d city=%d edge=%s camp_owner=%d pending=%d" % [state.day, rebel.size, rebel.state, rebel.location_city, rebel.on_edge, rebel.morale, crown.size, crown.state, crown.location_city, crown.on_edge, state.cities[1].owner_nation, conflict.pending_outcome])
		if rebel.size > 0 and rebel.state in [Army.State.RETREATING, Army.State.RECOVERING]:
			routed = true
			check(conflict.pending_outcome == SuccessionConflict.Outcome.SUPPRESSED, "real_side_defeat_ends_revolt")
		crown_moved = crown_moved or crown.on_edge
		camp_taken = camp_taken or state.cities[1].owner_nation == 0
		sim._update_succession_conflicts()
		if not state.succession_conflicts.has(0):
			break
	check(routed or rebel.size == 0, "real_field_side_defeat")
	check(conflict.resolution_reason == "field_defeat", "real_counterattack_locks_failure_at_field_result")
	check(crown_moved and not camp_taken, "real_defender_counterattack_wins_without_needing_to_capture_camp")
	check(not state.succession_conflicts.has(0), "cleanup")
	check(nation.crown_prince_person_id == conflict.crown_person_id and not bool(PrincePolitics.person(state, 0, prince).alive), "suppressed_not_crown_changed")
	check(state.campaign_pairs.is_empty(), "no_normal_cooldown_or_counterattack_privilege")
	sim.free()
	for failure in failures:
		push_error("SUCCESSION_COUNTERATTACK_FAIL: " + failure)
	print("SUCCESSION_COUNTERATTACK: %d failures day=%d routed=%s camp=%s size=%d morale=%.3f" % [failures.size(), state.day, routed, camp_taken, rebel.size, rebel.morale])
	quit(0 if failures.is_empty() else 1)
