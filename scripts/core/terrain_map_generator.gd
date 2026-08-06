class_name TerrainMapGenerator
extends RefCounted
## 从带 Alpha 的灰度高度图确定性生成城市位置和道路图。

const ANALYSIS_WIDTH: int = 256
const ALPHA_THRESHOLD: float = 0.20
const LUMA_THRESHOLD: float = 0.015
const CANDIDATE_STRIDE: int = 2
const INTERIOR_RADIUS: int = 2
const RELIEF_RADIUS: int = 3
const RELIEF_SPACING_WEIGHT: float = 0.015
const REFERENCE_CITY_COUNT: int = 64
const MIN_CITY_SPACING_AT_REFERENCE: float = 0.075
const LOCAL_SPACING_MIN_FACTOR: float = 0.55
const LOCAL_SPACING_MAX_FACTOR: float = 1.25
const SPACING_RELAXATION_STEP: float = 0.96
const SPACING_RELAXATION_FLOOR: float = 0.72
const RIVER_BANK_MIN_DISTANCE: float = 0.006
const RIVER_BANK_IDEAL_DISTANCE: float = 0.020
const RIVER_BANK_MAX_DISTANCE: float = 0.060
const MAX_LOCAL_EDGE_LENGTH: float = 0.30
const PREFERRED_BACKBONE_LENGTH: float = 0.34
const ROAD_SAMPLE_COUNT: int = 48
const RIVER_COUNT: int = 2
const RIVER_CHANNEL_DEVIATION_WEIGHT: float = 36.0
const RIVER_DOCK_SHARE: float = 0.25
const RIVER_DOCK_MIN_PER_RIVER: int = 2
const RIVER_CROSSING_ENDPOINT_EPS: float = 0.0001
const RIVER_CROSSING_MERGE_EPS: float = 0.0001
const LANDING_DANGER_MIN: float = 0.90
const EDGE_DISTANCE_UNITS_PER_MAP_HEIGHT: float = 12.0
## 河运速度为同 distance 陆路的 1.2 倍，因此耗时为陆路的 1/1.2。
const RIVER_TRAVEL_TIME_MULTIPLIER: float = 1.0 / 1.2
const RIVER_SUPPLY_LOSS_MULTIPLIER: float = 0.25

static var _cache: Dictionary = {}


static func build(source_path: String, city_count: int) -> Dictionary:
	var cache_key := "settlement-v2:%s:%d" % [source_path, city_count]
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
	var map_aspect_ratio := clampf(
		float(maxi(bounds.size.x, 1))
			/ float(maxi(bounds.size.y, 1)),
		0.5,
		2.5
	)
	var river_paths := _build_river_paths(
		analysis,
		mask,
		bounds
	)
	var samples := _sample_cities(
		analysis,
		mask,
		bounds,
		city_count,
		river_paths
	)
	var road_result := _build_roads(
		analysis,
		mask,
		samples,
		map_aspect_ratio
	)
	var transport := _build_river_transport(
		analysis,
		mask,
		bounds,
		samples,
		road_result["roads"],
		river_paths,
		city_count,
		map_aspect_ratio
	)
	var provinces := _build_province_raster(
		mask,
		analysis.get_width(),
		bounds,
		samples["pixels"]
	)
	var result := {
		"positions": samples["positions"],
		"pixels": samples["pixels"],
		"heights": samples["heights"],
		"reliefs": samples["reliefs"],
		"roads": transport["roads"],
		"docks": transport["docks"],
		"river_paths": transport["river_paths"],
		"bounds": bounds,
		"image_size": analysis.get_size(),
		"source_region_normalized": Rect2(
			Vector2(bounds.position) / Vector2(analysis.get_size()),
			Vector2(bounds.size) / Vector2(analysis.get_size())
		),
		"map_aspect_ratio": map_aspect_ratio,
		"province_map_size": provinces["size"],
		"province_ids": provinces["ids"],
	}
	_cache[cache_key] = result.duplicate(true)
	return result


