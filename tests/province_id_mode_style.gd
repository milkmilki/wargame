extends SceneTree
## Same labels must also use the same edge treatment when switching map modes.
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("PROVINCE_ID_MODE_STYLE_FAIL: ", message)

func run() -> void:
	root.size = Vector2i(1600, 900)
	var state := GameState.new()
	check(state.generate_world(12345, 40, 500, "", {}, 12345, "",
		"res://assets/terrain/eurasia_hydrology_map_source.json"), "formal Eurasia generation")
	if not failures.is_empty():
		quit(1)
		return
	var saved_ids := state.province_ids.duplicate()
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.paused = true
	var overlay := MapRenderer.new()
	root.add_child(overlay)
	overlay.setup(state, simulation)
	overlay.set_world_layer_visible(false)
	overlay.set_city_names_visible(false)
	overlay.set_nation_names_visible(false)
	overlay.set_army_icon_scale(0.25)
	var view := StrategicMap3D.new()
	root.add_child(view)
	view.setup(state, simulation, overlay)
	var started := Time.get_ticks_msec()
	while view._terrain == null or view._terrain.land_cell_count() == 0:
		if Time.get_ticks_msec() - started > 60000:
			check(false, "terrain timeout")
			quit(1)
			return
		await process_frame
	var material := view._terrain.mesh_instance().material_override as ShaderMaterial
	var atlas_ids: PackedByteArray = overlay.visual_atlas().city_id.get_data()
	var edge_id: RID
	var distance_id: RID
	var output := OS.get_environment("PROVINCE_STYLE_VISUAL_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	# Start in loyalty, then return to political after the other modes. This
	# catches mode-switch cache differences as well as the initial style.
	for mode in [MapRenderer.MapMode.LOYALTY, MapRenderer.MapMode.POLITICAL,
		MapRenderer.MapMode.TRADE, MapRenderer.MapMode.REGION, MapRenderer.MapMode.POLITICAL]:
		view.set_map_mode(mode)
		await process_frame
		check(material.get_shader_parameter("unified_region_fill_enabled") == 1.0, "all modes use shared IDs")
		check(material.get_shader_parameter("curved_province_borders_enabled") == 1.0, "all modes retain old loyalty curved border ink")
		check(material.get_shader_parameter("country_fill_fade_enabled") == 0.0, "no mode-specific raster gradient: %d" % mode)
		var edge: Texture2D = material.get_shader_parameter("visual_region_edge_texture")
		var distance: Texture2D = material.get_shader_parameter("visual_region_distance_texture")
		if not edge_id.is_valid():
			edge_id = edge.get_rid()
			distance_id = distance.get_rid()
		check(edge.get_rid() == edge_id and distance.get_rid() == distance_id, "mode switches reuse boundary textures")
		check(overlay.visual_atlas().city_id.get_data() == atlas_ids and state.province_ids == saved_ids, "mode switches preserve territory")
		if not output.is_empty():
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(output.path_join("province-style-%d.png" % mode)) == OK, "save real-render preview")
	# Legacy maps retain their existing finish. Exercise the same policy used
	# by both synchronous refresh and asynchronous texture commits.
	state.map_source_manifest = MapSource.DEFAULT_MANIFEST
	check(view._country_fill_fade_enabled(-1), "legacy political gradient stays enabled")
	check(not view._country_fill_fade_enabled(0), "diplomatic view keeps flat fill")
	view._map_mode = MapRenderer.MapMode.LOYALTY
	check(not view._country_fill_fade_enabled(-1), "legacy loyalty stays unchanged")
	view.free()
	overlay.free()
	simulation.free()
	print("PROVINCE_ID_MODE_STYLE: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)
