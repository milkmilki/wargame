extends SceneTree
## Compatibility-named gate for the new rule: docks are deterministic points on
## province-boundary rivers and each one exposes exactly both adjacent banks.


func _init() -> void:
	var first := TerrainMapGenerator.build(
		GameState.terrain_map_path(), GameState.TERRAIN_CITY_COUNT,
		GameState.DEFAULT_CITY_MASK_PATH
	)
	TerrainMapGenerator._cache.clear()
	var second := TerrainMapGenerator.build(
		GameState.terrain_map_path(), GameState.TERRAIN_CITY_COUNT,
		GameState.DEFAULT_CITY_MASK_PATH
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
	var candidates: Array = first.get("lowland_dock_regions", [])
	var bank_regions: Array = first.get("dock_bank_regions", [])
	var all_candidates_covered := not candidates.is_empty()
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		var covered := false
		for dock_value in first_docks:
			var dock: Dictionary = dock_value
			if int(dock["river_id"]) != int(candidate["river_id"]):
				continue
			if TerrainMapGenerator.metric_length_between(
				candidate["position"], dock["position"],
				MapSource.aspect_ratio()
			) < TerrainMapGenerator.RIVER_DOCK_MIN_SPACING:
				covered = true
				break
		if not covered:
			all_candidates_covered = false
			break
	valid = (
		valid
		and all_candidates_covered
		and first_docks.size() >= int(ceil(float(bank_regions.size()) * 0.75))
		and first_docks.size() <= bank_regions.size()
	)
	var counts := {}
	var bank_region_counts := {}
	for region_value in bank_regions:
		var region: Dictionary = region_value
		var river_id := int(region["river_id"])
		bank_region_counts[river_id] = int(
			bank_region_counts.get(river_id, 0)
		) + 1
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
		var region_count := int(bank_region_counts.get(river_id, 0))
		var dock_count := int(counts.get(river_id, 0))
		valid = (
			valid
			and dock_count >= 2
			and dock_count >= int(ceil(float(region_count) * 0.75))
			and dock_count <= region_count
		)
	if not valid:
		_fail("boundary docks invalid: %s" % counts)
		return
	print(
		"BOUNDARY_RIVER_DOCKS_OK counts=", counts,
		" lowland_regions=", candidates.size(),
		" bank_regions=", bank_region_counts
	)
	quit(0)


func _fail(message: String) -> void:
	push_error("BOUNDARY_RIVER_DOCKS_FAILED: " + message)
	quit(1)
