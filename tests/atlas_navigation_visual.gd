extends SceneTree
## Real GPU/input benchmark; cached native Earth only skips generation, not drawing.
var scene
var failures := 0
var rows: Array = []
var directory := "res://docs/atlas/navigation_evidence"
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_NAV_FAIL ",message)
func capture(name_value: String,center: Vector2,zoom_value: float):
	scene.zoom = zoom_value; scene.map_root.scale = Vector2.ONE*zoom_value
	scene.map_root.position = Vector2(root.size)*.5-center*zoom_value; scene.limit_pan()
	scene.finish_navigation(); await process_frame; await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(directory+"/"+name_value+".png")
func input_frame(kind: String):
	var layouts: int = scene.camera_layout_count; var symbols: int = scene.symbol_build_count
	var start := Time.get_ticks_usec()
	if kind=="pan":
		var motion := InputEventMouseMotion.new(); motion.relative = Vector2(4,0)
		scene.dragging = true; scene._unhandled_input(motion)
	else:
		var wheel := InputEventMouseButton.new(); wheel.position = Vector2(900,400); wheel.pressed = true
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP if kind=="zoom_in" else MOUSE_BUTTON_WHEEL_DOWN
		scene._unhandled_input(wheel)
	var command_ms := (Time.get_ticks_usec()-start)/1000.
	await process_frame; RenderingServer.force_draw(true)
	var row := {"kind":kind,"command_ms":command_ms,"frame_ms":(Time.get_ticks_usec()-start)/1000.,"layout_delta":scene.camera_layout_count-layouts,"symbol_delta":scene.symbol_build_count-symbols}
	rows.append(row)
	check(row.layout_delta==0 and row.symbol_delta==0,"input burst must not synchronously rebuild labels or symbol textures")
func run():
	root.size = Vector2i(1280,720)
	scene = load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready: await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	scene.hud.get_parent().hide()
	var geometry := hash(scene.state.province_ids); var graph := hash(scene.military_payload.graph)
	await capture("seed1-global",Vector2(1024,512),.625)
	await capture("seed1-china-4x",Vector2(1685,338),4.)
	for i in range(8): await input_frame("pan")
	scene.dragging = false
	var settle := Time.get_ticks_usec()
	while scene.navigation_in_progress: await process_frame
	await process_frame; RenderingServer.force_draw(true)
	var pan_settle_ms := (Time.get_ticks_usec()-settle)/1000.
	for i in range(6): await input_frame("zoom_in" if i%2==0 else "zoom_out")
	settle = Time.get_ticks_usec()
	while scene.navigation_in_progress: await process_frame
	await process_frame; RenderingServer.force_draw(true)
	var zoom_settle_ms := (Time.get_ticks_usec()-settle)/1000.
	check(scene.text_layer.position==Vector2.ZERO and scene.text_layer.scale==Vector2.ONE,"settled labels return to exact screen layout")
	check(scene.symbol_screen.scale==Vector2.ONE,"settled symbols return to original detail scale")
	check(scene.camera_layout_count>0,"labels are restored, not permanently hidden")
	check(hash(scene.state.province_ids)==geometry and hash(scene.military_payload.graph)==graph,"navigation never changes province or traffic data")
	await capture("seed1-china-8x",Vector2(1685,338),8.)
	await capture("seed1-dateline-4x",Vector2(0,512),4.)
	# Actual diplomacy still replaces the shared border after renderer culling.
	scene.simulation._set_coalition_war([1] as Array[int],[36] as Array[int]); await process_frame
	await capture("seed1-front-china-4x",Vector2(1621.7305,320.21884),4.)
	check(not scene.front_layer.fronts.is_empty(),"fronts remain visible with render caching")
	scene.mode_control.select(2); scene.update_mode()
	await capture("seed1-districts-china-4x",Vector2(1685,338),4.)
	check(not scene.front_layer.visible,"district mode still hides political fronts")
	var result := {"pid":OS.get_process_id(),"seed":scene.state.world_seed,"scene":"res://atlas_military.tscn","source":"atlas_development_cache","parameters":scene.state.generation_metadata,"options":scene.military_payload.data.options,"godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"rows":rows,"pan_settle_ms":pan_settle_ms,"zoom_settle_ms":zoom_settle_ms,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"symbol_builds":scene.symbol_build_count,"layout_builds":scene.camera_layout_count,"failures":failures}
	var file := FileAccess.open(directory+"/manifest.json",FileAccess.WRITE); file.store_string(JSON.stringify(result,"\t")); file.close()
	print("ATLAS_NAVIGATION ",JSON.stringify(result))
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(1 if failures else 0)
