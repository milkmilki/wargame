extends SceneTree
## Real-renderer smoke; run explicitly without --headless.
const OUTPUT := "res://.dbg/coastline-mesh/"
class View extends "res://scripts/atlas/military_preview.gd":
	func load_native(_seed: int) -> void:
		var payload: Dictionary=preload("res://tests/atlas_military_inputs.gd").eurasia_military(1)
		var prepared:=GameState.new();prepared.generate_from_atlas(payload)
		run_log=DebugRunLog.new()
		await present_world(prepared,payload,"coastline_mesh_visual")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	if not ok:failures+=1;printerr("COAST_VISUAL_FAIL ",label)
func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("REAL_RENDERER_REQUIRED");quit(1);return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.gui_disable_input=true;root.size=Vector2i(1280,720)
	var view:=View.new();view.terrain_model="earth"
	view.set_process_input(false);view.set_process_unhandled_input(false)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(view)
	var deadline:=Time.get_ticks_msec()+120000
	while not view.view_ready and Time.get_ticks_msec()<deadline:await process_frame
	check(view.view_ready,"coastline world loads in the real renderer")
	if not view.view_ready:quit(1);return
	view.simulation.paused=true;view.simulation.set_process(false)
	check(await view.await_render_ready(60000),"coastline layers complete")
	check(view.military_payload.data.mesh.get("model","")==preload("res://scripts/atlas/coastline_mesh.gd").MODEL,"rendered input uses the new coastline mesh")
	check(view.state.world_seed==1 and view.state.nations.size()==40 and view.military_payload.data.options.settlement_mask==preload("res://scripts/atlas/settlement_mask.gd").EURASIA,"actual seed1 / forty-country Eurasia world")
	await process_frame;RenderingServer.force_draw(true)
	var pixels:=root.get_texture().get_image();var colors:={}
	for y in range(160,640,24):
		for x in range(40,1240,32):colors[pixels.get_pixel(x,y).to_rgba32()]=true
	check(colors.size()>16,"map pixels are visible")
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	check(pixels.save_png(OUTPUT+"eurasia.png")==OK,"real map screenshot is saved")
	print("COASTLINE_VISUAL failures=",failures," cells=",view.military_payload.data.mesh.n," screenshot=",ProjectSettings.globalize_path(OUTPUT+"eurasia.png"))
	view.queue_free();await process_frame;quit(1 if failures else 0)
