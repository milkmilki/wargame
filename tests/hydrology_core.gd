extends SceneTree

func _init() -> void:
	if not ResourceLoader.exists("res://scripts/core/terrain_hydrology.gd"):
		push_error("Hydrology implementation is missing")
		quit(1)
		return
	var model = load("res://scripts/core/terrain_hydrology.gd")
	var size := Vector2i(17, 17)
	var heights := PackedFloat32Array()
	var wet := PackedFloat32Array()
	var sea := PackedByteArray()
	heights.resize(size.x * size.y)
	wet.resize(heights.size())
	sea.resize(heights.size())
	wet.fill(40.0)
	for y in range(size.y):
		for x in range(size.x):
			heights[y * size.x + x] = 0.02 + 0.005 * y + 0.002 * abs(x - 8)
			sea[y * size.x + x] = int(y == 0)
	var result: Dictionary = model.solve(heights, sea, wet, size, 2.879)
	_check(result, wet)
	assert(not result.features.is_empty())
	assert(not result.blocked_edges.is_empty())
	assert(result.features == model.solve(heights, sea, wet, size, 2.879).features)
	# A deep enclosed depression remains an inland terminal.
	heights.fill(0.5)
	heights[8 * size.x + 8] = 0.1
	sea.fill(0)
	result = model.solve(heights, sea, wet, size, 1.0)
	_check(result, wet)
	assert(result.terminal_kind[8 * size.x + 8] == "basin")
	assert(result.routing_heights[8 * size.x + 8] < 0.11)
	# A one-cell quantization pit is repaired on the analysis surface only.
	heights.fill(0.5)
	heights[8 * size.x + 8] = 0.495
	result = model.solve(heights, sea, wet, size, 1.0)
	_check(result, wet)
	assert(result.routing_heights[8 * size.x + 8] >= 0.5)
	assert(heights[8 * size.x + 8] < 0.5)
	print("HYDROLOGY_CORE_OK")
	quit(0)

func _check(result: Dictionary, local: PackedFloat32Array) -> void:
	var downstream: PackedInt32Array = result.downstream
	var total := 0.0
	var sinks := 0.0
	for i in range(local.size()):
		total += local[i]
		if downstream[i] < 0:
			sinks += result.flow[i]
		var node := i
		var seen := {}
		while node >= 0:
			assert(not seen.has(node), "Drainage cycle")
			seen[node] = true
			node = downstream[node]
	assert(abs(total - sinks) < maxf(0.01, total * 0.00001), "Runoff must be conserved")
	for feature in result.features:
		assert(feature.points.size() >= 2)
		if feature.river_class == "major" and feature.downstream_id >= 0:
			assert(result.features[feature.downstream_id].river_class == "major")
