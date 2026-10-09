extends SceneTree
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/tectonics.gd"):
		print("ATLAS_NATIVE_TECTONICS missing module"); quit(1); return
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var stages: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/environment-stages-1.json"))
	var mesh: Dictionary = ref.mesh
	for field in ["xyz","x","y"]: mesh[field] = PackedFloat32Array(mesh[field])
	for field in ["adj_start","adj"]: mesh[field] = PackedInt32Array(mesh[field])
	var actual: Dictionary = load("res://scripts/atlas/tectonics.gd").build(mesh,ref.params); var errors := 0
	for field in stages.tect:
		if field=="plateCount":
			if actual[field]!=stages.tect[field]: errors += 1
			continue
		var expected = PackedInt32Array(stages.tect[field]) if field in ["plate","plateContinental","land"] else PackedFloat32Array(stages.tect[field]); var count := 0
		for i in range(expected.size()):
			if actual[field][i]!=expected[i]: count += 1
		print("TECTONICS_COMPARE ",field," errors=",count); errors += count
	print("ATLAS_NATIVE_TECTONICS failures=",errors); quit(1 if errors else 0)
