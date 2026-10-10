extends SceneTree
## A committed external declaration must wake both blocs, including passive
## defenders, without consuming unrelated nations' regular decision backlog.
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func fixture() -> Simulation:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(1, 40, 120)
	state.atlas_layout = {"model": "diplomacy-wake-test", "territorial_pairs": [] as Array[Vector2i]}
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(1, 3, GameState.DiplomaticRelation.ALLIED)
	for nation in state.nations: nation.treasury_gold = 1000000
	for city in state.cities: city.food_storage = 1000000
	var sim := Simulation.new(); sim.setup(state)
	state.day = 206; sim._ai_last_decision_day = 205; sim._ai_regular_through_day = 205
	return sim
func run():
	var sim := fixture()
	var changed := sim._execute_diplomatic_action({"kind": DiplomacyAI.Action.DECLARE_WAR, "a": 0, "b": 1, "mobilization_armies": 0})
	check(changed, "real declaration transaction succeeds")
	check(sim._ai_last_decision_day == 205, "declaration does not request a global AI refresh")
	var forced: Array = sim._due_forced_ai_nations()
	for id in [0, 1, 2, 3]: check(forced.has(id), "attacker, defender and each allied participant wake immediately")
	check(not forced.has(4), "unrelated neutral nation keeps regular schedule")
	check(sim._ai_regular_through_day == 205, "local emergency preserves regular backlog")
	check(sim._ai_decision_due_today(sim._ai_decision_interval_days()), "quiet day handles declaration immediately")
	if not sim.has_method("_wake_coalition_ai"):
		finish(sim); return
	var phase: Dictionary = await sim._prepare_ai_view_phase(false, Time.get_ticks_usec())
	check((phase["managed_nations"] as Array).size() == 4, "actual view phase builds both blocs, not all forty nations")
	for id in [0, 1, 2, 3]: check((phase["managed_nations"] as Array).has(id), "actual phase includes every declaring or defending ally")
	check(sim._due_forced_ai_nations().is_empty(), "processed participant wakes are consumed")
	check(sim._ai_regular_through_day == 205, "urgent-only view preparation does not consume unrelated backlog")
	check(not sim._execute_diplomatic_action({"kind": DiplomacyAI.Action.DECLARE_WAR, "a": 0, "b": 1}), "repeat declaration is rejected")
	check(sim._due_forced_ai_nations().is_empty(), "rejected declaration does not wake anyone")
	sim._ai_forced_nations.clear(); sim._ai_last_decision_day = -1
	sim.call("_wake_coalition_ai", [0, 1] as Array[int])
	check(sim._ai_last_decision_day == -1, "local wake does not demote existing global invalidation")
	sim._ai_last_decision_day = 205
	var conflict := SuccessionConflict.new(); conflict.nation_id = 20
	sim.state.succession_conflicts[20] = conflict
	sim._ai_forced_nations.clear()
	sim.call("_wake_coalition_ai", [0, 1] as Array[int])
	check(sim._ai_last_decision_day == 205 and sim._due_forced_ai_nations().has(1), "unrelated succession conflict does not make external declaration a global refresh")
	sim.state.succession_conflicts.clear(); sim._ai_forced_nations.clear()
	sim.atlas_local_diplomacy_wakes_enabled = false
	sim.call("_wake_coalition_ai", [0, 1] as Array[int])
	check(sim._ai_last_decision_day == -1, "comparison switch restores the original global wake")
	sim.atlas_local_diplomacy_wakes_enabled = true; sim._ai_last_decision_day = 205
	sim.ai_policy_overrides[4] = func(_s, _n, _sim): pass
	sim.call("_wake_coalition_ai", [0, 1] as Array[int])
	check(sim._ai_last_decision_day == -1, "custom military policies preserve global compatibility")
	sim.ai_policy_overrides.clear(); sim._ai_last_decision_day = 205
	sim.state.atlas_layout.clear()
	sim.call("_wake_coalition_ai", [0, 1] as Array[int])
	check(sim._ai_last_decision_day == -1, "legacy map preserves global wake")
	sim.free()
	sim = fixture()
	sim.state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	sim._synchronize_alliance_wars(0, 2)
	check(sim.state.is_enemy(2, 1) and sim.state.is_enemy(0, 3), "alliance synchronization commits the genuine shared war")
	check(sim._ai_last_decision_day == 205, "war synchronization avoids unrelated global refresh")
	for id in [0, 1, 2, 3]: check(sim._due_forced_ai_nations().has(id), "newly joined allies and enemy bloc wake immediately")
	sim._ai_last_decision_day = 205; sim._ai_forced_nations.clear()
	sim.ai_staggered_decisions = false
	sim._wake_coalition_ai([0, 1] as Array[int])
	check(sim._ai_last_decision_day == -1, "non-staggered AI retains its global schedule")
	sim.ai_staggered_decisions = true; sim._ai_last_decision_day = 205
	sim.state.nations.resize(5)
	sim._wake_coalition_ai([0, 1] as Array[int])
	check(sim._ai_last_decision_day == -1, "small worlds retain their global schedule")
	finish(sim)
func finish(sim: Simulation):
	sim.free()
	for failure in failures: printerr("ATLAS_DIPLOMACY_WAKES_FAIL ", failure)
	print("ATLAS_DIPLOMACY_WAKES_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
