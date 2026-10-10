extends SceneTree
## World-coordinate labels must remain legal across the periodic seam.
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_WRAPPED_TEXT_FAIL ",message)
func _initialize():
	var state := preload("res://scripts/atlas/text_state.gd").new()
	state.canvas_size = Vector2(2048,1024); state.owners.resize(2048*1024)
	var water := PackedByteArray(); water.resize(2048*1024); water.fill(1)
	state.raster = {"water":water}; state.show_cities = false; state.show_polities = false
	state.data = {"cities":[],"ownership":[],"nations":[],"mesh":{"x":[],"y":[]},"places":[{"kind":"sea","rank":1,"name":"海","size":100.,"path":[2038.,100.,2060.,100.]}]}
	state.prepare(); var first: Dictionary = state.update(Rect2(2030,90,40,20))
	check(first.rows.size()==1,"a name straddling the seam is retained")
	var repeated: Dictionary = state.update(Rect2(-18,90,40,20))
	check(repeated.rows==first.rows,"opposite seam view reuses the same label")
	state = preload("res://scripts/atlas/text_state.gd").new()
	state.canvas_size = Vector2(2048,1024); state.show_names = false
	state.data = {"cities":[{"region":0,"cell":0,"major":false,"name":"城"}],"ownership":[0],"nations":[{"seat":0,"color":[100,80,60]}],"mesh":{"x":[2047.],"y":[100.]},"places":[]}
	state.prepare(); check(state.marks.size()==1,"periodic copies do not duplicate capital layout")
	state.all_jobs = [{"type":"nation","item":{"path":[100.,100.,120.,100.],"alt":{"path":[900.,100.,920.,100.]}}}]
	state.index = preload("res://scripts/atlas/render_index.gd").new(); state.build_index()
	check(state.index.query(Rect2(900,95,20,10)).size()==1,"country alternate path is indexed in full")
	state.active_job = 7; state.active_priority = 10.; state.buckets.clear(); state.add_box(Rect2(2040,90,20,20),1)
	check(state.hits(Rect2(-4,95,8,8),2),"conflicts are shared across the periodic seam")
	print("ATLAS_WRAPPED_TEXT failures=",failures); quit(1 if failures else 0)
