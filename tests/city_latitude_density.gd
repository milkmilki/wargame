extends SceneTree
## End-to-end latitude-density gate: with identical terrain, mask and city
## count, the configured subtropical curve must move settlements away from
## both the tropical and far-northern bands toward the density-1.0 middle.


func _init() -> void:
	var defaults := TerrainMapGenerator.default_city_density_settings()
	var flat := defaults.duplicate(true)
	flat["south_density"] = 1.0
	flat["north_density"] = 1.0
	var curved := TerrainMapGenerator.build(
		GameState.terrain_map_path(), 160,
		GameState.DEFAULT_CITY_MASK_PATH, defaults
	)
	var uniform := TerrainMapGenerator.build(
		GameState.terrain_map_path(), 160,
		GameState.DEFAULT_CITY_MASK_PATH, flat
	)
	var curved_bands := _band_counts(curved["positions"], defaults)
	var uniform_bands := _band_counts(uniform["positions"], defaults)
	if (
		int(curved_bands["north"]) >= int(uniform_bands["north"])
		or int(curved_bands["south"]) >= int(uniform_bands["south"])
		or int(curved_bands["middle"]) <= int(uniform_bands["middle"])
	):
		push_error(
			"CITY_LATITUDE_DENSITY_FAILED curved=%s uniform=%s"
			% [str(curved_bands), str(uniform_bands)]
		)
		quit(1)
		return
	print(
		"CITY_LATITUDE_DENSITY_OK curved=", curved_bands,
		" uniform=", uniform_bands
	)
	quit(0)


func _band_counts(positions: Array, settings: Dictionary) -> Dictionary:
	var result := {"south": 0, "middle": 0, "north": 0}
	for position_value in positions:
		var position: Vector2 = position_value
		var latitude := TerrainMapGenerator.latitude_for_map_y(
			position.y, settings
		)
		if latitude < 24.0:
			result["south"] += 1
		elif latitude > 42.0:
			result["north"] += 1
		else:
			result["middle"] += 1
	return result
