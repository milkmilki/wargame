extends SceneTree
## Compile all shipped and regression scripts without executing test scenes.
var failures := 0

func _initialize() -> void:
	for directory in ["res://scripts", "res://tests"]:
		compile_directory(directory)
	print("PROJECT_COMPILE failures=", failures)
	quit(1 if failures else 0)

func compile_directory(path: String) -> void:
	for file_name in DirAccess.get_files_at(path):
		if not file_name.ends_with(".gd"): continue
		var script = load(path.path_join(file_name))
		if script == null or not script.can_instantiate():
			failures += 1
			print("COMPILE_FAIL ", path.path_join(file_name))
	for directory in DirAccess.get_directories_at(path):
		compile_directory(path.path_join(directory))