static func _build_province_raster(
	land_mask: PackedByteArray,
	image_width: int,
	bounds: Rect2i,
	city_pixels: Array[Vector2i]
) -> Dictionary:
	var width := bounds.size.x
	var height := bounds.size.y
	var ids := PackedInt32Array()
	ids.resize(width * height)
	ids.fill(-1)
	for local_y in range(height):
		var image_y := bounds.position.y + local_y
		for local_x in range(width):
			var image_x := bounds.position.x + local_x
			if land_mask[image_y * image_width + image_x] == 0:
				continue
			var best_city := -1
			var best_distance := INF
			for city_id in range(city_pixels.size()):
				var delta := Vector2(city_pixels[city_id]) - Vector2(image_x, image_y)
				var distance := delta.length_squared()
				if (
					distance < best_distance
					or (
						is_equal_approx(distance, best_distance)
						and city_id < best_city
					)
				):
					best_distance = distance
					best_city = city_id
			ids[local_y * width + local_x] = best_city
	return {
		"size": Vector2i(width, height),
		"ids": ids,
	}


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
	city_count: int,
	river_paths: Array[Array]
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var scale := Vector2(
		maxi(bounds.size.x, 1),
		maxi(bounds.size.y, 1)
	)
	var map_aspect := (
		float(maxi(bounds.size.x, 1))
		/ float(maxi(bounds.size.y, 1))
	)
	var base_spacing := minimum_city_spacing_for_count(city_count)
	for y in range(bounds.position.y, bounds.end.y, CANDIDATE_STRIDE):
		for x in range(bounds.position.x, bounds.end.x, CANDIDATE_STRIDE):
			if not _is_interior(mask, image.get_width(), image.get_height(), x, y):
				continue
			var relief := _local_relief(image, x, y, RELIEF_RADIUS)
			var height := image.get_pixel(x, y).get_luminance()
			var normalized := (
				Vector2(x, y) - Vector2(bounds.position)
			) / scale
			var river_affinity := _river_bank_affinity(
				Vector2i(x, y),
				bounds,
				river_paths
			)
			var density := settlement_density(
				height,
				relief,
				normalized,
				river_affinity
			)
			candidates.append({
				"pixel": Vector2i(x, y),
				"height": height,
				"relief": relief,
				"density": density,
				"river_affinity": river_affinity,
				"spacing": clampf(
					base_spacing / sqrt(maxf(density, 0.01)),
					base_spacing * LOCAL_SPACING_MIN_FACTOR,
					base_spacing * LOCAL_SPACING_MAX_FACTOR
				),
			})
	assert(candidates.size() >= city_count, "平坦陆地候选点不足")
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var density_a := float(a["density"])
		var density_b := float(b["density"])
		if not is_equal_approx(density_a, density_b):
			return density_a > density_b
		var pa: Vector2i = a["pixel"]
		var pb: Vector2i = b["pixel"]
		return pa.y < pb.y or (pa.y == pb.y and pa.x < pb.x)
	)
	var first_index := 0
	var selected: Array[Dictionary] = [candidates[first_index]]
	var selected_pixels := {candidates[first_index]["pixel"]: true}
	var spacing_scale := 1.0
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
			var candidate_metric := Vector2(
				candidate_norm.x * map_aspect,
				candidate_norm.y
			)
			var min_distance_sq := INF
			for chosen in selected:
				var chosen_norm := (
					Vector2(chosen["pixel"]) - Vector2(bounds.position)
				) / scale
				var chosen_metric := Vector2(
					chosen_norm.x * map_aspect,
					chosen_norm.y
				)
				min_distance_sq = minf(
					min_distance_sq,
					candidate_metric.distance_squared_to(chosen_metric)
				)
				var required_spacing := (
					(
						float(candidate["spacing"])
						+ float(chosen["spacing"])
					) * 0.5 * spacing_scale
				)
				if (
					candidate_metric.distance_squared_to(
						chosen_metric
					)
					< required_spacing * required_spacing
				):
					min_distance_sq = -INF
					break
			if min_distance_sq < 0.0:
				continue
			var score := (
				min_distance_sq * float(candidate["density"])
				- float(candidate["relief"]) * RELIEF_SPACING_WEIGHT
			)
			var candidate_pixel: Vector2i = candidate["pixel"]
			var best_pixel: Vector2i = (
				candidates[best_index]["pixel"]
				if best_index >= 0
				else Vector2i(2147483647, 2147483647)
			)
			if (
				score > best_score
				or (
					is_equal_approx(score, best_score)
					and (
						candidate_pixel.y < best_pixel.y
						or (
							candidate_pixel.y == best_pixel.y
							and candidate_pixel.x < best_pixel.x
						)
					)
				)
			):
				best_score = score
				best_index = i
		if best_index == -1:
			spacing_scale *= SPACING_RELAXATION_STEP
			assert(
				spacing_scale >= SPACING_RELAXATION_FLOOR,
				"无法在动态最小间距下选满 %d 个城市点"
					% city_count
			)
			continue
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


static func minimum_city_spacing_for_count(city_count: int) -> float:
	return (
		MIN_CITY_SPACING_AT_REFERENCE
		* sqrt(
			float(REFERENCE_CITY_COUNT)
			/ float(maxi(city_count, 1))
		)
	)


## 聚落密度的唯一评分源。海拔/起伏越低越适居，中东部与东南获得人口带加权，
## 河岸获得额外加权；返回值也用于反向缩放局部最小间距。
static func settlement_density(
	height: float,
	relief: float,
	normalized_position: Vector2,
	river_affinity: float
) -> float:
	var lowland := pow(
		1.0 - clampf(height, 0.0, 1.0),
		1.6
	)
	var eastness := smoothstep(
		0.10,
		0.95,
		clampf(normalized_position.x, 0.0, 1.0)
	)
	var southness := smoothstep(
		0.20,
		0.95,
		clampf(normalized_position.y, 0.0, 1.0)
	)
	var centrality := 1.0 - clampf(
		absf(normalized_position.x - 0.62) / 0.62,
		0.0,
		1.0
	)
	return clampf(
		0.35
			+ lowland * 1.00
			+ eastness * 0.55
			+ eastness * southness * 0.35
			+ centrality * 0.15
			+ clampf(river_affinity, 0.0, 1.0) * 0.70
			- clampf(relief, 0.0, 1.0) * 1.20,
		0.35,
		3.00
	)


