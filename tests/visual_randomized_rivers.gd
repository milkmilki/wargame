extends SceneTree

const ATLAS := preload("res://scripts/view/map_visual_atlas.gd")
const GEOMETRY := preload("res://scripts/view/visual_region_geometry.gd")
const RIVERS := preload("res://scripts/view/visual_boundary_rivers.gd")


func _init() -> void:
	var texture := load(GameState.terrain_map_path()) as Texture2D
	var height := texture.get_image()
	var land := GEOMETRY._build_land_mask(height, ATLAS.SIZE)
	var valid := true
	for seed_value in [12345, 45678, 67890, 987654321]:
		var state := GameState.new()
		state.generate_world(seed_value, 40, 200, GameState.DEFAULT_CITY_MASK_PATH, {}, seed_value)
		var geometry := GEOMETRY.build_visual_region_geometry(
			height, ATLAS.visual_city_seeds(state), Vector2i(256, 256)
		)
		var result := RIVERS.build_paths(geometry["regions"], state.river_features, ATLAS.SIZE, land)
		print("RANDOMIZED_RIVERS seed=", seed_value, " logical=", state.river_features.size(),
			" missing=", result["missing_river_ids"])
		for feature in state.river_features:
			var source: PackedVector2Array = feature["points"]
			var path: PackedVector2Array = result["paths"][int(feature["id"])]
			print("RIVER id=", feature["id"], " from=", source[0], " to=", source[-1],
				" visual_points=", path.size())
			for point in path:
				var pixel := Vector2i(point * Vector2(ATLAS.SIZE))
				pixel.x = clampi(pixel.x, 0, ATLAS.SIZE.x - 1)
				pixel.y = clampi(pixel.y, 0, ATLAS.SIZE.y - 1)
				valid = land.get_pixelv(pixel).r > 0.5 and valid
		valid = result["missing_river_ids"].is_empty() and valid
	if not valid:
		push_error("VISUAL_RANDOMIZED_RIVERS_FAILED")
		quit(1)
		return
	print("VISUAL_RANDOMIZED_RIVERS_OK")
	quit(0)
