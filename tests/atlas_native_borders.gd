extends SceneTree
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/borders.gd"):
		print("ATLAS_NATIVE_BORDERS missing module"); quit(1); return
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/lines-1.json"))
	var display: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/display-1.json"))
	var mesh: Dictionary = ref.mesh
	for field in ["xyz","x","y"]: mesh[field] = PackedFloat32Array(mesh[field])
	for field in ["triangles","adj_start","adj"]: mesh[field] = PackedInt32Array(mesh[field])
	var module = load("res://scripts/atlas/borders.gd")
	var chains: Dictionary = module.trace(mesh,PackedInt32Array(ref.regions.of)); var errors := 0
	for field in ["left","right","n0","n1","start","nodeDeg","incStart","inc","pts"]:
		var expected = PackedFloat32Array(raw.chains[field]) if field=="pts" else PackedInt32Array(raw.chains[field])
		var actual = chains[field]; var count := 0
		if actual.size()!=expected.size(): count += 1
		else:
			for i in range(actual.size()):
				if actual[i]!=expected[i]: count += 1
		print("BORDERS_COMPARE ",field," errors=",count); errors += count
	var raster := {"w":2048,"h":1024,"water":FileAccess.get_file_as_bytes("res://.dbg/atlas-native-reference/water-1.bin"),"cell":FileAccess.get_file_as_bytes("res://.dbg/atlas-native-reference/cell-1.bin").to_int32_array()}
	var lines: Array = module.build(chains,PackedInt32Array(ref.ownership),mesh,raster,PackedInt32Array(ref.regions.of))
	if lines.size()!=display.lines.size(): errors += 1
	else:
		for i in range(lines.size()):
			if lines[i].pts!=PackedFloat32Array(display.lines[i].pts): errors += 1
			for field in ["closed","left","right","end0","end1"]:
				if lines[i][field]!=display.lines[i][field]: errors += 1
	print("ATLAS_NATIVE_BORDERS failures=",errors); quit(1 if errors else 0)
