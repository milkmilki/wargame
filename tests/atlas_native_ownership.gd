extends SceneTree
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/ownership.gd"):
		print("ATLAS_NATIVE_OWNERSHIP missing module"); quit(1); return
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	ref.mesh.xyz = PackedFloat32Array(ref.mesh.xyz)
	var actual: Dictionary = load("res://scripts/atlas/ownership.gd").build(ref.mesh,ref.regions,ref.cities)
	var errors := 0
	if actual.ownership!=PackedInt32Array(ref.ownership): errors += 1
	if actual.nations.size()!=ref.nations.size(): errors += 1
	else:
		for i in range(actual.nations.size()):
			if actual.nations[i].seat!=ref.nations[i].seat: errors += 1
	print("ATLAS_NATIVE_OWNERSHIP failures=",errors); quit(1 if errors else 0)
