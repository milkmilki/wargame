extends SceneTree
## Frontend artifact smoke test: verifies the layered strategic-map language used by
## counters, cities, battles, roads and campaign arrows. This test checks actual
## rendering artifacts rather than treating a non-empty terrain mesh as coverage.

const TIMEOUT_MSEC := 15000


func _init() -> void:
	call_deferred("_run")


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
