extends SceneTree
## Real map + real simulation; inspect navigation, history, scrolling and camera.
var scene
var failures := 0
var directory := "res://.dbg/information-ui"
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_INFO_GPU_FAIL ",message)
func capture(name_value: String):
	check(await scene.await_render_ready(30000),"map detail completes")
	await process_frame; await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(directory+"/"+name_value+".png")
func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	scene=load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready or scene.overlay==null: await process_frame
	scene.simulation.paused=true
	var graph := hash(scene.military_payload.graph); var provinces := hash(scene.state.province_ids); var rng: int=scene.state.rng.state
	scene.zoom=4.; scene.map_root.scale=Vector2.ONE*4.; scene.map_root.position=Vector2(826,360)-Vector2(1685,338)*4.
	scene.limit_pan(); scene.refresh_symbols()
	var closest := INF; var selected := -1
	for city in scene.state.land_cities():
		var d: float=city.map_position.distance_squared_to(Vector2(1685,338)/Vector2(2048,1024))
		if d<closest: closest=d; selected=city.id
	scene.select_at(scene.state.cities[selected].map_position*Vector2(2048,1024))
	check(scene.information_kind=="city" and scene.info_panel.visible,"map selection opens our city information")
	await capture("city-top")
	var builds: int=scene.info_panel.build_count
	scene.info_panel.scroll.scroll_vertical=10000; await capture("city-bottom")
	var owner: int=scene.state.cities[selected].owner_nation
	scene.information_action("nation",owner); check(scene.information_kind=="nation","country link opens our actual country")
	await capture("nation-top")
	scene.info_panel.scroll.scroll_vertical=10000; await capture("nation-bottom")
	scene.information_action("city",scene.state.nations[owner].capital_city_id); check(scene.information_kind=="city","capital links return to city information")
	for unit in scene.state.armies:
		if unit.owner_nation==owner and unit.size>0:
			scene.show_information("army",unit.id); break
	await capture("army")
	scene.show_information("road",0); await capture("road")
	scene.show_information("nation",owner); scene.history_control.value=0; scene.show_history(); await capture("history")
	check(scene.info_panel.document.get("notice","").contains("历史"),"history uses a visible read-only notice")
	check(not scene.info_panel.document.sections.any(func(s): return s.title in ["国库与人口库","军队","最近月度结算"]),"political history does not masquerade as a full economic/military save")
	check(scene.info_panel.document.actions.all(func(a): return a.disabled if a.key in ["player","declare"] else true),"history commands are disabled")
	var player_before: float = scene.player_nation.value; scene.information_action("player",(owner+1)%40)
	check(scene.player_nation.value==player_before,"direct historical actions cannot change the controlled country")
	check(scene.interface.pause_button.disabled and scene.interface.step_button.disabled,"history disables timeline advance controls too")
	var before_day: int=scene.state.day
	scene.interface.step_button.pressed.emit(); scene.interface.pause_button.pressed.emit()
	check(scene.state.day==before_day and scene.simulation.paused,"even a stale timeline action is inert during history")
	scene.historical_view=false; scene.overlay.state=scene.state; scene.last_owner_revision=-1; await process_frame
	scene.show_information("city",selected); await capture("current")
	var fixed_builds: int=scene.info_panel.build_count; var origin: Vector2=scene.map_root.position
	# Actual viewport input must be consumed by the card, rather than zooming the map.
	var wheel := InputEventMouseButton.new(); wheel.position=scene.info_panel.get_global_rect().get_center(); wheel.button_index=MOUSE_BUTTON_WHEEL_UP; wheel.pressed=true
	var zoom_before: float=scene.zoom; Input.parse_input_event(wheel); await process_frame; await process_frame
	check(scene.zoom==zoom_before,"scrolling within the inspector does not zoom the map")
	var elapsed: Array=[]
	for i in range(120):
		var event := InputEventMouseMotion.new(); event.relative=Vector2(2 if i%40<20 else -2,0)
		scene.dragging=true; var start := Time.get_ticks_usec(); scene._unhandled_input(event); await process_frame
		elapsed.append((Time.get_ticks_usec()-start)/1000.)
	scene.dragging=false
	check(scene.info_panel.build_count==fixed_builds,"camera operations do not reconstruct information controls")
	check(hash(scene.military_payload.graph)==graph and hash(scene.state.province_ids)==provinces and scene.state.rng.state==rng,"inspection and navigation do not mutate military state or RNG")
	root.size=Vector2i(900,600); await process_frame; await capture("compact")
	check(scene.info_panel.get_global_rect().end.y<=600 and scene.info_panel.get_global_rect().end.x<=900,"card fits the compact viewport")
	scene.interface.tools.show(); await capture("tools")
	var escape := InputEventKey.new(); escape.pressed=true; escape.keycode=KEY_ESCAPE; scene.info_panel._unhandled_key_input(escape)
	check(not scene.info_panel.visible,"Escape closes the inspector")
	elapsed.sort(); var result := {"pid":OS.get_process_id(),"seed":scene.state.world_seed,"scene":scene.scene_file_path,"p95":elapsed[floori((elapsed.size()-1)*.95)],"p99":elapsed[floori((elapsed.size()-1)*.99)],"failures":failures,"samples":elapsed,"parameters":scene.state.generation_metadata}
	FileAccess.open(directory+"/manifest.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")); print("ATLAS_INFO_GPU ",JSON.stringify(result))
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(1 if failures else 0)
