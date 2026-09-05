extends SceneTree
## Default-scene probe for docked map-editor regeneration and selection forms.

const TIMEOUT_MSEC := 20000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := load("res://main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	var started := Time.get_ticks_msec()
	while main.map_3d._terrain == null or main.map_3d._terrain.land_cell_count() <= 0:
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			push_error("MAP_EDITOR_UI_TIMEOUT")
			quit(1)
			return
		await process_frame
	var panel: MapEditorPanel = main.map_editor_panel
	panel.open_panel()
	await process_frame
	if panel._city_mask_path.text != GameState.DEFAULT_CITY_MASK_PATH:
		push_error("MAP_EDITOR_UI_DEFAULT_MASK_FAILED")
		quit(1)
		return
	if not panel._political_mask_path.text.is_empty():
		push_error("MAP_EDITOR_UI_DEFAULT_POLITICAL_MASK_FAILED")
		quit(1)
		return
	var density_defaults := TerrainMapGenerator.default_city_density_settings()
	if (
		not is_equal_approx(panel._latitude_min.value, float(density_defaults["latitude_min"]))
		or not is_equal_approx(panel._latitude_max.value, float(density_defaults["latitude_max"]))
		or not is_equal_approx(panel._density_peak_latitude.value, float(density_defaults["density_peak_latitude"]))
		or not is_equal_approx(panel._south_density.value, float(density_defaults["south_density"]))
		or not is_equal_approx(panel._north_density.value, float(density_defaults["north_density"]))
	):
		push_error(
			"MAP_EDITOR_UI_LATITUDE_DENSITY_DEFAULT_FAILED "
			+ "min=%.2f max=%.2f peak=%.2f south=%.2f north=%.2f" % [
				panel._latitude_min.value,
				panel._latitude_max.value,
				panel._density_peak_latitude.value,
				panel._south_density.value,
				panel._north_density.value,
			]
		)
		quit(1)
		return
	main.renderer.select_city(0)
	panel._refresh_selection_form()
	if not panel.is_open() or not main.simulation.paused or not panel._city_form.visible:
		push_error("MAP_EDITOR_UI_CITY_FORM_FAILED")
		quit(1)
		return
	var edge: Edge = main.state.edges[0]
	main.renderer.select_edge(edge.city_a, edge.city_b)
	panel._refresh_selection_form()
	if not panel._edge_form.visible or panel._city_form.visible:
		push_error("MAP_EDITOR_UI_EDGE_FORM_FAILED")
		quit(1)
		return
	main._on_map_regenerate_requested(
		72, main.state.city_generation_mask_path,
		main.state.political_mask_path,
		{
			"latitude_min": 10.0,
			"latitude_max": 70.0,
			"density_peak_latitude": 28.0,
			"south_density": 0.45,
			"north_density": 0.15,
		}
	)
	await process_frame
	if (
		main.state.land_cities().size() != 72
		or not main.simulation.paused
		or main.state.city_generation_mask_path
			!= GameState.DEFAULT_CITY_MASK_PATH
		or not is_equal_approx(float(main.state.city_density_settings["latitude_min"]), 10.0)
		or not is_equal_approx(float(main.state.city_density_settings["latitude_max"]), 70.0)
	):
		push_error("MAP_EDITOR_UI_REGENERATE_FAILED")
		quit(1)
		return
	var state_before_bad_mask: GameState = main.state
	main._on_map_regenerate_requested(
		72, "/private/tmp/not-a-real-city-mask.png",
		main.state.political_mask_path,
		main.state.city_density_settings
	)
	if main.state != state_before_bad_mask or not panel._status.text.contains("无法读取"):
		push_error("MAP_EDITOR_UI_BAD_MASK_GUARD_FAILED")
		quit(1)
		return
	main._on_map_regenerate_requested(
		72, main.state.city_generation_mask_path,
		"/private/tmp/not-a-real-political-mask.png",
		main.state.city_density_settings
	)
	if main.state != state_before_bad_mask or not panel._status.text.contains("无法读取"):
		push_error("MAP_EDITOR_UI_BAD_POLITICAL_MASK_GUARD_FAILED")
		quit(1)
		return
	main.renderer.select_city(0)
	panel._refresh_selection_form()
	var output := OS.get_environment("WW_VISUAL_OUTPUT")
	if not output.is_empty():
		await process_frame
		var image := root.get_texture().get_image()
		if image == null or image.is_empty() or image.save_png(output) != OK:
			push_error("MAP_EDITOR_UI_SCREENSHOT_FAILED")
			quit(1)
			return
	print(
		"MAP_EDITOR_UI_OK cities=", main.state.land_cities().size(),
		" docked=", panel._dock_panel != null,
		" output=", output
	)
	main.free()
	quit(0)
