extends SceneTree
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/glyph_plan.gd"):
		print("ATLAS_NATIVE_GLYPHS missing module"); quit(1); return
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var display: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/display-1.json"))
	var world: Dictionary = ref.environment; world.mesh = ref.mesh; world.params = ref.params
	for field in ["x","y","xyz"]: world.mesh[field] = PackedFloat32Array(world.mesh[field])
	for field in ["adj_start","adj"]: world.mesh[field] = PackedInt32Array(world.mesh[field])
	for field in ["elevation","temperature"]: world[field] = PackedFloat32Array(world[field])
	var actual: Dictionary = load("res://scripts/atlas/glyph_plan.gd").build(world); var errors := 0
	if actual.forest!=FileAccess.get_file_as_bytes("res://.dbg/atlas-native-reference/forest-1.bin"): errors += 1
	if actual.glyphs.size()!=display.glyphs.size(): errors += 1
	else:
		for i in range(actual.glyphs.size()):
			for field in ["x","y","kind","s","v","a","c","cell","z"]:
				if absf(actual.glyphs[i][field]-display.glyphs[i][field])>1e-12: errors += 1
	print("GLYPHS_COMPARE actual=",actual.glyphs.size()," reference=",display.glyphs.size())
	print("ATLAS_NATIVE_GLYPHS failures=",errors); quit(1 if errors else 0)
