extends SceneTree
## Compare the optimized search with the original exhaustive selection order.
## Optional timing gate: ROAD_GENERATION_BENCHMARK=1 (run without competing tests).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for seed_value in [12345, 23456, 34567, 45678]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var pixels: Array[Vector2i] = []
		var parent: Array[int] = []
		for i in range(24):
			pixels.append(Vector2i(rng.randi_range(1, 62), rng.randi_range(1, 62)))
			parent.append(i - i % 4)
		_check(pixels, parent, [], 2.879)
	# A vertical river blocks the shortest bridge but leaves a route around its end.
	_check([Vector2i(5, 5), Vector2i(20, 30), Vector2i(35, 30), Vector2i(55, 5)],
		[0, 0, 2, 2], [[Vector2i(28, 10), Vector2i(28, 63)]], 2.879)
	# Equal lengths, singleton components, no work for an already connected graph.
	_check([Vector2i(10, 10), Vector2i(20, 10), Vector2i(10, 20), Vector2i(20, 20)],
		[0, 1, 2, 3], [], 1.0)
	_check([Vector2i(10, 10), Vector2i(20, 20)], [0, 0], [], 1.0)
	_check([], [], [], 1.0)
	# Many distant river segments reproduce the old all-pairs intersection bottleneck.
	var pixels: Array[Vector2i] = []
	var parent: Array[int] = []
	for i in range(100):
		pixels.append(Vector2i(1 + i % 10 * 6, 1 + i / 10 * 6))
		parent.append(0 if i < 50 else 50)
	var river: Array = []
	for i in range(400):
		river.append(Vector2i(64 + i % 2, i))
	var times := _check(pixels, parent, [river], 2.879)
	print("ROAD_GENERATION_BENCHMARK reference_ms=%.2f optimized_ms=%.2f" % [times.x, times.y])
	if OS.get_environment("ROAD_GENERATION_BENCHMARK") == "1" and times.y >= times.x * 0.5:
		push_error("Distance pruning must remove at least half the exhaustive search time")
		quit(1)
		return
	print("ROAD_GENERATION_EQUIVALENCE_OK")
	quit()

func _check(pixels: Array[Vector2i], parent: Array[int], rivers: Array[Array], aspect: float) -> Vector2:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var mask := PackedByteArray()
	mask.resize(64 * 64)
	var positions: Array[Vector2] = []
	for pixel in pixels:
		positions.append((Vector2(pixel) + Vector2(0.5, 0.5)) / 64.0)
	for y in range(64):
		for x in range(64):
			image.set_pixel(x, y, Color(1, 1, 1, float(100 + (x + y) % 80) / 255.0))
			mask[y * 64 + x] = int((x + y) % 3 != 0)
	var expected: Array[Dictionary] = []
	var actual: Array[Dictionary] = []
	var before := parent.duplicate()
	var started := Time.get_ticks_usec()
	_reference_backbone(expected, before, image, mask, pixels, positions, aspect, rivers)
	var reference_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	TerrainMapGenerator._append_sea_component_backbone(actual, parent.duplicate(), image, mask, pixels, positions, aspect, rivers)
	var optimized_usec := Time.get_ticks_usec() - started
	assert(actual == expected, "SEA endpoints, order, capacities and terrain profiles must match exhaustive search")
	return Vector2(float(reference_usec) / 1000.0, float(optimized_usec) / 1000.0)


static func _reference_backbone(
	roads: Array[Dictionary],
	parent: Array[int],
	image: Image,
	mask: PackedByteArray,
	pixels: Array[Vector2i],
	positions: Array[Vector2],
	map_aspect_ratio: float,
	river_paths: Array[Array]
) -> void:
	while true:
		var remaining_roots := {}
		for city_id in range(parent.size()):
			remaining_roots[TerrainMapGenerator._root(parent, city_id)] = true
		if remaining_roots.size() <= 1:
			break
		var best_a := -1
		var best_b := -1
		var best_length := INF
		var best_profile := {}
		for a in range(pixels.size()):
			for b in range(a + 1, pixels.size()):
				if TerrainMapGenerator._root(parent, a) == TerrainMapGenerator._root(parent, b):
					continue
				if TerrainMapGenerator._segment_crosses_pixel_river(
					pixels[a], pixels[b], river_paths
				):
					continue
				var length := TerrainMapGenerator.metric_length_between(
					positions[a], positions[b], map_aspect_ratio
				)
				if length > best_length + 0.000001:
					continue
				var profile := TerrainMapGenerator._edge_profile(image, mask, pixels[a], pixels[b])
				if (
					length < best_length - 0.000001
					or (
						is_equal_approx(length, best_length)
						and TerrainMapGenerator._pair_key(a, b) < TerrainMapGenerator._pair_key(best_a, best_b)
					)
				):
					best_a = a
					best_b = b
					best_length = length
					best_profile = profile
		assert(best_a >= 0, "海区骨架必须存在不穿河道的SEA连接")
		var root_a := TerrainMapGenerator._root(parent, best_a)
		var root_b := TerrainMapGenerator._root(parent, best_b)
		parent[root_b] = root_a
		roads.append({
			"a": best_a,
			"b": best_b,
			"length": best_length,
			"height_difference": best_profile["height_difference"],
			"land_ratio": best_profile["land_ratio"],
			"cost": best_length,
			"backbone": true,
			"max_manpower": Edge.WATER_MANPOWER,
			"base_max_manpower": Edge.WATER_MANPOWER,
			"danger": 0.55,
			"distance": TerrainMapGenerator.distance_units_for_metric_length(best_length),
			"kind": Edge.Kind.SEA,
			"travel_time_multiplier": TerrainMapGenerator.RIVER_TRAVEL_TIME_MULTIPLIER,
			"supply_loss_multiplier": TerrainMapGenerator.RIVER_SUPPLY_LOSS_MULTIPLIER,
			"allows_holding": false,
		})
