extends SceneTree
## City instances must contribute pixels after asynchronous full-map publication.
## Run with -- --atlas-cache=res://.dbg/atlas-military-earth.bin to skip generation.
var scene
var directory := "res://.dbg/city-glyph-repro"
func _initialize(): call_deferred("run")
func capture(name_value: String) -> Image:
	await process_frame; await process_frame
	RenderingServer.force_draw(true)
	var image := root.get_texture().get_image()
	image.save_png(directory+"/"+name_value+".png")
	return image
func changed(a: Image,b: Image) -> int:
	var count := 0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if a.get_pixel(x,y)!=b.get_pixel(x,y): count += 1
	return count
func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	scene = load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready: await process_frame
	scene.hud.get_parent().hide(); scene.simulation.paused = true
	scene.zoom = 4.; scene.map_root.scale = Vector2.ONE*4.
	scene.map_root.position = Vector2(root.size)*.5-Vector2(1685,338)*4.
	scene.limit_pan(); scene.refresh_symbols()
	if not await scene.await_render_ready(30000): printerr("GLYPH_REPRO_FAIL render timed out"); quit(2); return
	var markers = scene.text_layer.city_markers
	var visible_count: int = markers.visible_count
	var normal := await capture("normal")
	# MapText owns marker visibility each frame, so use its public display state.
	scene.text_layer.show_cities = false
	var hidden := await capture("hidden")
	var correctly_hidden: bool = not markers.is_visible_in_tree()
	var pixels := changed(normal,hidden)
	print("GLYPH_REPRO visible_count=",visible_count," glyph_pixels=",pixels," correctly_hidden=",correctly_hidden)
	root.remove_child(scene); scene.queue_free(); await process_frame
	if visible_count<=0 or not correctly_hidden or pixels<10:
		printerr("GLYPH_REPRO_FAIL city glyphs contribute no pixels in the full renderer"); quit(1)
	else: print("GLYPH_REPRO passed"); quit()
