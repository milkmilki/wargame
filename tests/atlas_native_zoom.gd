extends SceneTree
func _initialize() -> void:
	var Zoom = load("res://scripts/atlas/zoom_geometry.gd")
	if not Zoom: quit(1); return
	var display: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/display-1.json"))
	var queries: Array = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/zoom-queries-1.json"))
	var index: Dictionary = Zoom.build(display.lines,4.0); var errors := 0
	for q in queries:
		var hit: Dictionary = Zoom.nearest(index,float(q.x),float(q.y))
		if q.distance==null:
			if is_finite(hit.distance): errors += 1
		elif hit.side!=int(q.side) or absf(hit.distance-float(q.distance))>1e-9:
			errors += 1
			if errors<4: print("ZOOM_DIFF ",q," ",hit)
	print("ATLAS_NATIVE_ZOOM queries=",queries.size()," failures=",errors); quit(1 if errors else 0)
