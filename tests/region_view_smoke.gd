extends SceneTree
## Region-view integration probe. Exercises the UI switch and the 3D visual
## state so the feature cannot regress into a data-only analysis pass.

const TIMEOUT_MSEC: int = 20000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://main.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	main.simulation.paused = true
	var map_3d: StrategicMap3D = main.map_3d
	var started := Time.get_ticks_msec()
	while (
		map_3d._terrain == null
		or map_3d._terrain.land_cell_count() <= 0
	):
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			push_error("REGION_VIEW_TIMEOUT")
			quit(1)
			return
		await process_frame
	var region_button := (
		main.road_tuning_panel._map_mode_buttons.get(
			RoadTuningPanel.MAP_MODE_REGION
		) as Button
	)
	if region_button == null:
		push_error("REGION_VIEW_BUTTON_MISSING")
		quit(1)
		return
	region_button.pressed.emit()
	for _frame in range(4):
		await process_frame
	var highest_city_id := -1
	var lowest_positive_city_id := -1
	var highest_score := -1.0
	var lowest_positive_score := INF
	var positive_score_count := 0
	for city in main.state.cities:
		var score := float(main.state.node_betweenness[city.id])
		if score > highest_score:
			highest_score = score
			highest_city_id = city.id
		if score > 0.0 and score < lowest_positive_score:
			lowest_positive_score = score
			lowest_positive_city_id = city.id
		if score > 0.0:
			positive_score_count += 1
	var score_radius_ordered := false
	if highest_city_id >= 0 and lowest_positive_city_id >= 0:
		score_radius_ordered = (
			MapRenderer.region_score_radius(
				highest_score, highest_score, 0.28, 1.20
			)
			> MapRenderer.region_score_radius(
				lowest_positive_score, highest_score, 0.28, 1.20
			)
		)
	var checks := {
		"regions": main.state.region_count > 1,
		"positive_scores": highest_score > 0.0,
		"overlay_mode": (
			main.renderer.map_mode() == MapRenderer.MAP_MODE_REGION
		),
		"map_3d_mode": map_3d.map_mode() == MapRenderer.MAP_MODE_REGION,
		"province_lut": map_3d._province_visual_lut_texture != null,
		"boundary_texture": map_3d._country_boundary_texture != null,
		"color_texture": map_3d._country_color_texture != null,
		"nation_labels_hidden": map_3d._nation_labels.is_empty(),
		"score_layer_visible": map_3d._region_score_markers.visible,
		"score_overlay_material": (
			map_3d._region_score_markers.material_override
				is StandardMaterial3D
			and (
				map_3d._region_score_markers.material_override
					as StandardMaterial3D
			).no_depth_test
			and MapRenderer.REGION_SCORE_COLOR.a >= 0.60
		),
		"score_instance_count": (
			map_3d._region_score_markers.multimesh.instance_count
				== main.state.cities.size()
		),
		"score_radius_ordered": score_radius_ordered,
	}
	var valid: bool = true
	for check_value in checks.values():
		valid = valid and bool(check_value)
	var output := OS.get_environment("WW_VISUAL_OUTPUT")
	if valid and not output.is_empty():
		var image := root.get_texture().get_image()
		valid = image != null and not image.is_empty()
		if valid:
			valid = image.save_png(output) == OK
	var political_button := (
		main.road_tuning_panel._map_mode_buttons.get(
			RoadTuningPanel.MAP_MODE_POLITICAL
		) as Button
	)
	if political_button != null:
		political_button.pressed.emit()
		await process_frame
	valid = (
		valid
		and political_button != null
		and map_3d.map_mode() == MapRenderer.MAP_MODE_POLITICAL
		and not map_3d._region_score_markers.visible
	)
	print(
		"REGION_VIEW_%s regions=%d scored_cities=%d output=%s"
		% [
			"OK" if valid else "FAILED",
			main.state.region_count,
			positive_score_count,
			output,
		]
	)
	if not valid:
		print("REGION_VIEW_DIAGNOSTIC checks=", checks)
	main.free()
	quit(0 if valid else 1)
