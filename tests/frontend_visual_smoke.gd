extends SceneTree
## Frontend artifact smoke test: verifies the layered strategic-map language used by
## counters, cities, battles, roads and campaign arrows. This test checks actual
## rendering artifacts rather than treating a non-empty terrain mesh as coverage.

const TIMEOUT_MSEC := 15000


func _init() -> void:
	call_deferred("_run")


func _mesh_vertex_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() <= 0:
		return 0
	return (
		mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		as PackedVector3Array
	).size()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := GameState.new()
	state.generate_world(12345)
	var frontier: Edge = null
	for edge in state.edges:
		if (
			edge.max_manpower > 0
			and state.cities[edge.city_a].owner_nation
				!= state.cities[edge.city_b].owner_nation
		):
			frontier = edge
			break
	if frontier == null:
		push_error("FRONTEND_VISUAL_NO_FRONTIER")
		quit(1)
		return
	state.add_campaign_visual_event(
		state.cities[frontier.city_a].owner_nation,
		frontier.city_b, [frontier.city_a], 1, 30
	)
	var battle := state.new_battle(Battle.Kind.FIELD)
	battle.edge = frontier
	battle.contact_dist_a = float(frontier.distance) * 0.5
	battle.round_no = 5
	state.armies[0].morale = state.armies[0].max_morale * 0.25
	state.armies[0].starving = true

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
			push_error("FRONTEND_VISUAL_TIMEOUT")
			quit(1)
			return
		await process_frame
	await process_frame

	var terrain_material := (
		map_3d._terrain.mesh_instance().material_override
		as ShaderMaterial
	)
	var terrain_shader_code := terrain_material.shader.code
	var initial_vertical_strength := map_3d._vertical_terrain_light_strength
	var initial_vertical_energy := map_3d._vertical_terrain_light.light_energy
	var initial_sculpt_strength := map_3d._elevation_shadow_strength
	var initial_sculpt_energy := map_3d._sculpt_terrain_light.light_energy
	map_3d.set_vertical_terrain_light_strength(0.37)
	var tuned_vertical_strength := map_3d._vertical_terrain_light_strength
	var tuned_vertical_energy := map_3d._vertical_terrain_light.light_energy
	map_3d.set_vertical_terrain_light_strength(-1.0)
	var minimum_vertical_strength := map_3d._vertical_terrain_light_strength
	var minimum_vertical_energy := map_3d._vertical_terrain_light.light_energy
	map_3d.set_vertical_terrain_light_strength(2.0)
	var maximum_vertical_strength := map_3d._vertical_terrain_light_strength
	var maximum_vertical_energy := map_3d._vertical_terrain_light.light_energy
	map_3d.set_vertical_terrain_light_strength(
		StrategicMap3D.VERTICAL_TERRAIN_LIGHT_DEFAULT_STRENGTH
	)

	var campaign_mesh := map_3d._campaigns.mesh as ArrayMesh
	var campaign_material := map_3d._campaigns.material_override as StandardMaterial3D
	var campaign_vertices := 0
	if campaign_mesh != null and campaign_mesh.get_surface_count() > 0:
		campaign_vertices = (
			campaign_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			as PackedVector3Array
		).size()
	var campaign_arch_valid := false
	var arrow_from := state.cities[frontier.city_a].map_position
	var arrow_to := state.cities[frontier.city_b].map_position
	var from_metric := Vector2(
		arrow_from.x * map_3d._world_size.x,
		arrow_from.y * map_3d._world_size.y
	)
	var to_metric := Vector2(
		arrow_to.x * map_3d._world_size.x,
		arrow_to.y * map_3d._world_size.y
	)
	var target_delta := to_metric - from_metric
	var source_delta := (
		MapRenderer.CAMPAIGN_ARROW_SOURCE_TIP
		- MapRenderer.CAMPAIGN_ARROW_SOURCE_TAIL
	)
	if target_delta.length_squared() > 0.000001:
		var arrow_scale := target_delta.length() / source_delta.length()
		var arrow_rotation := target_delta.angle() - source_delta.angle()
		var from_height := map_3d._terrain.height_at_map_position(arrow_from)
		var to_height := map_3d._terrain.height_at_map_position(arrow_to)
		var arch_height := map_3d._campaign_arrow_arch_height(
			arrow_from, arrow_to, target_delta.length(),
			from_height, to_height
		)
		var tail_world := map_3d._campaign_arrow_surface_point(
			MapRenderer.CAMPAIGN_ARROW_SOURCE_TAIL, from_metric,
			arrow_scale, arrow_rotation, from_height, to_height, arch_height
		)
		var middle_world := map_3d._campaign_arrow_surface_point(
			MapRenderer.CAMPAIGN_ARROW_SOURCE_TAIL + source_delta * 0.5,
			from_metric, arrow_scale, arrow_rotation,
			from_height, to_height, arch_height
		)
		var tip_world := map_3d._campaign_arrow_surface_point(
			MapRenderer.CAMPAIGN_ARROW_SOURCE_TIP, from_metric,
			arrow_scale, arrow_rotation, from_height, to_height, arch_height
		)
		campaign_arch_valid = (
			absf(
				tail_world.y - from_height
					- StrategicMap3D.CAMPAIGN_ARROW_ENDPOINT_CLEARANCE
			) < 0.001
			and absf(
				tip_world.y - to_height
					- StrategicMap3D.CAMPAIGN_ARROW_ENDPOINT_CLEARANCE
			) < 0.001
			and middle_world.y
				> lerpf(tail_world.y, tip_world.y, 0.5)
					+ StrategicMap3D.CAMPAIGN_ARROW_MIN_ARCH_HEIGHT * 0.95
		)
	var major_mesh := map_3d._roads.mesh as ArrayMesh
	var minor_mesh := map_3d._minor_roads.mesh as ArrayMesh
	var territory_labels_valid := not map_3d._nation_labels.is_empty()
	for nation_label in map_3d._nation_labels:
		territory_labels_valid = (
			territory_labels_valid
			and nation_label.billboard == BaseMaterial3D.BILLBOARD_DISABLED
			and nation_label.no_depth_test
			and nation_label.position.y < StrategicMap3D.HEIGHT_SCALE + 0.5
		)
	var territory_label_scale_ratio := 0.0
	if state.nations.size() >= 2:
		var layout_a := map_3d._nation_label_layout(0)
		var layout_b := map_3d._nation_label_layout(1)
		if not layout_a.is_empty() and not layout_b.is_empty():
			territory_label_scale_ratio = absf(
				float(layout_a["glyph_scale"])
				- float(layout_b["glyph_scale"])
			)
	var low_loyalty_color := MapRenderer.loyalty_color(10.0)
	var middle_loyalty_color := MapRenderer.loyalty_color(50.0)
	var high_loyalty_color := MapRenderer.loyalty_color(90.0)
	var renderer_source := FileAccess.get_file_as_string(
		"res://scripts/view/map_renderer.gd"
	)
	var trade_draw_start := renderer_source.find("func _draw_trade_routes()")
	var trade_draw_end := renderer_source.find(
		"func _draw_trade_flow_markers", trade_draw_start
	)
	var trade_draw_source := ""
	if trade_draw_start >= 0 and trade_draw_end > trade_draw_start:
		trade_draw_source = renderer_source.substr(
			trade_draw_start, trade_draw_end - trade_draw_start
		)
	var trade_2d_mode_visibility := trade_draw_source.contains(
		"_map_mode != MapMode.TRADE"
	)
	var sample_path := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 0.0),
	])
	var sample_2d_before := MapRenderer.polyline_sample(sample_path, 10.0)
	var sample_2d_after := MapRenderer.polyline_sample(sample_path, 20.0)
	var trade_2d_marker_motion := (
		(sample_2d_before["tangent"] as Vector2).is_equal_approx(
			Vector2.RIGHT
		)
		and (sample_2d_after["position"] as Vector2).x
			> (sample_2d_before["position"] as Vector2).x
	)
	var active_route := {
		"status": TradeNetwork.ACTIVE,
		"food_transfer": 0,
	}
	var food_route := {
		"status": TradeNetwork.ACTIVE,
		"food_transfer": 25,
	}
	var rerouted_route := {"status": TradeNetwork.REROUTED}
	var blocked_route := {"status": TradeNetwork.BLOCKED}
	var trade_style_contract := (
		MapRenderer.trade_route_color(active_route, true)
			.is_equal_approx(MapRenderer.TRADE_ACTIVE_GOLD)
		and MapRenderer.trade_route_color(food_route, true)
			.is_equal_approx(MapRenderer.TRADE_ACTIVE_CYAN)
		and MapRenderer.trade_route_color(rerouted_route, true)
			.is_equal_approx(MapRenderer.TRADE_REROUTED_ORANGE)
		and MapRenderer.trade_route_color(blocked_route, true)
			.is_equal_approx(MapRenderer.TRADE_BLOCKED_RED)
	)
	var visual_trade_route: Dictionary = {
		"status": TradeNetwork.ACTIVE,
		"food_transfer": 0,
		"city_path": [frontier.city_a, frontier.city_b],
	}
	var visual_trade_routes: Array[Dictionary] = []
	visual_trade_routes.append(visual_trade_route)
	state.trade_routes = visual_trade_routes
	state.trade_revision += 1
	await process_frame
	var active_trade_mesh := map_3d._trade_routes.mesh as ArrayMesh
	var active_trade_vertices := _mesh_vertex_count(active_trade_mesh)
	var active_marker_count := map_3d._trade_flow_markers.multimesh.instance_count
	state.trade_routes[0]["status"] = TradeNetwork.REROUTED
	state.trade_revision += 1
	await process_frame
	var rerouted_trade_mesh := map_3d._trade_routes.mesh as ArrayMesh
	var rerouted_trade_vertices := _mesh_vertex_count(rerouted_trade_mesh)
	var rerouted_marker_count := map_3d._trade_flow_markers.multimesh.instance_count
	state.trade_routes[0]["status"] = TradeNetwork.BLOCKED
	state.trade_revision += 1
	await process_frame
	var blocked_trade_mesh := map_3d._trade_routes.mesh as ArrayMesh
	var blocked_trade_vertices := _mesh_vertex_count(blocked_trade_mesh)
	var blocked_marker_count := map_3d._trade_flow_markers.multimesh.instance_count
	var trade_revision_rebuilt := (
		map_3d._last_trade_revision == state.trade_revision
		and active_trade_mesh != rerouted_trade_mesh
		and rerouted_trade_mesh != blocked_trade_mesh
	)
	var political_trade_hidden := (
		not map_3d._trade_routes.visible
		and not map_3d._trade_flow_markers.visible
	)
	state.trade_routes[0]["status"] = TradeNetwork.ACTIVE
	state.trade_revision += 1
	await process_frame
	map_3d.set_map_mode(MapRenderer.MAP_MODE_TRADE)
	var marker_material := (
		map_3d._trade_flow_markers.material_override as StandardMaterial3D
	)
	var marker_path: Dictionary = map_3d._trade_flow_paths[0]
	var marker_distance_before := fposmod(
		map_3d._trade_flow_offsets[0]
			+ map_3d._trade_flow_time * StrategicMap3D.TRADE_FLOW_SPEED,
		float(marker_path["length"])
	)
	var marker_pose := map_3d._trade_flow_pose_at_distance(
		marker_path, marker_distance_before
	)
	var marker_pose_after := map_3d._trade_flow_pose_at_distance(
		marker_path,
		fposmod(
			marker_distance_before + 0.25 * StrategicMap3D.TRADE_FLOW_SPEED,
			float(marker_path["length"])
		)
	)
	var marker_orientation_and_motion := (
		not marker_pose.is_empty()
		and not marker_pose_after.is_empty()
		and (marker_pose["transform"] as Transform3D).basis.z.normalized().dot(
			(marker_pose["direction"] as Vector3).normalized()
		) > 0.99
		and (marker_pose["transform"] as Transform3D).origin.distance_to(
			(marker_pose_after["transform"] as Transform3D).origin
		) > 0.001
	)
	var previous_camera_distance := map_3d._camera_distance
	map_3d._camera_distance = StrategicMap3D.CAMERA_MAX_DISTANCE
	map_3d._update_map_detail_visibility()
	var trade_visible_far := map_3d._trade_routes.visible
	map_3d._camera_distance = StrategicMap3D.CAMERA_MIN_DISTANCE
	map_3d._update_map_detail_visibility()
	var trade_visible_near := map_3d._trade_routes.visible
	map_3d._camera_distance = previous_camera_distance
	map_3d._update_map_detail_visibility()
	var trade_mode_visibility := (
		map_3d.map_mode() == MapRenderer.MAP_MODE_TRADE
		and overlay.map_mode() == MapRenderer.MAP_MODE_TRADE
		and map_3d._trade_routes.visible
		and map_3d._trade_flow_markers.visible
		and is_equal_approx(map_3d._trade_routes.transparency, 0.0)
		and map_3d._roads.transparency > 0.0
		and map_3d._minor_roads.transparency > 0.0
		and trade_visible_near
		and trade_visible_far
	)
	map_3d.set_map_mode(MapRenderer.MAP_MODE_LOYALTY)
	var loyalty_mode_contract := (
		map_3d.map_mode() == MapRenderer.MAP_MODE_LOYALTY
		and overlay.map_mode() == MapRenderer.MAP_MODE_LOYALTY
		and map_3d._loyalty_texture != null
		and not map_3d._trade_routes.visible
		and not map_3d._trade_flow_markers.visible
	)
	map_3d.set_map_mode(MapRenderer.MAP_MODE_POLITICAL)
	var checks := {
		"city_bases": map_3d._city_bases.multimesh.instance_count == state.cities.size(),
		"city_resources": map_3d._city_resource_markers.multimesh.instance_count == state.cities.size(),
		"dock_rings": map_3d._dock_rings.multimesh.instance_count == state.cities.size(),
		"army_bases": map_3d._army_bases.multimesh.instance_count == map_3d._armies.multimesh.instance_count,
		"army_symbol_a": map_3d._army_symbol_a.multimesh.instance_count == map_3d._armies.multimesh.instance_count,
		"army_symbol_b": map_3d._army_symbol_b.multimesh.instance_count == map_3d._armies.multimesh.instance_count,
		"morale_layer": map_3d._army_morale_bars.multimesh.instance_count == map_3d._armies.multimesh.instance_count and map_3d._morale_color(state.armies[0].morale_ratio(), state.armies[0].starving) == StrategicMap3D.MAP_ALERT,
		"battle_center": map_3d._battles.multimesh.instance_count == 1,
		"battle_ring": map_3d._battle_rings.multimesh.instance_count == 1,
		"battle_cross": map_3d._battle_cross_a.multimesh.instance_count == 1,
		"battle_label": map_3d._battle_labels.size() == 1,
		"campaign_geometry": campaign_vertices >= 150,
		"campaign_texture": (
			campaign_material != null
			and campaign_material.albedo_texture
				== MapRenderer.CAMPAIGN_ARROW_TEXTURE
		),
		"campaign_unlit_surface": (
			campaign_material != null
			and campaign_material.shading_mode
				== BaseMaterial3D.SHADING_MODE_UNSHADED
			and not campaign_material.no_depth_test
		),
		"campaign_arch": campaign_arch_valid,
		"major_roads": major_mesh != null and major_mesh.get_surface_count() > 0,
		"minor_roads": minor_mesh != null and minor_mesh.get_surface_count() > 0,
		"road_hierarchy": map_3d._road_width_for_capacity(Edge.TERRAIN_STANDARD_MANPOWER) > map_3d._road_width_for_capacity(Edge.TERRAIN_LOW_MANPOWER) * 2.0,
		"loyalty_gradient": (
			high_loyalty_color.g > low_loyalty_color.g
			and high_loyalty_color.g > high_loyalty_color.r
			and low_loyalty_color.r > low_loyalty_color.g
			and high_loyalty_color.g / high_loyalty_color.r
				> middle_loyalty_color.g / middle_loyalty_color.r
			and middle_loyalty_color.g / middle_loyalty_color.r
				> low_loyalty_color.g / low_loyalty_color.r
		),
		"trade_route_styles": trade_style_contract,
		"trade_route_geometry_styles": (
			active_trade_vertices > 0
			and rerouted_trade_vertices == active_trade_vertices
			and blocked_trade_vertices > 0
			and blocked_trade_vertices < active_trade_vertices
		),
		"trade_route_mesh_node": (
			map_3d._trade_routes != null
			and map_3d._trade_routes.name == "TradeRoutes"
			and (map_3d._trade_routes.material_override as StandardMaterial3D)
				.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
			and not (map_3d._trade_routes.material_override as StandardMaterial3D)
				.no_depth_test
		),
		"trade_flow_marker_node": (
			map_3d._trade_flow_markers != null
			and map_3d._trade_flow_markers.name == "TradeFlowMarkers"
			and marker_material != null
			and marker_material.shading_mode
				== BaseMaterial3D.SHADING_MODE_UNSHADED
			and not marker_material.no_depth_test
		),
		"trade_flow_marker_statuses": (
			active_marker_count > 0
			and rerouted_marker_count > 0
			and blocked_marker_count == 0
		),
		"trade_flow_orientation_and_motion": marker_orientation_and_motion,
		"trade_revision_rebuild": trade_revision_rebuilt,
		"trade_2d_mode_visibility": trade_2d_mode_visibility,
		"trade_2d_marker_motion": trade_2d_marker_motion,
		"political_trade_hidden": political_trade_hidden,
		"trade_mode_visibility": trade_mode_visibility,
		"loyalty_mode_contract": loyalty_mode_contract,
		"country_boundary_contract": (
			map_3d._country_boundary_texture != null
			and map_3d._country_color_texture != null
			and map_3d._country_boundary_texture.get_size()
				== map_3d._province_texture.get_size()
			and map_3d._country_color_texture.get_size()
				== map_3d._province_texture.get_size()
			and terrain_material.get_shader_parameter(
				"country_boundary_texture"
			) == map_3d._country_boundary_texture
			and terrain_material.get_shader_parameter(
				"country_color_texture"
			) == map_3d._country_color_texture
			and is_equal_approx(
				float(terrain_material.get_shader_parameter(
					"country_boundary_strength"
				)),
				1.0
			)
			and map_3d._country_boundary_texture.get_image().has_mipmaps()
			and terrain_shader_code.contains(
				"uniform sampler2D country_boundary_texture"
			)
			and terrain_shader_code.contains(
				"uniform sampler2D country_color_texture"
			)
			and terrain_shader_code.contains(
				"uniform float country_boundary_strength"
			)
			and not terrain_shader_code.contains(
				"diplomatic_boundary_texture"
			)
			and not terrain_shader_code.contains(
				"diplomatic_boundary_strength"
			)
		),
		"terrain_light_contract": (
			map_3d.has_method("set_vertical_terrain_light_strength")
			and is_equal_approx(
				StrategicMap3D.VERTICAL_TERRAIN_LIGHT_MAX_ENERGY,
				1.50
			)
			and is_equal_approx(
				StrategicMap3D.VERTICAL_TERRAIN_LIGHT_DEFAULT_STRENGTH,
				0.62
			)
			and is_equal_approx(
				StrategicMap3D.SCULPT_TERRAIN_LIGHT_MAX_ENERGY,
				2.00
			)
			and is_equal_approx(
				StrategicMap3D.SCULPT_TERRAIN_LIGHT_DEFAULT_STRENGTH,
				0.42
			)
			and is_equal_approx(
				initial_vertical_strength,
				StrategicMap3D.VERTICAL_TERRAIN_LIGHT_DEFAULT_STRENGTH
			)
			and is_equal_approx(
				initial_vertical_energy,
				StrategicMap3D.VERTICAL_TERRAIN_LIGHT_DEFAULT_STRENGTH
					* StrategicMap3D.VERTICAL_TERRAIN_LIGHT_MAX_ENERGY
			)
			and is_equal_approx(
				initial_sculpt_strength,
				StrategicMap3D.SCULPT_TERRAIN_LIGHT_DEFAULT_STRENGTH
			)
			and is_equal_approx(
				initial_sculpt_energy,
				StrategicMap3D.SCULPT_TERRAIN_LIGHT_DEFAULT_STRENGTH
					* StrategicMap3D.SCULPT_TERRAIN_LIGHT_MAX_ENERGY
			)
			and is_equal_approx(tuned_vertical_strength, 0.37)
			and is_equal_approx(
				tuned_vertical_energy,
				0.37 * StrategicMap3D.VERTICAL_TERRAIN_LIGHT_MAX_ENERGY
			)
			and is_zero_approx(minimum_vertical_strength)
			and is_zero_approx(minimum_vertical_energy)
			and is_equal_approx(maximum_vertical_strength, 1.0)
			and is_equal_approx(
				maximum_vertical_energy,
				StrategicMap3D.VERTICAL_TERRAIN_LIGHT_MAX_ENERGY
			)
			and is_equal_approx(
				map_3d._vertical_terrain_light_strength,
				StrategicMap3D.VERTICAL_TERRAIN_LIGHT_DEFAULT_STRENGTH
			)
		),
		"territory_labels": territory_labels_valid,
		"territory_label_scaling": territory_label_scale_ratio > 0.001,
	}
	var valid := true
	for check_value in checks.values():
		valid = valid and bool(check_value)
	if not valid:
		print(
			"FRONTEND_VISUAL_DIAGNOSTIC checks=", checks,
			" campaign_vertices=", campaign_vertices
		)
		push_error("FRONTEND_VISUAL_INVALID")
		quit(1)
		return
	print(
		"FRONTEND_VISUAL_OK counters=",
		map_3d._armies.multimesh.instance_count,
		" cities=", map_3d._cities.multimesh.instance_count,
		" campaign_vertices=", campaign_vertices
	)
	map_3d.free()
	overlay.free()
	simulation.free()
	quit(0)
