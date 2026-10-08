extends SceneTree
var failures:=0
func _init() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(1600,1000)
	var model:=OS.get_environment("ATLAS_VISUAL_MODEL")
	var template: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-world-12345.json" if model in ["true","matched"] else "res://.dbg/atlas-benchmark-world-false.json"))
	if model=="matched": template.map_source_manifest="res://assets/terrain/eurasia_atlas_baseline_map_source.json"
	var state:=GameState.new();state.generate_from_map_definition(template,12345)
	var sim:=Simulation.new();root.add_child(sim);sim.setup(state);sim.paused=true
	var overlay:=MapRenderer.new();root.add_child(overlay);overlay.setup(state,sim);overlay.set_world_layer_visible(false);overlay.set_city_names_visible(false);overlay.set_nation_names_visible(true);overlay.set_army_icon_scale(0.25)
	var view:=StrategicMap3D.new();root.add_child(view);view.setup(state,sim,overlay)
	while view._terrain==null or view._terrain.land_cell_count()<=0: await process_frame
	await process_frame;await process_frame
	var output:="res://.dbg/atlas-visual-"+model;DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var overview:=view._camera_distance;var target:=view._camera_target
	var display_id: int=overlay.visual_atlas().city_id.get_instance_id()
	for region in [{"name":"full","center":Vector2(0.5,0.5),"zoom":1.0},{"name":"mediterranean","center":Vector2(MapSource.lonlat_to_map(15,38,state.map_source_manifest)[0],MapSource.lonlat_to_map(15,38,state.map_source_manifest)[1]),"zoom":0.28},{"name":"china","center":Vector2(MapSource.lonlat_to_map(108.9,34.3,state.map_source_manifest)[0],MapSource.lonlat_to_map(108.9,34.3,state.map_source_manifest)[1]),"zoom":0.28},{"name":"boundary","center":state.cities[250].map_position,"zoom":0.09}]:
		var center:=view._terrain.map_to_world(region.center)
		view._camera_target=target if region.name=="full" else Vector3(center.x,0,center.z)
		view._camera_distance=overview*region.zoom;view._apply_camera_transform()
		for mode in [MapRenderer.MapMode.POLITICAL,MapRenderer.MapMode.LOYALTY,MapRenderer.MapMode.TRADE,MapRenderer.MapMode.REGION]:
			view.set_map_mode(mode)
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			if overlay.visual_atlas().city_id.get_instance_id()!=display_id: failures+=1
			root.get_texture().get_image().save_png(output+"/"+region.name+"-"+str(mode)+".png")
	view._camera.position=view._camera_target+(view._camera.position-view._camera_target).rotated(Vector3.UP,0.35);view._camera.look_at(view._camera_target,Vector3.UP);await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/rotated.png")
	print("ATLAS_VISUAL renderer=",RenderingServer.get_video_adapter_name()," model=",model," failures=",failures)
	quit(1 if failures else 0)
