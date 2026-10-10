extends SceneTree
const Codec=preload("res://.dbg/state_codec.gd")
func _initialize(): call_deferred("run")
func run():
	var sim: Simulation=Codec.new().restore("res://.dbg/frozen-day240.bin","res://.dbg/movement_profile_sim.gd")
	root.add_child(sim);sim.paused=true;sim.tick_phase_profiling_enabled=true
	var rows := []
	for day in range(3):
		for key in ["travel_calls","edge_unit_calls","events","arrivals","travel_us","edge_unit_us","encounter_us","block_us","junction_us"]: sim.set(key,0)
		sim._advance_day(false)
		var row := {"day":sim.state.day,"armies":sim.state.armies.size(),"phases":sim.tick_profile_last_usec}
		for key in ["travel_calls","edge_unit_calls","events","arrivals","travel_us","edge_unit_us","encounter_us","block_us","junction_us"]: row[key]=sim.get(key)
		rows.append(row);print(JSON.stringify(row));await process_frame
	FileAccess.open("res://.dbg/movement-subprofile.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	sim.free();quit()
