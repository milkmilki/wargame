extends SceneTree
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/raster_cover.gd"):
		print("ATLAS_NATIVE_RASTER_COVER missing module"); quit(1); return
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var mesh: Dictionary = ref.mesh
	mesh.xyz = PackedFloat32Array(mesh.xyz); mesh.triangles = PackedInt32Array(mesh.triangles)
	var actual: Dictionary = load("res://scripts/atlas/raster_cover.gd").build(mesh,2048,1024); var errors := 0
	for field in ["tri","wa","wb"]:
		var bytes := FileAccess.get_file_as_bytes("res://.dbg/atlas-native-reference/%s-1.bin"%field)
		var expected = bytes.to_int32_array() if field=="tri" else bytes.to_float32_array(); var count := 0
		for i in range(expected.size()):
			if actual[field][i]!=expected[i]: count += 1
		print("RASTER_COVER_COMPARE ",field," errors=",count); errors += count
	if actual.holes!=0: errors += 1
	print("ATLAS_NATIVE_RASTER_COVER failures=",errors); quit(1 if errors else 0)
