extends SceneTree
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/climate.gd"):
		print("ATLAS_NATIVE_CLIMATE missing module"); quit(1); return
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var mesh: Dictionary = ref.mesh
	for field in ["xyz","x","y"]: mesh[field] = PackedFloat32Array(mesh[field])
	for field in ["adj_start","adj"]: mesh[field] = PackedInt32Array(mesh[field])
	var currents := {"sst":PackedFloat32Array(ref.environment.currents.sst)}
	var actual: Dictionary = load("res://scripts/atlas/climate.gd").build(mesh,PackedFloat32Array(ref.environment.elevation),PackedByteArray(ref.environment.water),ref.params,currents)
	var errors := 0
	for field in ["temperature","precipitation"]:
		var expected := PackedFloat32Array(ref.environment[field]); var count := 0; var max_error := 0.0
		for i in range(mesh.n):
			if actual[field][i]!=expected[i]: count += 1; max_error = maxf(max_error,absf(actual[field][i]-expected[i]))
		print("CLIMATE_COMPARE ",field," errors=",count," max=",max_error); errors += count
	print("ATLAS_NATIVE_CLIMATE failures=",errors); quit(1 if errors else 0)
