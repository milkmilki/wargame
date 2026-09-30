extends SceneTree
## Fixed military workload; usable against the previous revision as well.

const SAMPLES: int = 12

class ProfiledSimulation extends Simulation:
	var objective_usec: int = 0
	var allocation_usec: int = 0
	var execution_usec: int = 0
	var objective_calls: int = 0

	func _cached_campaign_objective(nation_id: int, target_id: int, cache: Dictionary, excluded: Dictionary = {}) -> Dictionary:
		var started := Time.get_ticks_usec()
		var result := super._cached_campaign_objective(nation_id, target_id, cache, excluded)
		objective_usec += Time.get_ticks_usec() - started
		objective_calls += 1
		return result

	func _allocate_coalition_fronts(component: Dictionary) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._allocate_coalition_fronts(component)
		allocation_usec += Time.get_ticks_usec() - started
		return result

	func _manage_administrative_campaign(front: CoalitionCampaignFront) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._manage_administrative_campaign(front)
		execution_usec += Time.get_ticks_usec() - started
		return result


func _init() -> void:
	var state := GameState.new()
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
		var started := Time.get_ticks_usec()
		simulation._manage_coalition_campaigns()
		var duration := Time.get_ticks_usec() - started
		if sample >= 3:
			durations.append(duration)
	var total := 0
	for duration in durations:
		total += duration
	print("REGIONAL_PLANNING_BENCHMARK samples=%d avg_ms=%.3f peak_ms=%.3f fronts=%d" % [
		SAMPLES, float(total) / float(SAMPLES) / 1000.0,
		float(durations.max()) / 1000.0, state.campaign_fronts.size()])
	if simulation is ProfiledSimulation:
		var profiled := simulation as ProfiledSimulation
		print("PLANNING_PROFILE objectives_ms=%.2f calls=%d allocation_ms=%.2f execution_ms=%.2f" % [
			float(profiled.objective_usec) / 1000.0, profiled.objective_calls,
			float(profiled.allocation_usec) / 1000.0, float(profiled.execution_usec) / 1000.0])
	if FileAccess.file_exists("res://scripts/core/regional_strategy.gd"):
		var strategy = load("res://scripts/core/regional_strategy.gd")
		print("REGIONAL_PROFILE queries=%d geometry=%d control=%d" % [
			strategy.query_count, strategy.geometry_build_count, strategy.control_build_count])
	simulation.free()
	quit(0)
