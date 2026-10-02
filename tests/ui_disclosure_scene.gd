extends SceneTree
## Real scene interactions and supported-resolution visual evidence.

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.simulation.paused = true
	var renderer: MapRenderer = main.renderer
	var panel := renderer.detail_panel()
	var modes: OptionButton = main.road_tuning_panel._map_mode_option
	var timeline: HistoryTimeline = main.history_timeline
	for frame in range(12):
		await process_frame
	_check(not renderer._display_controls.expanded, "display_controls_default_closed")
	var old_scale := renderer.army_icon_scale()
	var old_names := renderer.city_names_visible()
	renderer._display_controls.set_expanded(true)
	await process_frame
	_check(renderer._army_icon_slider.is_visible_in_tree(), "display_controls_expand")
	renderer._display_controls.set_expanded(false)
	await process_frame
	_check(renderer.army_icon_scale() == old_scale and renderer.city_names_visible() == old_names, "display_fold_preserves_settings")
	_check(not renderer._army_icon_slider.is_visible_in_tree(), "display_hidden_controls_hidden")
	main.road_tuning_panel.set_map_mode(RoadTuningPanel.MAP_MODE_MIXED)
	main._on_history_position_requested(0)
	_check(modes.disabled and modes.selected == 2, "history_disables_and_shows_political_view")
	_check(main.renderer.map_mode() == MapRenderer.MAP_MODE_POLITICAL and main.map_3d.map_mode() == MapRenderer.MAP_MODE_POLITICAL, "history_modes_match")
	var history_pause: bool = main.simulation.paused
	timeline.set_expanded(false)
	_check(main._history_active and main.simulation.paused == history_pause, "history_fold_keeps_history_and_pause")
	main._leave_history_view()
	_check(not modes.disabled and modes.selected == 1, "live_restores_mixed_selection")
	_check(is_equal_approx(main.renderer._province_strength, 0.42), "live_restores_overlay_strength")
	timeline.set_expanded(true)
	(main.road_tuning_panel._sliders[RoadTuningPanel.PROVINCE_STRENGTH_KEY] as HSlider).value = 0.0
	_check(modes.selected == 0, "slider_updates_dropdown")
	modes.item_selected.emit(4)
	_check(main.renderer.map_mode() == MapRenderer.MAP_MODE_TRADE and main.map_3d.map_mode() == MapRenderer.MAP_MODE_TRADE, "dropdown_updates_both_maps")
	await _click(modes)
	_check(modes.get_popup().visible, "native_view_dropdown_opens")
	_check(renderer.world_input_blocked(Vector2(200, 200)), "open_dropdown_blocks_map_gestures")
	modes.get_popup().hide()
	renderer.select_nation(0)
	await process_frame
	await process_frame
	var selection_before := renderer.selected_nation_id()
	var camera_before: float = main.map_3d._camera_distance
	await _click(panel.section("nation.finance").header)
	_check(panel.section("nation.finance").expanded, "native_arrow_click_expands")
	_check(renderer.selected_nation_id() == selection_before, "arrow_does_not_select_map")
	await _click(panel.action_button("family_tree"))
	_check(main.family_tree_panel.is_open(), "native_family_button_opens")
	main.family_tree_panel.close_panel()
	renderer.select_city(main.state.nations[0].capital_city_id)
	await process_frame
	await process_frame
	await _click(panel.action_button("nation"))
	_check(renderer.selected_nation_id() == 0, "native_city_button_selects_nation")
	await process_frame
	await process_frame
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = panel.get_global_rect().get_center()
	wheel.global_position = wheel.position
	Input.parse_input_event(wheel)
	await process_frame
	_check(is_equal_approx(main.map_3d._camera_distance, camera_before), "detail_wheel_does_not_zoom_map")
	panel.section("nation.finance").header.grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	_check(main.simulation.paused, "focused_disclosure_space_does_not_toggle_simulation")
	_check(not panel.section("nation.finance").expanded, "keyboard_can_fold")
	main.simulation.paused = true
	var output := OS.get_environment("WW_UI_VISUAL_DIR")
	for resolution in DisplaySettings.RESOLUTIONS:
		root.size = resolution
		for frame in range(8):
			await process_frame
		var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
		_check(viewport.encloses(panel.get_global_rect()), "detail_bounds_%s" % resolution)
		_check(not timeline._panel.get_global_rect().intersects(modes.get_global_rect()), "timeline_view_no_overlap_%s" % resolution)
		_check(viewport.encloses(timeline._panel.get_global_rect()), "timeline_bounds_%s" % resolution)
		_check(renderer.world_input_blocked(timeline._panel.get_global_rect().get_center()), "timeline_blocks_gestures_%s" % resolution)
		renderer._display_controls.set_expanded(true)
		await process_frame
		await process_frame
		_check(viewport.encloses(renderer._army_icon_panel.get_global_rect()), "expanded_display_bounds_%s" % resolution)
		renderer._display_controls.set_expanded(false)
		await process_frame
		await process_frame
		if not output.is_empty():
			var image := root.get_texture().get_image()
			_check(image != null and not image.is_empty(), "screenshot_nonempty_%s" % resolution)
			if image != null:
				_check(image.save_png(output.path_join("ui-%dx%d.png" % [resolution.x, resolution.y])) == OK, "screenshot_saved_%s" % resolution)
		panel.set_expanded(false)
		timeline.set_expanded(false)
		await process_frame
		await process_frame
		_check(panel.size.y < 60 * renderer._display_scale, "compact_detail_%s" % resolution)
		_check(not timeline._panel.get_global_rect().intersects(modes.get_global_rect()), "compact_timeline_no_overlap_%s" % resolution)
		panel.set_expanded(true)
		timeline.set_expanded(true)
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	await _click(renderer._nation_list_toggle)
	_check(renderer._nation_stats_open, "native_list_arrow_opens")
	_check(renderer.world_input_blocked(renderer._nation_stats_window_rect().get_center()), "list_blocks_map")
	if not output.is_empty():
		await process_frame
		_check(root.get_texture().get_image().save_png(output.path_join("ui-nation-list.png")) == OK, "list_screenshot")
	await _click(renderer._nation_list_toggle)
	_check(not renderer._nation_stats_open, "native_list_arrow_closes")
	_check(renderer._nation_list_canvas.visible == false, "list_canvas_hidden")
	await _click(renderer._nation_list_toggle)
	var first_row := MapRenderer.nation_stats_row_rect(renderer._nation_stats_window_rect(), renderer._display_scale, 0)
	var row_press := InputEventMouseButton.new()
	row_press.button_index = MOUSE_BUTTON_LEFT
	row_press.pressed = true
	row_press.position = first_row.get_center()
	row_press.global_position = row_press.position
	Input.parse_input_event(row_press)
	await process_frame
	row_press = row_press.duplicate()
	row_press.pressed = false
	Input.parse_input_event(row_press)
	await process_frame
	_check(renderer.selected_nation_id() >= 0, "list_row_selects_nation")
	_check(not renderer._nation_stats_open and not renderer._nation_list_canvas.visible, "narrow_list_selection_closes_canvas")
	renderer._display_controls.set_expanded(true)
	await process_frame
	await process_frame
	if not output.is_empty():
		_check(root.get_texture().get_image().save_png(output.path_join("ui-display-controls.png")) == OK, "display_screenshot")
	renderer._display_controls.set_expanded(false)
	main._activate_state(main.state)
	_check(main.renderer.map_mode() == MapRenderer.MAP_MODE_TRADE and main.map_3d.map_mode() == MapRenderer.MAP_MODE_TRADE and modes.selected == 4, "world_rebind_keeps_actual_view_consistent")
	# Windows may clamp a native window to the monitor; render the largest size offscreen too.
	var large_viewport := SubViewport.new()
	large_viewport.size = Vector2i(2560, 1440)
	large_viewport.own_world_3d = true
	large_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(large_viewport)
	main.reparent(large_viewport)
	timeline._layout_panel()
	renderer.select_nation(0)
	renderer.queue_redraw()
	for frame in range(12):
		await process_frame
	_check(panel.get_viewport_rect().size == Vector2(2560, 1440), "large_viewport_has_exact_dimensions")
	_check(panel.visible and Rect2(Vector2.ZERO, Vector2(2560, 1440)).encloses(panel.get_global_rect()), "exact_large_detail_bounds")
	if not output.is_empty():
		var large_image := large_viewport.get_texture().get_image()
		_check(large_image.get_size() == Vector2i(2560, 1440), "large_image_has_exact_dimensions")
		_check(large_image.save_png(output.path_join("ui-2560x1440.png")) == OK, "large_image_saved")
	main.free()
	large_viewport.free()
	for failure in _failures:
		push_error("UI_DISCLOSURE_SCENE_FAIL: " + failure)
	print("UI_DISCLOSURE_SCENE checks=%d failures=%d" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _click(button: Button) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
