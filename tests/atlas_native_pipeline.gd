extends SceneTree
func _initialize() -> void:
	var seed_value := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.get_slice("=",1))
	var actual: Dictionary = load("res://scripts/atlas/generator.gd").generate(seed_value,1.0)
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-%d.json"%seed_value)); var errors := 0
	for field in ["of","seat","area","capacity"]:
		var expected = PackedFloat32Array(ref.regions[field]) if field in ["area","capacity"] else PackedInt32Array(ref.regions[field])
		if actual.data.regions[field]!=expected: errors += 1; print("PIPELINE_DIFF regions.",field)
	if actual.data.ownership!=PackedInt32Array(ref.ownership): errors += 1; print("PIPELINE_DIFF ownership")
	if actual.data.roads.size()!=ref.roads.size(): errors += 1
	else:
		for i in range(ref.roads.size()):
			if actual.data.roads[i].cells!=PackedInt32Array(ref.roads[i].cells): errors += 1
	var provinces: PackedInt32Array = load("res://scripts/atlas/generator.gd").pixel_regions(actual.data,actual.raster)
	var bytes := FileAccess.get_file_as_bytes("res://.dbg/atlas-native-reference/provinces-%d.bin"%seed_value); var expected_provinces := PackedInt32Array(); expected_provinces.resize(bytes.size()/2)
	for i in range(expected_provinces.size()):
		var value := bytes.decode_u16(i*2); expected_provinces[i] = value-65536 if value>=32768 else value
	if provinces!=expected_provinces: errors += 1; print("PIPELINE_DIFF pixel_regions")
	FileAccess.open("res://.dbg/atlas-native-generated-%d.bin"%seed_value,FileAccess.WRITE).store_var(actual)
	print("PIPELINE_COUNTS ",actual.data.mesh.n," / ",actual.data.regions.count," / ",actual.data.cities.size()," / ",actual.data.roads.size())
	print("PIPELINE_TIMING ",actual.timing)
	print("ATLAS_NATIVE_PIPELINE failures=",errors); quit(1 if errors else 0)
