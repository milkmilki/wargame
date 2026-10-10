extends SceneTree
class Pattern extends Node2D:
	func _draw():
		draw_rect(Rect2(0,0,64,64),Color(.3,.5,.7,.8)); draw_circle(Vector2(32,32),15,Color(.7,.2,.1,.6))
var received: Texture2D
var success := false
func _initialize(): call_deferred("run")
func run():
	var view := SubViewport.new(); view.size = Vector2i(64,64); view.transparent_bg = true; view.msaa_2d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ONCE; root.add_child(view); view.add_child(Pattern.new())
	await process_frame; await process_frame; RenderingServer.force_draw(true)
	var before := view.get_texture().get_image().get_region(Rect2i(8,8,40,40))
	preload("res://scripts/atlas/tile_texture.gd").copy(view.get_texture(),Rect2i(8,8,40,40),func(texture,copied): received = texture; success = copied)
	var deadline := Time.get_ticks_msec()+2000
	while received==null and Time.get_ticks_msec()<deadline: await process_frame
	if received==null or not success: printerr("ATLAS_COPY_FAIL unresolved texture"); quit(1); return
	RenderingServer.force_draw(true)
	var after := received.get_image()
	if before.get_data()!=after.get_data(): printerr("ATLAS_COPY_FAIL GPU copy changed RGBA"); quit(1); return
	view.queue_free(); await process_frame; RenderingServer.force_draw(true)
	if received.get_image().get_data()!=before.get_data(): printerr("ATLAS_COPY_FAIL copied pixels depend on the old viewport"); quit(1); return
	received = null; await process_frame; print("ATLAS_TILE_COPY passed renderer=",RenderingServer.get_current_rendering_method()); quit()
