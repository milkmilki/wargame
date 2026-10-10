extends SceneTree
## Full GPU checks for modes, window size and disposal of pending world work.
var scene
var failures := 0
var directory := "res://.dbg/cached-lifecycle"
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_CACHE_LIFECYCLE_FAIL ",message)
func _initialize(): call_deferred("run")
func show_view(name_value: String,mode: int,center: Vector2,detail: float):
	scene.mode_control.select(mode); scene.update_mode()
	scene.zoom = detail; scene.map_root.scale = Vector2.ONE*detail
	scene.map_root.position = Vector2(root.size)*.5-center*detail
	scene.limit_pan(); scene.refresh_symbols()
	check(await scene.await_render_ready(30000),"visible detail completes: "+name_value)
	await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(directory+"/"+name_value+".png")
func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1280,720); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	scene = load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready or scene.overlay==null: await process_frame
	scene.hud.get_parent().hide(); scene.simulation.paused = true
	var graph := hash(scene.military_payload.graph); var provinces := hash(scene.state.province_ids)
	await show_view("political1",0,Vector2(1300,360),1.)
	await show_view("political2",0,Vector2(1685,338),2.)
	await show_view("terrain4",1,Vector2(1685,338),4.)
	await show_view("habitability4",3,Vector2(1685,338),4.)
	var road: ArrayMesh = scene.copies[0].ink.persistent_layers[2].chunks[0].mesh
	root.size = Vector2i(1600,900); await process_frame; await process_frame
	check(await scene.await_render_ready(30000),"resized visible area completes")
	check(scene.symbol_view.size==Vector2i(1600,900),"GPU compositors follow window size")
	check(scene.copies[0].ink.persistent_layers[2].chunks[0].mesh==road,"resize retains road geometry")
	root.size = Vector2i(1280,720); await process_frame; await process_frame
	# Queue cold-region jobs, then replace the world before they publish.
	scene.zoom = 8.; scene.map_root.scale = Vector2.ONE*8.; scene.map_root.position = -Vector2(2400,1000)
	scene.limit_pan(); scene.refresh_symbols(); await process_frame
	var old_tiles = scene.symbol_tiles
	await scene.load_cached_payload(scene.military_payload)
	check(not is_instance_valid(old_tiles),"replacement releases old tile owner")
	check(await scene.await_render_ready(30000),"replacement publishes only its own version")
	check(hash(scene.military_payload.graph)==graph and hash(scene.state.province_ids)==provinces,"reload preserves authoritative geography and traffic")
	check(scene.render_scheduler.cache_bytes<=scene.render_scheduler.cache_budget,"world replacement respects the cache budget")
	await show_view("reloaded4",0,Vector2(1685,338),4.)
	var definition := MapDefinition.from_state(scene.state)
	check(MapDefinition.validate(definition).is_empty(),"native world template validates")
	var restored := GameState.new()
	restored.generate_from_map_definition(JSON.parse_string(JSON.stringify(definition)))
	await scene.present_world(restored,restored.atlas_layout,"atlas_renderer_template_roundtrip")
	await show_view("template4",0,Vector2(1685,338),4.)
	check(hash(scene.state.province_ids)==provinces,"template retains authoritative geography")
	check(scene.render_scheduler.cache_bytes<=scene.render_scheduler.cache_budget,"template replacement respects the cache budget")
	print("ATLAS_CACHE_LIFECYCLE failures=",failures," pid=",OS.get_process_id()," cache_bytes=",scene.render_scheduler.cache_bytes)
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(1 if failures else 0)
