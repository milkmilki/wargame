extends SceneTree
const Ice = preload("res://scripts/atlas/ice_geometry.gd")
const Fields = preload("res://scripts/atlas/paint_fields.gd")
func _initialize() -> void:
	var payload: Dictionary = FileAccess.open("res://.dbg/atlas-native-generated-1.bin",FileAccess.READ).get_var(false)
	var planner := Ice.new(payload.raster,Fields.ice_field(payload.raster).mask); var actual := planner.lines()
	var expected: Array = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/coasts-1.json")).ice; var errors := 0
	if actual.size()!=expected.size(): errors += 1; print("ICE_GEO_DIFF count")
	for i in range(mini(actual.size(),expected.size())):
		if actual[i].pts!=PackedFloat32Array(expected[i].pts) or actual[i].ink!=PackedByteArray(expected[i].ink) or actual[i].wrap!=expected[i].wrap: errors += 1; print("ICE_GEO_DIFF ",i)
	print("ATLAS_NATIVE_ICE_GEOMETRY lines=",actual.size()," failures=",errors); quit(1 if errors else 0)
