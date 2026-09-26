class_name VisualWeightedVoronoi
extends RefCounted
## High-resolution, visual-only city partitioning in heightmap UV space.

const DEFAULT_SIZE := Vector2i(2048, 2048)
const DEFAULT_PROPAGATION_SIZE := Vector2i(512, 512)
const DEFAULT_SLOPE_SCALE := 32.0
const SEA_COST := 255


static func visual_step_cost(height_a: float, height_b: float,
		slope_scale: float = DEFAULT_SLOPE_SCALE) -> int:
	var slope := absf(height_b - height_a)
	return clampi(1 + int(round(slope * slope_scale)), 1, 254)


static func build_visual_cost_field(
		height_image: Image,
		size: Vector2i = DEFAULT_SIZE,
		land_threshold: float = 0.5
	) -> Dictionary:
	var safe_size := Vector2i(maxi(size.x, 1), maxi(size.y, 1))
	var heights := PackedFloat32Array()
	heights.resize(safe_size.x * safe_size.y)
	var costs := PackedByteArray()
	costs.resize(heights.size())
	for y in range(safe_size.y):
		for x in range(safe_size.x):
			var color := _sample_height(height_image, x, y, safe_size)
			var index := y * safe_size.x + x
			var is_land := TerrainMapGenerator.packed_is_land(color)
			heights[index] = TerrainMapGenerator.packed_altitude(color)
			costs[index] = 1 if is_land and color.a >= land_threshold else SEA_COST
	return {
		"size": safe_size,
		"heights": heights,
		"costs": costs,
	}


static func build_visual_city_ids(
		height_image: Image,
		city_seeds: Array[Dictionary],
		size: Vector2i = DEFAULT_SIZE,
		slope_scale: float = DEFAULT_SLOPE_SCALE,
		propagation_size: Vector2i = DEFAULT_PROPAGATION_SIZE
	) -> Dictionary:
	var safe_size := Vector2i(maxi(size.x, 1), maxi(size.y, 1))
	var work_size := Vector2i(
		mini(safe_size.x, maxi(propagation_size.x, 1)),
		mini(safe_size.y, maxi(propagation_size.y, 1))
	)
	if safe_size.x <= propagation_size.x and safe_size.y <= propagation_size.y:
		work_size = safe_size
	var field := build_visual_cost_field(height_image, work_size)
	var labels := _propagate(
		field["heights"], field["costs"], work_size,
		city_seeds, slope_scale
	)
	var city_ids := Image.create(safe_size.x, safe_size.y, false, Image.FORMAT_RF)
	city_ids.fill(Color(-1.0, 0.0, 0.0, 1.0))
	var land_mask := Image.create(safe_size.x, safe_size.y, false, Image.FORMAT_L8)
	var coarse_labels := labels["labels"] as PackedInt32Array
	var coarse_costs := field["costs"] as PackedByteArray
	var seed_positions := _seed_positions(city_seeds)
	for y in range(safe_size.y):
		for x in range(safe_size.x):
			var wx := mini(int(floor(float(x) * work_size.x / safe_size.x)), work_size.x - 1)
			var wy := mini(int(floor(float(y) * work_size.y / safe_size.y)), work_size.y - 1)
			var work_index := wy * work_size.x + wx
			var color := _sample_height(height_image, x, y, safe_size)
			if not TerrainMapGenerator.packed_is_land(color):
				continue
			land_mask.set_pixel(x, y, Color.WHITE)
			var city_id := int(coarse_labels[work_index])
			if city_id >= 0:
				city_id = _refine_boundary_label(
					x, y, safe_size, wx, wy, work_size, coarse_labels,
					coarse_costs, seed_positions, city_id, height_image, slope_scale
				)
				city_ids.set_pixel(x, y, Color(float(city_id), 0.0, 0.0, 1.0))
	return {
		"city_ids": city_ids,
		"land_mask": land_mask,
		"unassigned_land_pixels": _count_unassigned(city_ids, land_mask),
		"blocked_pixels": _count_blocked(land_mask),
		"seed_count": city_seeds.size(),
		"propagation_size": work_size,
		"revision": visual_region_signature(city_ids),
	}


static func visual_region_signature(city_ids: Image) -> int:
	if city_ids == null or city_ids.is_empty():
		return 0
	return hash([city_ids.get_size(), city_ids.get_data()])


