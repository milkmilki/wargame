extends SceneTree
const Codec=preload("res://.dbg/state_codec.gd")
func _initialize(): call_deferred("run")
func run():
	var payload: Dictionary=FileAccess.open("res://.dbg/atlas-military-eurasia-mask.bin",FileAccess.READ).get_var(false)
	assert(payload.data.options.settlement_mask==preload("res://scripts/atlas/settlement_mask.gd").EURASIA)
	var state := GameState.new(); state.generate_from_atlas(payload)
	var sim := Simulation.new(); sim.setup(state); sim.paused=true; sim.tick_phase_profiling_enabled=true; root.add_child(sim)
	var file := FileAccess.open("res://.dbg/eurasia-baseline.jsonl",FileAccess.WRITE)
	for day in range(750):
		sim._advance_day(false)
		assert(state.territory_structure_valid() and state._battle_group_structure_valid())
		var row := {"day":state.day,"profile":sim.tick_profile_last_usec.duplicate(),"armies":state.armies.size(),"wars":state.war_relation_ids.size(),"fronts":state.campaign_fronts.size()}
		if state.day==720:
			Codec.new().save("res://.dbg/eurasia-frozen-day720.bin",sim)
			var context := HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(var_to_bytes(NativeSnapshotBuilder.build(state)))
			FileAccess.open("res://.dbg/eurasia-frozen-manifest.json",FileAccess.WRITE).store_string(JSON.stringify({"seed":1,"day":720,"mask":payload.data.options.settlement_mask,"pid":OS.get_process_id(),"nodes":state.cities.size(),"settlements":state.land_cities().size(),"sha256":context.finish().hex_encode()},"  "))
		if state.day>720:
			var context := HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(var_to_bytes(NativeSnapshotBuilder.build(state)));row.sha256=context.finish().hex_encode()
		file.store_line(JSON.stringify(row));file.flush()
		if state.day%30==0: print("EURASIA_BASELINE day=",state.day," total_ms=",row.profile.total/1000.," armies=",row.armies," wars=",row.wars)
		await process_frame
	file.close();sim.free();quit()
