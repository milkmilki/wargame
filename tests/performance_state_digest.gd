extends SceneTree
## Manual before/after guard: hash the native gameplay snapshot on every day.
## Use on both source trees; timing belongs in tick_compute_budget_probe.gd.


func _init() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(12345, 40, 160)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	var daily_hashes: Array[String] = []
	for day in range(365):
		sim._advance_day(false)
		var snapshot := NativeSnapshotBuilder.build(state)
		# Include the deterministic RNG and the clock explicitly in the guard.
		snapshot["performance_clock_rng"] = [state.day, state.month, state.rng.seed, state.rng.state]
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(var_to_bytes(snapshot))
		var checksum := digest.finish().hex_encode()
		daily_hashes.append(checksum)
		if state.day % 30 == 0 or state.day == 365:
			print("STATE_SHA256 day=%d digest=%s" % [state.day, checksum])
	var sequence := HashingContext.new()
	sequence.start(HashingContext.HASH_SHA256)
	sequence.update(var_to_bytes(daily_hashes))
	print("STATE_SEQUENCE_SHA256 days=%d digest=%s" % [daily_hashes.size(), sequence.finish().hex_encode()])
	sim.free()
	quit()