static func _river_bank_affinity(
	pixel: Vector2i,
	bounds: Rect2i,
	river_paths: Array[Array]
) -> float:
	if river_paths.is_empty():
		return 0.0
	var scale := Vector2(
		maxi(bounds.size.x, 1),
		maxi(bounds.size.y, 1)
	)
	var map_aspect := (
		float(maxi(bounds.size.x, 1))
		/ float(maxi(bounds.size.y, 1))
	)
	var normalized := (
		Vector2(pixel) - Vector2(bounds.position)
	) / scale
	var minimum_distance := INF
	for path in river_paths:
		for river_pixel_value in path:
			var river_pixel: Vector2i = river_pixel_value
			var river_normalized := (
				Vector2(river_pixel) - Vector2(bounds.position)
			) / scale
			var delta := normalized - river_normalized
			delta.x *= map_aspect
			minimum_distance = minf(
				minimum_distance,
				delta.length()
			)
	if minimum_distance < RIVER_BANK_MIN_DISTANCE:
		return 0.0
	if minimum_distance <= RIVER_BANK_IDEAL_DISTANCE:
		return inverse_lerp(
			RIVER_BANK_MIN_DISTANCE,
			RIVER_BANK_IDEAL_DISTANCE,
			minimum_distance
		)
	if minimum_distance >= RIVER_BANK_MAX_DISTANCE:
		return 0.0
	return 1.0 - inverse_lerp(
		RIVER_BANK_IDEAL_DISTANCE,
		RIVER_BANK_MAX_DISTANCE,
		minimum_distance
	)


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
	samples: Dictionary,
	map_aspect_ratio: float
) -> Dictionary:
	var pixels: Array[Vector2i] = samples["pixels"]
	var positions: Array[Vector2] = samples["positions"]
	# 选边拓扑沿用原始分析图比例，避免距离数值调整改变道路连接关系。
	var topology_aspect := (
		float(image.get_width())
		/ float(maxi(image.get_height(), 1))
	)
	var metric_positions := PackedVector2Array()
	for position in positions:
		metric_positions.append(Vector2(
			position.x * topology_aspect,
			position.y
		))
	var candidates: Array[Dictionary] = []
	for a in range(pixels.size()):
		for b in range(a + 1, pixels.size()):
			var profile := _edge_profile(image, mask, pixels[a], pixels[b])
			var length := metric_positions[a].distance_to(
				metric_positions[b]
			)
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
	var local_keys := {}
	var triangles := Geometry2D.triangulate_delaunay(metric_positions)
	for index in range(0, triangles.size(), 3):
		for pair in [
			[triangles[index], triangles[index + 1]],
			[triangles[index + 1], triangles[index + 2]],
			[triangles[index + 2], triangles[index]],
		]:
			local_keys[_pair_key(int(pair[0]), int(pair[1]))] = true
	var planar_candidates: Array[Dictionary] = []
	for candidate in candidates:
		if local_keys.has(
			_pair_key(int(candidate["a"]), int(candidate["b"]))
		):
			planar_candidates.append(candidate)

	var selected: Array[Dictionary] = []
	var selected_keys := {}
	var parent: Array[int] = []
	parent.resize(pixels.size())
	for city_id in range(parent.size()):
		parent[city_id] = city_id
	var backbone_edges := 0
	for candidate in planar_candidates:
		if (
			float(candidate["land_ratio"]) < 0.88
			or float(candidate["length"]) > PREFERRED_BACKBONE_LENGTH
		):
			continue
		var root_a := _root(parent, int(candidate["a"]))
		var root_b := _root(parent, int(candidate["b"]))
		if root_a == root_b:
			continue
		parent[root_b] = root_a
		candidate["backbone"] = true
		selected.append(candidate)
		selected_keys[_pair_key(int(candidate["a"]), int(candidate["b"]))] = true
		backbone_edges += 1
	for candidate in planar_candidates:
		if backbone_edges >= pixels.size() - 1:
			break
		var root_a := _root(parent, int(candidate["a"]))
		var root_b := _root(parent, int(candidate["b"]))
		if root_a == root_b:
			continue
		parent[root_b] = root_a
		candidate["backbone"] = true
		selected.append(candidate)
		selected_keys[_pair_key(int(candidate["a"]), int(candidate["b"]))] = true
		backbone_edges += 1
	assert(
		backbone_edges == pixels.size() - 1,
		"Delaunay 平面候选图必须生成完整连通骨架"
	)

	var local_edge_keys := local_keys.keys()
	local_edge_keys.sort()
	for key_variant in local_edge_keys:
		var key := int(key_variant)
		if selected_keys.has(key):
			continue
		var candidate: Dictionary = candidate_by_key[key]
		if (
			float(candidate["land_ratio"]) < 0.90
			or float(candidate["length"]) > MAX_LOCAL_EDGE_LENGTH
		):
			continue
		candidate["backbone"] = false
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
		road["max_manpower"] = (
			100000 if percentile < 0.05
			else 60000 if percentile < 0.15
			else 30000 if percentile < 0.55
			else 15000 if percentile < 0.85
			else 5000 if percentile < 0.90
			else 0
		)
		if bool(road.get("backbone", false)):
			road["max_manpower"] = maxi(
				int(road["max_manpower"]),
				5000
			)
		road["danger"] = clampf(percentile, 0.0, 1.0)
		road["length"] = metric_length_between(
			positions[int(road["a"])],
			positions[int(road["b"])],
			map_aspect_ratio
		)
		road["distance"] = distance_units_for_metric_length(
			float(road["length"])
		)
	var blocked_target := maxi(int(round(float(count) * 0.10)), 1)
	var blocked_count := 0
	for i in range(count - 1, -1, -1):
		var road := selected[i]
		if bool(road.get("backbone", false)):
			continue
		road["max_manpower"] = 0
		blocked_count += 1
		if blocked_count >= blocked_target:
			break
	return {
		"roads": selected,
	}


