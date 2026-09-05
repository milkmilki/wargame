extends SceneTree

const TIMEOUT_MSEC: int = 20000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := GameState.new()
	state.generate_world(12345)
	var history := PoliticalHistory.new()
	history.reset(state)

	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.paused = true
	var overlay := MapRenderer.new()
	root.add_child(overlay)
	overlay.setup(state, simulation)
	overlay.set_world_layer_visible(false)
	var map_3d := StrategicMap3D.new()
	root.add_child(map_3d)
	map_3d.setup(state, simulation, overlay)

	var started := Time.get_ticks_msec()
	while map_3d._terrain == null or map_3d._terrain.land_cell_count() <= 0:
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			push_error("POLITICAL_HISTORY_3D_TIMEOUT")
			quit(1)
			return
		await process_frame
	await process_frame
	if map_3d._armies.multimesh.instance_count <= 0:
		push_error("POLITICAL_HISTORY_3D_FIXTURE_HAS_NO_ARMIES")
		quit(1)
		return

	var historical_state := history.build_view_state(state, 0)
	overlay.set_display_state(
		historical_state, true, MapRenderer.MapMode.POLITICAL
	)
	map_3d.set_display_state(
		historical_state, MapRenderer.MapMode.POLITICAL
	)
	var first_task_id := map_3d._country_visual_task_id
	var preview_started := Time.get_ticks_usec()
	overlay.set_display_state(
		state, false, MapRenderer.MapMode.POLITICAL, true
	)
	map_3d.set_display_state(
		state, MapRenderer.MapMode.POLITICAL, true
	)
	var preview_usec := Time.get_ticks_usec() - preview_started
	if first_task_id < 0 or map_3d._country_visual_task_id != first_task_id:
		push_error("history preview must not wait for the active country task")
		quit(1)
		return
	if preview_usec > 100000:
		push_error("history preview exceeded 100ms: %dus" % preview_usec)
		quit(1)
		return
	if not map_3d.history_preview_active():
		push_error("history preview must expose its lightweight render state")
		quit(1)
		return
	for label in map_3d._nation_labels:
		if label.visible:
			push_error("history preview must hide stale nation labels")
			quit(1)
			return

	var military_layers: Array[MultiMeshInstance3D] = [
		map_3d._army_bases,
		map_3d._armies,
		map_3d._army_symbol_a,
		map_3d._army_symbol_b,
		map_3d._army_morale_backs,
		map_3d._army_morale_bars,
		map_3d._battles,
		map_3d._battle_rings,
		map_3d._battle_cross_a,
		map_3d._battle_cross_b,
	]
	for layer in military_layers:
		if layer.multimesh != null and layer.multimesh.instance_count != 0:
			push_error("POLITICAL_HISTORY_3D_MILITARY_LAYER_VISIBLE: %s" % layer.name)
			quit(1)
			return
	for label in map_3d._battle_labels:
		if label.visible:
			push_error("POLITICAL_HISTORY_3D_BATTLE_LABEL_VISIBLE")
			quit(1)
			return
	map_3d._finish_country_visual_task(false)

	print("POLITICAL_HISTORY_3D_TEST PASS preview=%.2fms" % (
		float(preview_usec) / 1000.0
	))
	quit(0)
