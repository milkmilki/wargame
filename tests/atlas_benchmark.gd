extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var source:=OS.get_environment("ATLAS_SOURCE")
	var index:=OS.get_environment("ATLAS_BENCH_INDEX")
	var state:=GameState.new();var started:=Time.get_ticks_msec()
	if not state.generate_world(12345,40,500,"",{},12345,"",source): printerr(state.last_generation_error);quit(1);return
	var generation:=Time.get_ticks_msec()-started
	var template:=MapDefinition.from_state(state)
	var file:=FileAccess.open("res://.dbg/atlas-benchmark-world-"+str(MapSource.atlas_roads(source))+".json",FileAccess.WRITE);file.store_string(JSON.stringify(template));file.close()
	var sim:=Simulation.new();root.add_child(sim);sim.setup(state);sim.paused=true
	var renderer:=MapRenderer.new();root.add_child(renderer);started=Time.get_ticks_msec();renderer.setup(state,sim)
	var atlas:=renderer.visual_atlas();var cold:=Time.get_ticks_msec()-started
	var revision:=hash(atlas.city_id.get_data());var switch_times: Array[int]=[]
	for mode in [MapRenderer.MapMode.LOYALTY,MapRenderer.MapMode.TRADE,MapRenderer.MapMode.REGION,MapRenderer.MapMode.POLITICAL]:
		started=Time.get_ticks_msec();renderer.set_map_mode(mode);renderer.visual_atlas();switch_times.append(Time.get_ticks_msec()-started)
		if hash(renderer.visual_atlas().city_id.get_data())!=revision: printerr("mode rebuilt geometry");quit(1);return
	var report: Dictionary={"source":source,"seed":12345,"cities":500,"nations":40,"generation_ms":generation,"display_cold_ms":cold,"switch_ms":switch_times,"metadata":state.generation_metadata}
	file=FileAccess.open("res://.dbg/atlas-benchmark-"+str(MapSource.atlas_roads(source))+"-"+index+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	print("ATLAS_BENCHMARK ",JSON.stringify(report));quit()
