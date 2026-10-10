extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_PERSISTENT_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var script = load("res://scripts/atlas/persistent_strokes.gd")
	if script==null: quit(1); return
	var path := PackedVector2Array([Vector2(0,0),Vector2(200,0),Vector2(300,100),Vector2(600,100)])
	var batches: Array = script.plan([path])
	var total := 0; var arcs: Array = []
	for batch in batches:
		total += batch.vertices.size()/4
		for i in range(0,batch.uv.size(),4): arcs.append(batch.uv[i].x)
	check(total==3,"each physical segment is stored once across spatial chunks")
	check(arcs.has(200.) and arcs.any(func(v): return absf(v-(200.+sqrt(20000.)))<.001),"arc distance does not restart at a chunk boundary")
	var layer = script.new(); root.add_child(layer); layer.set_paths([path]); layer.set_zoom(2.)
	var builds: int = layer.build_count; var mesh: ArrayMesh = layer.chunks[0].mesh
	layer.set_zoom(4.); layer.set_view(Rect2(100,0,400,200))
	check(layer.build_count==builds and layer.chunks[0].mesh==mesh,"pan and zoom retain the same mesh resource")
	check(layer.material.get_shader_parameter("view_zoom")==4.,"zoom changes a shader parameter")
	root.remove_child(layer); layer.free()
	print("ATLAS_PERSISTENT_STROKES failures=",failures); quit(1 if failures else 0)