static func _propagate(
		heights: PackedFloat32Array,
		costs: PackedByteArray,
		size: Vector2i,
		city_seeds: Array[Dictionary],
		slope_scale: float
	) -> Dictionary:
	var total := size.x * size.y
	var distances := PackedInt32Array()
	distances.resize(total)
	var labels := PackedInt32Array()
	labels.resize(total)
	for index in range(total):
		distances[index] = 2147483647
		labels[index] = -1
	var heap: Array[Vector3i] = []
	for seed_value in city_seeds:
		var seed := seed_value as Dictionary
		var city_id := int(seed.get("city_id", -1))
		var position: Vector2 = seed.get("position", Vector2(-1, -1))
		var x := clampi(int(floor(position.x * size.x)), 0, size.x - 1)
		var y := clampi(int(floor(position.y * size.y)), 0, size.y - 1)
		var index := y * size.x + x
		if city_id < 0 or costs[index] >= SEA_COST:
			continue
		if city_id < labels[index] or labels[index] < 0:
			distances[index] = 0
			labels[index] = city_id
			heap.push_back(Vector3i(0, city_id, index))
	while not heap.is_empty():
		var current := _heap_pop(heap)
		var distance := current.x
		var city_id := current.y
		var index := current.z
		if distances[index] != distance or labels[index] != city_id:
			continue
		var x: int = index % size.x
		var y: int = index / size.x
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nx: int = x + offset.x
			var ny: int = y + offset.y
			if nx < 0 or ny < 0 or nx >= size.x or ny >= size.y:
				continue
			var next_index: int = ny * size.x + nx
			if costs[next_index] >= SEA_COST:
				continue
			var step := visual_step_cost(heights[index], heights[next_index], slope_scale)
			var candidate := distance + step
			if candidate < distances[next_index] or (
				candidate == distances[next_index] and
				(city_id < labels[next_index] or labels[next_index] < 0)
			):
				distances[next_index] = candidate
				labels[next_index] = city_id
				heap.push_back(Vector3i(candidate, city_id, next_index))
				heapify_up(heap, heap.size() - 1)
	return {"labels": labels, "distances": distances}


static func _refine_boundary_label(
		x: int, y: int, size: Vector2i, wx: int, wy: int, work_size: Vector2i,
		labels: PackedInt32Array, costs: PackedByteArray,
		seed_positions: Dictionary, fallback: int, height_image: Image,
		slope_scale: float
) -> int:
	var candidates := PackedInt32Array([fallback])
	var is_boundary := false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx: int = wx + dx
			var ny: int = wy + dy
			if nx < 0 or ny < 0 or nx >= work_size.x or ny >= work_size.y:
				continue
			var id := int(labels[ny * work_size.x + nx])
			if id >= 0 and id != fallback:
				is_boundary = true
				if not candidates.has(id):
					candidates.append(id)
	if not is_boundary:
		return fallback
	var best := fallback
	var best_score := INF
	var sample := Vector2((float(x) + 0.5) / size.x, (float(y) + 0.5) / size.y)
	for id in candidates:
		if not seed_positions.has(id):
			continue
		var seed: Vector2 = seed_positions[id]
		var score := sample.distance_squared_to(seed)
		if score < best_score or (is_equal_approx(score, best_score) and id < best):
			best_score = score
			best = id
	return best


static func _seed_positions(city_seeds: Array[Dictionary]) -> Dictionary:
	var result := {}
	for seed_value in city_seeds:
		var seed := seed_value as Dictionary
		var id := int(seed.get("city_id", -1))
		if id >= 0:
			result[id] = seed.get("position", Vector2.ZERO)
	return result


static func _sample_height(image: Image, x: int, y: int, size: Vector2i) -> Color:
	if image == null or image.is_empty():
		return Color(1.0, 1.0, 1.0, 1.0)
	var sx := clampi(int(floor((float(x) + 0.5) * image.get_width() / size.x)), 0, image.get_width() - 1)
	var sy := clampi(int(floor((float(y) + 0.5) * image.get_height() / size.y)), 0, image.get_height() - 1)
	return image.get_pixel(sx, sy)


static func _count_unassigned(ids: Image, land: Image) -> int:
	var count := 0
	for y in range(ids.get_height()):
		for x in range(ids.get_width()):
			if land.get_pixel(x, y).r > 0.5 and ids.get_pixel(x, y).r < 0.0:
				count += 1
	return count


static func _count_blocked(land: Image) -> int:
	var count := 0
	for y in range(land.get_height()):
		for x in range(land.get_width()):
			if land.get_pixel(x, y).r < 0.5:
				count += 1
	return count


static func _heap_pop(heap: Array[Vector3i]) -> Vector3i:
	var result := heap[0]
	var last: Vector3i = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var index := 0
		while true:
			var left := index * 2 + 1
			var right := left + 1
			var smallest := index
			if left < heap.size() and _heap_less(heap[left], heap[smallest]):
				smallest = left
			if right < heap.size() and _heap_less(heap[right], heap[smallest]):
				smallest = right
			if smallest == index:
				break
			var swap := heap[index]
			heap[index] = heap[smallest]
			heap[smallest] = swap
			index = smallest
	return result


static func heapify_up(heap: Array[Vector3i], index: int) -> void:
	while index > 0:
		var parent := (index - 1) / 2
		if not _heap_less(heap[index], heap[parent]):
			break
		var swap := heap[index]
		heap[index] = heap[parent]
		heap[parent] = swap
		index = parent


static func _heap_less(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z
