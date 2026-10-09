extends SceneTree
const Ink = preload("res://scripts/atlas/preview_ink.gd")
func _initialize() -> void:
	var seed_value := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.get_slice("=",1))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-%d.json"%seed_value))
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/lines-%d.json"%seed_value))
	var actual := Ink.road_lines(data); var errors := 0
	for kind in ["road","trail"]:
		if actual[kind].size()!=expected.roads[kind].size(): errors += 1; print("ROAD_LINES_DIFF count ",kind); continue
		for i in range(actual[kind].size()):
			var points: PackedVector2Array = actual[kind][i]; var flat: Array = expected.roads[kind][i].pts
			if points.size()*2!=flat.size(): errors += 1; continue
			for j in range(points.size()):
				if points[j].x!=PackedFloat32Array([flat[2*j]])[0] or points[j].y!=PackedFloat32Array([flat[2*j+1]])[0]: errors += 1
	print("ATLAS_NATIVE_ROAD_LINES seed=",seed_value," failures=",errors); quit(1 if errors else 0)
