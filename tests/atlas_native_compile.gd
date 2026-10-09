extends SceneTree
func _initialize() -> void:
	var errors := 0
	for filename in DirAccess.get_files_at("res://scripts/atlas"):
		if not filename.ends_with(".gd"): continue
		var script = load("res://scripts/atlas/"+filename)
		if not script or not script.can_instantiate(): errors += 1; print("COMPILE_FAIL ",filename)
	print("ATLAS_NATIVE_COMPILE failures=",errors); quit(1 if errors else 0)
