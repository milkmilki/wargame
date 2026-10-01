extends SceneTree

const GEOMETRY := preload("res://scripts/view/visual_region_geometry.gd")
const ATLAS := preload("res://scripts/view/map_visual_atlas.gd")


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345, 40)
	var texture := load(GameState.terrain_map_path()) as Texture2D
	var height := texture.get_image() if texture != null else null
	var size := Vector2i(
		_environment_int("VISUAL_REGION_TEST_SIZE", 256),
		_environment_int("VISUAL_REGION_TEST_SIZE", 256)
	)
	var source_ids := state.province_ids.duplicate()
	var result := GEOMETRY.build_visual_region_geometry(
		height, ATLAS.visual_city_seeds(state), size
	)
	var valid := true
	valid = _check(
		(result["city_id"] as Image).get_size() == size,
		"city id atlas size mismatch"
	) and valid
	valid = _check(
		(result["region_coverage"] as Image).get_size() == size
			and (result["region_distance"] as Image).get_size() == size,
		"coverage/distance atlas size mismatch"
	) and valid
	valid = _check(
		state.province_ids == source_ids,
		"visual geometry modified province_ids"
	) and valid
	var valid_city_ids := {}
	for city in state.cities:
		valid_city_ids[city.id] = true
	var ids: Image = result["city_id"]
	for y in range(ids.get_height()):
		for x in range(ids.get_width()):
			var city_id := int(round(ids.get_pixel(x, y).r))
			if city_id >= 0:
				valid = _check(valid_city_ids.has(city_id), "invalid visual city id") and valid
	if not valid:
		quit(1)
		return
	print("VISUAL_REGION_CONSISTENCY_OK size=", size, " regions=", result["regions"].size())
	quit(0)


func _environment_int(name: String, fallback: int) -> int:
	var raw := OS.get_environment(name)
	return fallback if raw.is_empty() else maxi(int(raw), 32)


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("VISUAL_REGION_CONSISTENCY_FAILED: " + message)
	return false
