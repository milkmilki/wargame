extends SceneTree
## Abstract strategy may run less often; territorial/diplomatic emergencies,
## war-report wakeups and normal nation coverage must remain dependable.
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func _initialize(): call_deferred("run")
func run():
	var state := GameState.new(); state._reset_world(1)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 40, false)
	state.atlas_layout = {"model":"cadence-test"}; state.uses_heightmap = true
	var sim := Simulation.new(); sim.state = state; sim.paused = true
	if not sim.has_method("_ai_decision_due_today"):
		printerr("ATLAS_AI_CADENCE_FAIL Atlas batching is not implemented")
		sim.free(); quit(1); return
	check(sim._ai_decision_interval_days() == 15, "Atlas regular strategy defaults to fifteen days")
	sim._ai_last_decision_day = 0; sim._ai_regular_through_day = 0
	var last_seen := {}; var scheduled_days := 0
	for day in range(1, 46):
		state.day = day
		check(sim._ai_decision_due_today(15) == (day % 3 == 0), "quiet world uses only scheduled batches")
		var order: Array[int] = sim._regular_ai_nation_order(15)
		check(order.size() == order.duplicate().reduce(func(acc: Dictionary, n): acc[n]=true; return acc, {}).size(), "no duplicate scheduled nations")
		if day % 3 != 0:
			check(order.is_empty(), "quiet days do not build regular nation contexts")
		else:
			scheduled_days += 1
			for nation in order:
				if last_seen.has(nation): check(day-int(last_seen[nation]) <= 18, "no nation starvation across stagger windows")
				last_seen[nation] = day
			sim._ai_regular_through_day = day
	check(scheduled_days == 15 and last_seen.size() == 40, "all nations receive regular decisions")
	state.day = 46; sim._ai_regular_through_day = 45
	sim._queue_ai_nation_wake(7)
	check(not sim._ai_decision_due_today(15), "routine arrival warning is coalesced, not a full immediate batch")
	check(sim._due_forced_ai_nations().is_empty(), "future local wake is not consumed early")
	state.day = 48
	check(sim._due_forced_ai_nations().has(7), "local warning wakes no later than the next batch")
	sim._ai_forced_nations.clear(); state.day = 49
	sim._queue_ai_nation_wake(3, true)
	check(sim._ai_decision_due_today(15) and sim._due_forced_ai_nations().has(3), "hard local emergency runs on a quiet day")
	sim._queue_ai_nation_wake(3)
	check(sim._due_forced_ai_nations().has(3), "routine warning cannot postpone a hard emergency")
	check(sim._regular_ai_nation_order(15).is_empty() and sim._ai_regular_through_day == 45, "urgent-only decisions do not consume the regular backlog")
	sim._ai_forced_nations.clear(); sim._coalition_campaign_wake_day = 49
	check(sim._ai_decision_due_today(15), "battle report retains next-day coalition response")
	sim._coalition_campaign_wake_day = 2147483647; sim._ai_last_decision_day = -1
	check(sim._ai_decision_due_today(15) and sim._regular_ai_nation_order(15, true).size() == 40, "global diplomacy invalidation still refreshes all nations")
	sim._ai_last_decision_day = 45
	sim.ai_policy_overrides[0] = func(_s, _n, _sim): pass
	check(sim._ai_decision_interval_days() == 10 and not sim._regular_ai_nation_order(10).is_empty(), "custom military policies preserve their existing schedule")
	sim.ai_policy_overrides.clear(); state.atlas_layout.clear(); state.uses_heightmap = false
	check(sim._ai_decision_interval_days() == 5, "legacy grid worlds preserve their five-day interval")
	sim.free()
	for failure in failures: printerr("ATLAS_AI_CADENCE_FAIL ", failure)
	print("ATLAS_AI_CADENCE_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
