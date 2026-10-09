extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(2048,1024)
	var scene = load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready or scene.overlay==null: await process_frame
	scene.hud.get_parent().hide()
	var directory := "res://docs/atlas/military_evidence"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for mode in range(4):
		scene.mode_control.select(mode); scene.update_mode()
		for framing in [{"name":"world","zoom":1.,"center":Vector2(1024,512)},{"name":"china","zoom":4.,"center":Vector2(1685,338)}]:
			scene.zoom = framing.zoom; scene.map_root.scale = Vector2.ONE*scene.zoom; scene.map_root.position = Vector2(1024,512)-framing.center*scene.zoom
			scene.limit_pan(); scene.refresh_symbols(); scene.overlay.queue_redraw()
			await process_frame; await process_frame; RenderingServer.force_draw(true)
			var path := directory+"/seed1-%s-mode%d.png"%[framing.name,mode]
			root.get_texture().get_image().save_png(path); print("ATLAS_MILITARY_VISUAL ",path)
	scene.mode_control.select(0); scene.update_mode(); scene.zoom = 4.; scene.map_root.scale = Vector2.ONE*4.
	scene.map_root.position = Vector2(1024,512)-Vector2(0,512)*4.; scene.limit_pan(); scene.refresh_symbols()
	await process_frame; await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(directory+"/seed1-dateline.png")
	print("ATLAS_MILITARY_VISUAL_DONE pid=",OS.get_process_id()," seed=",scene.state.world_seed," scene=atlas_military.tscn")
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(0)
