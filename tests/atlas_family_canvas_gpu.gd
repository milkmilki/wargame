extends SceneTree
## Manual synthetic stress fixture; timings are not whole-game/map FPS.
const Canvas = preload("res://scripts/atlas/family_canvas.gd")
const Style = preload("res://scripts/atlas/information_theme.gd")
func _initialize(): call_deferred("run")
func frames(count: int=3):
	for i in range(count): await process_frame
func shot(path: String):
	await frames(); RenderingServer.force_draw(true); root.get_texture().get_image().save_png(path)
func run():
	if DisplayServer.get_name()=="headless": printerr("FAMILY_CANVAS_REQUIRES_GPU"); quit(1); return
	root.size=Vector2i(1280,720)
	var canvas:=Canvas.new(); canvas.theme=Style.create(); canvas.size=Vector2(1280,720); canvas.clip_contents=true; root.add_child(canvas)
	var model: Dictionary={"members":{},"root":0,"current":2400}
	for id in range(5000):
		model.members[id]={"parent_id":id-200 if id>=200 else -1,"birth_order":id%200,"last_reign":id,
			"name":"宗室%d"%id,"was_ruler":id%200==0,"was_emperor":id==2400,"display_title":"郡王" if id%200==0 else "无爵","alive":id>=2400}
	var before:=Time.get_ticks_usec(); canvas.update_model(model); var layout_us:=Time.get_ticks_usec()-before
	await frames(); canvas.fit_all(); await shot("res://.dbg/family-5000-overview.png")
	var scale_fit: float=canvas.scale_value
	assert(canvas.layout.bounds.size.x*scale_fit<=1280 and canvas.layout.bounds.size.y*scale_fit<=720)
	canvas.locate(2400); await frames(); await shot("res://.dbg/family-5000-detail.png")
	var layout_count: int=canvas.layout_count; var durations: Array=[]; var visible_max:=0
	for i in range(120):
		before=Time.get_ticks_usec(); canvas.offset+=Vector2(5 if i<60 else -5,0); canvas.queue_redraw(); await process_frame
		durations.append((Time.get_ticks_usec()-before)/1000.); visible_max=maxi(visible_max,canvas.visible_ids().size())
	assert(canvas.layout_count==layout_count)
	var expected:=2400
	var point: Vector2=canvas.layout.positions[expected]*canvas.scale_value+canvas.offset+Vector2(10,10)
	var press:=InputEventMouseButton.new(); press.button_index=MOUSE_BUTTON_LEFT; press.position=point; press.global_position=point; press.pressed=true
	Input.parse_input_event(press); await process_frame
	var release:=press.duplicate(); release.pressed=false; Input.parse_input_event(release); await frames()
	assert(canvas.focus_id==expected)
	durations.sort()
	var receipt: Dictionary={"fixture":"synthetic 5000 people / 25 generations / 200 root branches","gpu":RenderingServer.get_video_adapter_name(),"godot":Engine.get_version_info(),"viewport":[1280,720],"layout_ms":layout_us/1000.,"scale_fit":scale_fit,"pan_samples":durations.size(),"pan_frame_p95_ms":durations[int(durations.size()*.95)],"pan_frame_max_ms":durations.back(),"visible_max":visible_max,"layouts_before_after":[layout_count,canvas.layout_count],"click_selected":canvas.focus_id,"note":"Isolated family canvas on real GPU; includes concurrent headless audits. Not map/game FPS."}
	FileAccess.open("res://.dbg/family-stress-gpu.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"\t"))
	print("FAMILY_STRESS_GPU_OK ",JSON.stringify(receipt))
	canvas.queue_free(); await process_frame; quit()
