extends SceneTree
func _initialize():
	var index := preload("res://scripts/atlas/render_index.gd").new()
	index.add(Rect2(2040,20,20,20)); index.add(Rect2(400,100,5,5)); index.add(Rect2(10,20,4,4))
	var out: PackedInt32Array = index.query(Rect2(-10,10,40,40))
	if out!=PackedInt32Array([0,2]): printerr("ATLAS_INDEX_FAIL seam copies must be unique"); quit(1); return
	print("ATLAS_RENDER_INDEX passed"); quit()
