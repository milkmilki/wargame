extends SceneTree
func _initialize() -> void:
	var actual: Dictionary = FileAccess.open("res://.dbg/atlas-native-raster-raw.bin",FileAccess.READ).get_var()
	if not OS.get_cmdline_user_args().has("--raw"):
		load("res://scripts/atlas/ice_pixels.gd").apply(actual,1)
	var errors := 0
	for pair in [["ice","ice"],["iceConc","ice_conc"],["biome","biome"]]:
		var bytes := FileAccess.get_file_as_bytes("res://.dbg/atlas-native-reference/%s-1.bin"%pair[1])
		var expected = bytes.to_float32_array() if pair[0]=="ice" else bytes; var count := 0
		if not actual.has(pair[0]): count = expected.size()
		else:
			for i in range(expected.size()):
				if actual[pair[0]][i]!=expected[i]: count += 1
		print("ICE_PIXELS_COMPARE ",pair[0]," errors=",count); errors += count
	print("ATLAS_NATIVE_ICE_PIXELS failures=",errors); quit(1 if errors else 0)
