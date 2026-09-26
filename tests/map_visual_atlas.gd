extends SceneTree

const ATLAS := preload("res://scripts/view/map_visual_atlas.gd")


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	var height := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	height.fill(Color(1.0, 1.0, 1.0, 1.0))
	for index in range(64):
		height.set_pixel(index, 0, Color(1.0, 1.0, 1.0, 0.25))
		height.set_pixel(index, 63, Color(1.0, 1.0, 1.0, 0.25))
		height.set_pixel(0, index, Color(1.0, 1.0, 1.0, 0.25))
		height.set_pixel(63, index, Color(1.0, 1.0, 1.0, 0.25))
	var atlas := ATLAS.build_visual_atlas(state, height, Vector2i(64, 64))
	var valid := true
	for key in [
		"elevation", "land_mask", "city_id", "region_edge",
		"coast_mask", "river_mask", "road_mask",
	]:
		valid = _check(atlas.has(key), "missing atlas channel: " + key) and valid
		valid = _check(
			(atlas[key] as Image).get_size() == Vector2i(64, 64),
			"atlas channel size mismatch: " + key
		) and valid
	valid = _check(
		(atlas["land_mask"] as Image).get_pixel(0, 0).r < 0.5,
		"sea pixel entered land mask"
	) and valid
	valid = _check(
		(atlas["land_mask"] as Image).get_pixel(32, 32).r > 0.5,
		"land pixel missing from land mask"
	) and valid
	valid = _check(
		(atlas["city_id"] as Image).get_pixel(0, 0).r < 0.0,
		"sea pixel received city ownership"
	) and valid
	var second := ATLAS.build_visual_atlas(state, height, Vector2i(64, 64))
	valid = _check(
		(atlas["city_id"] as Image).get_data()
			== (second["city_id"] as Image).get_data(),
		"visual atlas is not deterministic"
	) and valid
	if not valid:
		quit(1)
		return
	print("MAP_VISUAL_ATLAS_OK")
	quit(0)


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("MAP_VISUAL_ATLAS_FAILED: " + message)
	return false
