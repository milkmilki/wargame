class_name TerrainMapGenerator
extends RefCounted
## 从带 Alpha 的灰度高度图确定性生成城市位置和道路图。

const ANALYSIS_WIDTH: int = 256
const ALPHA_THRESHOLD: float = 0.20
const LUMA_THRESHOLD: float = 0.015
const CANDIDATE_STRIDE: int = 2
const INTERIOR_RADIUS: int = 2
const RELIEF_RADIUS: int = 3
const TARGET_EDGE_COUNT: int = 112
const ROAD_SAMPLE_COUNT: int = 48

static var _cache: Dictionary = {}


static func build(source_path: String, city_count: int) -> Dictionary:
	var cache_key := "%s:%d" % [source_path, city_count]
	if _cache.has(cache_key):
		return (_cache[cache_key] as Dictionary).duplicate(true)
	var texture := load(source_path) as Texture2D
	var source := texture.get_image() if texture != null else null
	assert(source != null and not source.is_empty(), "无法加载地形高度图：%s" % source_path)
	var analysis := source.duplicate()
	var analysis_height := maxi(
		int(round(float(source.get_height()) * float(ANALYSIS_WIDTH) / float(source.get_width()))),
		1
	)
	analysis.resize(ANALYSIS_WIDTH, analysis_height, Image.INTERPOLATE_LANCZOS)
	var component := _largest_land_component(analysis)
	assert(component["count"] >= city_count * 16, "高度图有效陆地区域不足")
	var mask: PackedByteArray = component["mask"]
	var bounds: Rect2i = component["bounds"]
	var samples := _sample_cities(analysis, mask, bounds, city_count)
	var road_result := _build_roads(analysis, mask, samples)
	var result := {
		"positions": samples["positions"],
		"pixels": samples["pixels"],
		"heights": samples["heights"],
		"reliefs": samples["reliefs"],
		"roads": road_result["roads"],
		"nation_order": road_result["nation_order"],
		"bounds": bounds,
		"image_size": analysis.get_size(),
		"map_aspect_ratio": (
			float(maxi(bounds.size.x, 1)) / float(maxi(bounds.size.y, 1))
		),
	}
	_cache[cache_key] = result.duplicate(true)
	return result


