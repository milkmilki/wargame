extends SceneTree
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/roads.gd"):
		print("ATLAS_NATIVE_ROADS missing module"); quit(1); return
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var mesh: Dictionary = ref.mesh
	for field in ["xyz","x","y","lengths","areas"]: mesh[field] = PackedFloat32Array(mesh[field])
	for field in ["adj_start","adj"]: mesh[field] = PackedInt32Array(mesh[field])
	var module = load("res://scripts/atlas/roads.gd")
	var cities: Array = module.seat_cities(mesh,ref.environment,ref.regions,1.0)
	var errors := 0
	if cities.size() != ref.cities.size(): errors += 1
	else:
		for i in range(cities.size()):
			if cities[i].cell != int(ref.cities[i].cell) or cities[i].major != ref.cities[i].major: errors += 1
	print("ROADS_COMPARE cities errors=",errors)
	var actual: Dictionary = module.build(mesh,ref.environment,cities)
	if actual.routes.size() != ref.roads.size(): errors += 1
	else:
		for i in range(actual.routes.size()):
			var route: Dictionary = actual.routes[i]; var expected: Dictionary = ref.roads[i]
			if route.kind != expected.kind or route.cells != PackedInt32Array(expected.cells): errors += 1
	print("ROADS_COMPARE actual=",actual.routes.size()," reference=",ref.roads.size())
	for route in actual.routes:
		for cell in route.cells:
			if ref.environment.water[cell] != 0 or ref.environment.biome[cell] == 3: errors += 1
	print("ATLAS_NATIVE_ROADS failures=",errors); quit(1 if errors else 0)