static func _build_river_transport(
	image: Image,
	mask: PackedByteArray,
	bounds: Rect2i,
	samples: Dictionary,
	base_roads: Array[Dictionary],
	river_paths: Array[Array],
	city_count: int,
	map_aspect_ratio: float
) -> Dictionary:
	var dock_result := _find_river_docks(
		image,
		bounds,
		samples["pixels"],
		samples["positions"],
		base_roads,
		river_paths,
		city_count
	)
	var docks: Array[Dictionary] = dock_result["docks"]
	var crossings_by_road: Dictionary = dock_result[
		"crossings_by_road"
	]
	var blocked_crossing_roads: Dictionary = dock_result[
		"blocked_crossing_roads"
	]
	var city_positions: Array[Vector2] = samples["positions"]
	city_positions = city_positions.duplicate()
	for dock in docks:
		assert(
			int(dock["city_id"]) == city_positions.size(),
			"码头位置顺序必须与城市 id 一致"
		)
		city_positions.append(dock["position"])
	var roads: Array[Dictionary] = []
	for road_index in range(base_roads.size()):
		var road: Dictionary = base_roads[road_index]
		var crossings: Array = crossings_by_road.get(
			road_index,
			[]
		)
		if crossings.is_empty():
			if blocked_crossing_roads.has(road_index):
				continue
			var land_road := road.duplicate(true)
			land_road["kind"] = Edge.Kind.LAND
			land_road["travel_time_multiplier"] = 1.0
			land_road["supply_loss_multiplier"] = 1.0
			land_road["allows_holding"] = true
			roads.append(land_road)
			continue
		crossings.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return float(a["road_t"]) < float(b["road_t"])
		)
		var previous_city := int(road["a"])
		for crossing in crossings:
			var dock_city := int(crossing["city_id"])
			roads.append(_landing_road_segment(
				road,
				previous_city,
				dock_city,
				city_positions,
				map_aspect_ratio
			))
			previous_city = dock_city
		roads.append(_landing_road_segment(
			road,
			previous_city,
			int(road["b"]),
			city_positions,
			map_aspect_ratio
		))

	var river_groups: Dictionary = dock_result["river_groups"]
	var active_paths: Array[PackedVector2Array] = []
	var occupied_pairs := {}
	for road in roads:
		occupied_pairs[_pair_key(
			int(road["a"]),
			int(road["b"])
		)] = true
	var river_ids := river_groups.keys()
	river_ids.sort()
	for river_id_value in river_ids:
		var river_id := int(river_id_value)
		var river_docks: Array = river_groups[river_id]
		if river_docks.size() < 2:
			continue
		river_docks.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return (
					float(a["river_progress"])
					< float(b["river_progress"])
				)
		)
		var path: Array[Vector2i] = river_paths[river_id]
		active_paths.append(_normalized_river_path(path, bounds))
		for index in range(river_docks.size() - 1):
			var from_dock: Dictionary = river_docks[index]
			var to_dock: Dictionary = river_docks[index + 1]
			var from_city := int(from_dock["city_id"])
			var to_city := int(to_dock["city_id"])
			var pair_key := _pair_key(from_city, to_city)
			if occupied_pairs.has(pair_key):
				continue
			occupied_pairs[pair_key] = true
			var from_position: Vector2 = from_dock["position"]
			var to_position: Vector2 = to_dock["position"]
			var metric_length := metric_length_between(
				from_position,
				to_position,
				map_aspect_ratio
			)
			var river_edge := {
				"a": from_city,
				"b": to_city,
				"length": metric_length,
				"height_difference": absf(
					float(from_dock["height"])
					- float(to_dock["height"])
				),
				"land_ratio": 1.0,
				"cost": metric_length,
				"backbone": true,
				"max_manpower": Edge.MAX_MANPOWER,
				"danger": _river_link_danger(
					image,
					path,
					float(from_dock["river_progress"]),
					float(to_dock["river_progress"])
				),
				"distance": distance_units_for_metric_length(
					metric_length
				),
				"kind": Edge.Kind.RIVER,
				"travel_time_multiplier":
					RIVER_TRAVEL_TIME_MULTIPLIER,
				"supply_loss_multiplier":
					RIVER_SUPPLY_LOSS_MULTIPLIER,
				"allows_holding": false,
			}
			roads.append(river_edge)
	assert(
		active_paths.size() == RIVER_COUNT,
		"正式地图必须生成两条具备至少两个码头的有效河运路线"
	)
	return {
		"roads": roads,
		"docks": docks,
		"river_paths": active_paths,
	}


