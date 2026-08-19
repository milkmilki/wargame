extends SceneTree
## Default-scene frontend integration smoke. Loads main.tscn so the evidence covers
## the strategic map, HUD, settings, road controls and map-mode controls together.

const TIMEOUT_MSEC := 20000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://main.tscn") as PackedScene
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
	var checks := {
		"map_visible": map_3d.visible,
		"overlay_hud_only": not renderer.world_layer_visible,
		"settings_button": settings_button != null,
		"settings_style": settings_button != null and settings_button.get_theme_stylebox("normal") != null,
		"panel_style": settings_panel != null and settings_panel.get_theme_stylebox("panel") != null,
		"road_control": road_button != null and road_button.get_theme_stylebox("normal") != null,
		"map_modes": map_modes != null,
		"map_mode_count": map_modes != null and map_modes.get_child_count() == 3,
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
		" cities=", main.state.cities.size(),
		" output=", output
	)
	main.free()
	quit(0)
