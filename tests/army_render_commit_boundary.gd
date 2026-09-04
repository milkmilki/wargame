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
	map_3d.overlay = MapRenderer.new()
	map_3d._army_instances_initialized = true
	map_3d._last_army_instances_day = 6
	map_3d._last_army_icon_scale = map_3d.overlay.army_icon_scale()

	var deferred := not map_3d._should_update_army_instances()
	map_3d._last_army_instances_day = state.day
	simulation._runtime_day_in_progress = false
	var stable_after_commit := not map_3d._should_update_army_instances()
	map_3d._last_army_instances_day = state.day - 1
	var refreshed_after_commit := map_3d._should_update_army_instances()
	var scaled := StrategicMap3D.scaled_counter_transform(
		Transform3D(Basis.IDENTITY, Vector3(2.0, 3.0, 4.0)),
		Vector3(2.0, 1.0, 2.0),
		0.5
	)
	var scaled_during_runtime := (
		is_equal_approx(scaled.basis.get_scale().x, 0.5)
		and scaled.origin.is_equal_approx(Vector3(2.0, 2.0, 3.0))
	)
	var ok := (
		deferred
		and stable_after_commit
		and refreshed_after_commit
		and scaled_during_runtime
	)
	print("ARMY_RENDER_COMMIT_BOUNDARY_%s" % ("OK" if ok else "FAILED"))
	quit(0 if ok else 1)
