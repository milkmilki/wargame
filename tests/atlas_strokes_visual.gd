extends SceneTree
const New = preload("res://scripts/atlas/persistent_strokes.gd")
const Old = preload("res://scripts/atlas/ink_strokes.gd")
class Reference extends Node2D:
	var meshes: Array = []
	func _draw():
		for row in meshes: draw_mesh(row[0],null,Transform2D.IDENTITY,row[1])
func _initialize(): call_deferred("run")
func run():
	root.size = Vector2i(1280,720)
	var path := PackedVector2Array([Vector2(20,20),Vector2(80,20),Vector2(83,23),Vector2(100,60),Vector2(130,10),Vector2(160,40),Vector2(210,40)])
	for i in range(4):
		var z: float = [1.,2.,4.,8.][i]; var gs := pow(maxf(1.,z/1.35),-.22)
		for dash_pass in range(2):
			var parent := Node2D.new(); parent.position = Vector2(20+i*310,30+dash_pass*330); parent.scale = Vector2.ONE*z
			root.add_child(parent)
			var new := New.new(); parent.add_child(new); new.set_paths([path]); new.style(1.2,Color(.3,.17,.1,.8),4.6 if dash_pass else 0.,2.6); new.set_zoom(z)
			var old := Reference.new(); old.position.y = 100./z; parent.add_child(old)
			var lines: Array = [path]
			if dash_pass:
				lines.clear()
				for d in Old.dashes(path,4.6*gs,2.6*gs): lines.append(d.path)
			old.meshes = [[Old.build(lines,1.2*gs,.55/z),Color(.3,.17,.1,.8)]]
	await process_frame; await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png("res://.dbg/persistent-strokes.png")
	print("ATLAS_STROKES_GPU renderer=",RenderingServer.get_current_rendering_method()); quit()
