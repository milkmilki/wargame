extends SceneTree
var scene
var checks := 0
var failures := 0
const DIRECTORY := "res://.dbg/trade-corridors"
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr("CORRIDOR_GPU_FAIL ",message)
func capture(name: String):
	await process_frame; await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(DIRECTORY+"/"+name+".png")
func focus(zoom: float,point: Vector2):
	scene.zoom=zoom; scene.map_root.scale=Vector2.ONE*zoom
	scene.map_root.position=Vector2(640,380)-point*zoom
	scene.limit_pan(); scene.camera_feedback()
	check(await scene.await_render_ready(60000),"trade camera settles")
func run():
	root.size=Vector2i(1280,720); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	scene=load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	var deadline := Time.get_ticks_msec()+120000
	while (not scene.view_ready or scene.overlay==null) and Time.get_ticks_msec()<deadline: await process_frame
	check(scene.view_ready,"real scene starts")
	if not scene.view_ready: quit(1); return
	scene.simulation.paused=true; scene.mode_control.select(scene.TRADE_MODE); scene.update_mode()
	check(await scene.await_render_ready(60000),"real trade view finishes")
	check(scene.state.world_seed==1 and scene.state.nations.size()==40 and scene.state.atlas_layout.data.options.settlement_mask.enabled,"seed-1/40/Eurasia")
	check(scene.state.trade_routes.size()==300,"all trade relationships survive corridor routing")
	var point := Vector2((25.+180.)/360.,(90.-37.)/180.)*Vector2(2048,1024)
	await focus(2.2,point); await capture("detail")
	check(is_equal_approx(scene.shipping_layer.material.get_shader_parameter("stroke_color").a,.18),"available sea routes are faint behind actual commerce")
	check(not scene.trade_routes_layer.stroke_layers[0].visible,"regional zoom prioritizes trunks")
	await focus(4.,point); await capture("detail-all")
	check(scene.trade_routes_layer.stroke_layers[0].visible,"close zoom restores local branches")
	var builds: int=scene.trade_routes_layer.build_count
	scene.fit_map(); scene.camera_feedback()
	check(await scene.await_render_ready(60000),"world overview finishes"); await capture("world")
	check(scene.trade_routes_layer.build_count==builds,"camera changes reuse corridor meshes")
	var samples: Array[int]=[]
	for _i in range(120):
		var started := Time.get_ticks_usec(); await process_frame; samples.append(Time.get_ticks_usec()-started)
	samples.sort(); var total := 0
	for value in samples: total+=value
	var metrics := {"average_ms":float(total)/samples.size()/1000.,"p95_ms":samples[114]/1000.,"peak_ms":samples.back()/1000.}
	print("CORRIDOR_GPU checks=",checks," failures=",failures," frames=",metrics," renderer=",RenderingServer.get_video_adapter_name())
	FileAccess.open(DIRECTORY+"/gpu.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"frames":metrics},"  "))
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(1 if failures else 0)
