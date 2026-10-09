extends SceneTree
var side := "after"
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--climate-before": side = "before"
	root.size = Vector2i(2048,1024)
	root.content_scale_size = Vector2i(2048,1024); root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var scene = load("res://atlas_earth_preview.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready or scene.generating: await process_frame
	scene.hud.hide()
	var directory := "res://docs/atlas/climate_limits"; DirAccess.make_dir_recursive_absolute(directory)
	for view in [["southern-africa",4.5,1150.,665.,0],["southern-africa-terrain",4.5,1150.,665.,1],["southern-africa-habitat",4.5,1150.,665.,3],["europe",5.5,1120.,230.,0],["china",7.,1660.,345.,0],["africa",3.5,1120.,480.,0],["world",1.,1024.,512.,0]]:
		scene.mode_control.select(view[4]); scene.update_mode(); scene.zoom = view[1]; scene.map_root.scale = Vector2.ONE*scene.zoom
		scene.map_root.position = Vector2(1024,512)-Vector2(view[2],view[3])*scene.zoom
		scene.limit_pan(); scene.refresh_symbols(); await process_frame; RenderingServer.force_draw(true)
		root.get_texture().get_image().save_png(directory+"/%s-%s.png"%[side,view[0]])
	print("ATLAS_CLIMATE_LIMIT_VIEWS ",side," seed=",scene.data.seed," rain=",scene.data.options.rainfall_model," settlement=",scene.data.options.settlement_model," PASS"); quit()
