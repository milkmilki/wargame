extends SceneTree
func _initialize(): call_deferred("run")
func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); root.size = Vector2i(800,400)
	var parent := Node2D.new(); parent.position = Vector2(-300,-100); parent.z_index = 7; root.add_child(parent)
	var marks := preload("res://scripts/atlas/city_markers.gd").new(); marks.z_index = -1; parent.add_child(marks)
	marks.setup({"cities":[{"region":0,"cell":0,"major":false},{"region":1,"cell":1,"major":false}],"ownership":[0,0],"nations":[{"seat":0,"color":[100,80,60]}],"mesh":{"x":[100.,250.],"y":[100.,100.]}})
	marks.set_view(Rect2(0,0,400,200),2.)
	for layer in marks.layers:
		print("CITY_GPU count=",layer.mesh.visible_instance_count," transform=",layer.mesh.get_instance_transform_2d(0)," bounds=",layer.mesh.get_aabb()," node_visible=",layer.nodes[1].is_visible_in_tree())
	await process_frame;await process_frame;RenderingServer.force_draw(true)
	var image := root.get_texture().get_image();image.save_png("res://.dbg/city-markers.png")
	var count := 0
	for y in range(80,120):
		for x in range(180,220):
			if image.get_pixel(x,y).r>.55:count+=1
	if count<10:printerr("ATLAS_CITY_GPU_FAIL capital glyph is absent");quit(1);return
	print("ATLAS_CITY_GPU passed");quit()
