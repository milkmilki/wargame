extends SceneTree

const GEOMETRY := preload("res://scripts/view/visual_region_geometry.gd")


func _init() -> void:
	var height := Image.create(48, 32, false, Image.FORMAT_RGBA8)
	height.fill(Color(1.0, 1.0, 1.0, 0.78))
	for y in range(height.get_height()):
		height.set_pixel(0, y, Color(1.0, 1.0, 1.0, 0.2))
		height.set_pixel(47, y, Color(1.0, 1.0, 1.0, 0.2))
	var seeds: Array[Dictionary] = [
		{"city_id": 2, "position": Vector2(0.28, 0.5)},
		{"city_id": 5, "position": Vector2(0.72, 0.5)},
	]
	var first := GEOMETRY.build_visual_region_geometry(
		height, seeds, Vector2i(96, 64)
	)
	var second := GEOMETRY.build_visual_region_geometry(
		height, seeds, Vector2i(96, 64)
	)
	var valid := true
	for key in [
		"city_id", "land_mask", "region_coverage", "region_distance",
	]:
		valid = _check(
			(first[key] as Image).get_size() == Vector2i(96, 64),
			"channel size mismatch: " + key
		) and valid
	valid = _check(
		first["revision"] == second["revision"],
		"geometry revision is not deterministic"
	) and valid
	valid = _check(
		(first["city_id"] as Image).get_data()
			== (second["city_id"] as Image).get_data(),
		"city id raster is not deterministic"
	) and valid
	var regions: Array = first["regions"]
	valid = _check(not regions.is_empty(), "no closed visual regions generated") and valid
	for region_value in regions:
		var region := region_value as Dictionary
		valid = _check(
			GEOMETRY.validate_visual_region(region, first["land_mask"], first["adjacency"]),
			"invalid visual region for city %d" % int(region["city_id"])
		) and valid
	var ids: Image = first["city_id"]
	var land: Image = first["land_mask"]
	for y in range(ids.get_height()):
		for x in range(ids.get_width()):
			if land.get_pixel(x, y).r < 0.5:
				valid = _check(ids.get_pixel(x, y).r < 0.0, "ocean received city id") and valid
	if not valid:
		quit(1)
		return
	print("VISUAL_REGION_GEOMETRY_OK regions=", regions.size())
	quit(0)


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("VISUAL_REGION_GEOMETRY_FAILED: " + message)
	return false