static func _build_river_paths(
	image: Image,
	mask: PackedByteArray,
	bounds: Rect2i
) -> Array[Array]:
	var templates: Array[PackedVector2Array] = [
		PackedVector2Array([
			Vector2(0.10, 0.58),
			Vector2(0.25, 0.54),
			Vector2(0.42, 0.50),
			Vector2(0.58, 0.53),
			Vector2(0.75, 0.59),
			Vector2(0.94, 0.56),
		]),
		PackedVector2Array([
			Vector2(0.08, 0.69),
			Vector2(0.25, 0.63),
			Vector2(0.43, 0.68),
			Vector2(0.61, 0.60),
			Vector2(0.78, 0.65),
			Vector2(0.97, 0.61),
		]),
	]
	var paths: Array[Array] = []
	for river_index in range(mini(RIVER_COUNT, templates.size())):
		var template := templates[river_index]
		var grid := _build_river_path_grid(
			image,
			mask,
			bounds,
			template
		)
		var control_points: Array[Vector2i] = []
		for normalized_point in template:
			var control := _nearest_river_land_point(
				mask,
				image.get_width(),
				bounds,
				normalized_point
			)
			if (
				control == Vector2i(-1, -1)
				or (
					not control_points.is_empty()
					and control == control_points[-1]
				)
			):
				continue
			control_points.append(control)
		if control_points.size() < 2:
			continue
		var path: Array[Vector2i] = []
		for control_index in range(control_points.size() - 1):
			var segment := grid.get_id_path(
				control_points[control_index],
				control_points[control_index + 1]
			)
			for point_value in segment:
				var point: Vector2i = point_value
				if path.is_empty() or point != path[-1]:
					path.append(point)
		if path.size() >= 2:
			paths.append(path)
	return paths


static func _build_river_path_grid(
	image: Image,
	mask: PackedByteArray,
	bounds: Rect2i,
	template: PackedVector2Array
) -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, image.get_size())
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = (
		AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	)
	grid.update()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var point := Vector2i(x, y)
			if mask[y * image.get_width() + x] == 0:
				grid.set_point_solid(point, true)
				continue
			var normalized := _normalized_map_point(point, bounds)
			var target_y := _river_template_y(
				template,
				normalized.x
			)
			var height := image.get_pixel(x, y).get_luminance()
			var relief := _pixel_relief(image, x, y)
			grid.set_point_weight_scale(
				point,
				1.0
					+ height * 2.0
					+ relief * 16.0
					+ absf(normalized.y - target_y)
						* RIVER_CHANNEL_DEVIATION_WEIGHT
			)
	return grid


static func _river_template_y(
	template: PackedVector2Array,
	normalized_x: float
) -> float:
	if normalized_x <= template[0].x:
		return template[0].y
	for index in range(template.size() - 1):
		var from := template[index]
		var to := template[index + 1]
		if normalized_x > to.x:
			continue
		var ratio := clampf(
			(normalized_x - from.x)
				/ maxf(to.x - from.x, 0.0001),
			0.0,
			1.0
		)
		return lerpf(from.y, to.y, ratio)
	return template[-1].y


static func _nearest_river_land_point(
	mask: PackedByteArray,
	image_width: int,
	bounds: Rect2i,
	normalized_target: Vector2
) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			if mask[y * image_width + x] == 0:
				continue
			var point := Vector2i(x, y)
			var distance := _normalized_map_point(
				point,
				bounds
			).distance_squared_to(normalized_target)
			if distance < best_distance:
				best_distance = distance
				best = point
	return best


