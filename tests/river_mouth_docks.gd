extends SceneTree
## Compatibility-named gate for the new rule: docks are deterministic points on
## province-boundary rivers and each one exposes exactly both adjacent banks.


func _init() -> void:
	var first := TerrainMapGenerator.build(
		GameState.terrain_map_path(), GameState.TERRAIN_CITY_COUNT
	)
	TerrainMapGenerator._cache.clear()
	var second := TerrainMapGenerator.build(
		GameState.terrain_map_path(), GameState.TERRAIN_CITY_COUNT
	)
	var first_docks: Array = first.get("docks", [])
	var second_docks: Array = second.get("docks", [])
	if first_docks.size() != second_docks.size():
		_fail("dock count is not deterministic")
		return
	var valid: bool = (
		(first.get("river_paths", []) as Array).size()
			== TerrainMapGenerator.RIVER_COUNT
	)
	var counts := {}
	for index in range(first_docks.size()):
		var a: Dictionary = first_docks[index]
		var b: Dictionary = second_docks[index]
		var river_id := int(a["river_id"])
		counts[river_id] = int(counts.get(river_id, 0)) + 1
		valid = (
			valid
			and a["position"] == b["position"]
			and is_equal_approx(float(a["river_progress"]), float(b["river_progress"]))
			and int(a["bank_a"]) != int(a["bank_b"])
			and int(a["owner_city"]) in [int(a["bank_a"]), int(a["bank_b"])]
		)
	for river_id in range(TerrainMapGenerator.RIVER_COUNT):
		valid = valid and int(counts.get(river_id, 0)) >= 2
	if not valid:
		_fail("boundary docks invalid: %s" % counts)
		return
	print("BOUNDARY_RIVER_DOCKS_OK counts=", counts)
	quit(0)


func _fail(message: String) -> void:
	push_error("BOUNDARY_RIVER_DOCKS_FAILED: " + message)
	quit(1)
