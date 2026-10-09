extends SceneTree
## Preview controls and placeholder viewports must not survive scene destruction.
func _initialize() -> void:
	var scene := (load("res://atlas_military.tscn") as PackedScene).instantiate()
	var members: Array = []
	for name in ["symbol_view", "forest_view", "map_root", "hud", "owner_control", "rain_control", "threshold_control", "status", "text_layer", "player_nation", "history_control"]:
		members.append(scene.get(name))
	scene.free()
	var failures := 0
	for node in members:
		if is_instance_valid(node): failures += 1
	print("ATLAS_PREVIEW_LIFECYCLE failures=", failures)
	quit(1 if failures else 0)