static func _largest_land_component(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var eligible := PackedByteArray()
	eligible.resize(width * height)
	for y in range(height):
		for x in range(width):
			var color := image.get_pixel(x, y)
			if color.a >= ALPHA_THRESHOLD and color.get_luminance() >= LUMA_THRESHOLD:
				eligible[y * width + x] = 1
	var visited := PackedByteArray()
	visited.resize(width * height)
	var best: Array[int] = []
	var offsets := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for index in range(eligible.size()):
		if eligible[index] == 0 or visited[index] != 0:
			continue
		var queue: Array[int] = [index]
		var component: Array[int] = []
		visited[index] = 1
		var cursor := 0
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			component.append(current)
			var point := Vector2i(current % width, current / width)
			for offset in offsets:
				var next: Vector2i = point + offset
				if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
					continue
				var next_index: int = next.y * width + next.x
				if eligible[next_index] == 0 or visited[next_index] != 0:
					continue
				visited[next_index] = 1
				queue.append(next_index)
		if component.size() > best.size():
			best = component
	var mask := PackedByteArray()
	mask.resize(width * height)
	var min_x := width
	var min_y := height
	var max_x := 0
	var max_y := 0
	for index in best:
		mask[index] = 1
		var x := index % width
		var y := index / width
		min_x = mini(min_x, x)
		min_y = mini(min_y, y)
		max_x = maxi(max_x, x)
		max_y = maxi(max_y, y)
	return {
		"mask": mask,
		"count": best.size(),
		"bounds": Rect2i(
			min_x,
			min_y,
			maxi(max_x - min_x + 1, 1),
			maxi(max_y - min_y + 1, 1)
		),
	}


static func _sample_cities(
	image: Image,
	mask: PackedByteArray,
	bounds: Rect2i,
	city_count: int
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for y in range(bounds.position.y, bounds.end.y, CANDIDATE_STRIDE):
		for x in range(bounds.position.x, bounds.end.x, CANDIDATE_STRIDE):
			if not _is_interior(mask, image.get_width(), image.get_height(), x, y):
				continue
			var relief := _local_relief(image, x, y, RELIEF_RADIUS)
			candidates.append({
				"pixel": Vector2i(x, y),
				"height": image.get_pixel(x, y).get_luminance(),
				"relief": relief,
			})
	assert(candidates.size() >= city_count, "平坦陆地候选点不足")
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var relief_a := float(a["relief"])
		var relief_b := float(b["relief"])
		if not is_equal_approx(relief_a, relief_b):
			return relief_a < relief_b
		var pa: Vector2i = a["pixel"]
		var pb: Vector2i = b["pixel"]
		return pa.y < pb.y or (pa.y == pb.y and pa.x < pb.x)
	)
	var usable_count := maxi(int(round(float(candidates.size()) * 0.70)), city_count)
	candidates.resize(usable_count)
	var center := Vector2(bounds.get_center())
	var first_index := 0
	var first_score := INF
	for i in range(candidates.size()):
		var point := Vector2(candidates[i]["pixel"])
		var score := point.distance_squared_to(center) + float(candidates[i]["relief"]) * 10000.0
		if score < first_score:
			first_score = score
			first_index = i
	var selected: Array[Dictionary] = [candidates[first_index]]
	var selected_pixels := {candidates[first_index]["pixel"]: true}
	var scale := Vector2(maxi(bounds.size.x, 1), maxi(bounds.size.y, 1))
	while selected.size() < city_count:
		var best_index := -1
		var best_score := -INF
		for i in range(candidates.size()):
			var candidate := candidates[i]
			if selected_pixels.has(candidate["pixel"]):
				continue
			var candidate_norm := (
				Vector2(candidate["pixel"]) - Vector2(bounds.position)
			) / scale
			var min_distance_sq := INF
			for chosen in selected:
				var chosen_norm := (
					Vector2(chosen["pixel"]) - Vector2(bounds.position)
				) / scale
				min_distance_sq = minf(
					min_distance_sq,
					candidate_norm.distance_squared_to(chosen_norm)
				)
			var score := min_distance_sq - float(candidate["relief"]) * 0.08
			if score > best_score:
				best_score = score
				best_index = i
		assert(best_index != -1, "无法选满城市点")
		selected.append(candidates[best_index])
		selected_pixels[candidates[best_index]["pixel"]] = true
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector2i = a["pixel"]
		var pb: Vector2i = b["pixel"]
		return pa.y < pb.y or (pa.y == pb.y and pa.x < pb.x)
	)
	var positions: Array[Vector2] = []
	var pixels: Array[Vector2i] = []
	var heights: Array[float] = []
	var reliefs: Array[float] = []
	for selected_city in selected:
		var pixel: Vector2i = selected_city["pixel"]
		positions.append(Vector2(
			float(pixel.x - bounds.position.x) / float(maxi(bounds.size.x - 1, 1)),
			float(pixel.y - bounds.position.y) / float(maxi(bounds.size.y - 1, 1))
		))
		pixels.append(pixel)
		heights.append(float(selected_city["height"]))
		reliefs.append(float(selected_city["relief"]))
	return {
		"positions": positions,
		"pixels": pixels,
		"heights": heights,
		"reliefs": reliefs,
	}


static func _is_interior(
	mask: PackedByteArray,
	width: int,
	height: int,
	x: int,
	y: int
) -> bool:
	for oy in range(-INTERIOR_RADIUS, INTERIOR_RADIUS + 1):
		for ox in range(-INTERIOR_RADIUS, INTERIOR_RADIUS + 1):
			var px := x + ox
			var py := y + oy
			if px < 0 or py < 0 or px >= width or py >= height:
				return false
			if mask[py * width + px] == 0:
				return false
	return true


static func _local_relief(image: Image, x: int, y: int, radius: int) -> float:
	var minimum := 1.0
	var maximum := 0.0
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			var px := clampi(x + ox, 0, image.get_width() - 1)
			var py := clampi(y + oy, 0, image.get_height() - 1)
			var height := image.get_pixel(px, py).get_luminance()
			minimum = minf(minimum, height)
			maximum = maxf(maximum, height)
	return maximum - minimum


