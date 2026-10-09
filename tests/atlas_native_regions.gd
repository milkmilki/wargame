extends SceneTree
var failures := 0
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/regions.gd"):
		print("ATLAS_NATIVE_REGIONS missing module"); quit(1); return
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var regions = load("res://scripts/atlas/regions.gd")
	var mesh: Dictionary = reference.mesh
	for field in ["xyz","x","y","lengths","areas"]: mesh[field] = PackedFloat32Array(mesh[field])
	for field in ["triangles","adj_start","adj"]: mesh[field] = PackedInt32Array(mesh[field])
	var actual: Dictionary = regions.build(mesh,reference.environment,1,750.0)
	for field in ["of","seat","landmass","area","capacity","biome","elevation","cellStart","cells","adjStart","adj","adjLen","adjBorder","adjKind"]:
		var count := 0
		if actual[field].size()!=reference.regions[field].size(): count += 1
		else:
			for i in range(actual[field].size()):
				if field in ["area","capacity","elevation","adjLen","adjBorder"]:
					if actual[field][i] != float(PackedFloat32Array([reference.regions[field][i]])[0]): count += 1
				elif field=="adjKind":
					# River classification is disabled as part of environment-only hydrology.
					var expected := int(reference.regions[field][i]); expected = 0 if expected==1 else expected
					if int(actual[field][i])!=expected: count += 1
				elif int(actual[field][i]) != int(reference.regions[field][i]): count += 1
		failures += count; print("REGIONS_COMPARE ",field," errors=",count)
	print("ATLAS_NATIVE_REGIONS failures=",failures)
	quit(1 if failures else 0)
