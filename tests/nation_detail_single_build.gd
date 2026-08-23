extends SceneTree
## 国家详情单帧构建专项：
## 1. 选中国家触发一次 redraw 时，只构建一次 nation detail sections。
## 2. 预计算 payload 复用的 sections 文本与静态 nation_detail_sections 一致。
## 3. city / edge 详情路径仍可生成有效面板，且不会误触发 nation build 计数。

var _checks: int = 0
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
	await process_frame
	await process_frame

	await _test_nation_redraw_builds_once(renderer, state)
	await _test_city_and_edge_paths_do_not_regress(renderer, state)

	renderer.free()
	simulation.free()
	if _failures.is_empty():
		print("NATION_DETAIL_SINGLE_BUILD_OK checks=%d" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("NATION_DETAIL_SINGLE_BUILD_FAIL: " + failure)
	print("NATION_DETAIL_SINGLE_BUILD_INVALID checks=%d failures=%d" % [
		_checks, _failures.size(),
	])
	quit(1)


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	var message := label
	if not detail.is_empty():
		message += " :: " + detail
	_failures.append(message)


func _test_nation_redraw_builds_once(
	renderer: MapRenderer,
	state: GameState
) -> void:
	var nation_id := _pick_alive_nation_id(state)
	var expected_sections := MapRenderer.nation_detail_sections(state, nation_id)
	var expected_signature := _section_signature(expected_sections)
	var expected_line_count := _section_visual_line_count(expected_sections)

	MapRenderer.reset_nation_detail_section_build_count()
	renderer.select_nation(nation_id)
	await process_frame
	await process_frame

	_check(
		MapRenderer.nation_detail_section_build_count() == 1,
		"nation/redraw_builds_sections_once",
		"count=%d nation=%d" % [
			MapRenderer.nation_detail_section_build_count(), nation_id,
		]
	)

	MapRenderer.reset_nation_detail_section_build_count()
	var payload := renderer._selection_detail_payload()
	var payload_sections := payload.get("sections", []) as Array[Dictionary]
	var payload_signature := _section_signature(payload_sections)
	_check(
		payload_signature == expected_signature,
		"nation/payload_sections_match_static_sections",
		"expected=%s actual=%s" % [expected_signature, payload_signature]
	)
	_check(
		int(payload.get("line_count", -1)) == expected_line_count,
		"nation/payload_line_count_matches_sections",
		"expected=%d actual=%d" % [
			expected_line_count, int(payload.get("line_count", -1)),
		]
	)
	_check(
		str(payload.get("title", "")).begins_with("国家信息  "),
		"nation/payload_title_present",
		str(payload)
	)
	_check(
		MapRenderer.nation_detail_section_build_count() == 1,
		"nation/payload_single_call_builds_once",
		"count=%d" % MapRenderer.nation_detail_section_build_count()
	)
	MapRenderer.reset_nation_detail_section_build_count()
	var detail_rect := renderer._selection_detail_rect(
		renderer._selection_detail_line_count()
	)
	var blocked := renderer.world_input_blocked(detail_rect.get_center())
	_check(
		blocked,
		"nation/world_input_blocked_hits_detail_rect",
		"rect=%s" % str(detail_rect)
	)
	_check(
		MapRenderer.nation_detail_section_build_count() == 0,
		"nation/world_input_blocked_does_not_build_sections",
		"count=%d" % MapRenderer.nation_detail_section_build_count()
	)


func _test_city_and_edge_paths_do_not_regress(
	renderer: MapRenderer,
	state: GameState
) -> void:
	var city_id := _pick_city_with_edge(state)
	var edge := _first_edge_for_city(state, city_id)

	MapRenderer.reset_nation_detail_section_build_count()
	renderer.select_city(city_id)
	await process_frame
	await process_frame
	_check(
		renderer._selection_detail_line_count() > 0,
		"city/detail_line_count_positive",
		"city=%d count=%d" % [city_id, renderer._selection_detail_line_count()]
	)
	_check(
		MapRenderer.nation_detail_section_build_count() == 0,
		"city/does_not_build_nation_sections",
		"count=%d" % MapRenderer.nation_detail_section_build_count()
	)

	MapRenderer.reset_nation_detail_section_build_count()
	renderer.select_edge(edge.city_a, edge.city_b)
	await process_frame
	await process_frame
	_check(
		renderer._selection_detail_line_count() > 0,
		"edge/detail_line_count_positive",
		"edge=%d-%d count=%d" % [
			edge.city_a, edge.city_b, renderer._selection_detail_line_count(),
		]
	)
	_check(
		MapRenderer.nation_detail_section_build_count() == 0,
		"edge/does_not_build_nation_sections",
		"count=%d" % MapRenderer.nation_detail_section_build_count()
	)


func _pick_alive_nation_id(state: GameState) -> int:
	for nation in state.nations:
		if nation.alive:
			return nation.id
	return 0


func _pick_city_with_edge(state: GameState) -> int:
	for edge in state.edges:
		if edge != null:
			return edge.city_a
	return 0


func _first_edge_for_city(state: GameState, city_id: int) -> Edge:
	for edge in state.edges:
		if edge.city_a == city_id or edge.city_b == city_id:
			return edge
	return state.edges[0]


func _section_signature(sections: Array[Dictionary]) -> String:
	var chunks: Array[String] = []
	for section in sections:
		var lines: Array[String] = []
		for line_value in section.get("lines", []):
			lines.append(str(line_value))
		chunks.append("%s=>%s" % [
			str(section.get("title", "")),
			" | ".join(lines),
		])
	return "\n".join(chunks)


func _section_visual_line_count(sections: Array[Dictionary]) -> int:
	var count := 0
	for section in sections:
		count += 1 + (section.get("lines", []) as Array).size()
	return count
