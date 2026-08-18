extends SceneTree
## End-to-end road tuning UI probe, including pause and renderer refresh.

const TIMEOUT_MSEC := 15000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var width := int(OS.get_environment("WW_VISUAL_WIDTH"))
	var height := int(OS.get_environment("WW_VISUAL_HEIGHT"))
	root.size = Vector2i(
		width if width > 0 else 1280,
		height if height > 0 else 720
	)
	var scene := load("res://main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	if width > 0 and height > 0:
		root.size = Vector2i(width, height)
	var started := Time.get_ticks_msec()
	while (
		main.map_3d._terrain == null
		or main.map_3d._terrain.land_cell_count() <= 0
	):
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			push_error("ROAD_TUNING_UI_TIMEOUT")
			quit(1)
			return
		await process_frame
	var panel: RoadTuningPanel = main.road_tuning_panel
	panel.open_panel()
	await process_frame
	if not panel.is_open() or not main.simulation.paused:
		push_error("ROAD_TUNING_UI_PAUSE_FAILED")
		quit(1)
		return
	(panel._map_mode_buttons[0.72] as Button).pressed.emit()
	if (
		not is_equal_approx(panel.province_strength(), 0.72)
		or not is_equal_approx(main.map_3d._province_strength, 0.72)
	):
		push_error("ROAD_TUNING_UI_MAP_MODE_FAILED")
		quit(1)
		return
	(panel._sliders["blocked_branch_share"] as HSlider).value = 0.20
	(panel._sliders["capacity_multiplier"] as HSlider).value = 1.25
	main._on_road_regenerate_requested(panel.road_settings())
	await process_frame
	await process_frame
	if (
		main.state.road_network_revision != 1
		or not panel._status.text.begins_with("已生成")
		or main.map_3d._last_road_network_revision != 1
	):
		push_error("ROAD_TUNING_UI_REBUILD_FAILED")
		quit(1)
		return
	var output := OS.get_environment("WW_VISUAL_OUTPUT")
	if not output.is_empty():
		var image := root.get_texture().get_image()
		var error := image.save_png(output)
		if error != OK:
			push_error("ROAD_TUNING_UI_SCREENSHOT_FAILED")
			quit(1)
			return
	panel.close_panel()
	if main.simulation.paused:
		push_error("ROAD_TUNING_UI_PAUSE_RESTORE_FAILED")
		quit(1)
		return
	var closed_output := OS.get_environment("WW_CLOSED_VISUAL_OUTPUT")
	if not closed_output.is_empty():
		await process_frame
		var closed_image := root.get_texture().get_image()
		var closed_error := closed_image.save_png(closed_output)
		if closed_error != OK:
			push_error("ROAD_TUNING_UI_CLOSED_SCREENSHOT_FAILED")
			quit(1)
			return
	print(
		"ROAD_TUNING_UI_OK revision=",
		main.state.road_network_revision,
		" status=",
		panel._status.text
	)
	main.free()
	quit(0)