static func _find_river_docks(
	image: Image,
	bounds: Rect2i,
	city_pixels: Array[Vector2i],
	city_positions: Array[Vector2],
	roads: Array[Dictionary],
	river_paths: Array[Array],
	city_count: int
) -> Dictionary:
	var docks: Array[Dictionary] = []
	var crossings_by_road := {}
	var river_groups := {}
	var raw_crossings_by_road := {}
	var candidates_by_river := {}
	for river_id in range(river_paths.size()):
		var path: Array[Vector2i] = river_paths[river_id]
		var candidates: Array[Dictionary] = []
		for road_index in range(roads.size()):
			var road := roads[road_index]
			if int(road["max_manpower"]) <= 0:
				continue
			var road_crossings := _road_river_crossings(
				city_pixels,
				road,
				road_index,
				path,
				river_id,
				bounds
			)
			for crossing in road_crossings:
				candidates.append(crossing)
				if not raw_crossings_by_road.has(road_index):
					raw_crossings_by_road[road_index] = []
				(raw_crossings_by_road[road_index] as Array).append(
					crossing
				)
		candidates_by_river[river_id] = candidates

	var selected_dock_roads := _select_dock_crossing_roads(
		candidates_by_river,
		roads,
		city_positions
	)
	for river_id in range(river_paths.size()):
		var candidates: Array[Dictionary] = candidates_by_river.get(
			river_id,
			[]
		)
		candidates.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return (
					float(a["river_progress"])
					< float(b["river_progress"])
				)
		)
		if candidates.size() < 2:
			continue
		for candidate in candidates:
			if not selected_dock_roads.has(
				int(candidate["road_index"])
			):
				continue
			var pixel_position: Vector2 = candidate[
				"pixel_position"
			]
			var x := clampi(
				int(round(pixel_position.x)),
				0,
				image.get_width() - 1
			)
			var y := clampi(
				int(round(pixel_position.y)),
				0,
				image.get_height() - 1
			)
			candidate["city_id"] = city_count + docks.size()
			candidate["height"] = image.get_pixel(
				x,
				y
			).get_luminance()
			candidate["relief"] = _local_relief(
				image,
				x,
				y,
				RELIEF_RADIUS
			)
			var road: Dictionary = roads[
				int(candidate["road_index"])
			]
			candidate["road_a"] = int(road["a"])
			candidate["road_b"] = int(road["b"])
			docks.append(candidate)
			if not crossings_by_road.has(
				int(candidate["road_index"])
			):
				crossings_by_road[
					int(candidate["road_index"])
				] = []
			(crossings_by_road[
				int(candidate["road_index"])
			] as Array).append(candidate)
			if not river_groups.has(river_id):
				river_groups[river_id] = []
			(river_groups[river_id] as Array).append(candidate)
	var blocked_crossing_roads := {}
	for road_index_value in raw_crossings_by_road:
		var road_index := int(road_index_value)
		if not crossings_by_road.has(road_index):
			blocked_crossing_roads[road_index] = true
	return {
		"docks": docks,
		"crossings_by_road": crossings_by_road,
		"blocked_crossing_roads": blocked_crossing_roads,
		"river_groups": river_groups,
	}


static func _select_dock_crossing_roads(
	candidates_by_river: Dictionary,
	roads: Array[Dictionary],
	city_positions: Array[Vector2]
) -> Dictionary:
	var selected := {}
	var crossing_roads := {}
	for candidates_value in candidates_by_river.values():
		for candidate in candidates_value:
			crossing_roads[int(candidate["road_index"])] = true
	var river_ids := candidates_by_river.keys()
	river_ids.sort()
	for river_id_value in river_ids:
		var candidates: Array[Dictionary] = (
			candidates_by_river[river_id_value]
		)
		candidates.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return (
					float(a["river_progress"])
						< float(b["river_progress"])
				)
		)
		var target := clampi(
			int(round(
				float(candidates.size()) * RIVER_DOCK_SHARE
			)),
			mini(RIVER_DOCK_MIN_PER_RIVER, candidates.size()),
			candidates.size()
		)
		for selection_index in range(target):
			var candidate_index := clampi(
				int(round(
					(float(selection_index) + 0.5)
						* float(candidates.size())
						/ float(maxi(target, 1))
						- 0.5
				)),
				0,
				candidates.size() - 1
			)
			selected[int(
				candidates[candidate_index]["road_index"]
			)] = true
	var node_count := 0
	for road in roads:
		node_count = maxi(
			node_count,
			maxi(int(road["a"]), int(road["b"])) + 1
		)
	var parent: Array[int] = []
	parent.resize(node_count)
	for node in range(node_count):
		parent[node] = node
	for road_index in range(roads.size()):
		var road := roads[road_index]
		if (
			int(road["max_manpower"]) <= 0
			or (
				crossing_roads.has(road_index)
				and not selected.has(road_index)
			)
		):
			continue
		_river_union_find_join(
			parent,
			int(road["a"]),
			int(road["b"])
		)
	var crossing_indices := crossing_roads.keys()
	crossing_indices.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			var road_a: Dictionary = roads[int(a)]
			var road_b: Dictionary = roads[int(b)]
			var backbone_a := bool(road_a.get("backbone", false))
			var backbone_b := bool(road_b.get("backbone", false))
			if backbone_a != backbone_b:
				return backbone_a
			if not is_equal_approx(
				float(road_a["cost"]),
				float(road_b["cost"])
			):
				return float(road_a["cost"]) < float(road_b["cost"])
			return int(a) < int(b)
	)
	# 正式地图开局按空间四分区分国。先在各国内部补足最少渡口，
	# 避免河道移动后全图仍连通、但单个国家领土被河流切成孤岛。
	var initial_owner := _initial_nation_owner_by_position(
		city_positions
	)
	var nation_parent: Array[int] = []
	nation_parent.resize(node_count)
	for node in range(node_count):
		nation_parent[node] = node
	for road_index in range(roads.size()):
		var road: Dictionary = roads[road_index]
		var city_a := int(road["a"])
		var city_b := int(road["b"])
		if (
			int(road["max_manpower"]) <= 0
			or initial_owner[city_a] != initial_owner[city_b]
			or (
				crossing_roads.has(road_index)
				and not selected.has(road_index)
			)
		):
			continue
		_river_union_find_join(
			nation_parent,
			city_a,
			city_b
		)
	for road_index_value in crossing_indices:
		var road_index := int(road_index_value)
		if selected.has(road_index):
			continue
		var road: Dictionary = roads[road_index]
		var city_a := int(road["a"])
		var city_b := int(road["b"])
		if initial_owner[city_a] != initial_owner[city_b]:
			continue
		if (
			_river_union_find_root(nation_parent, city_a)
				== _river_union_find_root(nation_parent, city_b)
		):
			continue
		selected[road_index] = true
		_river_union_find_join(
			nation_parent,
			city_a,
			city_b
		)

	# 在国家内部连通的基础上，再恢复全图连通所需的最少 crossing。
	parent.fill(0)
	for node in range(node_count):
		parent[node] = node
	for road_index in range(roads.size()):
		var road: Dictionary = roads[road_index]
		if (
			int(road["max_manpower"]) <= 0
			or (
				crossing_roads.has(road_index)
				and not selected.has(road_index)
			)
		):
			continue
		_river_union_find_join(
			parent,
			int(road["a"]),
			int(road["b"])
		)
	for road_index_value in crossing_indices:
		var road_index := int(road_index_value)
		if selected.has(road_index):
			continue
		var road: Dictionary = roads[road_index]
		var city_a := int(road["a"])
		var city_b := int(road["b"])
		if (
			_river_union_find_root(parent, city_a)
				== _river_union_find_root(parent, city_b)
		):
			continue
		selected[road_index] = true
		_river_union_find_join(parent, city_a, city_b)
	return selected


