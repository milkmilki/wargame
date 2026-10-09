extends SceneTree
const Coast = preload("res://scripts/atlas/coast_ink.gd")
func _initialize() -> void:
	var generated: Dictionary = FileAccess.open("res://.dbg/atlas-native-generated-1.bin",FileAccess.READ).get_var(false)
	var node := Coast.new(); node.setup(generated.raster)
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/coasts-1.json")); var errors := 0
	var groups: Array = [[node.coast,expected.sea],[node.lake,expected.lake]]
	for i in range(3): groups.append([node.rings[i],expected.rings[i]])
	for group in groups:
		if group[0].size()!=group[1].size(): errors += 1; print("COAST_DIFF count ",group[0].size()," / ",group[1].size()); continue
		for i in range(group[0].size()):
			var p: PackedVector2Array = group[0][i]; var q: PackedFloat32Array = PackedFloat32Array(group[1][i])
			if p.size()*2!=q.size(): errors += 1; continue
			for j in range(p.size()):
				if p[j].x!=q[2*j] or p[j].y!=q[2*j+1]: errors += 1; break
	node.free(); print("ATLAS_NATIVE_COASTS failures=",errors); quit(1 if errors else 0)
