extends SceneTree
## Army rendering must consume committed simulation state. Rebuilding while a
## sliced day is in progress wastes every frame and exposes partial day state.


func _init() -> void:
	var state := GameState.new()
	state.day = 7
	var simulation := Simulation.new()
	simulation.state = state
	simulation._runtime_day_in_progress = true
	var map_3d := StrategicMap3D.new()
	map_3d.state = state
	map_3d.sim = simulation
	map_3d._army_instances_initialized = true
	map_3d._last_army_instances_day = 6

	var deferred := not map_3d._should_update_army_instances()
	simulation._runtime_day_in_progress = false
	var refreshed_after_commit := map_3d._should_update_army_instances()
	var ok := deferred and refreshed_after_commit
	print("ARMY_RENDER_COMMIT_BOUNDARY_%s" % ("OK" if ok else "FAILED"))
	quit(0 if ok else 1)
