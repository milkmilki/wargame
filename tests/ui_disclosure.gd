extends SceneTree

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := GameState.new()
	state.generate_world(12345)
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.paused = true
	var renderer := MapRenderer.new()
	root.add_child(renderer)
	renderer.setup(state, simulation)
	renderer.set_world_layer_visible(false)
	renderer.select_nation(0)
	await process_frame
	await process_frame
	var samples: Array[int] = []
	for index in range(100):
		var started := Time.get_ticks_usec()
		renderer._selection_detail_payload()
		samples.append(Time.get_ticks_usec() - started)
	var total := 0
	for value in samples:
		total += value
	print("DETAIL_QUERY_BENCH avg_us=%.2f peak_us=%d nodes=%d" % [
		float(total) / samples.size(), samples.max(), _node_count(renderer),
	])
	if OS.get_environment("WW_UI_BASELINE") == "1":
		renderer.free()
		simulation.free()
		quit(0)
		return
	_check(renderer.has_method("detail_panel"), "native_detail_panel_exists")
	if not renderer.has_method("detail_panel"):
		renderer.free()
		simulation.free()
		_finish()
		return
	var panel = renderer.detail_panel()
	_check(panel.section("nation.identity").expanded, "identity_defaults_open")
	_check(panel.section("nation.region").expanded, "region_defaults_open")
	_check(not panel.section("nation.finance").expanded, "finance_defaults_closed")
	panel.section("nation.finance").set_expanded(true)
	panel.section("nation.identity").set_expanded(false)
	_check(not panel.action_button("ruler").is_visible_in_tree(), "hidden_ruler_cannot_be_clicked")
	MapRenderer.reset_nation_detail_section_build_count()
	panel.section("nation.finance").set_expanded(false)
	_check(MapRenderer.nation_detail_section_build_count() == 0, "fold_does_not_requery_armies")
	renderer.select_nation(1)
	await process_frame
	_check(not panel.section("nation.identity").expanded, "nation_switch_keeps_preferences")
	renderer.clear_map_selection()
	await process_frame
	_check(not panel.visible, "clear_selection_hides_panel")
	renderer.select_nation(0)
	await process_frame
	_check(not panel.section("nation.identity").expanded, "reopen_keeps_preferences")
	panel.section("nation.identity").set_expanded(true)
	panel.set_expanded(false)
	await process_frame
	_check(panel.size.y < 50.0, "whole_panel_minimizes_to_title")
	_check(not panel.action_button("family_tree").is_visible_in_tree(), "minimized_actions_hidden")
	_check(renderer.world_input_blocked(panel.get_global_rect().get_center()), "title_blocks_map")
	_check(not renderer.world_input_blocked(panel.get_global_rect().end + Vector2(0, 15)), "hidden_area_does_not_block_map")
	panel.set_expanded(true)
	renderer.select_city(state.nations[0].capital_city_id)
	await process_frame
	_check(panel.section("city.summary").expanded, "city_summary_defaults_open")
	_check(not panel.section("city.economy").expanded, "city_economy_defaults_closed")
	_check(panel.action_button("nation").is_visible_in_tree(), "city_nation_action_visible")
	panel.action_button("nation").pressed.emit()
	await process_frame
	_check(renderer.selected_nation_id() == 0, "city_nation_action_selects_owner")
	var edge := state.edges[0]
	renderer.select_edge(edge.city_a, edge.city_b)
	await process_frame
	await process_frame
	_check(panel.section("edge.summary").expanded, "edge_defaults_open")
	_check(panel.action_button("family_tree") == null, "edge_has_no_stale_nation_action")
	renderer.set_display_state(state, true)
	renderer.select_nation(0)
	await process_frame
	await process_frame
	_check(panel.section("history.identity").expanded, "historical_identity_defaults_open")
	_check(panel.action_button("ruler") == null and panel.action_button("family_tree") == null, "history_has_no_live_actions")
	renderer.set_display_state(state, false)
	renderer.select_nation(0)
	await process_frame
	await process_frame
	var before_nodes := _node_count(renderer)
	for index in range(20):
		renderer.queue_redraw()
		await process_frame
	_check(_node_count(renderer) == before_nodes, "refresh_reuses_nodes")
	var layout_samples: Array[int] = []
	var payload := renderer._selection_detail_payload()
	for index in range(100):
		var started := Time.get_ticks_usec()
		panel.present(payload, renderer._display_scale)
		layout_samples.append(Time.get_ticks_usec() - started)
	var layout_total := 0
	for value in layout_samples:
		layout_total += value
	print("DETAIL_PRESENT_BENCH avg_us=%.2f peak_us=%d nodes=%d" % [
		float(layout_total) / layout_samples.size(), layout_samples.max(), _node_count(renderer),
	])
	var dirty_total := 0
	var dirty_peak := 0
	for index in range(100):
		payload.sections[0].lines[0] = "身份变更 %d" % index
		var started := Time.get_ticks_usec()
		panel.present(payload, renderer._display_scale)
		var elapsed := Time.get_ticks_usec() - started
		dirty_total += elapsed
		dirty_peak = maxi(dirty_peak, elapsed)
	print("DETAIL_DIRTY_PRESENT_BENCH avg_us=%.2f peak_us=%d" % [float(dirty_total) / 100, dirty_peak])
	await _test_overflow(panel, renderer)
	await _test_history()
	renderer.free()
	simulation.free()
	_finish()


