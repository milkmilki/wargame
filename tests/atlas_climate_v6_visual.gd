extends SceneTree
## Run with a real renderer; input is the freshly validated Eurasia v6 world.
const OUTPUT="res://.dbg/climate-v6/"
class View extends "res://scripts/atlas/military_preview.gd":
	func load_native(_seed:int) -> void:
		var payload:Dictionary=preload("res://tests/atlas_military_inputs.gd").eurasia_military(1)
		var prepared:=GameState.new();prepared.generate_from_atlas(payload)
		run_log=DebugRunLog.new()
		await present_world(prepared,payload,"climate_v6_visual")
var failures:=0
func check(ok:bool,label:String) -> void:
	if not ok:failures+=1;printerr("CLIMATE_V6_VISUAL_FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("REAL_RENDERER_REQUIRED");quit(1);return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);root.gui_disable_input=true;root.size=Vector2i(1280,720)
	var view:=View.new();view.terrain_model="earth"
	view.set_process_input(false);view.set_process_unhandled_input(false)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(view)
	var deadline:=Time.get_ticks_msec()+120000
	while not view.view_ready and Time.get_ticks_msec()<deadline:await process_frame
	check(view.view_ready,"v6 world loads")
	if not view.view_ready:quit(1);return
	view.simulation.paused=true;view.simulation.set_process(false)
	var data:Dictionary=view.military_payload.data
	check(view.state.world_seed==1 and view.state.nations.size()==40 and data.options.settlement_mask==preload("res://scripts/atlas/settlement_mask.gd").EURASIA,"actual seed1, forty nations and Eurasia bounds")
	check(data.options.rainfall_model=="seasonal_circulation_v6" and data.environment.has("soil_moisture"),"renderer receives modern climate and root-zone fields")
	check(data.params.rainfall_transport.revision==preload("res://scripts/atlas/seasonal_circulation.gd").REVISION,"renderer receives current monsoon/terrain revision")
	view.mode_control.select(1);view.update_mode()
	check(await view.await_render_ready(60000),"terrain layers complete")
	await process_frame;RenderingServer.force_draw(true)
	var pixels:=root.get_texture().get_image();var colors:={}
	for y in range(160,640,24):
		for x in range(40,1240,32):colors[pixels.get_pixel(x,y).to_rgba32()]=true
	check(colors.size()>16,"visible map pixels")
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	check(pixels.save_png(OUTPUT+"eurasia-game.png")==OK,"actual game screenshot is saved")
	print("CLIMATE_V6_VISUAL ",JSON.stringify({"failures":failures,"seed":view.state.world_seed,"nations":view.state.nations.size(),"mask":data.options.settlement_mask,"model":data.options.rainfall_model,"run_log":ProjectSettings.globalize_path(view.run_log.path)}))
	view.queue_free();await process_frame;quit(1 if failures else 0)
