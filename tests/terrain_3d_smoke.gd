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
	var terrain_vertices: PackedVector3Array = terrain_arrays[
		Mesh.ARRAY_VERTEX
	]
	var terrain_normals: PackedVector3Array = terrain_arrays[
		Mesh.ARRAY_NORMAL
	]
	var terrain_indices: PackedInt32Array = terrain_arrays[
		Mesh.ARRAY_INDEX
	]
	var expected_indices := (
		(map_3d._terrain.resolution.x - 1)
		* (map_3d._terrain.resolution.y - 1)
		* 6
	)
	var expected_vertices := (
		map_3d._terrain.resolution.x
		* map_3d._terrain.resolution.y
	)
	var smooth_normals_valid := (
		terrain_normals.size() == expected_vertices
		and terrain_vertices.size() == expected_vertices
	)
	var has_normal_variation := false
	for normal_index in range(terrain_normals.size()):
		var normal := terrain_normals[normal_index]
		smooth_normals_valid = smooth_normals_valid and (
			normal.is_normalized() and normal.y >= -0.000001
		)
		if (
			normal_index > 0
			and normal.distance_to(terrain_normals[normal_index - 1]) > 0.0001
		):
			has_normal_variation = true
	var terrain_material := (
		map_3d._terrain.mesh_instance().material_override
		as ShaderMaterial
	)
	var terrain_shader_code := terrain_material.shader.code
	var vertical_light_direction := (
		map_3d._vertical_terrain_light.global_basis
		* Vector3(0.0, 0.0, -1.0)
	).normalized()
	var sculpt_light_direction := (
		map_3d._sculpt_terrain_light.global_basis
		* Vector3(0.0, 0.0, -1.0)
	).normalized()
	var initial_sculpt_energy := map_3d._sculpt_terrain_light.light_energy
	map_3d.set_elevation_shadow_strength(0.25)
	var quarter_sculpt_energy := map_3d._sculpt_terrain_light.light_energy
	map_3d.set_elevation_shadow_strength(0.62)
	var political_geometry := (
		MapRenderer.build_province_boundary_segments(state)
	)
	var cached_topology := MapRenderer.build_province_boundary_topology(state)
	var classified_geometry := MapRenderer.classify_province_boundary_topology(
		state, cached_topology
	)
	var cached_classification_matches := true
	for geometry_key in [
		"province", "local", "coast", "nation", "alliance",
		"enemy", "suzerainty",
	]:
		cached_classification_matches = (
			cached_classification_matches
			and classified_geometry[geometry_key]
				== political_geometry[geometry_key]
		)
	var classified_segment_count := 0
	for classified_key in [
		"local", "nation", "alliance", "enemy", "suzerainty",
	]:
		classified_segment_count += (
			classified_geometry[classified_key] as PackedVector2Array
		).size() / 2
	var topology_partition_complete := (
		classified_segment_count
		== (cached_topology["province"] as PackedVector2Array).size() / 2
		and (cached_topology["province_a"] as PackedInt32Array).size()
			== classified_segment_count
		and (cached_topology["province_b"] as PackedInt32Array).size()
			== classified_segment_count
	)
	var political_canvas := MapRenderer.build_political_canvas_images(state)
	var canvas_fill: Image = political_canvas["fill"]
	var terrain_fill: Image = political_canvas["terrain_fill"]
	var province_boundaries: Image = political_canvas["province_boundaries"]
	var coast_boundaries: Image = political_canvas["coast_boundaries"]
	var diplomatic_boundaries: Image = political_canvas["diplomatic_boundaries"]
	var province_boundary_max_alpha := 0.0
	var coast_boundary_max_alpha := 0.0
	var diplomatic_boundary_max_alpha := 0.0
	var province_boundary_pixels := 0
	var coast_boundary_pixels := 0
	var diplomatic_boundary_pixels := 0
	var province_has_feather := false
	var coast_has_feather := false
	var diplomatic_has_feather := false
	var terrain_fill_covers_land := true
	for fill_y in range(canvas_fill.get_height()):
		for fill_x in range(canvas_fill.get_width()):
			if (
				canvas_fill.get_pixel(fill_x, fill_y).a > 0.5
				and terrain_fill.get_pixel(fill_x, fill_y).a <= 0.5
			):
				terrain_fill_covers_land = false
				break
		if not terrain_fill_covers_land:
			break
	var boundary_sampler_lines := 0
	for shader_line in terrain_shader_code.split("\n"):
		if (
			shader_line.contains("boundary_texture")
			and shader_line.contains("uniform sampler2D")
			and shader_line.contains("filter_linear_mipmap_anisotropic")
			and shader_line.contains("repeat_disable")
		):
			boundary_sampler_lines += 1
	for image_entry in [
		[province_boundaries, "province"],
		[coast_boundaries, "coast"],
		[diplomatic_boundaries, "diplomatic"],
	]:
		var boundary_image: Image = image_entry[0]
		var maximum := 0.0
		for boundary_y in range(boundary_image.get_height()):
			for boundary_x in range(boundary_image.get_width()):
				maximum = maxf(
					maximum, boundary_image.get_pixel(boundary_x, boundary_y).a
				)
				var alpha := boundary_image.get_pixel(boundary_x, boundary_y).a
				if alpha > 0.01:
					if image_entry[1] == "province":
						province_boundary_pixels += 1
						province_has_feather = province_has_feather or alpha < 0.45
					elif image_entry[1] == "coast":
						coast_boundary_pixels += 1
						coast_has_feather = coast_has_feather or alpha < 0.45
					else:
						diplomatic_boundary_pixels += 1
						diplomatic_has_feather = (
							diplomatic_has_feather or alpha < 0.65
						)
		if image_entry[1] == "province":
			province_boundary_max_alpha = maximum
		elif image_entry[1] == "coast":
			coast_boundary_max_alpha = maximum
		else:
			diplomatic_boundary_max_alpha = maximum
	var zero_meter_city_boundary: PackedVector2Array = (
		political_geometry["coast"]
	)
	var unclaimed_color := StrategicTerrainRenderer.UNCLAIMED_POLITICAL_COLOR
	var shallow_sea := StrategicTerrainRenderer.SHALLOW_SEA_COLOR
	var deep_sea := StrategicTerrainRenderer.DEEP_SEA_COLOR
	var overview_angle := map_3d._camera_normal_angle_degrees()
	var lod_close := StrategicMap3D.boundary_lod_strengths(24.0)
	var lod_mid := StrategicMap3D.boundary_lod_strengths(50.0)
	var lod_58_before := StrategicMap3D.boundary_lod_strengths(57.999)
	var lod_58_at := StrategicMap3D.boundary_lod_strengths(58.0)
	var lod_far := StrategicMap3D.boundary_lod_strengths(72.0)
	var lod_country_mid := StrategicMap3D.boundary_lod_strengths(82.0)
	var lod_overview := StrategicMap3D.boundary_lod_strengths(92.0)
	var fill_before_diplomacy_refresh := map_3d._province_texture
	var province_boundary_before_refresh := map_3d._province_boundary_texture
	var coast_boundary_before_refresh := map_3d._coast_boundary_texture
	map_3d._update_province_visuals()
	var diplomacy_refresh_kept_fill := (
		map_3d._province_texture == fill_before_diplomacy_refresh
	)
	var dynamic_refresh_kept_static_boundaries := (
		map_3d._province_boundary_texture == province_boundary_before_refresh
		and map_3d._coast_boundary_texture == coast_boundary_before_refresh
	)
	var topology_refresh_rebuilds_fill := false
	var topology_refresh_rebuilds_static_boundaries := false
	if map_3d._province_topology_ids.size() > 0:
		var saved_topology_id := map_3d._province_topology_ids[0]
		map_3d._province_topology_ids[0] = saved_topology_id - 1
		var fill_before_topology_refresh := map_3d._province_texture
		var province_before_topology_refresh := map_3d._province_boundary_texture
		var coast_before_topology_refresh := map_3d._coast_boundary_texture
		map_3d._update_province_visuals()
		topology_refresh_rebuilds_fill = (
			map_3d._province_texture != fill_before_topology_refresh
		)
		topology_refresh_rebuilds_static_boundaries = (
			map_3d._province_boundary_texture != province_before_topology_refresh
			and map_3d._coast_boundary_texture != coast_before_topology_refresh
		)
	overlay._ensure_province_visual_cache()
	var overlay_fill_before_diplomacy_refresh := overlay._province_texture
	var overlay_base_before_diplomacy_refresh := overlay._political_base_texture
	var overlay_ocean_before_diplomacy_refresh := overlay._political_ocean_texture
	overlay._province_diplomacy_revision = state.diplomacy_revision - 1
	overlay._ensure_province_visual_cache()
	var overlay_diplomacy_refresh_kept_fill := (
		overlay._province_texture == overlay_fill_before_diplomacy_refresh
		and overlay._political_base_texture
			== overlay_base_before_diplomacy_refresh
		and overlay._political_ocean_texture
			== overlay_ocean_before_diplomacy_refresh
	)
	map_3d._camera_distance = 50.0
	map_3d._apply_camera_transform()
	var material_mid_province := float(terrain_material.get_shader_parameter(
		"province_boundary_strength"
	))
	var material_mid_coast := float(terrain_material.get_shader_parameter(
		"coast_boundary_strength"
	))
	var material_mid_diplomatic := float(terrain_material.get_shader_parameter(
		"diplomatic_boundary_strength"
	))
	map_3d._camera_distance = 92.0
	map_3d._apply_camera_transform()
	var material_far_province := float(terrain_material.get_shader_parameter(
		"province_boundary_strength"
	))
	var material_far_coast := float(terrain_material.get_shader_parameter(
		"coast_boundary_strength"
	))
	var material_far_diplomatic := float(terrain_material.get_shader_parameter(
		"diplomatic_boundary_strength"
	))
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
		"terrain_indexed_low_poly": (
			terrain_vertices.size() == expected_vertices
			and terrain_indices.size() == expected_indices
		),
		"terrain_smooth_normals": (
			smooth_normals_valid and has_normal_variation
		),
		"geometry_ocean_threshold": (
			is_equal_approx(
				float(terrain_material.get_shader_parameter(
					"ocean_height_threshold"
				)),
				StrategicTerrainRenderer.OCEAN_HEIGHT_THRESHOLD
			)
			and terrain_shader_code.contains("terrain_elevation = VERTEX.y")
			and terrain_shader_code.contains(
				"step(ocean_height_threshold, terrain_elevation)"
			)
			and terrain_shader_code.contains(
				"ocean_height_threshold - terrain_elevation"
			)
			and not terrain_shader_code.contains("height_texture")
		),
		"default_political_mode": is_equal_approx(
			float(terrain_material.get_shader_parameter(
				"province_strength"
			)),
			MapRenderer.POLITICAL_MAP_DEFAULT_STRENGTH
		),
		"lit_low_poly_shader": (
			not terrain_shader_code.contains("unshaded")
			and not terrain_shader_code.contains("height_left")
			and not terrain_shader_code.contains("detail_normal_strength")
		),
		"categorical_political_paint": (
			terrain_shader_code.contains("filter_nearest")
			and terrain_shader_code.contains("texelFetch(province_texture")
			and terrain_shader_code.contains("step(0.5, province.a)")
			and not terrain_shader_code.contains("unclaimed_mix")
		),
		"white_base_political_modes": (
			terrain_shader_code.contains("political_land_base_color")
			and terrain_shader_code.contains(
				"white_low_poly_base = political_land_base_color"
			)
			and terrain_shader_code.contains("political_target")
			and terrain_shader_code.contains("province_strength")
			and terrain_shader_code.contains("province_strength <= 0.000001")
			and terrain_shader_code.contains("only mode that samples satellite RGB")
		),
		"shared_soft_boundary_layers": (
			cached_classification_matches
			and topology_partition_complete
			and map_3d._boundary_topology.size() > 0
			and map_3d._diplomatic_boundary_texture != null
			and map_3d._province_boundary_texture != null
			and map_3d._coast_boundary_texture != null
			and map_3d._diplomatic_boundary_texture.get_size()
				== map_3d._province_texture.get_size()
			and map_3d._province_boundary_texture.get_size()
				== map_3d._province_texture.get_size()
			and map_3d._coast_boundary_texture.get_size()
				== map_3d._province_texture.get_size()
			and terrain_shader_code.contains("diplomatic_boundary_texture")
			and terrain_shader_code.contains("province_boundary_texture")
			and terrain_shader_code.contains("coast_boundary_texture")
			and terrain_shader_code.contains(
				"1.0 - smoothstep(0.01, 0.18, diplomatic_boundary.a)"
			)
			and boundary_sampler_lines == 3
			and map_3d._boundaries.mesh == null
			and province_boundaries.get_size() == canvas_fill.get_size()
			and coast_boundaries.get_size() == canvas_fill.get_size()
			and diplomatic_boundaries.get_size() == canvas_fill.get_size()
			and terrain_fill_covers_land
			and province_boundaries.has_mipmaps()
			and coast_boundaries.has_mipmaps()
			and diplomatic_boundaries.has_mipmaps()
			and map_3d._province_boundary_texture.get_image().has_mipmaps()
			and map_3d._coast_boundary_texture.get_image().has_mipmaps()
			and map_3d._diplomatic_boundary_texture.get_image().has_mipmaps()
			and diplomacy_refresh_kept_fill
			and dynamic_refresh_kept_static_boundaries
			and topology_refresh_rebuilds_fill
			and topology_refresh_rebuilds_static_boundaries
			and overlay_diplomacy_refresh_kept_fill
		),
		"vertical_plane_light": (
			vertical_light_direction.distance_to(Vector3.DOWN) < 0.0001
			and is_equal_approx(
				map_3d._vertical_terrain_light.light_energy,
				StrategicMap3D.VERTICAL_TERRAIN_LIGHT_ENERGY
			)
			and map_3d._vertical_terrain_light.light_cull_mask
				== StrategicTerrainRenderer.TERRAIN_VISUAL_LAYER
		),
		"northwest_sculpt_plane_light": (
			absf(sculpt_light_direction.y) < 0.0001
			and sculpt_light_direction.x > 0.70
			and sculpt_light_direction.z > 0.70
			and is_equal_approx(
				initial_sculpt_energy,
				0.62 * StrategicMap3D.SCULPT_TERRAIN_LIGHT_MAX_ENERGY
			)
			and is_equal_approx(
				quarter_sculpt_energy,
				0.25 * StrategicMap3D.SCULPT_TERRAIN_LIGHT_MAX_ENERGY
			)
			and map_3d._sculpt_terrain_light.light_cull_mask
				== StrategicTerrainRenderer.TERRAIN_VISUAL_LAYER
			and map_3d._terrain.mesh_instance().layers
				== StrategicTerrainRenderer.TERRAIN_VISUAL_LAYER
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
		"strict_zero_meter_coast": terrain_shader_code.contains(
			"strictly below the 0m contour"
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
		"province_visual_supersample": (
			map_3d._province_texture != null
			and map_3d._province_texture.get_width()
				== state.province_map_size.x
					* MapRenderer.PROVINCE_VISUAL_SUPERSAMPLE
			and map_3d._province_texture.get_height()
				== state.province_map_size.y
					* MapRenderer.PROVINCE_VISUAL_SUPERSAMPLE
		),
		# 海岸与城市边界共享平滑 coverage 样式，高程只保留海陆遮罩，
		# 不再额外生成第二条 0m contour。
		"unified_coast_boundary_style": (
			not zero_meter_city_boundary.is_empty()
			and zero_meter_city_boundary.size() % 2 == 0
			and not terrain_shader_code.contains("coast_band")
			and not terrain_shader_code.contains("contour_distance")
			and terrain_shader_code.contains("coast_boundary_strength")
			and is_equal_approx(
				province_boundary_max_alpha, coast_boundary_max_alpha
			)
			and province_boundary_max_alpha <= 0.53
			and diplomatic_boundary_max_alpha <= 0.73
			and province_boundary_pixels > 0
			and coast_boundary_pixels > 0
			and diplomatic_boundary_pixels > 0
			and province_has_feather
			and coast_has_feather
			and diplomatic_has_feather
		),
		"boundary_lod": (
			terrain_shader_code.contains("province_boundary_strength")
			and terrain_shader_code.contains("diplomatic_boundary_strength")
			and map_3d.has_method("_update_boundary_lod")
			and is_equal_approx(float(lod_close["province"]), 1.0)
			and float(lod_mid["province"]) < 1.0
			and float(lod_mid["province"]) > 0.55
			and absf(
				float(lod_58_before["province"])
					- float(lod_58_at["province"])
			) < 0.001
			and is_zero_approx(float(lod_far["province"]))
			and is_equal_approx(float(lod_far["coast"]), 1.0)
			and float(lod_country_mid["diplomatic"]) < 1.0
			and float(lod_country_mid["diplomatic"]) > 0.86
			and is_equal_approx(float(lod_overview["diplomatic"]), 0.86)
			and is_equal_approx(
				material_mid_province, float(lod_mid["province"])
			)
			and is_equal_approx(material_mid_coast, float(lod_mid["coast"]))
			and is_equal_approx(
				material_mid_diplomatic, float(lod_mid["diplomatic"])
			)
			and is_equal_approx(
				material_far_province, float(lod_overview["province"])
			)
			and is_equal_approx(
				material_far_coast, float(lod_overview["coast"])
			)
			and is_equal_approx(
				material_far_diplomatic, float(lod_overview["diplomatic"])
			)
		),
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
