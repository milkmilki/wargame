extends SceneTree
func _initialize() -> void:
	var geometry = load("res://scripts/atlas/display_geometry.gd")
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var display: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/display-1.json"))
	var pixels := FileAccess.get_file_as_bytes("res://.dbg/atlas-native-reference/cell-1.bin").to_int32_array()
	var water := FileAccess.get_file_as_bytes("res://.dbg/atlas-native-reference/water-1.bin")
	var provinces := FileAccess.get_file_as_bytes("res://.dbg/atlas-native-reference/provinces-1.bin")
	var expected := FileAccess.get_file_as_bytes("res://.dbg/atlas-native-reference/labels-1.bin")
	var labels := PackedInt32Array(); labels.resize(pixels.size())
	var weak := PackedByteArray(); weak.resize(pixels.size())
	for i in range(pixels.size()):
		var r := provinces.decode_s16(i*2)
		labels[i] = int(world.ownership[r]) if r >= 0 else -2
		weak[i] = 1 if water[i] == 0 and int(world.regions.of[pixels[i]]) < 0 else 0
	geometry.band_labels(labels,2048,1024,display.lines,weak)
	var output := FileAccess.open("res://.dbg/atlas-native-labels.bin",FileAccess.WRITE)
	output.store_buffer(labels.to_byte_array()); output.close()
	var errors := 0
	for i in range(labels.size()):
		if labels[i] != expected.decode_s16(i*2): errors += 1
	var dash: PackedVector2Array = geometry.dashed_segments(PackedVector2Array([Vector2(0,0),Vector2(3,0),Vector2(10,0)]),4.0,2.0)
	var length := 0.0
	for i in range(0,dash.size(),2): length += dash[i].distance_to(dash[i+1])
	if absf(length-8.0) > 0.00001: errors += 1
	print("ATLAS_NATIVE_DISPLAY pixels=",labels.size()," failures=",errors)
	quit(1 if errors else 0)
