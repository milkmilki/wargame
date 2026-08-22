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
	if (
		not is_equal_approx(panel.province_strength(), 0.93)
		or not is_equal_approx(main.renderer._province_strength, 0.93)
		or not is_equal_approx(main.map_3d._province_strength, 0.93)
		or not is_equal_approx(
			panel.elevation_shadow_strength(),
			StrategicMap3D.SCULPT_TERRAIN_LIGHT_DEFAULT_STRENGTH
		)
		or not is_equal_approx(
			main.map_3d._elevation_shadow_strength,
			StrategicMap3D.SCULPT_TERRAIN_LIGHT_DEFAULT_STRENGTH
		)
		or not is_equal_approx(
			main.map_3d._sculpt_terrain_light.light_energy,
			StrategicMap3D.SCULPT_TERRAIN_LIGHT_DEFAULT_STRENGTH
				* StrategicMap3D.SCULPT_TERRAIN_LIGHT_MAX_ENERGY
		)
		or not is_equal_approx(
			panel.vertical_terrain_light_strength(),
			StrategicMap3D.VERTICAL_TERRAIN_LIGHT_DEFAULT_STRENGTH
		)
		or not is_equal_approx(
			main.map_3d._vertical_terrain_light_strength,
			StrategicMap3D.VERTICAL_TERRAIN_LIGHT_DEFAULT_STRENGTH
		)
		or not is_equal_approx(
			main.map_3d._vertical_terrain_light.light_energy,
			StrategicMap3D.VERTICAL_TERRAIN_LIGHT_DEFAULT_STRENGTH
				* StrategicMap3D.VERTICAL_TERRAIN_LIGHT_MAX_ENERGY
		)
	):
		push_error("ROAD_TUNING_UI_DEFAULT_POLITICAL_MODE_FAILED")
		quit(1)
		return
	var expected_modes := {
		RoadTuningPanel.MAP_MODE_TERRAIN: MapRenderer.MAP_MODE_POLITICAL,
		RoadTuningPanel.MAP_MODE_MIXED: MapRenderer.MAP_MODE_POLITICAL,
		RoadTuningPanel.MAP_MODE_POLITICAL: MapRenderer.MAP_MODE_POLITICAL,
		RoadTuningPanel.MAP_MODE_LOYALTY: MapRenderer.MAP_MODE_LOYALTY,
		RoadTuningPanel.MAP_MODE_TRADE: MapRenderer.MAP_MODE_TRADE,
	}
	if (
		panel._map_mode_buttons.size() != expected_modes.size()
		or panel.map_mode() != RoadTuningPanel.MAP_MODE_POLITICAL
		or panel.renderer_map_mode() != MapRenderer.MAP_MODE_POLITICAL
		or not (panel._map_mode_buttons[
			RoadTuningPanel.MAP_MODE_POLITICAL
		] as Button).button_pressed
	):
		push_error("ROAD_TUNING_UI_MODE_CONTRACT_FAILED")
		quit(1)
		return
	for mode_id in expected_modes:
		var mode_button := panel._map_mode_buttons[mode_id] as Button
		if (
			mode_button == null
			or str(mode_button.get_meta(&"map_mode", "")) != mode_id
			or int(mode_button.get_meta(&"renderer_map_mode", -1))
				!= int(expected_modes[mode_id])
		):
			push_error("ROAD_TUNING_UI_MODE_METADATA_FAILED")
			quit(1)
			return
	(
		panel._sliders[
			RoadTuningPanel.VERTICAL_TERRAIN_LIGHT_STRENGTH_KEY
		] as HSlider
	).value = 0.37
	if (
		not is_equal_approx(panel.vertical_terrain_light_strength(), 0.37)
		or not is_equal_approx(
			main.map_3d._vertical_terrain_light_strength, 0.37
		)
		or not is_equal_approx(
			main.map_3d._vertical_terrain_light.light_energy,
			0.37 * StrategicMap3D.VERTICAL_TERRAIN_LIGHT_MAX_ENERGY
		)
	):
		push_error("ROAD_TUNING_UI_VERTICAL_LIGHT_FAILED")
		quit(1)
		return
	(
		panel._sliders[
			RoadTuningPanel.ELEVATION_SHADOW_STRENGTH_KEY
		] as HSlider
	).value = 1.0
	if (
		not is_equal_approx(main.map_3d._elevation_shadow_strength, 1.0)
		or not is_equal_approx(
			main.map_3d._sculpt_terrain_light.light_energy,
			2.0
		)
	):
		push_error("ROAD_TUNING_UI_ELEVATION_SHADOW_FAILED")
		quit(1)
		return
	for mode_case in [
		[RoadTuningPanel.MAP_MODE_TERRAIN, 0.0, MapRenderer.MAP_MODE_POLITICAL],
		[RoadTuningPanel.MAP_MODE_MIXED, 0.42, MapRenderer.MAP_MODE_POLITICAL],
		[RoadTuningPanel.MAP_MODE_POLITICAL, 0.93, MapRenderer.MAP_MODE_POLITICAL],
		[RoadTuningPanel.MAP_MODE_LOYALTY, 0.93, MapRenderer.MAP_MODE_LOYALTY],
		[RoadTuningPanel.MAP_MODE_TRADE, 0.93, MapRenderer.MAP_MODE_TRADE],
	]:
		var mode_id := str(mode_case[0])
		var expected_strength := float(mode_case[1])
		var expected_renderer_mode := int(mode_case[2])
		(panel._map_mode_buttons[mode_id] as Button).pressed.emit()
		var unique_highlight := true
		for other_mode_id in expected_modes:
			unique_highlight = (
				unique_highlight
				and (panel._map_mode_buttons[other_mode_id] as Button).button_pressed
					== (str(other_mode_id) == mode_id)
			)
		if (
			panel.map_mode() != mode_id
			or panel.renderer_map_mode() != expected_renderer_mode
			or main.renderer.map_mode() != expected_renderer_mode
			or main.map_3d.map_mode() != expected_renderer_mode
			or not is_equal_approx(panel.province_strength(), expected_strength)
			or not is_equal_approx(
				main.map_3d._province_strength, expected_strength
			)
			or not unique_highlight
		):
			push_error("ROAD_TUNING_UI_MODE_SWITCH_FAILED_%s" % mode_id)
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
	for edge in main.state.edges:
		if not Edge.production_capacity_valid(edge.kind, edge.max_manpower):
			push_error("ROAD_TUNING_UI_CAPACITY_BAND_FAILED")
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
