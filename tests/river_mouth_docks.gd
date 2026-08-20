extends SceneTree
## Both generated rivers must terminate in ocean and concentrate at least three
## docks in their low-elevation eastern reaches.


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	if state.river_paths.size() != TerrainMapGenerator.RIVER_COUNT:
		_fail("missing rivers")
		return
	for river_id in range(state.river_paths.size()):
		var path := state.river_paths[river_id]
		if path.size() < 2 or TerrainMapGenerator.is_land_map_position(
			GameState.terrain_map_path(), path[-1]
		):
			_fail("river %d does not terminate in ocean" % river_id)
			return
		if not TerrainMapGenerator.is_land_map_position(
			GameState.terrain_map_path(), path[-2]
		):
			_fail("river %d lacks a 0m coastal mouth" % river_id)
			return
		var eastern_docks := 0
		for city in state.cities:
			if not city.is_dock or city.map_position.x < TerrainMapGenerator.RIVER_DOCK_EASTERN_MIN_X:
				continue
			var minimum := INF
			for point in path:
				var delta := city.map_position - point
				delta.x *= state.map_aspect_ratio
				minimum = minf(minimum, delta.length())
			if minimum <= 0.012 and city.terrain_height <= TerrainMapGenerator.RIVER_DOCK_LOWLAND_ALTITUDE:
				eastern_docks += 1
		if eastern_docks < TerrainMapGenerator.RIVER_DOCK_EASTERN_MIN_PER_RIVER:
			_fail("river %d eastern lowland docks=%d" % [river_id, eastern_docks])
			return
	print("RIVER_MOUTH_DOCKS_OK rivers=", state.river_paths.size())
	quit(0)


func _fail(message: String) -> void:
	push_error("RIVER_MOUTH_DOCKS_FAILED: " + message)
	quit(1)
