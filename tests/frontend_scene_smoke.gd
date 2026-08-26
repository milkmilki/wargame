extends SceneTree
## Default-scene frontend integration smoke. Loads main.tscn so the evidence covers
## the strategic map, HUD, settings, road controls and map-mode controls together.

const TIMEOUT_MSEC := 20000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene_path := OS.get_environment("WW_FRONTEND_SCENE")
	if scene_path.is_empty():
		scene_path = "res://main.tscn"
	var expected_nation_count := int(OS.get_environment(
		"WW_EXPECTED_NATION_COUNT"
	))
	if expected_nation_count <= 0:
		expected_nation_count = GameState.NATION_COUNT
	var expect_random_start := (
		OS.get_environment("WW_EXPECT_RANDOM_START") == "1"
	)
	var packed := load(scene_path) as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	var simulation := main.get_node("Simulation") as Simulation
	simulation.paused = true
	var map_3d := main.get_node("StrategicMap3D") as StrategicMap3D
	var started := Time.get_ticks_msec()
	while (
		map_3d._terrain == null
		or map_3d._terrain.land_cell_count() <= 0
	):
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			push_error("FRONTEND_SCENE_TIMEOUT")
			quit(1)
			return
		await process_frame
	await process_frame

	var settings_button := main.get_node(
		"SettingsLayer/SettingsButton"
	) as Button
	var settings_panel := main.get_node(
		"SettingsLayer/SettingsOverlay/SettingsPanel"
	) as PanelContainer
	var road_layer := main.get_node("RoadTuningLayer") as RoadTuningPanel
	var road_button := road_layer.get_node_or_null(
		"RoadTuningButton"
	) as Button
	var map_modes := road_layer.get_node_or_null("MapModes") as HBoxContainer
	var renderer := main.get_node("MapRenderer") as MapRenderer
	var editor_layer := main.get_node("MapEditorLayer") as MapEditorPanel
	var editor_button := editor_layer.get_node_or_null(
		"MapEditorButton"
	) as Button
	var expected_mode_ids := PackedStringArray([
		RoadTuningPanel.MAP_MODE_TERRAIN,
		RoadTuningPanel.MAP_MODE_MIXED,
		RoadTuningPanel.MAP_MODE_POLITICAL,
		RoadTuningPanel.MAP_MODE_LOYALTY,
		RoadTuningPanel.MAP_MODE_TRADE,
	])
	var expected_renderer_modes := PackedInt32Array([
		MapRenderer.MAP_MODE_POLITICAL,
		MapRenderer.MAP_MODE_POLITICAL,
		MapRenderer.MAP_MODE_POLITICAL,
		MapRenderer.MAP_MODE_LOYALTY,
		MapRenderer.MAP_MODE_TRADE,
	])
	var mode_contract_valid := (
		map_modes != null
		and map_modes.get_child_count() == expected_mode_ids.size()
	)
	if mode_contract_valid:
		for index in range(expected_mode_ids.size()):
			var mode_button := map_modes.get_child(index) as Button
			mode_contract_valid = (
				mode_contract_valid
				and mode_button != null
				and str(mode_button.get_meta(&"map_mode", ""))
					== expected_mode_ids[index]
				and int(mode_button.get_meta(&"renderer_map_mode", -1))
					== expected_renderer_modes[index]
			)
	var checks := {
		"nation_count": main.state.nations.size() == expected_nation_count,
		"random_start": (
			not expect_random_start
			or (
				bool(main.get("randomize_world_seed_on_start"))
				and int(main.get("_seed")) == main.state.world_seed
				and int(main.get("_seed")) != int(main.get("world_seed"))
			)
		),
		"map_visible": map_3d.visible,
		"overlay_hud_only": not renderer.world_layer_visible,
		"settings_button": settings_button != null,
		"settings_style": settings_button != null and settings_button.get_theme_stylebox("normal") != null,
		"panel_style": settings_panel != null and settings_panel.get_theme_stylebox("panel") != null,
		"road_control": road_button != null and road_button.get_theme_stylebox("normal") != null,
		"map_modes": map_modes != null,
		"map_mode_count": map_modes != null and map_modes.get_child_count() == 5,
		"map_mode_contract": mode_contract_valid,
		"map_mode_default": (
			road_layer.map_mode() == RoadTuningPanel.MAP_MODE_POLITICAL
			and road_layer.renderer_map_mode()
				== MapRenderer.MAP_MODE_POLITICAL
			and (road_layer._map_mode_buttons[
				RoadTuningPanel.MAP_MODE_POLITICAL
			] as Button).button_pressed
		),
		"map_mode_style": map_modes != null and (map_modes.get_child(0) as Button).get_theme_stylebox("pressed") != null,
		"map_editor": editor_button != null and editor_button.get_theme_stylebox("normal") != null,
		"capital_rings": map_3d._capital_rings.multimesh.instance_count == main.state.nations.size(),
	}
	var valid: bool = true
	for check_value in checks.values():
		valid = valid and bool(check_value)
	if not valid:
		print("FRONTEND_SCENE_DIAGNOSTIC checks=", checks)
		push_error("FRONTEND_SCENE_INVALID")
		quit(1)
		return
	var output := OS.get_environment("WW_VISUAL_OUTPUT")
	if not output.is_empty():
		var image := root.get_texture().get_image()
		if image == null or image.is_empty() or image.save_png(output) != OK:
			push_error("FRONTEND_SCENE_SCREENSHOT_FAILED")
			quit(1)
			return
	print(
		"FRONTEND_SCENE_OK settings=1 road=1 modes=",
		map_modes.get_child_count(),
		" nations=", main.state.nations.size(),
		" cities=", main.state.cities.size(),
		" seed=", main.state.world_seed,
		" output=", output
	)
	main.free()
	quit(0)
