extends SceneTree

const VORONOI := preload("res://scripts/view/visual_weighted_voronoi.gd")


func _init() -> void:
	var height := Image.create(32, 20, false, Image.FORMAT_RGBA8)
	height.fill(Color(1.0, 1.0, 1.0, 0.78))
	for y in range(height.get_height()):
		height.set_pixel(0, y, Color(1.0, 1.0, 1.0, 0.2))
		height.set_pixel(31, y, Color(1.0, 1.0, 1.0, 0.2))
	var seeds: Array[Dictionary] = [
		{"city_id": 3, "position": Vector2(0.25, 0.5)},
		{"city_id": 7, "position": Vector2(0.75, 0.5)},
	]
	var first := VORONOI.build_visual_city_ids(
		height, seeds, Vector2i(64, 40), 32.0, Vector2i(32, 20)
	)
	var second := VORONOI.build_visual_city_ids(
		height, seeds, Vector2i(64, 40), 32.0, Vector2i(32, 20)
	)
	var valid := true
	valid = _check(
		VORONOI.visual_step_cost(0.0, 0.0) == 1,
		"flat terrain cost must be one"
	) and valid
	valid = _check(
		VORONOI.visual_step_cost(0.0, 1.0) < 255,
		"land slope must remain traversable"
	) and valid
	valid = _check(
		(first["city_ids"] as Image).get_data()
			== (second["city_ids"] as Image).get_data(),
		"visual propagation is not deterministic"
	) and valid
	valid = _check(
		first["revision"] == second["revision"],
		"visual region revision is not deterministic"
	) and valid
	var ids: Image = first["city_ids"]
	var land: Image = first["land_mask"]
	for y in range(ids.get_height()):
		for x in range(ids.get_width()):
			var value := ids.get_pixel(x, y).r
			if land.get_pixel(x, y).r < 0.5:
				valid = _check(value < 0.0, "ocean received a city id") and valid
			else:
				valid = _check(value == 3.0 or value == 7.0, "invalid city id") and valid
	valid = _check(
		int(first["unassigned_land_pixels"]) == 0,
		"connected land was left unassigned"
	) and valid
	if not valid:
		quit(1)
		return
	print("VISUAL_WEIGHTED_VORONOI_OK")
	quit(0)


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("VISUAL_WEIGHTED_VORONOI_FAILED: " + message)
	return false
