extends SceneTree
var failures := 0
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/sphere_mesh.gd"):
		print("ATLAS_NATIVE_MESH missing module"); quit(1); return
	var mesh_builder = load("res://scripts/atlas/sphere_mesh.gd")
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var mesh: Dictionary = mesh_builder.build(1,36000)
	for field in ["xyz","x","y","triangles","adj_start","adj"]:
		var actual: Array = Array(mesh[field])
		var expected: Array = reference.mesh[field]
		var errors := 0
		if actual.size()!=expected.size(): errors += 1
		else:
			for i in range(actual.size()):
				if field in ["xyz","x","y"]:
					if actual[i] != float(PackedFloat32Array([expected[i]])[0]): errors += 1
				elif int(actual[i]) != int(expected[i]): errors += 1
		failures += errors
		print("MESH_COMPARE ",field," errors=",errors," size=",actual.size())
	print("ATLAS_NATIVE_MESH failures=",failures)
	quit(1 if failures else 0)