static func _initial_nation_owner_by_position(
	city_positions: Array[Vector2]
) -> Array[int]:
	var owner: Array[int] = []
	owner.resize(city_positions.size())
	owner.fill(-1)
	var ordered: Array[int] = []
	for city_id in range(city_positions.size()):
		ordered.append(city_id)
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var pa := city_positions[a]
		var pb := city_positions[b]
		if not is_equal_approx(pa.x, pb.x):
			return pa.x < pb.x
		return pa.y < pb.y
	)
	var side_size := city_positions.size() / 2
	for side in range(2):
		var side_cities: Array[int] = []
		for index in range(
			side * side_size,
			(side + 1) * side_size
		):
			side_cities.append(ordered[index])
		side_cities.sort_custom(func(a: int, b: int) -> bool:
			var pa := city_positions[a]
			var pb := city_positions[b]
			if not is_equal_approx(pa.y, pb.y):
				return pa.y < pb.y
			return pa.x < pb.x
		)
		for index in range(side_cities.size()):
			var row_half := (
				0
				if index < side_cities.size() / 2
				else 1
			)
			owner[side_cities[index]] = row_half * 2 + side
	return owner


static func _river_union_find_root(
	parent: Array[int],
	node: int
) -> int:
	var current := node
	while parent[current] != current:
		parent[current] = parent[parent[current]]
		current = parent[current]
	return current


static func _river_union_find_join(
	parent: Array[int],
	a: int,
	b: int
) -> void:
	var root_a := _river_union_find_root(parent, a)
	var root_b := _river_union_find_root(parent, b)
	if root_a != root_b:
		parent[root_b] = root_a


static func _road_river_crossings(
	city_pixels: Array[Vector2i],
	road: Dictionary,
	road_index: int,
	path: Array[Vector2i],
	river_id: int,
	bounds: Rect2i
) -> Array[Dictionary]:
	var road_start := Vector2(city_pixels[int(road["a"])])
	var road_end := Vector2(city_pixels[int(road["b"])])
	var road_delta := road_end - road_start
	var road_length_sq := road_delta.length_squared()
	var crossings: Array[Dictionary] = []
	if road_length_sq <= 0.001:
		return crossings
	for path_index in range(path.size() - 1):
		var river_start := Vector2(path[path_index])
		var river_end := Vector2(path[path_index + 1])
		var hit = Geometry2D.segment_intersects_segment(
			road_start,
			road_end,
			river_start,
			river_end
		)
		if hit == null:
			continue
		var point: Vector2 = hit
		var road_t := (
			(point - road_start).dot(road_delta)
			/ road_length_sq
		)
		if (
			road_t <= RIVER_CROSSING_ENDPOINT_EPS
			or road_t >= 1.0 - RIVER_CROSSING_ENDPOINT_EPS
		):
			continue
		crossings.append({
			"road_index": road_index,
			"road_t": road_t,
			"river_id": river_id,
			"river_progress": float(path_index)
				+ _segment_fraction(
					point,
					river_start,
					river_end
				),
			"pixel_position": point,
			"position": _normalized_map_point(point, bounds),
		})
	crossings.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(
				float(a["road_t"]),
				float(b["road_t"])
			):
				return float(a["road_t"]) < float(b["road_t"])
			return (
				float(a["river_progress"])
				< float(b["river_progress"])
			)
	)
	var merged: Array[Dictionary] = []
	for crossing in crossings:
		if (
			not merged.is_empty()
			and absf(
				float(crossing["road_t"])
					- float(merged[-1]["road_t"])
			) <= RIVER_CROSSING_MERGE_EPS
		):
			continue
		merged.append(crossing)
	return merged


