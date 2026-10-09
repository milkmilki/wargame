extends SceneTree
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/habitat.gd"):
		print("ATLAS_NATIVE_HABITAT missing module"); quit(1); return
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var mesh: Dictionary = ref.mesh
	for field in ["lengths","areas"]: mesh[field] = PackedFloat32Array(mesh[field])
	for field in ["adj_start","adj"]: mesh[field] = PackedInt32Array(mesh[field])
	var actual: Dictionary = load("res://scripts/atlas/habitat.gd").build(mesh,ref.environment)
	var errors := 0
	for field in ["suitability","capacity"]:
		var expected := PackedFloat32Array(ref.environment[field])
		var count := 0
		for i in range(mesh.n):
			if actual[field][i] != expected[i]: count += 1
		print("HABITAT_COMPARE ",field," errors=",count); errors += count
	print("ATLAS_NATIVE_HABITAT failures=",errors); quit(1 if errors else 0)
