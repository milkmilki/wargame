extends SceneTree
## Actual native entry, including generation, simulation import and GPU readiness.
var scene
func _initialize(): call_deferred("run")
func run():
	root.size=Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var directory := "res://.dbg/startup-baseline"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--startup-evidence="): directory=argument.trim_prefix("--startup-evidence=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var started := Time.get_ticks_msec()
	scene=load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	var stage := ""
	while not scene.view_ready or scene.generating:
		if stage!=scene.status.text:
			stage=scene.status.text; print("ATLAS_STARTUP_STAGE ",Time.get_ticks_msec()-started," ",stage)
		await process_frame
	var ready: bool=await scene.await_render_ready(60000)
	var result := {"pid":OS.get_process_id(),"scene":scene.scene_file_path,"godot":Engine.get_version_info().string,"seed":scene.state.world_seed,"ready":ready,"elapsed_ms":Time.get_ticks_msec()-started,"timing":scene.timing,"military_timing":scene.military_payload.timing,"cells":scene.data.mesh.n,"settlements":scene.state.land_cities().size(),"road_segments":scene.state.edges.size(),"args":OS.get_cmdline_user_args()}
	if "startup_profile" in scene: result.profile=scene.startup_profile
	var fingerprints := {}
	for key in ["raster","hierarchy","graph","ownership","district_pixels"]:
		fingerprints[key]=var_to_bytes(scene.military_payload[key]).hex_encode().sha256_text()
	result.fingerprints=fingerprints
	FileAccess.open(directory+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	FileAccess.open(directory+"/payload.bin",FileAccess.WRITE).store_var(scene.military_payload)
	RenderingServer.force_draw(true); root.get_texture().get_image().save_png(directory+"/global.png")
	print("ATLAS_STARTUP_RESULT ",JSON.stringify(result))
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(0 if ready else 1)
