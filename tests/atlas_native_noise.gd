extends SceneTree
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/simplex.gd"):
		print("ATLAS_NATIVE_NOISE missing module"); quit(1); return
	var fixture: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/atlas_native_noise.json"))
	var module = load("res://scripts/atlas/simplex.gd"); var errors := 0; var max_error := 0.0
	for item in fixture:
		var noise = module.new(int(item.seed))
		for i in range(item.points.size()):
			var p: Array = item.points[i]
			var actual := [noise.at(p[0],p[1],p[2]),noise.fbm(p[0],p[1],p[2],4),noise.ridged(p[0],p[1],p[2],4)]
			for k in range(3):
				var expected: float = item[["noise","fbm","ridged"][k]][i]
				max_error = maxf(max_error,absf(actual[k]-expected))
				if absf(actual[k]-expected)>1e-13: errors += 1
	print("ATLAS_NATIVE_NOISE failures=",errors," max_error=",max_error); quit(1 if errors else 0)
