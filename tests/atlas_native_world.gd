extends SceneTree
func _initialize() -> void:
	var seed_value := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.get_slice("=",1))
	if not ResourceLoader.exists("res://scripts/atlas/world.gd"):
		print("ATLAS_NATIVE_WORLD missing module"); quit(1); return
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-%d.json"%seed_value))
	var actual: Dictionary = load("res://scripts/atlas/world.gd").generate(ref.params); var errors := 0
	for field in ["elevation","water","waterLevel","temperature","precipitation","seaIce","flux","biome"]:
		var expected = PackedByteArray(ref.environment[field]) if field in ["water","biome"] else PackedFloat32Array(ref.environment[field]); var count := 0; var max_error := 0.0
		for i in range(expected.size()):
			if actual[field][i]!=expected[i]: count += 1; max_error = maxf(max_error,absf(actual[field][i]-expected[i]))
		print("WORLD_COMPARE ",field," errors=",count," max=",max_error); errors += count
	print("ATLAS_NATIVE_WORLD failures=",errors); quit(1 if errors else 0)
