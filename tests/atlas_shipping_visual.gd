extends SceneTree
var scene
var checks := 0
var failures := 0
const DIRECTORY := "res://.dbg/atlas-shipping"
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr("SHIPPING_GPU_FAIL ",message)
func capture(name: String):
	await process_frame; await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(DIRECTORY+"/"+name+".png")
func run():
	root.size=Vector2i(1280,720); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	scene=load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	var deadline := Time.get_ticks_msec()+120000
	while (not scene.view_ready or scene.overlay==null) and Time.get_ticks_msec()<deadline: await process_frame
	check(scene.view_ready,"real scene starts with shipping")
	if not scene.view_ready: quit(1); return
	scene.simulation.paused=true
	check(await scene.await_render_ready(60000),"political rendering completes")
	var state: GameState=scene.state
	check(state.world_seed==1 and state.nations.size()==40 and state.atlas_layout.data.options.settlement_mask.enabled,"real seed-1/40/Eurasia")
	check(is_instance_valid(scene.shipping_layer) and not state.atlas_layout.shipping.routes.is_empty(),"real sea strokes are installed")
	var nomad := -1
	for nation in state.nations:
		if nation.environment_kind=="nomad": nomad=nation.id; break
	check(nomad>=0,"real scene has a nomadic country")
	if nomad>=0:
		var nation: Nation=state.nations[nomad]; var capital: City=state.cities[nation.founding_city_id]
		check(capital.name==capital.short_name and nation.name==capital.name,"live nomadic seat and country retain complete names")
		await scene.show_information("nation",nomad)
		check(scene.information_document().title==nation.name+"部","live country inspector displays transliteration plus tribal title")
		scene.zoom=3.; scene.map_root.scale=Vector2.ONE*3.; scene.map_root.position=Vector2(890,360)-capital.map_position*Vector2(2048,1024)*3.; scene.limit_pan(); scene.camera_feedback()
		check(await scene.await_render_ready(60000),"nomadic map labels settle")
		await capture("nomad-names")
	scene.info_panel.dismiss()
	scene.mode_control.select(scene.TRADE_MODE); scene.update_mode()
	check(await scene.await_render_ready(60000),"trade rendering completes")
	scene.refresh_trade_routes()
	check(is_instance_valid(scene.trade_routes_layer) and scene.trade_routes_layer.visible,"sea-capable trade routes display")
	check(state.trade_routes.any(func(route):return route.get("uses_water",false)),"published live trade includes sea routes")
	scene.zoom=2.2; scene.map_root.scale=Vector2.ONE*2.2
	scene.map_root.position=Vector2(640,380)-Vector2((25.+180.)/360.,(90.-37.)/180.)*Vector2(2048,1024)*2.2; scene.limit_pan(); scene.camera_feedback()
	check(await scene.await_render_ready(60000),"Mediterranean navigation finishes")
	await capture("sea-trade")
	var samples: Array[int] = []
	for _i in range(120):
		var started := Time.get_ticks_usec(); await process_frame; samples.append(Time.get_ticks_usec()-started)
	samples.sort(); var total := 0
	for value in samples: total+=value
	var metrics := {"average_ms":float(total)/samples.size()/1000.,"p95_ms":samples[114]/1000.,"peak_ms":samples.back()/1000.}
	FileAccess.open(DIRECTORY+"/gpu.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"frames":metrics,"shipping_routes":state.atlas_layout.shipping.routes.size(),"renderer":RenderingServer.get_video_adapter_name()},"  "))
	print("SHIPPING_GPU checks=",checks," failures=",failures," frames=",metrics," renderer=",RenderingServer.get_video_adapter_name())
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(1 if failures else 0)
