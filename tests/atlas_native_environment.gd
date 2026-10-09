extends SceneTree
func _initialize() -> void:
	for name_value in ["currents","sea_ice"]:
		if not ResourceLoader.exists("res://scripts/atlas/%s.gd"%name_value):
			print("ATLAS_NATIVE_ENVIRONMENT missing ",name_value); quit(1); return
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var mesh: Dictionary = ref.mesh
	for field in ["xyz","x","y"]: mesh[field] = PackedFloat32Array(mesh[field])
	for field in ["adj_start","adj"]: mesh[field] = PackedInt32Array(mesh[field])
	var water := PackedByteArray(ref.environment.water); var elevation := PackedFloat32Array(ref.environment.elevation)
	var currents: Dictionary = load("res://scripts/atlas/currents.gd").build(mesh,water); var errors := 0
	for field in ["sst","u","v"]:
		var expected := PackedFloat32Array(ref.environment.currents[field]); var count := 0
		for i in range(mesh.n):
			if currents[field][i]!=expected[i]: count += 1
		print("CURRENTS_COMPARE ",field," errors=",count); errors += count
	var climate: Dictionary = load("res://scripts/atlas/climate.gd").build(mesh,elevation,water,ref.params,currents)
	var actual: PackedFloat32Array = load("res://scripts/atlas/sea_ice.gd").build(mesh,elevation,water,climate.temperature,climate.windX,climate.windY,1)
	var expected := PackedFloat32Array(ref.environment.seaIce); var count := 0
	for i in range(mesh.n):
		if actual[i]!=expected[i]: count += 1
	print("ICE_COMPARE errors=",count); errors += count
	print("ATLAS_NATIVE_ENVIRONMENT failures=",errors); quit(1 if errors else 0)