func _test_overflow(panel, renderer: MapRenderer) -> void:
	# Freeze the real feed while exercising an injected multi-war display payload.
	renderer.set_process(false)
	await process_frame
	await process_frame
	var lines: Array[String] = []
	for index in range(100):
		lines.append("很长的州战场信息用于验证文字换行以及滚动后仍然可以查看全部内容 %d" % index)
	var payload := {"title": "多场战争", "kind": "nation", "sections": [
		{"id": "war.99", "title": "战争99", "lines": lines, "default_expanded": true},
	], "actions": [], "stripe_color": MapRenderer.COMMAND_GREEN}
	panel.present(payload, renderer._display_scale)
	panel.section("war.99").set_expanded(false)
	panel.present(payload, renderer._display_scale)
	_check(not panel.section("war.99").expanded, "refresh_does_not_reopen_war")
	panel.section("war.99").set_expanded(true)
	await process_frame
	await process_frame
	_check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(panel.get_global_rect()), "overflow_panel_stays_on_screen")
	_check(panel.scroll.get_v_scroll_bar().max_value > panel.scroll.size.y, "overflow_has_scroll_range")
	panel.scroll.scroll_vertical = 1000
	_check(panel.scroll.scroll_vertical > 0, "overflow_can_scroll")
	payload.sections.append({"id": "war.100", "title": "战争100", "lines": ["新战争"], "default_expanded": true})
	panel.present(payload, renderer._display_scale)
	_check(panel.section("war.100").expanded, "new_war_defaults_open")
	payload.sections.remove_at(0)
	panel.present(payload, renderer._display_scale)
	_check(panel.section("war.99") == null, "ended_war_removes_old_group")


func _test_history() -> void:
	var timeline := HistoryTimeline.new()
	root.add_child(timeline)
	timeline.set_history_points(PackedInt32Array([0, 30, 60]), 90)
	timeline._on_value_changed(1)
	var committed: Array[int] = []
	timeline.position_requested.connect(func(index: int) -> void: committed.append(index))
	timeline.set_expanded(false)
	await process_frame
	_check(committed == [1], "history_fold_commits_pending_selection_once")
	_check(timeline.selected_index() == 1, "history_fold_keeps_historical_position")
	_check(not timeline._slider.is_visible_in_tree(), "history_fold_hides_slider")
	timeline.set_expanded(true)
	_check(timeline.selected_index() == 1, "history_reopen_keeps_position")
	timeline.free()


func _node_count(node: Node) -> int:
	var result := 1
	for child in node.get_children():
		result += _node_count(child)
	return result


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	for failure in _failures:
		push_error("UI_DISCLOSURE_FAIL: " + failure)
	print("UI_DISCLOSURE checks=%d failures=%d" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
