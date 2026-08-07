extends SceneTree
## 正式地图驻防规划隔离基准。手动运行，不纳入快速回归。

const ITERATIONS: int = 100


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	var war_mode := (
		OS.get_environment(
			"AI_DEFENSE_BENCHMARK_WAR"
		) == "1"
	)
	if war_mode:
		state.set_diplomatic_relation(
			0,
			1,
			GameState.DiplomaticRelation.WAR
		)
		state.set_diplomatic_relation(
			2,
			3,
			GameState.DiplomaticRelation.WAR
		)
	var fixtures: Array[Dictionary] = []
	var shared_path_cache := {}
	var shared_threat_cache := {}
	for nation in state.nations:
		var view := AiWorldView.build(
			state,
			nation.id,
			shared_path_cache
		)
		fixtures.append({
			"view": view,
			"snapshot": StrategicMapSnapshot.build(view),
			"threat": ThreatField.build(
				view,
				shared_threat_cache
			),
		})
	for fixture in fixtures:
		fixture["previous_plan"] = CityDefensePlan.build(
			fixture["view"],
			fixture["snapshot"],
			fixture["threat"]
		)
	var started := Time.get_ticks_usec()
	var assignments := 0
	var build_usec := 0
	var role_assignment_usec := 0
	var topology_reuses := 0
	var dynamic_reuses := 0
	for _iteration in range(ITERATIONS):
		for fixture in fixtures:
			var plan := CityDefensePlan.new()
			plan.view = fixture["view"]
			plan.snapshot = fixture["snapshot"]
			plan.threat = fixture["threat"]
			var phase_started := Time.get_ticks_usec()
			plan._prepare_frontier_topology()
			plan.input_signature = plan._input_signature()
			var previous: CityDefensePlan = (
				fixture["previous_plan"]
			)
			if (
				previous.topology == plan.topology
				and previous.input_signature
					== plan.input_signature
			):
				plan._reuse_dynamic_plan(previous)
			else:
				plan._build()
			build_usec += (
				Time.get_ticks_usec() - phase_started
			)
			phase_started = Time.get_ticks_usec()
			plan._assign_role_based_defense()
			role_assignment_usec += (
				Time.get_ticks_usec() - phase_started
			)
			if plan.topology_reused:
				topology_reuses += 1
			if plan.dynamic_plan_reused:
				dynamic_reuses += 1
			fixture["previous_plan"] = plan
			assignments += plan.assigned_city_by_army.size()
	var elapsed_usec := Time.get_ticks_usec() - started
	print(
		(
			"mode=%s iterations=%d plans=%d assignments=%d elapsed_ms=%.3f "
			+ "us_per_plan=%.3f build_us_per_plan=%.3f "
			+ "role_us_per_plan=%.3f topology_reuses=%d "
			+ "dynamic_reuses=%d"
		)
		% [
			"war" if war_mode else "peace",
			ITERATIONS,
			ITERATIONS * fixtures.size(),
			assignments,
			float(elapsed_usec) / 1000.0,
			float(elapsed_usec)
				/ float(ITERATIONS * fixtures.size()),
			float(build_usec)
				/ float(ITERATIONS * fixtures.size()),
			float(role_assignment_usec)
				/ float(ITERATIONS * fixtures.size()),
			topology_reuses,
			dynamic_reuses,
		]
	)
	quit()
