extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://main.tscn") as PackedScene
	var main := packed.instantiate()
	main.use_grid_world = true
	main.use_3d_map = false
	main.nation_count = GameState.NATION_COUNT
	root.add_child(main)
	await process_frame

	var sim := main.get_node("Simulation") as Simulation
	var renderer := main.get_node("MapRenderer") as MapRenderer
	var timeline := main.get_node("HistoryTimeline") as HistoryTimeline
	var preview_indices: Array[int] = []
	var final_indices: Array[int] = []
	timeline.preview_requested.connect(func(index: int) -> void:
		preview_indices.append(index)
	)
	timeline.position_requested.connect(func(index: int) -> void:
		final_indices.append(index)
	)
	var timeline_rect: Rect2 = timeline._panel.get_global_rect()
	var viewport_rect := root.get_visible_rect()
	if not viewport_rect.encloses(timeline_rect):
		_fail("history timeline %s must fit inside viewport %s" % [
			str(timeline_rect), str(viewport_rect),
		])
	if timeline_rect.size.x < 600.0 or timeline_rect.size.y < 30.0:
		_fail("history timeline must keep a stable usable size")
	timeline._selected_index = 0
	timeline._emit_preview_position()
	timeline._emit_final_position()
	if preview_indices != [0] or final_indices != [0]:
		_fail("timeline must distinguish drag previews from final selections")
	sim.paused = false
	main._on_history_position_requested(0, true)
	if not sim.paused:
		_fail("selecting history must pause simulation")
	if not renderer.history_mode() or renderer.state.day != 0:
		_fail("renderer must switch to the selected historical day")
	if not renderer.state.armies.is_empty() or not renderer.state.battles.is_empty():
		_fail("historical renderer state must hide military entities")

	main._on_history_position_requested(
		main._political_history.snapshot_count(), true
	)
	if renderer.history_mode() or renderer.state != main.state:
		_fail("rightmost position must restore the live state")
	if sim.paused:
		_fail("leaving history must restore the previous running state")
	if timeline == null or timeline.selected_index() < 0:
		_fail("history timeline must be present in the main scene")

	main._on_history_position_requested(0, true)
	main._start_new_game(54321)
	if renderer.history_mode() or renderer.state != main.state:
		_fail("starting a new world from history must restore live rendering")
	if sim.paused:
		_fail("starting a new world must restore the pre-history pause state")
	if main._political_history.snapshot_count() != 1:
		_fail("starting a new world must reset political history")

	print("POLITICAL_HISTORY_SCENE_TEST PASS")
	main.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