static func _landing_road_segment(
	base: Dictionary,
	from_city: int,
	to_city: int,
	city_positions: Array[Vector2],
	map_aspect_ratio: float
) -> Dictionary:
	var segment := base.duplicate(true)
	segment["a"] = from_city
	segment["b"] = to_city
	segment["length"] = metric_length_between(
		city_positions[from_city],
		city_positions[to_city],
		map_aspect_ratio
	)
	segment["distance"] = distance_units_for_metric_length(
		float(segment["length"])
	)
	segment["danger"] = maxf(
		float(base["danger"]),
		LANDING_DANGER_MIN
	)
	segment["kind"] = Edge.Kind.LANDING
	segment["travel_time_multiplier"] = 1.0
	segment["supply_loss_multiplier"] = 1.0
	segment["allows_holding"] = true
	return segment


static func distance_units_for_metric_length(metric_length: float) -> int:
	return maxi(
		int(round(
			maxf(metric_length, 0.0)
				* EDGE_DISTANCE_UNITS_PER_MAP_HEIGHT
		)),
		1
	)


static func metric_length_between(
	from_position: Vector2,
	to_position: Vector2,
	map_aspect_ratio: float
) -> float:
	var delta := to_position - from_position
	delta.x *= map_aspect_ratio
	return delta.length()


static func _river_link_danger(
	image: Image,
	path: Array[Vector2i],
	from_progress: float,
	to_progress: float
) -> float:
	var first := clampi(
		int(floor(from_progress)),
		0,
		path.size() - 1
	)
	var last := clampi(
		int(ceil(to_progress)),
		first + 1,
		path.size() - 1
	)
	var slope_total := 0.0
	var turn_total := 0.0
	var samples := 0
	for index in range(first, last):
		var a := path[index]
		var b := path[index + 1]
		slope_total += absf(
			image.get_pixel(a.x, a.y).get_luminance()
			- image.get_pixel(b.x, b.y).get_luminance()
		)
		if index + 2 <= last:
			var first_direction := Vector2(
				path[index + 1] - path[index]
			).normalized()
			var second_direction := Vector2(
				path[index + 2] - path[index + 1]
			).normalized()
			turn_total += (
				1.0
				- clampf(
					first_direction.dot(second_direction),
					-1.0,
					1.0
				)
			)
		samples += 1
	return clampf(
		0.12
			+ slope_total / float(maxi(samples, 1)) * 10.0
			+ turn_total / float(maxi(samples, 1)) * 0.18,
		0.12,
		0.60
	)


static func _normalized_river_path(
	path: Array[Vector2i],
	bounds: Rect2i
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in path:
		result.append(_normalized_map_point(point, bounds))
	return result


static func _normalized_map_point(
	point: Vector2,
	bounds: Rect2i
) -> Vector2:
	return Vector2(
		(point.x - float(bounds.position.x))
			/ float(maxi(bounds.size.x - 1, 1)),
		(point.y - float(bounds.position.y))
			/ float(maxi(bounds.size.y - 1, 1))
	)


static func _segment_fraction(
	point: Vector2,
	from: Vector2,
	to: Vector2
) -> float:
	var delta := to - from
	if delta.length_squared() <= 0.000001:
		return 0.0
	return clampf(
		(point - from).dot(delta) / delta.length_squared(),
		0.0,
		1.0
	)


static func _pixel_relief(
	image: Image,
	x: int,
	y: int
) -> float:
	var center := image.get_pixel(x, y).get_luminance()
	var result := 0.0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var px := clampi(x + ox, 0, image.get_width() - 1)
			var py := clampi(y + oy, 0, image.get_height() - 1)
			result = maxf(
				result,
				absf(
					center
					- image.get_pixel(px, py).get_luminance()
				)
			)
	return result


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


static func _pair_key(a: int, b: int) -> int:
	return mini(a, b) * 10000 + maxi(a, b)


static func _root(parent: Array[int], node: int) -> int:
	var current := node
	while parent[current] != current:
		parent[current] = parent[parent[current]]
		current = parent[current]
	return current
