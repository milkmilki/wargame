extends SceneTree

func _init() -> void:
	var state := GameState.new()
	state.province_map_size = Vector2i(16, 16)
	for y in range(16):
		for x in range(16):
			state.province_ids.append(0 if x <= y else 1)
	var original := state.province_ids.duplicate()
	# The old loyalty border is the compatibility reference: trace the saved
	# labels, simplify shared chains, then curve them with pinned endpoints.
	state.map_source_manifest = MapSource.DEFAULT_MANIFEST
	var reference := MapRenderer.build_province_boundary_topology(state)
	state.map_source_manifest = "res://assets/terrain/eurasia_hydrology_map_source.json"
	var actual := MapRenderer.build_province_boundary_topology(state)
	var failures := 0
	for key in ["province", "province_a", "province_b", "province_side_a", "province_side_b"]:
		if actual[key] != reference[key]:
			printerr("SMOOTH_BORDER_FAIL: old loyalty geometry not preserved: ", key)
			failures += 1
	var oblique := 0
	var points: PackedVector2Array = actual.province
	for i in range(0, points.size(), 2):
		var delta := points[i + 1] - points[i]
		if absf(delta.x) > 0.000001 and absf(delta.y) > 0.000001:
			oblique += 1
	if oblique == 0:
		printerr("SMOOTH_BORDER_FAIL: diagonal boundary still consists entirely of grid steps")
		failures += 1
	if state.province_ids != original:
		printerr("SMOOTH_BORDER_FAIL: rendering changed province ownership")
		failures += 1
	print("PROVINCE_ID_SMOOTH_BORDERS: %d failures" % failures)
	quit(1 if failures else 0)
