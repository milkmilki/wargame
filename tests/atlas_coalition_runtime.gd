extends SceneTree
## Exercise the default Eurasia cache in the real frame-sliced daily entry.
func _initialize(): call_deferred("run")
func run():
	var payload: Dictionary = preload("res://tests/atlas_military_inputs.gd").eurasia_military()
	var a := GameState.new(); a.generate_from_atlas(payload.duplicate(true))
	var b := GameState.new(); b.generate_from_atlas(payload.duplicate(true))
	var before := Simulation.new(); root.add_child(before); before.setup(a); before.paused = true
	before.ai_coalition_component_cache_disabled = true
	var after := Simulation.new(); root.add_child(after); after.setup(b); after.paused = true
	var log := DebugRunLog.new(); log.begin("tests/atlas_coalition_runtime.gd")
	log.world_started(b, {"days": 65, "settlement_mask": payload.data.options.settlement_mask,
		"simulation_options": payload.simulation_options}, "coalition_runtime")
	for day in range(60):
		before._advance_day(false); after._advance_day(false)
		if a.day % 15 == 0: print("ATLAS_COALITION_RUNTIME_WARM ", a.day); await process_frame
	var same := var_to_bytes(NativeSnapshotBuilder.build(a)) == var_to_bytes(NativeSnapshotBuilder.build(b))
	var exercised_war := not b.campaign_fronts.is_empty()
	for day in range(5):
		before._advance_day(false); await after.advance_one_day()
		same = same and var_to_bytes(NativeSnapshotBuilder.build(a)) == var_to_bytes(NativeSnapshotBuilder.build(b))
		exercised_war = exercised_war or not b.campaign_fronts.is_empty()
		log.checkpoint(b)
		print("ATLAS_COALITION_RUNTIME_DAY ", b.day, " equivalent=", same)
	print("ATLAS_COALITION_RUNTIME_RESULT pid=", OS.get_process_id(), " day=", b.day,
		" equivalent=", same, " war=", exercised_war)
	if not same: printerr("ATLAS_COALITION_RUNTIME_FAIL complete daily state differs")
	if not exercised_war: printerr("ATLAS_COALITION_RUNTIME_FAIL no active campaign tested")
	before.free(); after.free(); quit(0 if same and exercised_war else 1)
