extends SceneTree
## 500 城场景烟测：既检查场景配置，也实际启动随机大地图，确保 3D 国名
## 标签不是只在导出属性上开启，而是真的完成布局并进入可见状态。

const TIMEOUT_MSEC: int = 30000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://five_hundred_city_stress.tscn") as PackedScene
	var scenario := packed.instantiate()
	var map_3d := scenario.get_node("StrategicMap3D") as StrategicMap3D
	var config_ok: bool = (
		int(scenario.nation_count) == 80
		and int(scenario.terrain_city_count) == 500
		and bool(scenario.randomize_world_seed_on_start)
		and is_equal_approx(float(scenario.map_world_scale), 2.0)
		and not bool(scenario.initial_city_names_visible)
		and bool(scenario.initial_nation_names_visible)
	)
	root.add_child(scenario)
	var started := Time.get_ticks_msec()
	while (
		scenario.state == null
		or map_3d._terrain == null
		or map_3d._terrain.land_cell_count() <= 0
		or map_3d._nation_labels.is_empty()
	):
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			push_error("FIVE_HUNDRED_CITY_SCENE_TIMEOUT")
			quit(1)
			return
		await process_frame
	await process_frame
	var visible_labels := 0
	var named_labels := 0
	for label in map_3d._nation_labels:
		if label.visible:
			visible_labels += 1
		if not label.text.strip_edges().is_empty():
			named_labels += 1
	var state: GameState = scenario.state
	var aspect := clampf(state.map_aspect_ratio, 0.5, 2.5)
	var expected_span := StrategicMap3D.BASE_WORLD_SPAN * 2.0
	var expected_world_size := (
		Vector2(expected_span, expected_span / aspect)
		if aspect >= 1.0
		else Vector2(expected_span * aspect, expected_span)
	)
	var ok: bool = (
		config_ok
		and state.land_cities().size() == 500
		and scenario.renderer.nation_names_visible()
		and not map_3d._nation_labels.is_empty()
		and visible_labels == map_3d._nation_labels.size()
		and named_labels == map_3d._nation_labels.size()
		and map_3d._world_size.is_equal_approx(expected_world_size)
		and is_equal_approx(
			map_3d._camera_max_distance(),
			StrategicMap3D.CAMERA_MAX_DISTANCE * 2.0
		)
	)
	print("FIVE_HUNDRED_CITY_SCENE_%s span=%s labels=%d/%d" % [
		"OK" if ok else "FAILED", str(map_3d._world_size),
		visible_labels, state.nations.size(),
	])
	quit(0 if ok else 1)
