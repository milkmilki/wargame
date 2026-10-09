extends SceneTree
var side := "after"
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--circulation-before": side = "before"
	root.size = Vector2i(2048,1024)
	var scene = load("res://atlas_earth_preview.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready or scene.generating: await process_frame
	var expected := "legacy_monsoon_global_v1" if side=="before" else "seasonal_circulation_v2"
	if scene.data.options.rainfall_model!=expected:
		print("ATLAS_CIRCULATION_VIEWS refuses to overwrite historical evidence with ",scene.data.options.rainfall_model); quit(1); return
	scene.hud.hide(); scene.mode_control.select(0); scene.update_mode()
	for view in [["europe",5.5,1120.,230.],["africa",3.5,1120.,480.],["china",7.,1660.,345.]]:
		scene.zoom = view[1]; scene.map_root.scale = Vector2.ONE*scene.zoom; scene.map_root.position = Vector2(1024,512)-Vector2(view[2],view[3])*scene.zoom
		scene.limit_pan(); scene.refresh_symbols(); await process_frame; RenderingServer.force_draw(true)
		root.get_texture().get_image().save_png("res://docs/atlas/circulation/%s-%s.png"%[side,view[0]])
	print("ATLAS_CIRCULATION_VIEWS ",side," seed=",scene.data.seed," model=",scene.data.options.rainfall_model," PASS"); quit()