static func _build_roads(
	image: Image,
	mask: PackedByteArray,
	samples: Dictionary
) -> Dictionary:
	var pixels: Array[Vector2i] = samples["pixels"]
	var positions: Array[Vector2] = samples["positions"]
	var candidates: Array[Dictionary] = []
	for a in range(pixels.size()):
		for b in range(a + 1, pixels.size()):
			var profile := _edge_profile(image, mask, pixels[a], pixels[b])
			var length := positions[a].distance_to(positions[b])
			candidates.append({
				"a": a,
				"b": b,
				"length": length,
				"height_difference": profile["height_difference"],
				"land_ratio": profile["land_ratio"],
				"cost": (
					length
					+ float(profile["height_difference"]) * 0.8
					+ (1.0 - float(profile["land_ratio"])) * 3.0
				),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var cost_a := float(a["cost"])
		var cost_b := float(b["cost"])
		if not is_equal_approx(cost_a, cost_b):
			return cost_a < cost_b
		return _pair_key(int(a["a"]), int(a["b"])) < _pair_key(int(b["a"]), int(b["b"]))
	)
	var candidate_by_key := {}
	for candidate in candidates:
		candidate_by_key[_pair_key(int(candidate["a"]), int(candidate["b"]))] = candidate
	var nation_order: Array[int] = []
	var start := 0
	for i in range(1, positions.size()):
		if (
			positions[i].x + positions[i].y < positions[start].x + positions[start].y
		):
			start = i
	nation_order.append(start)
	var route_visited := {start: true}
	var selected: Array[Dictionary] = []
	var selected_keys := {}
	while nation_order.size() < pixels.size():
		var current := nation_order[nation_order.size() - 1]
		var best_next := -1
		var best_cost := INF
		for city_id in range(pixels.size()):
			if route_visited.has(city_id):
				continue
			var candidate: Dictionary = candidate_by_key[
				_pair_key(current, city_id)
			]
			var cost := float(candidate["cost"])
			if cost < best_cost or (
				is_equal_approx(cost, best_cost) and city_id < best_next
			):
				best_cost = cost
				best_next = city_id
		var route_edge: Dictionary = candidate_by_key[
			_pair_key(current, best_next)
		]
		route_edge["backbone"] = true
		selected.append(route_edge)
		selected_keys[_pair_key(current, best_next)] = true
		nation_order.append(best_next)
		route_visited[best_next] = true
	for candidate in candidates:
		if selected.size() >= TARGET_EDGE_COUNT:
			break
		var key := _pair_key(int(candidate["a"]), int(candidate["b"]))
		if selected_keys.has(key) or float(candidate["land_ratio"]) < 0.90:
			continue
		if _crosses_selected(candidate, selected, positions):
			continue
		candidate["backbone"] = false
		selected.append(candidate)
		selected_keys[key] = true
	if selected.size() < TARGET_EDGE_COUNT:
		for candidate in candidates:
			if selected.size() >= TARGET_EDGE_COUNT:
				break
			var key := _pair_key(int(candidate["a"]), int(candidate["b"]))
			if selected_keys.has(key) or float(candidate["land_ratio"]) < 0.80:
				continue
			selected.append(candidate)
			selected_keys[key] = true
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var diff_a := float(a["height_difference"])
		var diff_b := float(b["height_difference"])
		if not is_equal_approx(diff_a, diff_b):
			return diff_a < diff_b
		return _pair_key(int(a["a"]), int(a["b"])) < _pair_key(int(b["a"]), int(b["b"]))
	)
	var count := selected.size()
	for i in range(count):
		var road := selected[i]
		var percentile := float(i) / float(maxi(count - 1, 1))
		road["max_throughput"] = (
			4 if percentile < 0.12
			else 3 if percentile < 0.32
			else 2 if percentile < 0.65
			else 1 if percentile < 0.90
			else 0
		)
		if bool(road.get("backbone", false)):
			road["max_throughput"] = maxi(int(road["max_throughput"]), 1)
		road["danger"] = clampf(percentile, 0.0, 1.0)
		road["distance"] = clampi(int(round(float(road["length"]) * 12.0)), 1, 5)
	var blocked_target := maxi(int(round(float(count) * 0.10)), 1)
	var blocked_count := 0
	for i in range(count - 1, -1, -1):
		var road := selected[i]
		if bool(road.get("backbone", false)):
			continue
		road["max_throughput"] = 0
		blocked_count += 1
		if blocked_count >= blocked_target:
			break
	return {
		"roads": selected,
		"nation_order": nation_order,
	}


static func _edge_profile(
	image: Image,
	mask: PackedByteArray,
	from: Vector2i,
	to: Vector2i
) -> Dictionary:
	var minimum := 1.0
	var maximum := 0.0
	var land_samples := 0
	for i in range(ROAD_SAMPLE_COUNT + 1):
		var t := float(i) / float(ROAD_SAMPLE_COUNT)
		var point := Vector2(from).lerp(Vector2(to), t)
		var x := clampi(int(round(point.x)), 0, image.get_width() - 1)
		var y := clampi(int(round(point.y)), 0, image.get_height() - 1)
		var height := image.get_pixel(x, y).get_luminance()
		minimum = minf(minimum, height)
		maximum = maxf(maximum, height)
		if mask[y * image.get_width() + x] != 0:
			land_samples += 1
	return {
		"height_difference": maximum - minimum,
		"land_ratio": float(land_samples) / float(ROAD_SAMPLE_COUNT + 1),
	}


static func _crosses_selected(
	candidate: Dictionary,
	selected: Array[Dictionary],
	positions: Array[Vector2]
) -> bool:
	var a := int(candidate["a"])
	var b := int(candidate["b"])
	for road in selected:
		var c := int(road["a"])
		var d := int(road["b"])
		if a in [c, d] or b in [c, d]:
			continue
		if Geometry2D.segment_intersects_segment(
			positions[a], positions[b], positions[c], positions[d]
		) != null:
			return true
	return false


static func _pair_key(a: int, b: int) -> int:
	return mini(a, b) * 10000 + maxi(a, b)
