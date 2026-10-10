extends SceneTree
## Full native world, normal renderer and real input events. Dev cache skips generation only.
var scene
var failures := 0
var frames: Array = []
var directory := "res://.dbg/cached-navigation"
var sample_count := 500
var captures: Array = []
var detail_samples: Array = []
var simulate := false
var show_ui := false
var information := false
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_CACHED_FAIL ",message)
func percentile(values: Array,fraction: float) -> float:
	var ordered := values.duplicate(); ordered.sort(); return ordered[mini(ordered.size()-1,floori((ordered.size()-1)*fraction))]
func capture(name_value: String,center: Vector2,zoom_value: float):
	scene.zoom = zoom_value; scene.map_root.scale = Vector2.ONE*zoom_value
	scene.map_root.position = Vector2(root.size)*.5-center*zoom_value; scene.limit_pan(); scene.refresh_symbols()
	var start := Time.get_ticks_usec(); var ready: bool = await scene.await_render_ready(15000)
	check(ready,"visible content completed: "+name_value)
	await process_frame; var ready_ms := (Time.get_ticks_usec()-start)/1000.
	RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(directory+"/"+name_value+".png")
	var row := {"name":name_value,"ready_ms":ready_ms,"capture_ms":(Time.get_ticks_usec()-start)/1000.,"cache_bytes":scene.render_scheduler.cache_bytes}
	captures.append(row); print("ATLAS_CACHED_CAPTURE ",JSON.stringify(row))
func run():
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--samples="): sample_count = int(argument.get_slice("=",1))
		if argument.begins_with("--evidence="): directory = argument.get_slice("=",1)
		if argument=="--simulate": simulate = true
		if argument=="--show-ui": show_ui = true
		if argument=="--information": information = true
	root.size = Vector2i(1280,720); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	# Hidden D3D12 windows on this driver periodically block even with an empty
	# scene. Measure render/input work independently of that presentation wait.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene = load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready: await process_frame
	if not show_ui: scene.hud.get_parent().hide()
	scene.simulation.paused = true
	var graph := hash(scene.military_payload.graph); var provinces := hash(scene.state.province_ids)
	await capture("global",Vector2(1024,512),.625)
	await capture("china4",Vector2(1685,338),4.)
	if information: scene.show_information("nation",1)
	if simulate:
		scene.simulation.runtime_stage_profiling_enabled = true
		scene.simulation.paused = false
	var original_meshes: Array = []
	for layer in scene.copies[0].ink.persistent_layers: original_meshes.append(layer.build_count)
	var static_tiles: int=scene.symbol_tiles.tile_build_count
	var static_text: int=scene.text_layer.static_build_count
	var marker_data: Array=scene.text_layer.static_marker_key.duplicate()
	for i in range(sample_count):
		var start := Time.get_ticks_usec(); var kind := "pan"
		if i%10<8:
			var motion := InputEventMouseMotion.new(); motion.relative = Vector2(8 if i%100<50 else -8,2 if i%60<30 else -2)
			scene.dragging = true; scene._unhandled_input(motion)
		else:
			kind = "zoom"; var wheel := InputEventMouseButton.new(); wheel.position = Vector2(900,400); wheel.pressed = true
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP if i%10==8 else MOUSE_BUTTON_WHEEL_DOWN; scene._unhandled_input(wheel)
		var command_ms := (Time.get_ticks_usec()-start)/1000.
		await process_frame
		frames.append({"kind":kind,"command_ms":command_ms,"frame_ms":(Time.get_ticks_usec()-start)/1000.,"simulation_stage":str(scene.simulation.runtime_profile_stage)})
	scene.dragging = false; var settle := Time.get_ticks_usec(); await scene.await_render_ready(); var settle_ms := (Time.get_ticks_usec()-settle)/1000.
	check(not scene.navigation_in_progress,"there is no stop-input full-redraw timer")
	scene.simulation.paused = true
	if scene.symbol_tiles.static_world:
		check(scene.symbol_tiles.tile_build_count==static_tiles,"camera input never prepares natural symbols")
		check(scene.text_layer.static_build_count==static_text,"camera input never lays out fixed names")
		check(scene.text_layer.static_marker_key==marker_data,"camera input retains all-world city markers")
	while scene.simulation.runtime_day_in_progress(): await process_frame
	for i in range(12):
		var z := 5.7 if i%2==0 else 4.; var center := Vector2(1685+(i%3)*4,338)
		scene.zoom = z; scene.map_root.scale = Vector2.ONE*z; scene.map_root.position = Vector2(root.size)*.5-center*z; scene.limit_pan(); scene.refresh_symbols()
		var started := Time.get_ticks_usec(); check(await scene.await_render_ready(),"ordinary detail completes while navigation remains active")
		await process_frame; detail_samples.append((Time.get_ticks_usec()-started)/1000.)
	for i in range(original_meshes.size()): check(scene.copies[0].ink.persistent_layers[i].build_count==original_meshes[i],"input preserves stroke geometry")
	await capture("china8",Vector2(1685,338),8.)
	await capture("europe4",Vector2(1055,280),4.)
	await capture("dateline4",Vector2(0,512),4.)
	scene.simulation._set_coalition_war([1] as Array[int],[36] as Array[int]); await process_frame
	await capture("front4",Vector2(1621.7305,320.21884),4.)
	scene.mode_control.select(2); scene.update_mode(); await capture("districts4",Vector2(1685,338),4.)
	check(hash(scene.military_payload.graph)==graph and hash(scene.state.province_ids)==provinces,"rendering preserves traffic and administrative data")
	var times: Array = frames.map(func(row): return row.frame_ms)
	var result := {"pid":OS.get_process_id(),"seed":scene.state.world_seed,"scene":scene.scene_file_path,"godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"source":"atlas_development_cache" if Array(OS.get_cmdline_user_args()).any(func(arg): return arg.begins_with("--atlas-cache=")) else "native_generation","parameters":scene.state.generation_metadata,"frames":frames,"p50":percentile(times,.5),"p95":percentile(times,.95),"p99":percentile(times,.99),"settle_ms":settle_ms,"cache_bytes":scene.render_scheduler.cache_bytes,"tile_builds":scene.symbol_tiles.tile_build_count,"labels":scene.text_layer.layout_count,"max_publish_us":scene.render_scheduler.max_publish_usec,"failures":failures}
	result.captures = captures; result.profile = scene.render_scheduler.profile
	result.marker_update_us = scene.text_layer.city_markers.max_update_usec
	result.vsync = "disabled_for_render_benchmark"
	result.detail_samples = detail_samples; result.detail_p95 = percentile(detail_samples,.95)
	result.simulation = "running_during_input" if simulate else "paused"
	result.day = scene.state.day
	result.simulation_peak_us = scene.simulation.runtime_span_peak_usec
	result.simulation_total_us = scene.simulation.runtime_span_total_usec
	result.ui_visible = show_ui; result.information_visible = information
	result.symbol_group_updates = scene.symbol_tiles.group_update_count
	result.terrain_bakes = scene.raster_layers.build_count if scene.raster_layers!=null else 0
	result.army_redraws = scene.overlay.marker_redraw_count
	FileAccess.open(directory+"/manifest.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")); print("ATLAS_CACHED_RESULT ",JSON.stringify(result))
	while scene.simulation.runtime_day_in_progress(): await process_frame
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(1 if failures else 0)
