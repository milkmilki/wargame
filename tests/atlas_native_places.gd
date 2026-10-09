extends SceneTree
const Places = preload("res://scripts/atlas/places.gd")
func _initialize() -> void:
	var seed_value := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.get_slice("=",1))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-%d.json"%seed_value))
	var m: Dictionary = data.mesh
	for key in ["x","y","areas","lengths"]: m[key] = PackedFloat32Array(m[key])
	for key in ["adj_start","adj","triangles"]: m[key] = PackedInt32Array(m[key])
	m.xyz = PackedFloat32Array(m.xyz)
	var w: Dictionary = data.environment; w.mesh = m; w.params = data.params
	for key in ["biome","water"]: w[key] = PackedByteArray(w[key])
	for key in ["temperature","elevation","seaIce"]: w[key] = PackedFloat32Array(w[key])
	var actual := Places.build(w); var expected: Array = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/places-%d.json"%seed_value)); var errors := 0
	if actual.size()!=expected.size(): errors += 1; print("PLACES_DIFF count ",actual.size()," / ",expected.size())
	for i in range(mini(actual.size(),expected.size())):
		var a: Dictionary = actual[i]; var b: Dictionary = expected[i]
		for key in ["kind","name","cell","rank","latin"]:
			if a.get(key)!=b.get(key): errors += 1; print("PLACES_DIFF ",i," ",key," ",a.get(key)," / ",b.get(key))
		if absf(a.size-b.size)>1e-7: errors += 1; print("PLACES_DIFF size ",i," ",a.size-b.size)
		if a.path!=PackedFloat32Array(b.path): errors += 1; print("PLACES_DIFF path ",i," ",a.path," / ",b.path)
	print("ATLAS_NATIVE_PLACES seed=",seed_value," count=",actual.size()," failures=",errors); quit(1 if errors else 0)
