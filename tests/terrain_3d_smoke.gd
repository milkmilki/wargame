extends SceneTree
## 3D 地形运行时烟测：等待高度网格生成并验证核心视觉资源非空。

const TIMEOUT_MSEC: int = 15000


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
	var overlay := MapRenderer.new()
	root.add_child(overlay)
	overlay.setup(state, simulation)
	overlay.set_world_layer_visible(false)
	var map_3d := StrategicMap3D.new()
	root.add_child(map_3d)
	map_3d.setup(state, simulation, overlay)

	var started := Time.get_ticks_msec()
	while (
		map_3d._terrain == null
		or map_3d._terrain.land_cell_count() <= 0
	):
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			push_error("TERRAIN_3D_SMOKE_TIMEOUT")
			quit(1)
			return
		await process_frame

	var first_height_samples := (
		map_3d._terrain._height_samples.duplicate()
	)
	var first_land_count := map_3d._terrain.land_cell_count()
	map_3d._terrain.generate_from_height_texture(
		load(GameState.TERRAIN_MAP_PATH) as Texture2D,
		state.map_source_region_normalized,
		TerrainMapGenerator.ALPHA_THRESHOLD,
		TerrainMapGenerator.LUMA_THRESHOLD
	)
	if (
		map_3d._terrain._height_samples
			!= first_height_samples
		or map_3d._terrain.land_cell_count()
			!= first_land_count
	):
		push_error("TERRAIN_3D_NON_DETERMINISTIC")
		quit(1)
		return

	var terrain_mesh := map_3d._terrain.mesh_instance().mesh
	var sample_position := Vector2(0.42, 0.58)
	var world_position := map_3d._terrain.map_to_world(
		sample_position
	)
	var round_trip := map_3d._terrain.world_to_map(
		world_position
	)
	var city_screen_position := map_3d._camera.unproject_position(
		map_3d._terrain.map_to_world(
			state.cities[0].map_position
		)
		+ Vector3(0.0, 0.34, 0.0)
	)
	map_3d._pick_map_feature(city_screen_position)
	map_3d._update_selection_marker()
	var selected_edge: Edge = null
	for edge in state.edges:
		if MapRenderer.is_edge_visible(edge):
			selected_edge = edge
			break
	if selected_edge != null:
		overlay.select_edge(
			selected_edge.city_a,
			selected_edge.city_b
		)
		map_3d._update_edge_selection()
	var valid := (
		terrain_mesh != null
		and terrain_mesh.get_surface_count() > 0
		and map_3d._terrain.land_cell_count() > 1000
		and round_trip.distance_to(sample_position) < 0.0001
		and map_3d._cities.multimesh != null
		and map_3d._cities.multimesh.instance_count
			== state.cities.size()
		and map_3d._armies.multimesh != null
		and map_3d._armies.multimesh.instance_count > 0
		and map_3d._province_texture != null
		and map_3d._selection.visible
		and selected_edge != null
		and map_3d._edge_selection.mesh != null
		and map_3d._capital_rings.multimesh != null
		and map_3d._capital_rings.multimesh.instance_count
			== state.nations.size()
	)
	if not valid:
		push_error("TERRAIN_3D_SMOKE_INVALID")
		quit(1)
		return
	print(
		"TERRAIN_3D_SMOKE_OK land_cells=",
		map_3d._terrain.land_cell_count(),
		" surfaces=",
		terrain_mesh.get_surface_count(),
		" cities=",
		map_3d._cities.multimesh.instance_count,
		" armies=",
		map_3d._armies.multimesh.instance_count
	)
	map_3d.free()
	overlay.free()
	simulation.free()
	quit(0)
