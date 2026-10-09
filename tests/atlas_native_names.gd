extends SceneTree
func _initialize() -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/atlas_native_names.json")); var errors := 0
	var Names = load("res://scripts/atlas/names.gd")
	if not Names: quit(1); return
	for fixture in fixtures:
		var namer = Names.new(int(fixture.seed),fixture.style)
		for item in fixture.sequential:
			var actual = namer.name_value(item.kind)
			if actual!=item.value:
				errors += 1
				if errors<8: print("NAME_DIFF ",fixture.seed," ",fixture.style," ",item.kind," ",actual," != ",item.value)
		for kind in Names.KINDS:
			var stream = namer.keyed(kind,[12,89])
			for item in fixture.keyed:
				if item.kind!=kind: continue
				var actual = stream.next()
				if actual!=item.value:
					errors += 1
					if errors<8: print("KEYED_NAME_DIFF ",fixture.style," ",actual," != ",item.value)
	print("ATLAS_NATIVE_NAMES fixtures=",fixtures.size()," failures=",errors); quit(1 if errors else 0)
