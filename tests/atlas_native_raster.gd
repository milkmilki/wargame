extends SceneTree
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/raster.gd"):
		print("ATLAS_NATIVE_RASTER missing module"); quit(1); return
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var world: Dictionary = ref.environment
	world.mesh = ref.mesh; world.params = ref.params
	for field in ["xyz","x","y"]: world.mesh[field] = PackedFloat32Array(world.mesh[field])
	for field in ["adj_start","adj","triangles"]: world.mesh[field] = PackedInt32Array(world.mesh[field])
	for field in ["elevation","waterLevel","temperature","precipitation","seaIce"]: world[field] = PackedFloat32Array(world[field])
	world.water = PackedByteArray(world.water)
	var module = load("res://scripts/atlas/raster.gd"); var actual: Dictionary = module.build(world,false); var errors := 0
	FileAccess.open("res://.dbg/atlas-native-raster-raw.bin",FileAccess.WRITE).store_var(actual)
	load("res://scripts/atlas/ice_pixels.gd").apply(actual,1)
	for field in ["elev","temp","precip","water","cell","ice"]:
		var bytes := FileAccess.get_file_as_bytes("res://.dbg/atlas-native-reference/%s-1.bin"%field)
		var expected = bytes.to_int32_array() if field=="cell" else bytes if field=="water" else bytes.to_float32_array(); var count := 0; var max_error := 0.0
		for i in range(expected.size()):
			if actual[field][i]!=expected[i]: count += 1; max_error = maxf(max_error,absf(actual[field][i]-expected[i]))
		print("RASTER_COMPARE ",field," errors=",count," max=",max_error); errors += count
	print("ATLAS_NATIVE_RASTER failures=",errors); quit(1 if errors else 0)
