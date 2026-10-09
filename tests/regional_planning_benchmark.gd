extends SceneTree
## Fixed military workload matching the pre-pair baseline, with current pair invariants.

const SAMPLES: int = 12

class ProfiledGameState extends "res://tests/support/grid_world.gd":
	var pair_sync_usec: int = 0
	var pair_sync_calls: int = 0

	func sync_campaign_pairs(components: Array[Dictionary]) -> void:
		var started := Time.get_ticks_usec()
		super.sync_campaign_pairs(components)
		pair_sync_usec += Time.get_ticks_usec() - started
		pair_sync_calls += 1

class ProfiledSimulation extends Simulation:
	var objective_usec: int = 0
	var allocation_usec: int = 0
	var execution_usec: int = 0
	var objective_calls: int = 0
	var segments: Dictionary = {}

	func _record_segment(name: String, started: int) -> void:
		var data: Dictionary = segments.get(name, {"usec": 0, "calls": 0})
		data["usec"] += Time.get_ticks_usec() - started
		data["calls"] += 1
		segments[name] = data

	func _prepare_coalition_campaign_batch() -> Array[Dictionary]:
		var started := Time.get_ticks_usec()
		var result := super._prepare_coalition_campaign_batch()
		_record_segment("prepare_batch", started)
		return result

	func _plan_coalition_component(component: Dictionary, defense_centers: Array[int], objective_cache: Dictionary) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._plan_coalition_component(component, defense_centers, objective_cache)
		_record_segment("plan_component", started)
		return result

	func _reconcile_campaign_battlefields() -> void:
		var started := Time.get_ticks_usec()
		super._reconcile_campaign_battlefields()
		_record_segment("reconcile_battlefields", started)

	func _plan_campaign_pair(pair: CoalitionCampaignPair, cache: Dictionary) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._plan_campaign_pair(pair, cache)
		_record_segment("plan_pair", started)
		return result

	func _pair_proposal_force(pair: CoalitionCampaignPair, members: Array[int]) -> int:
		var started := Time.get_ticks_usec()
		var result := super._pair_proposal_force(pair, members)
		_record_segment("proposal_force", started)
		return result

	func _pair_proposal(pair: CoalitionCampaignPair, members: Array[int], slot: Dictionary, cache: Dictionary) -> Dictionary:
		var started := Time.get_ticks_usec()
		var result := super._pair_proposal(pair, members, slot, cache)
		_record_segment("proposal", started)
		return result

	func _select_component_objective(component: Dictionary, objective_cache: Dictionary, excluded_centers: Dictionary, expedition_only: bool = false, camp_counterattack: bool = false) -> Dictionary:
		var started := Time.get_ticks_usec()
		var result := super._select_component_objective(component, objective_cache, excluded_centers, expedition_only, camp_counterattack)
		_record_segment("select_objective", started)
		return result

	func _campaign_deployment_distance(army: Army, target: int) -> float:
		var started := Time.get_ticks_usec()
		var result := super._campaign_deployment_distance(army, target)
		_record_segment("deployment_distance", started)
		return result

	func _coalition_allocation_candidates(front: CoalitionCampaignFront, armies: Array[Army], target: int) -> Array[Dictionary]:
		var started := Time.get_ticks_usec()
		var result := super._coalition_allocation_candidates(front, armies, target)
		_record_segment("allocation_candidates", started)
		return result

	func _cached_campaign_objective(nation_id: int, target_id: int, cache: Dictionary, excluded: Dictionary = {}, camp_counterattack: bool = false) -> Dictionary:
		var started := Time.get_ticks_usec()
		var result := super._cached_campaign_objective(nation_id, target_id, cache, excluded, camp_counterattack)
		objective_usec += Time.get_ticks_usec() - started
		objective_calls += 1
		_record_segment("cached_objective", started)
		return result

	func _allocate_coalition_fronts(component: Dictionary) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._allocate_coalition_fronts(component)
		allocation_usec += Time.get_ticks_usec() - started
		_record_segment("allocate_fronts", started)
		return result

	func _manage_administrative_campaign(front: CoalitionCampaignFront) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._manage_administrative_campaign(front)
		execution_usec += Time.get_ticks_usec() - started
		_record_segment("execute_offense", started)
		return result


