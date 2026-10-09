extends SceneTree
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/erosion.gd"):
		print("ATLAS_NATIVE_EROSION missing module"); quit(1); return
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var stages: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/environment-stages-1.json"))
	var mesh: Dictionary = ref.mesh
	for field in ["xyz","x","y"]: mesh[field] = PackedFloat32Array(mesh[field])
	for field in ["adj_start","adj"]: mesh[field] = PackedInt32Array(mesh[field])
	var module = load("res://scripts/atlas/erosion.gd")
	var actual: Dictionary = module.drainage(mesh,PackedByteArray(stages.tect.land),PackedFloat32Array(ref.environment.elevation),.001)
	var errors := 0
	for field in ["order","receiver","filled"]:
		var expected = PackedFloat32Array(stages.drainage[field]) if field=="filled" else PackedInt32Array(stages.drainage[field]); var count := 0
		for i in range(expected.size()):
			if actual[field][i]!=expected[i]: count += 1
		print("EROSION_COMPARE ",field," errors=",count); errors += count
	if actual.orderLen!=int(stages.drainage.orderLen): errors += 1
	print("ATLAS_NATIVE_EROSION failures=",errors); quit(1 if errors else 0)
