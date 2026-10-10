extends SceneTree
const Codec=preload("res://.dbg/state_codec.gd")
func _initialize(): call_deferred("run")
func run():
	var sim: Simulation=Codec.new().restore("res://.dbg/frozen-day240.bin","res://.dbg/campaign_profile_sim.gd")
	root.add_child(sim);sim.paused=true;sim.tick_phase_profiling_enabled=true
	var rows := []
	for day in range(3):
		sim.segments.clear();sim.requests.clear();sim._advance_day(false)
		rows.append({"day":sim.state.day,"segments":sim.segments.duplicate(true),"path_requests":sim.requests.duplicate(true),"phases":sim.tick_profile_last_usec})
		print(JSON.stringify(rows[-1]));await process_frame
	FileAccess.open("res://.dbg/campaign-subprofile.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	sim.free();quit()
