extends SceneTree
## Run without --headless: real renderer, Eurasia fixture, history scrubbing and screenshots.
class View extends "res://scripts/atlas/military_preview.gd":
	func load_native(seed_value: int) -> void:
		var payload := preload("res://tests/atlas_military_inputs.gd").eurasia_military(seed_value)
		var prepared := GameState.new(); prepared.generate_from_atlas(payload)
		await present_world(prepared,payload,"history_visual_fixture")
var view
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; printerr("HISTORY_VISUAL_FAIL ",message)
func capture(name_value: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png("res://.dbg/history-timeline/"+name_value+".png")
func press_key(code: Key) -> void:
	var key := InputEventKey.new(); key.keycode=code; key.pressed=true; Input.parse_input_event(key)
	await process_frame; await process_frame
	key=InputEventKey.new(); key.keycode=code; Input.parse_input_event(key)
	await process_frame
func mouse(point: Vector2,pressed: bool) -> void:
	var event := InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
	Input.parse_input_event(event); await process_frame; await process_frame
func move(point: Vector2,relative: Vector2) -> void:
	var event := InputEventMouseMotion.new(); event.position=point; event.global_position=point; event.relative=relative; event.button_mask=MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event); await process_frame; await process_frame
func run() -> void:
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://.dbg/history-timeline")
	view=View.new(); view.terrain_model="earth"; view.settlement_mask=preload("res://scripts/atlas/settlement_mask.gd").EURASIA
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(view)
	var deadline := Time.get_ticks_msec()+120000
	while not view.view_ready and Time.get_ticks_msec()<deadline: await process_frame
	if not view.view_ready: check(false,"map startup timeout"); quit(1); return
	check(await view.await_render_ready(60000),"initial map publication completes")
	var mask: Dictionary=view.military_payload.data.options.settlement_mask
	check(mask.enabled and mask.south==20. and mask.north==55. and mask.west==-15. and mask.east==145.,"actual Eurasia mask")
	check(view.state.world_seed==1 and view.state.nations.size()==40,"seed1 / 40 countries")
	var camera_origin: Vector2=view.map_root.position; var camera_zoom: float=view.zoom
	view.zoom=1.; view.map_root.scale=Vector2.ONE; view.map_root.position=Vector2(-360,-150); view.schedule_symbols()
	check(await view.await_render_ready(60000),"zoomed map is ready for actual pointer gestures")
	var before_pan: Vector2=view.map_root.position; var point := Vector2(600,280)
	await mouse(point,true); await move(point+Vector2(40,20),Vector2(40,20)); await mouse(point+Vector2(40,20),false)
	check(view.map_root.position==before_pan+Vector2(40,20) and view.information_kind.is_empty(),"actual left drag moves the GPU map without opening an inspector")
	check(await view.await_render_ready(60000),"map finishes rendering after a left drag")
	var pick := {}; var land_point := Vector2.ZERO
	for y in range(160,420,16):
		for x in range(440,820,16):
			var hit: Dictionary=view.pick_map(view.map_root.to_local(Vector2(x,y)))
			if hit.kind=="nation": pick=hit; land_point=Vector2(x,y); break
		if not pick.is_empty(): break
	check(not pick.is_empty(),"a visible territory remains clickable after panning")
	if not pick.is_empty():
		await mouse(land_point,true); await mouse(land_point,false)
		check(view.information_kind=="nation" and view.information_id==pick.id,"left click still opens the expected country after panning")
	view.close_information(); view.info_panel.hide()
	view.zoom=camera_zoom; view.map_root.scale=Vector2.ONE*camera_zoom; view.map_root.position=camera_origin; view.schedule_symbols()
	for day in range(60): await view.simulation.advance_one_day()
	check(view.history.snapshot_days()==PackedInt32Array([0,30,60]),"real day commits publish every monthly snapshot")
	check(await view.await_render_ready(60000),"live map publication completes")
	await capture("live-1280")
	var rng_before: int=view.state.rng.state
	var slider_rect: Rect2=view.history_control.get_global_rect(); var pointer := slider_rect.position+Vector2(8,slider_rect.size.y*.5)
	before_pan=view.map_root.position
	await mouse(pointer,true)
	var destination: Vector2=slider_rect.position+Vector2(slider_rect.size.x/3.,slider_rect.size.y*.5)
	await move(destination,destination-pointer); await mouse(destination,false)
	check(view.historical_view and view.overlay.state.day==30 and view.map_root.position==before_pan,"dragging the independent timeline changes history without dragging the map")
	view.history_control.value=0
	check(await view.await_render_ready(60000),"historical map publication completes")
	check(view.historical_view and view.overlay.state.day==0,"first stop displays the initial world")
	check(not view.attack_arrows.visible and view.overlay.state.armies.is_empty(),"history contains no live military overlays")
	view.show_information("nation",0)
	var historical_ruler: Dictionary=view.info_panel.document.sections[0]
	check(historical_ruler.title=="君主信息" and not historical_ruler.has("ruler"),"historical ruler details appear first as read-only text")
	check(historical_ruler.rows.any(func(entry): return entry.label=="君主类型" and entry.value==RulerProfile.archetype_name(view.overlay.state.nations[0].ruler_archetype)),"visible ruler type belongs to the selected snapshot")
	await capture("history-1280")
	view.history_control.grab_focus(); await press_key(KEY_RIGHT)
	check(view.historical_view and view.overlay.state.day==30,"focused timeline accepts native keyboard stepping")
	await press_key(KEY_LEFT)
	check(view.historical_view and view.overlay.state.day==0,"keyboard stepping returns to the previous snapshot")
	for width in [960,768]:
		root.size=Vector2i(width,720); await process_frame; await process_frame
		var timeline: Control=view.interface.history_timeline
		check(timeline.get_global_rect().end.x<=width and timeline.get_global_rect().position.y>=0,"timeline stays inside %dpx viewport"%width)
		check(absf(timeline.get_global_rect().get_center().x-width*.5)<1.,"timeline stays centered at %dpx"%width)
		check(view.interface.footer.get_global_rect().end.y<view.interface.timeline_bar.position.y,"status panel stays above the separate history bar")
		check(view.info_panel.get_global_rect().end.y<view.interface.timeline_bar.position.y,"country details stop above the history bar")
		check(view.interface.history_timeline.date.size.x>120.,"selected historical date has readable space at %dpx"%width)
		await capture("history-%d"%width)
	root.size=Vector2i(1280,720); await process_frame
	view.history_control.value=1; view.history_control.value=0; view.history_control.value=2
	check(await view.await_render_ready(60000),"rapid scrubbing publishes the latest selection")
	check(view.overlay.state.day==60,"latest requested date wins")
	var before_return: int=view.political_revision
	view.interface.history_timeline.current.pressed.emit()
	check(await view.await_render_ready(60000),"return publishes the live map")
	check(not view.historical_view and view.overlay.state==view.state and view.state.day==60 and view.state.rng.state==rng_before,"return preserves live state and random stream")
	check(view.political_revision==before_return+1,"return only requests one political map rebuild")
	await capture("return-1280")
	var days: PackedInt32Array=view.history.snapshot_days()
	var payload: Dictionary=view.military_payload
	var prepared := GameState.new(); prepared.generate_from_atlas(payload)
	await view.present_world(prepared,payload,"history_visual_reset")
	check(view.history.snapshot_days()==PackedInt32Array([0]) and view.history_control.value==1 and not view.history_session,"a replacement world clears old dates, selection and resume state")
	check(view.simulation.paused and view.overlay.state==prepared,"replacement world starts paused in its own live state")
	check(await view.await_render_ready(60000),"replacement world publication completes")
	FileAccess.open("res://.dbg/history-timeline/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"snapshots":Array(days),"seed":1,"nations":40,"mask":mask}))
	print("ATLAS_HISTORY_VISUAL failures=",failures," snapshots=",view.history.snapshot_days())
	view.queue_free(); await process_frame; quit(1 if failures else 0)
