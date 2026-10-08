extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var template: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-world-12345.json"))
	var state:=GameState.new();state.generate_from_map_definition(template,12345)
	var sim:=Simulation.new();root.add_child(sim);sim.setup(state);sim.paused=true
	var original: Array[PackedVector2Array]=[]
	for edge in state.edges: original.append(edge.map_path.duplicate())
	for day in range(365):
		sim._advance_day()
		if not state.territory_structure_valid(): printerr("ATLAS_SIMULATION invalid territory day ",state.day);quit(1);return
		if not state.river_features.is_empty() or not state.river_paths.is_empty(): printerr("ATLAS_SIMULATION rivers reappeared");quit(1);return
		for i in range(state.edges.size()):
			if state.edges[i].map_path!=original[i]: printerr("runtime rebuilt static road");quit(1);return
		if (day+1)%30==0: print("ATLAS_SIMULATION day=",state.day," trade_routes=",state.trade_routes.size()," wars=",state.war_objectives.size());await process_frame
	print("ATLAS_SIMULATION_PASS seed=12345 days=365 roads=",state.edges.size()," trade_routes=",state.trade_routes.size());quit()
