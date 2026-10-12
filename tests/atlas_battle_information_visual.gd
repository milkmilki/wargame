extends SceneTree
## Real renderer + map input. Run without --headless; evidence stays in .dbg.
var view
var failures := 0
const DIRECTORY := "res://.dbg/battle-information"
func _initialize():
	create_timer(120.).timeout.connect(func(): printerr("BATTLE_INFORMATION_GPU_TIMEOUT"); quit(1))
	call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("BATTLE_INFORMATION_GPU_FAIL ",message)
func settle():
	for i in range(4): await process_frame
func capture(name_value: String):
	check(await view.await_render_ready(30000),"map renders for "+name_value)
	await settle(); RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(DIRECTORY+"/"+name_value+".png")
func click(screen: Vector2):
	var motion:=InputEventMouseMotion.new(); motion.position=screen; Input.parse_input_event(motion); await process_frame
	var event:=InputEventMouseButton.new(); event.position=screen; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
	Input.parse_input_event(event); await process_frame
	event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); await settle()
func actor(owner: int,city: int,count: int) -> Army:
	# Test formations may start on traffic nodes, which are not recruitment seats.
	var army:=Army.new(); army.id=900000+view.state.armies.size(); army.owner_nation=owner
	army.location_city=city; army.size=count; army.max_size=count; view.state.armies.append(army)
	army.morale=.8; army.supply_ratio=.75; army.funding_multiplier=.9
	return army
func run():
	if DisplayServer.get_name()=="headless": quit(1); return
	root.size=Vector2i(1280,720); DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	view=load("res://atlas_military.tscn").instantiate(); root.add_child(view)
	while not view.view_ready or view.overlay==null or view.generating: await process_frame
	view.simulation.paused=true
	var mask: Dictionary=view.state.atlas_layout.data.options.settlement_mask
	check(view.state.world_seed==1 and view.state.nations.size()==40 and mask.enabled and mask.south==20. and mask.north==55. and mask.west==-15. and mask.east==145.,"real Earth seed 1 uses the agreed Eurasia mask")
	var edge: Edge=null
	for candidate in view.state.edges:
		if candidate.max_manpower>0 and candidate.control_city_id>=0 and view.state.cities[candidate.control_city_id].owner_nation>=0:
			edge=candidate; break
	check(edge!=null,"physical battle route exists")
	if edge==null: quit(1); return
	var owner: int=view.state.cities[edge.control_city_id].owner_nation; var enemy: int=(owner+1)%view.state.nations.size()
	view.simulation._set_coalition_war([owner] as Array[int],[enemy] as Array[int])
	var a:=actor(owner,edge.city_a,15000); var b:=actor(enemy,edge.city_b,12000)
	for army in [a,b]:
		army.on_edge=true; army.state=Army.State.MOVING; army.move_progress=.51
		edge.passing_count+=1
	a.move_from=edge.city_a; a.move_to=edge.city_b; b.move_from=edge.city_b; b.move_to=edge.city_a
	view.simulation._detect_encounters()
	check(a.battle_id>=0 and a.battle_id==b.battle_id,"runtime encounter creates the displayed battle")
	var battle: Battle=null
	for candidate in view.state.battles:
		if candidate.id==a.battle_id: battle=candidate; break
	if battle==null: quit(1); return
	view.simulation._resolve_battles()
	check(battle.round_no>0 and Battle.valid_dice(battle.opening_dice()),"detail fixture has a real resolved opening round")
	view.zoom=4.; view.map_root.scale=Vector2.ONE*4.
	var anchor: Vector2=view.overlay.battle_position(battle)
	view.map_root.position=Vector2(800,390)-anchor*4.; view.limit_pan(); view.refresh_symbols()
	await capture("bar")
	var rng_before: int=view.state.rng.state; var size_before:=a.size; var round_before:=battle.round_no
	await click(view.map_root.to_global(anchor+Vector2(0,-25)/view.zoom))
	check(view.information_kind=="battle" and view.information_id==battle.id and view.info_panel.visible,"real viewport click opens battle details")
	check(root.gui_get_focus_owner()==view.info_panel.close_button,"battle details have keyboard focus")
	await capture("field-top")
	view.info_panel.scroll.scroll_vertical=320; await capture("comparison-modifiers")
	view.info_panel.scroll.scroll_vertical=900; await capture("comparison-rosters")
	var wheel:=InputEventMouseButton.new(); wheel.position=view.info_panel.scroll.get_global_rect().get_center(); wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed=true
	Input.parse_input_event(wheel); await settle()
	wheel=wheel.duplicate(); wheel.pressed=false; Input.parse_input_event(wheel); await settle()
	check(view.zoom==4.,"detail scrolling does not zoom the map")
	root.size=Vector2i(900,600); await settle(); view.info_panel.scroll.scroll_vertical=0
	await capture("compact")
	check(view.info_panel.get_global_rect().end.y<=600 and view.info_panel.get_global_rect().end.x<=900,"details fit a smaller game window")
	check(view.info_panel.size.x==560.,"comparison card has space for both columns")
	var close_presses: Array=[]
	view.info_panel.close_button.pressed.connect(func(): close_presses.append(true))
	await click(view.info_panel.close_button.get_global_rect().get_center())
	check(close_presses.size()==1 and not view.info_panel.visible,"compact card close click is not intercepted by toolbar")
	view.show_information("battle",battle.id); await settle()
	var escape:=InputEventKey.new(); escape.keycode=KEY_ESCAPE; escape.pressed=true; Input.parse_input_event(escape); await settle()
	check(not view.info_panel.visible,"Escape closes battle details")
	check(view.state.rng.state==rng_before and a.size==size_before and battle.round_no==round_before,"real clicking and scrolling do not advance combat")
	for dimensions in [Vector2i(1280,720),Vector2i(900,600)]:
		root.size=dimensions; view.family_panel.open(owner); await settle()
		var close: Button=view.family_panel.get_child(0).get_child(0).get_child(1)
		await click(close.get_global_rect().get_center())
		check(not view.family_panel.visible,"family close receives actual GPU viewport input at %s"%dimensions)
	await capture("family-closed")
	var report: Dictionary={"seed":view.state.world_seed,"mask":mask,"battle_id":battle.id,"failures":failures,"pid":OS.get_process_id()}
	FileAccess.open(DIRECTORY+"/manifest.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ATLAS_BATTLE_INFORMATION_GPU ",JSON.stringify(report))
	root.remove_child(view); view.queue_free(); await process_frame; quit(1 if failures else 0)