func _init() -> void:
	var result := _run_benchmark()
	var performance_ok := true
	var baseline_ms := float(OS.get_environment("REGIONAL_BENCH_BASELINE_MS"))
	if baseline_ms > 0.0:
		var average_ms := float(result["average"]) / 1000.0
		performance_ok = average_ms <= baseline_ms * 1.05
		print("PLANNING_PERFORMANCE_BUDGET baseline_ms=%.3f current_ms=%.3f regression_pct=%.2f verdict=%s" % [
			baseline_ms, average_ms, 100.0 * (average_ms / baseline_ms - 1.0),
			"PASS" if performance_ok else "FAIL"])
	quit(0 if bool(result["audit_ok"]) and performance_ok else 1)


func _run_benchmark() -> Dictionary:
	var state: GameState = ProfiledGameState.new() if OS.get_environment("REGIONAL_BENCH_PROFILE") == "1" else preload("res://tests/support/grid_world.gd").new()
	state.generate_world(12345, 40)
	state.region_ids.fill(0)
	state.region_analysis_revision += 1
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
		nation.treasury_gold = 1000000
		nation.manpower_pool = 1000000
	for city in state.cities:
		city.gold_per_month = 100
		city.food_per_half_year = 10000
		city.manpower_per_month = 1000
	for a in range(40):
		for b in range(a + 1, 40):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.ALLIED
				if (a < 20) == (b < 20) else GameState.DiplomaticRelation.WAR)
	var war_id := state.war_id_between(0, 20)
	for a in range(20):
		for b in range(20, 40):
			state.merge_war_ids(war_id, state.war_id_between(a, b))
	var simulation: Simulation = ProfiledSimulation.new() if OS.get_environment("REGIONAL_BENCH_PROFILE") == "1" else Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	var durations: Array[int] = []
	var path_cache_new_entries: Array[int] = []
	if state is ProfiledGameState:
		(state as ProfiledGameState).pair_sync_usec = 0
		(state as ProfiledGameState).pair_sync_calls = 0
	var violations := {"overfull_pairs": 0, "duplicate_defenses": 0, "duplicate_bindings": 0}
	for sample in range(SAMPLES + 3):
		state.day = 10 * (sample + 1)
		state.clear_campaign_fronts()
		for army in state.armies:
			army.campaign_war_id = -1
			army.campaign_front_id = -1
			army.path.clear()
			army.state = Army.State.IDLE
			army.on_edge = false
			army.size = 15000
			army.morale = 100.0
			army.ai_order_until_day = 0
			army.defensive_deployment_until_day = 0
		simulation._ai_planned_armies.clear()
		var previous_path_entries := _path_cache_entry_count(simulation)
		var started := Time.get_ticks_usec()
		simulation._manage_coalition_campaigns()
		var duration := Time.get_ticks_usec() - started
		path_cache_new_entries.append(_path_cache_entry_count(simulation) - previous_path_entries)
		_audit_campaign_state(state, violations)
		if sample >= 3:
			durations.append(duration)
	var total := 0
	for duration in durations:
		total += duration
	print("REGIONAL_PLANNING_BENCHMARK samples=%d avg_ms=%.3f peak_ms=%.3f fronts=%d" % [
		SAMPLES, float(total) / float(SAMPLES) / 1000.0,
		float(durations.max()) / 1000.0, state.campaign_fronts.size()])
	var battlefield_count := 0
	for pair_value in state.campaign_pairs.values():
		battlefield_count += (pair_value as CoalitionCampaignPair).battlefields.size()
	print("PAIR_PLANNING_AUDIT pairs=%d battlefields=%d overfull_pairs=%d duplicate_defenses=%d duplicate_bindings=%d" % [
		state.campaign_pairs.size(), battlefield_count, violations["overfull_pairs"],
		violations["duplicate_defenses"], violations["duplicate_bindings"]])
	print("PLANNING_AI_PATH_CACHE new_entries_by_round=%s total_entries=%d" % [
		path_cache_new_entries, _path_cache_entry_count(simulation)])
	if simulation is ProfiledSimulation:
		var profiled := simulation as ProfiledSimulation
		print("PLANNING_PROFILE objectives_ms=%.2f calls=%d allocation_ms=%.2f execution_ms=%.2f" % [
			float(profiled.objective_usec) / 1000.0, profiled.objective_calls,
			float(profiled.allocation_usec) / 1000.0, float(profiled.execution_usec) / 1000.0])
		for segment_name in profiled.segments:
			var segment: Dictionary = profiled.segments[segment_name]
			print("PLANNING_SEGMENT name=%s inclusive_ms=%.3f calls=%d" % [
				segment_name, float(segment["usec"]) / 1000.0, segment["calls"]])
	if state is ProfiledGameState:
		var profiled_state := state as ProfiledGameState
		print("PLANNING_SEGMENT name=state_sync_pairs inclusive_ms=%.3f calls=%d" % [
			float(profiled_state.pair_sync_usec) / 1000.0, profiled_state.pair_sync_calls])
	var ruler_started := Time.get_ticks_usec()
	for _query in range(10000):
		RulerProfile.offensive_allowed(state.nations[0])
	print("RULER_POLICY_QUERY_PROFILE calls=10000 total_ms=%.3f" % [
		float(Time.get_ticks_usec() - ruler_started) / 1000.0])
	if FileAccess.file_exists("res://scripts/core/regional_strategy.gd"):
		var strategy = load("res://scripts/core/regional_strategy.gd")
		print("REGIONAL_PROFILE queries=%d geometry=%d control=%d" % [
			strategy.query_count, strategy.geometry_build_count, strategy.control_build_count])
	var snapshot := var_to_bytes(NativeSnapshotBuilder.build(state)).hex_encode().sha256_text()
	print("PLANNING_SNAPSHOT sha256=%s" % snapshot)
	simulation.free()
	return {"average": float(total) / float(SAMPLES), "peak": durations.max(), "snapshot": snapshot,
		"audit_ok": violations.values().all(func(value: int) -> bool: return value == 0)}


