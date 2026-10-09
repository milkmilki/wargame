extends SceneTree
func _init() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(12345, 40, 500)
	var sim := Simulation.new()
	sim.setup(state)
	var flows := Simulation.monthly_gold_flows(state)
	var elapsed := 0
	var peak := 0
	var report_time := 0
	var capacity_time := 0
	var input_time := 0
	for sample in range(13):
		var cache := {"monthly_gold_flows": flows}
		var start := Time.get_ticks_usec()
		if OS.get_environment("RESOURCE_PROFILE_INPUT") == "1":
			load("res://scripts/ai/diplomacy_ai.gd").call("_resource_forecast_inputs", state, cache)
		var input_done := Time.get_ticks_usec()
		for nation in state.nations:
			DiplomacyAI.resource_report(state, nation.id, cache)
		var midway := Time.get_ticks_usec()
		for nation in state.nations:
			DiplomacyAI.force_capacity_report(state, nation.id, -1, cache)
		var duration := Time.get_ticks_usec() - start
		if sample > 0:
			elapsed += duration
			peak = maxi(peak, duration)
			report_time += midway - start
			capacity_time += Time.get_ticks_usec() - midway
			input_time += input_done - start
	print("RESOURCE_PLANNING_BENCH samples=12 avg_ms=%.3f peak_ms=%.3f" % [elapsed / 12000.0, peak / 1000.0])
	print("RESOURCE_REPORT_MS=%.3f CAPACITY_MS=%.3f" % [report_time / 12000.0, capacity_time / 12000.0])
	print("RESOURCE_INPUT_MS=%.3f" % (input_time / 12000.0))
	sim.free()
	quit()
