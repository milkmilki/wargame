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
	var negative_water_samples := 0
	var shallow_water_samples := 0
	var deep_water_samples := 0
	for height in first_height_samples:
		if height < StrategicTerrainRenderer.WATER_SURFACE_HEIGHT:
			negative_water_samples += 1
			if height > -0.28:
				shallow_water_samples += 1
			elif height < -0.55:
				deep_water_samples += 1
	map_3d._terrain.generate_from_height_texture(
		load(GameState.terrain_map_path()) as Texture2D,
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
	var terrain_arrays := terrain_mesh.surface_get_arrays(0)
	var terrain_indices: PackedInt32Array = terrain_arrays[
		Mesh.ARRAY_INDEX
	]
	var expected_indices := (
		(map_3d._terrain.resolution.x - 1)
		* (map_3d._terrain.resolution.y - 1)
		* 6
	)
	var terrain_material := (
		map_3d._terrain.mesh_instance().material_override
		as ShaderMaterial
	)
	var unclaimed_color := StrategicTerrainRenderer.UNCLAIMED_POLITICAL_COLOR
	var shallow_sea := StrategicTerrainRenderer.SHALLOW_SEA_COLOR
	var deep_sea := StrategicTerrainRenderer.DEEP_SEA_COLOR
	var overview_angle := map_3d._camera_normal_angle_degrees()
	var overview_framed := true
	for corner in [
		Vector3(
			-map_3d._world_size.x * 0.5,
			0.0,
			-map_3d._world_size.y * 0.5
		),
		Vector3(
			map_3d._world_size.x * 0.5,
			0.0,
			-map_3d._world_size.y * 0.5
		),
		Vector3(
			-map_3d._world_size.x * 0.5,
			0.0,
			map_3d._world_size.y * 0.5
		),
		Vector3(
			map_3d._world_size.x * 0.5,
			0.0,
			map_3d._world_size.y * 0.5
		),
	]:
		var screen := map_3d._camera.unproject_position(corner)
		overview_framed = overview_framed and (
			screen.x >= 0.0
			and screen.x <= 1280.0
			and screen.y >= 34.0
			and screen.y <= 712.0
		)
	map_3d._camera_distance = lerpf(
		map_3d._camera_overview_distance,
		StrategicMap3D.CAMERA_MIN_DISTANCE,
		0.5
	)
	var middle_angle := map_3d._camera_normal_angle_degrees()
	map_3d._camera_distance = StrategicMap3D.CAMERA_MIN_DISTANCE
	map_3d._apply_camera_transform()
	var close_angle := map_3d._camera_normal_angle_degrees()
	var focus := map_3d._camera_target + Vector3(
		0.0,
		StrategicMap3D.HEIGHT_SCALE * 0.18,
		0.0
	)
	var actual_close_angle := rad_to_deg(acos(clampf(
		(map_3d._camera.position - focus).normalized().dot(
			Vector3.UP
		),
		-1.0,
		1.0
	)))
	map_3d._camera_distance = map_3d._camera_overview_distance
	map_3d._apply_camera_transform()
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
	var checks := {
		"terrain_mesh": terrain_mesh != null and terrain_mesh.get_surface_count() > 0,
		"terrain_indices": terrain_indices.size() == expected_indices,
		"alpha_threshold": is_equal_approx(
			float(terrain_material.get_shader_parameter(
				"land_alpha_threshold"
			)),
			TerrainMapGenerator.ALPHA_THRESHOLD
		),
		"default_political_mode": is_equal_approx(
			float(terrain_material.get_shader_parameter(
				"province_strength"
			)),
			MapRenderer.POLITICAL_MAP_DEFAULT_STRENGTH
		),
		"default_elevation_shadow": is_equal_approx(
			float(terrain_material.get_shader_parameter(
				"elevation_shadow_strength"
			)), 0.62
		),
		"unclaimed_political_dark_blue": (
			unclaimed_color.b > unclaimed_color.r
			and unclaimed_color.b > unclaimed_color.g
			and unclaimed_color.v >= 0.16
			and unclaimed_color.v <= 0.20
		),
		"sea_depth_gradient": (
			shallow_sea.v > deep_sea.v
			and shallow_sea.b > shallow_sea.r
			and deep_sea.b > deep_sea.r
		),
		"overview_angle": absf(
			overview_angle
				- StrategicMap3D.CAMERA_OVERVIEW_NORMAL_ANGLE_DEGREES
		) < 0.001,
		"overview_framed": overview_framed,
		"middle_angle": absf(
			middle_angle
				- lerpf(
					StrategicMap3D.CAMERA_OVERVIEW_NORMAL_ANGLE_DEGREES,
					StrategicMap3D.CAMERA_MAX_NORMAL_ANGLE_DEGREES,
					0.5
				)
		) < 0.001,
		"close_angle": absf(
			close_angle
				- StrategicMap3D.CAMERA_MAX_NORMAL_ANGLE_DEGREES
		) < 0.001,
		"actual_close_angle": absf(actual_close_angle - close_angle) < 0.001,
		"land_cells": map_3d._terrain.land_cell_count() > 1000,
		"negative_water": negative_water_samples > 0,
		"bathymetry_depth_bands": (
			shallow_water_samples > 0 and deep_water_samples > 0
		),
		"source_water_layer_disabled": not map_3d._water.visible,
		"round_trip": round_trip.distance_to(sample_position) < 0.0001,
		"cities": map_3d._cities.multimesh != null and map_3d._cities.multimesh.instance_count == state.cities.size(),
		"armies": map_3d._armies.multimesh != null and map_3d._armies.multimesh.instance_count > 0,
		"provinces": map_3d._province_texture != null,
		"selection": map_3d._selection.visible,
		"edge_selection": selected_edge != null and map_3d._edge_selection.mesh != null,
		"capitals": map_3d._capital_rings.multimesh != null and map_3d._capital_rings.multimesh.instance_count == state.nations.size(),
	}
	var valid := true
	for check_value in checks.values():
		valid = valid and bool(check_value)
	if not valid:
		print("TERRAIN_3D_DIAGNOSTIC checks=", checks)
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
		map_3d._armies.multimesh.instance_count,
		" water_samples=", negative_water_samples
	)
	map_3d.free()
	overlay.free()
	simulation.free()
	quit(0)