func _audit_campaign_state(state: GameState, violations: Dictionary) -> void:
	for pair_value in state.campaign_pairs.values():
		if (pair_value as CoalitionCampaignPair).battlefields.size() > CoalitionCampaignPair.MAX_BATTLEFIELDS:
			violations["overfull_pairs"] += 1
	var defense_keys := {}
	var assigned_fronts := {}
	for front_value in state.campaign_fronts.values():
		var front := front_value as CoalitionCampaignFront
		if front.mode == CoalitionCampaignFront.Mode.DEFENSE and not front.retiring:
			var key := "%d:%s:%d" % [front.war_id, str(front.participant_nation_ids), front.center_city_id]
			if defense_keys.has(key):
				violations["duplicate_defenses"] += 1
			defense_keys[key] = true
		for army_id in front.army_assignments:
			if assigned_fronts.has(army_id):
				violations["duplicate_bindings"] += 1
			assigned_fronts[army_id] = front.front_id
	for army in state.armies:
		if army.campaign_front_id >= 0 and int(assigned_fronts.get(army.id, -1)) != army.campaign_front_id:
			violations["duplicate_bindings"] += 1


func _path_cache_entry_count(simulation: Simulation) -> int:
	var count := 0
	for cache in simulation._ai_path_field_cache_by_nation.values():
		count += (cache as Dictionary).size()
	return count
